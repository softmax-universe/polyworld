import polyworld/[rooms, roomclients]

echo "Testing command and hash retransmission after connection loss"
let client = RoomClient(participant: 7, match: 2, began: true, welcomed: true)
client.snapshot = RoomMessage(
  kind: RoomState, room: "room", phase: Playing,
  seats: @[Seat(owner: 7, name: "Human")]
)
doAssert not client.hasPendingCommand(0)
doAssert client.submit(0, "opaque game command")
doAssert client.hasPendingCommand(0)
doAssert not client.hasPendingCommand(1)
client.send(RoomMessage(kind: ReportHash, match: 2, tick: 24, hash: 123))
client.send(RoomMessage(kind: FinishMatch, match: 2, tick: 25, hash: 456))
client.lost()
doAssert client.hasPendingCommand(0)
client.opened()
client.accept(RoomMessage(kind: Welcome, participant: 7, token: "secret").encode)
doAssert client.hasPendingCommand(0)
var commands, checkpoints, finals: int
for bytes in client.outgoing:
  let message = decode(bytes)
  case message.kind
  of SubmitCommand:
    inc commands
    doAssert message.sequence == 1 and message.payload == "opaque game command"
    doAssert message.seatKind == HumanSeat
  of ReportHash:
    inc checkpoints
    doAssert message.tick == 24 and message.hash == 123
  of FinishMatch:
    inc finals
    doAssert message.tick == 25 and message.hash == 456
  else:
    discard
doAssert commands == 1 and checkpoints == 1 and finals == 1
# Acknowledged commands are not retransmitted; hash confirmations still are.
client.accept(RoomMessage(kind: CommandAck, match: 2, sequence: 1).encode)
doAssert not client.hasPendingCommand(0)
client.lost()
client.opened()
client.accept(RoomMessage(kind: Welcome, participant: 7, token: "secret").encode)
for bytes in client.outgoing:
  doAssert decode(bytes).kind != SubmitCommand
let nextSeats = @[Seat(owner: 8, name: "Replacement", kind: BotSeat)]
client.accept(RoomMessage(kind: TickPacket, match: 2, tick: 1,
  seats: nextSeats).encode)
client.accept(RoomMessage(kind: TickPacket, match: 2, tick: 1,
  seats: nextSeats).encode)
doAssert client.packets.len == 1
var failed = false
try:
  client.accept(RoomMessage(kind: TickPacket, match: 2, tick: 1,
    commands: @[Command(payload: "changed")]).encode)
except RoomsError:
  failed = true
doAssert failed
var packet: RoomMessage
doAssert client.takeTick(packet) and packet.tick == 1
client.appliedTick(1)
doAssert client.appliedSeats == nextSeats
doAssert client.snapshot.seats[0].owner == 7,
  "Applying history must not replace the latest administrative snapshot"
doAssert not client.takeTick(packet)
echo "Reconnect receipts, mandatory hashes and immutable ticks passed"

echo "Testing pending commands acknowledged before their tick"
doAssert client.submit(0, "reserved game command")
client.lost()
client.opened()
client.accept(RoomMessage(kind: Welcome, participant: 7, token: "secret").encode)
client.accept(RoomMessage(kind: CommandAck, match: 2, sequence: 2, tick: 2).encode)
doAssert client.hasPendingCommand(0)
client.outgoing.setLen(0)
client.flushCommands()
doAssert client.outgoing.len == 0
client.lost()
client.opened()
client.accept(RoomMessage(kind: Welcome, participant: 7, token: "secret").encode)
commands = 0
for bytes in client.outgoing:
  let message = decode(bytes)
  if message.kind == SubmitCommand:
    inc commands
    doAssert message.sequence == 2 and message.payload == "reserved game command"
doAssert commands == 1
client.accept(RoomMessage(kind: TickPacket, match: 2, tick: 2,
  seats: client.snapshot.seats,
  commands: @[Command(participant: 7, seat: 0, sequence: 2,
    payload: "reserved game command")]).encode)
doAssert not client.hasPendingCommand(0)
doAssert client.takeTick(packet) and packet.tick == 2
client.appliedTick(2)

client.accept(RoomMessage(
  kind: MatchStatus, match: client.match, phase: Waiting,
  flag: true, tick: client.applied, detail: "Paused"
).encode())
doAssert client.snapshot.flag
client.accept(RoomMessage(
  kind: MatchStatus, match: client.match, phase: Waiting,
  flag: false, tick: client.applied, detail: "Waiting for hashes"
).encode())
doAssert not client.snapshot.flag

block discardedReceipts:
  echo "Testing discarded command acknowledgement and subsequent submissions"
  let revoked = RoomClient(participant: 7, match: 2,
    began: true, welcomed: true,
    snapshot: RoomMessage(phase: Playing,
      seats: @[Seat(owner: 7, name: "Player")]))
  doAssert revoked.submit(0, "in flight during reassignment")
  doAssert revoked.hasPendingCommand(0)
  let discarded = RoomMessage(kind: CommandAck,
    match: 2, sequence: 1, tick: 0, flag: true)
  revoked.accept(discarded.encode)
  revoked.accept(discarded.encode)
  doAssert not revoked.hasPendingCommand(0)
  doAssert revoked.rejectedCommands == 1
  var rejected: RoomMessage
  doAssert revoked.takeRejected(rejected)
  doAssert rejected.kind == SubmitCommand and rejected.sequence == 1
  doAssert rejected.payload == "in flight during reassignment"
  doAssert rejected.seatKind == HumanSeat
  doAssert not revoked.takeRejected(rejected)
  revoked.outgoing.setLen(0)
  revoked.snapshot.seats[0].kind = BotSeat
  doAssert revoked.submit(0, "next authorized command")
  doAssert decode(revoked.outgoing[^1]).sequence == 2
  doAssert decode(revoked.outgoing[^1]).seatKind == BotSeat
  revoked.lost()
  revoked.opened()
  revoked.accept(RoomMessage(kind: Welcome, participant: 7).encode)
  var resumed = 0
  for bytes in revoked.outgoing:
    let message = decode(bytes)
    if message.kind == SubmitCommand:
      doAssert message.sequence == 2
      inc resumed
  doAssert resumed == 1

block consumedEdgeDiscovery:
  echo "Testing bounded discovery at the consumed history edge"
  proc catchups(client: RoomClient): int =
    for bytes in client.outgoing:
      if decode(bytes).kind == Catchup: inc result

  # Controllers and seatless spectators both fetch history; neither fetching nor
  # polling may advance the simulation/receipt cursor on their behalf.
  for spectator in [false, true]:
    for paused in [false, true]:
      let edge = RoomClient(participant: 7, match: 2, began: true, welcomed: true)
      edge.snapshot = RoomMessage(kind: RoomState, room: "edge",
        phase: (if paused: Waiting else: Playing), flag: paused)
      if not spectator: edge.snapshot.seats = @[Seat(owner: 7, name: "Human")]
      for tick in 1'u32 .. 2'u32:
        edge.accept(RoomMessage(kind: TickPacket, match: 2, tick: tick).encode)
      var packet: RoomMessage
      doAssert edge.applied == 0
      doAssert edge.takeTick(packet) and packet.tick == 1
      edge.appliedTick(packet.tick)
      doAssert edge.catchups == 0, "Do not fetch while a contiguous buffer remains"
      doAssert edge.takeTick(packet) and packet.tick == 2
      edge.appliedTick(packet.tick)
      doAssert edge.serverTick == edge.applied
      doAssert edge.catchups == 1, "Exhausting a stale known edge must discover history"
      doAssert edge.catchupPending
      doAssert not edge.catchingUp,
        "A live-edge request must not block game input"
      for frame in 0 ..< 200: doAssert not edge.takeTick(packet)
      doAssert edge.catchups == 1, "A pending request must suppress duplicates"
      edge.accept(RoomMessage(kind: CaughtUp, match: 2, tick: 2, number: 2).encode)
      doAssert not edge.catchupPending
      doAssert not edge.catchingUp
      for frame in 0 ..< 200: doAssert not edge.takeTick(packet)
      doAssert edge.catchups == 1, "An empty CaughtUp reply must not cause polling loops"
      doAssert edge.applied == 2
      edge.accept(RoomMessage(kind: TickPacket, match: 2, tick: 3).encode)
      doAssert edge.applied == 2, "Receiving history must not auto-advance spectators"
      doAssert edge.takeTick(packet) and packet.tick == 3
      edge.appliedTick(packet.tick)
      doAssert edge.catchups == 2, "New applied progress permits one new edge probe"

  # Ended matches still drain known final history but need no speculative probe
  # once the final advertised tick has been applied.
  let ended = RoomClient(match: 2, began: true, welcomed: true)
  ended.snapshot = RoomMessage(kind: RoomState, phase: Ended)
  ended.accept(RoomMessage(kind: MatchStatus, match: 2, phase: Ended, tick: 2).encode)
  ended.accept(RoomMessage(kind: TickPacket, match: 2, tick: 1).encode)
  var packet: RoomMessage
  doAssert ended.takeTick(packet)
  ended.appliedTick(packet.tick)
  doAssert ended.catchups == 1
  ended.accept(RoomMessage(kind: TickPacket, match: 2, tick: 2).encode)
  ended.accept(RoomMessage(kind: CaughtUp, match: 2, tick: 2, number: 2).encode)
  doAssert ended.takeTick(packet)
  ended.appliedTick(packet.tick)
  for frame in 0 ..< 200: doAssert not ended.takeTick(packet)
  doAssert ended.catchups == 1

  for phase in [Lobby, Desynced]:
    let idle = RoomClient(match: 2, began: true, welcomed: true,
      snapshot: RoomMessage(phase: phase))
    idle.appliedTick(1)
    doAssert idle.catchups == 0
  for began in [false, true]:
    let idle = RoomClient(match: (if began: 2'u32 else: 0'u32), began: began,
      welcomed: false, snapshot: RoomMessage(phase: Playing))
    idle.appliedTick(1)
    doAssert idle.catchups == 0
  let noMatch = RoomClient(welcomed: true, snapshot: RoomMessage(phase: Playing))
  noMatch.appliedTick(1)
  doAssert noMatch.catchups == 0
  echo "Consumed-edge discovery is bounded and preserves playback authority"

block recoveryState:
  echo "Testing initial, reconnect and incomplete history recovery"
  let history = RoomClient(participant: 7, welcomed: true,
    snapshot: RoomMessage(room: "history", phase: Playing))
  var initial = RoomMessage(kind: BeginMatch, match: 3, room: "history",
    revision: 1, tickRate: 24, payload: "{}",
    seats: @[Seat(owner: 7, name: "Human")],
    participants: @[Participant(id: 7, name: "Player")])
  initial.hash = setupHash(initial)
  history.accept(initial.encode)
  doAssert history.setupSnapshot().payload == "{}"
  var changedInitial = initial
  changedInitial.payload = "{\"changed\":true}"
  changedInitial.hash = setupHash(changedInitial)
  var changedSetupRejected = false
  try:
    history.accept(changedInitial.encode)
  except RoomsError:
    changedSetupRejected = true
  doAssert changedSetupRejected,
    "Reconnect must not replace an established initial setup"
  doAssert history.setupSnapshot().payload == "{}"
  history.requestHistory()
  doAssert history.catchingUp
  for tick in 1'u32 .. 2'u32:
    history.accept(RoomMessage(kind: TickPacket, match: 3, tick: tick).encode)
  history.accept(RoomMessage(kind: CaughtUp, match: 3, tick: 2, number: 2).encode)
  doAssert history.catchingUp,
    "Receiving a recovery reply does not apply its history"
  var packet: RoomMessage
  for tick in 1'u32 .. 2'u32:
    doAssert history.takeTick(packet) and packet.tick == tick
    history.appliedTick(tick)
  doAssert not history.catchingUp and history.catchupPending,
    "Reaching the recovery target permits play during the next edge probe"
  history.accept(RoomMessage(kind: CaughtUp, match: 3, tick: 2, number: 2).encode)

  history.lost()
  doAssert history.catchingUp
  history.opened()
  history.accept(RoomMessage(kind: Welcome, participant: 7).encode)
  doAssert history.catchingUp,
    "Reconnect must await history even before the repeated BeginMatch"
  history.accept(initial.encode)
  history.accept(RoomMessage(kind: CaughtUp, match: 3, tick: 2, number: 2).encode)
  doAssert not history.catchingUp

  # A missing known tick upgrades even an already pending probe to recovery.
  history.requestHistory(recovery = false)
  doAssert not history.catchingUp
  history.accept(RoomMessage(kind: TickPacket, match: 3, tick: 4).encode)
  doAssert not history.takeTick(packet) and history.catchingUp
  history.accept(RoomMessage(kind: TickPacket, match: 3, tick: 3).encode)
  history.accept(RoomMessage(kind: CaughtUp, match: 3, tick: 4, number: 4).encode)
  for tick in 3'u32 .. 4'u32:
    doAssert history.takeTick(packet) and packet.tick == tick
    history.appliedTick(tick)
  doAssert not history.catchingUp and history.catchupPending

  # A speculative probe can discover a larger history than one bounded batch.
  for tick in 5'u32 .. 20'u32:
    history.accept(RoomMessage(kind: TickPacket, match: 3, tick: tick).encode)
  history.accept(RoomMessage(kind: CaughtUp,
    match: 3, tick: 20, number: 24).encode)
  doAssert history.catchingUp
  for tick in 5'u32 .. 20'u32:
    doAssert history.takeTick(packet) and packet.tick == tick
    history.appliedTick(tick)
  doAssert history.catchingUp and history.catchupPending
  for tick in 21'u32 .. 24'u32:
    history.accept(RoomMessage(kind: TickPacket, match: 3, tick: tick).encode)
  history.accept(RoomMessage(kind: CaughtUp,
    match: 3, tick: 24, number: 24).encode)
  doAssert history.catchingUp
  for tick in 21'u32 .. 24'u32:
    doAssert history.takeTick(packet) and packet.tick == tick
    history.appliedTick(tick)
  doAssert not history.catchingUp
  history.accept(RoomMessage(kind: RoomState, phase: Lobby).encode)
  doAssert not history.catchingUp and not history.catchupPending
  echo "Only missing history blocks gameplay during recovery"
