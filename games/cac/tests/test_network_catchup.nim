import
  polyworld/[rooms, roomclients],
  ../src/core/[battlesetup, replays, sim],
  ../src/net/multiplayer

proc fixture(bot = false, automaticBots = true): NetworkMatch =
  ## Starts an owned acting seat with an unanswered initial history request.
  let
    setup = defaultBattleSetup(2)
    game = newGame(setup.battleSeats(), setup.seed.int64)
    actor = game.actingPlayer()
    client = RoomClient(participant: uint32(actor + 1), connected: true,
      welcomed: true, snapshot: RoomMessage(kind: RoomState, room: "catchup",
        phase: Lobby, revision: 1, tickRate: CacNetworkTickRate.uint32,
        payload: setup.encodeBattleSetup(), seats: @[
          rooms.Seat(owner: 1, name: "Human"),
          rooms.Seat(owner: 2, name: "Human")], participants: @[
          Participant(id: 1, name: "First", connected: true),
          Participant(id: 2, name: "Second", connected: true)]))
  var sources = newSeq[string](2)
  if bot:
    client.snapshot.seats[actor].name = "Passive bot"
    client.snapshot.seats[actor].kind = BotSeat
    sources[actor] = "endTurn()\nend\n"
  result = prepareNetworkMatch(client, sources)
  result.automaticBots = automaticBots
  var started = client.snapshot
  started.kind = BeginMatch
  started.match = 1
  started.hash = setupHash(client.snapshot)
  client.snapshot.phase = Playing
  client.accept(started.encode())
  result.start(started)

proc applyEmpty(session: NetworkMatch, tick: uint32) =
  ## Applies a real empty relay packet through the normal session entry point.
  session.client.accept(RoomMessage(kind: TickPacket, match: 1,
    tick: tick, seats: session.client.snapshot.seats).encode())
  var packet: RoomMessage
  doAssert session.client.takeTick(packet)
  session.applyPacket(packet)

block:
  let
    session = fixture()
    client = session.client
    action = ReplayAction(kind: ActionEndTurn,
      playerId: session.humanSeat.int32)
  doAssert client.catchingUp
  doAssert not session.submitAction(action)
  doAssert session.submitMailbox(session.humanSeat, -2, "Starting") == 0
  client.accept(RoomMessage(kind: CaughtUp, match: 1).encode())
  session.applyEmpty(1)
  doAssert client.catchupPending
  doAssert not client.catchingUp
  let before = session.game.networkHash()
  doAssert session.submitMailbox(session.humanSeat, -2, "Live") == 2
  doAssert session.submitAction(action),
    "A routine history probe must not reject a human action"
  doAssert session.game.networkHash() == before

block:
  let
    session = fixture()
    client = session.client
    action = ReplayAction(kind: ActionEndTurn,
      playerId: session.humanSeat.int32)
  client.accept(RoomMessage(kind: CaughtUp, match: 1).encode())
  session.applyEmpty(1)
  # Discover a real gap while the ordinary edge probe is still in flight.
  client.accept(RoomMessage(kind: MatchStatus, match: 1, phase: Playing,
    tick: 3).encode())
  var packet: RoomMessage
  doAssert not client.takeTick(packet)
  doAssert client.catchingUp
  doAssert not session.submitAction(action)
  client.accept(RoomMessage(kind: TickPacket, match: 1, tick: 2,
    seats: client.snapshot.seats).encode())
  client.accept(RoomMessage(kind: TickPacket, match: 1, tick: 3,
    seats: client.snapshot.seats).encode())
  client.accept(RoomMessage(kind: CaughtUp, match: 1, tick: 3,
    number: 3).encode())
  doAssert not client.catchupPending
  doAssert client.catchingUp
  doAssert session.canApplyTick(presentationReady = false)
  doAssert client.takeTick(packet)
  session.applyPacket(packet)
  doAssert client.catchingUp
  doAssert not session.submitAction(action)
  doAssert client.takeTick(packet)
  session.applyPacket(packet)
  doAssert not client.catchingUp
  doAssert session.submitAction(action)

block:
  let
    session = fixture(bot = true)
    client = session.client
  doAssert client.catchingUp
  doAssert not session.pendingAction
  client.accept(RoomMessage(kind: CaughtUp, match: 1).encode())
  session.applyEmpty(1)
  doAssert client.catchupPending
  doAssert not client.catchingUp
  doAssert session.pendingAction,
    "A routine history probe must not stop an owned bot"
  doAssert session.actionCount == 0

block:
  let
    session = fixture(bot = true, automaticBots = false)
    client = session.client
  client.accept(RoomMessage(kind: CaughtUp, match: 1).encode())
  # A four-second animation must keep acknowledging the live empty stream.
  for tick in 1'u32 .. 96'u32:
    client.accept(RoomMessage(kind: TickPacket, match: 1, tick: tick,
      seats: client.snapshot.seats).encode())
    doAssert session.canApplyTick(presentationReady = false)
    var packet: RoomMessage
    doAssert client.takeTick(packet)
    session.applyPacket(packet)
    doAssert not session.pendingAction
    doAssert not client.catchingUp
    client.accept(RoomMessage(kind: CaughtUp, match: 1, tick: tick,
      number: tick).encode())
  doAssert session.tick == 96
  # The renderer releases the next decision only when the animation settles.
  session.pumpBots()
  doAssert session.pendingAction
  var submission: RoomMessage
  for bytes in client.outgoing:
    let message = decode(bytes)
    if message.kind == SubmitCommand:
      submission = message
  doAssert submission.kind == SubmitCommand
  client.accept(RoomMessage(kind: TickPacket, match: 1, tick: 97,
    seats: client.snapshot.seats,
    commands: @[Command(participant: client.participant,
      seat: submission.seat, seatKind: BotSeat, sequence: submission.sequence,
      payload: submission.payload)]).encode())
  doAssert not session.canApplyTick(presentationReady = false)
  doAssert session.canApplyTick(presentationReady = true)
  var packet: RoomMessage
  doAssert client.takeTick(packet)
  session.applyPacket(packet)
  doAssert session.actionCount == 1

block:
  let
    session = fixture()
    client = session.client
  client.accept(RoomMessage(kind: CaughtUp, match: 1).encode())
  session.applyEmpty(1)
  doAssert session.submitMailbox(session.humanSeat, -2, "A canceled message") == 2
  doAssert session.submitAction(ReplayAction(kind: ActionEndTurn,
    playerId: session.humanSeat.int32))
  var mailbox, action: RoomMessage
  for bytes in client.outgoing:
    let message = decode(bytes)
    if message.kind == SubmitCommand:
      if message.payload.decodeSubmission().mailbox:
        mailbox = message
      else:
        action = message
  doAssert mailbox.kind == SubmitCommand and action.kind == SubmitCommand
  client.accept(RoomMessage(kind: CommandAck, match: 1,
    sequence: mailbox.sequence, flag: true).encode())
  doAssert session.pendingAction,
    "Discarding policy mail must not clear an unrelated pending turn."
  var discarded: RoomMessage
  doAssert not client.takeRejected(discarded)
  client.accept(RoomMessage(kind: CommandAck, match: 1,
    sequence: action.sequence, flag: true).encode())
  doAssert not session.pendingAction
  doAssert not client.takeRejected(discarded)

echo "CaC history probes preserve input; real recovery waits for application."
