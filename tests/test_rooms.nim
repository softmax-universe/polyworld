import polyworld/[rooms, relays]

proc expectError(relay: Relay, connection: int, message: RoomMessage) =
  ## Checks invalid client operations without hiding unexpected failures.
  var rejected = false
  try:
    relay.receive(connection, message, 0)
  except RoomsError:
    rejected = true
  doAssert rejected

proc flush(relay: Relay) =
  ## Emulates receivers acknowledging transport deliveries.
  let outgoing = relay.outgoing
  relay.outgoing = @[]
  for output in outgoing:
    var connected = false
    for guest in relay.guests:
      if guest.connection == output.connection:
        connected = true
    if connected and output.bytes.len > 0 and not output.close:
      let message = decode(output.bytes)
      if message.delivery > 0:
        relay.receive(output.connection, RoomMessage(
          kind: Received, sequence: message.delivery
        ), 0)

proc connect(relay: Relay, connection: int, game: string): uint32 =
  ## Identifies a synthetic game without loading any game modules.
  relay.receive(connection, RoomMessage(
    kind: Hello, identity: GameIdentity(game: game, gameplay: 7, protocol: 1),
    name: "Guest " & $connection
  ), 0)
  result = decode(relay.outgoing[^1].bytes).participant
  relay.flush()

proc send(relay: Relay, connection: int, message: RoomMessage) =
  ## Exercises binary serialization for every synthetic client command.
  let decoded = decode(message.encode())
  doAssert decoded == message
  relay.receive(connection, decoded, 0)
  relay.flush()

proc start(relay: Relay, connection: int, room: RelayRoom) =
  ## Starts from the current shared setup without any readiness gate.
  relay.send(connection, RoomMessage(kind: StartMatch,
    revision: room.revision, hash: setupHash(relay.state(room))))

echo "Testing generic room envelopes and authoritative ticks"
var relay = Relay()
let
  first = relay.connect(1, "test-chess")
  second = relay.connect(2, "test-chess")
  different = relay.connect(3, "test-racing")
relay.send(1, RoomMessage(
  kind: CreateRoom, name: "Chess", flag: true, tickRate: 24,
  number: 2, payload: "\x00\xffopaque setup"
))
let room = relay.rooms[0]
relay.expectError(3, RoomMessage(kind: JoinRoom, room: room.id))
relay.send(2, RoomMessage(kind: JoinRoom, room: room.id))
relay.send(1, RoomMessage(kind: ClaimSeat, seat: 0, name: "Human"))
relay.send(2, RoomMessage(kind: ClaimSeat, seat: 1, name: "Private bot", seatKind: BotSeat))
relay.expectError(2, RoomMessage(kind: ClaimSeat, seat: 0, name: "Steal"))
relay.send(1, RoomMessage(kind: ReadyStatus, flag: true))
relay.expectError(2, RoomMessage(kind: ConfigureRoom, number: 2))
relay.send(1, RoomMessage(
  kind: ConfigureRoom, name: "Chess", number: 2, tickRate: 24, payload: "new"
))
relay.expectError(1, RoomMessage(kind: StartMatch,
  revision: room.revision - 1, hash: setupHash(relay.state(room))))
relay.start(1, room)
doAssert room.phase == Playing
# A revoked or foreign slot discards the command while retaining its receipt.
let discarded = RoomMessage(
  kind: SubmitCommand, match: room.match, seat: 1, sequence: 1,
  payload: "in-flight command"
)
for attempt in 0 .. 1:
  relay.receive(1, decode(discarded.encode()), 0)
  var acknowledged = false
  for output in relay.outgoing:
    if output.connection == 1 and output.bytes.len > 0:
      let message = decode(output.bytes)
      if message.kind == CommandAck:
        doAssert message.sequence == 1 and message.flag and message.tick == 0
        acknowledged = true
  doAssert acknowledged and room.pending.len == 0
  relay.flush()
var changedDiscard = discarded
changedDiscard.payload = "altered discarded command"
relay.expectError(1, changedDiscard)
changedDiscard = discarded
changedDiscard.seatKind = BotSeat
relay.expectError(1, changedDiscard)
for connection in [2, 1]:
  relay.send(connection, RoomMessage(
    kind: SubmitCommand, match: room.match, seat: uint32(connection - 1),
    seatKind: (if connection == 2: BotSeat else: HumanSeat),
    sequence: (if connection == 1: 2'u64 else: 1'u64),
    payload: "\x00\xffgame bytes " & $connection
  ))
relay.send(1, RoomMessage(
  kind: SubmitCommand, match: room.match, seat: 0,
  sequence: 2, payload: "\x00\xffgame bytes 1"
))
doAssert room.pending.len == 2
relay.expectError(1, RoomMessage(
  kind: SubmitCommand, match: room.match, seat: 0,
  sequence: 2, payload: "changed retransmission"
))
relay.advance(0.05)
relay.flush()
doAssert room.tick == 1
let packet = decode(room.history[0])
doAssert packet.commands[0].participant == second
doAssert packet.commands[0].seatKind == BotSeat
doAssert packet.commands[1].seatKind == HumanSeat
doAssert packet.seats == room.seats
doAssert packet.commands[1].participant == first
doAssert packet.commands[1].sequence == 2
relay.advance(0.1)
relay.flush()
doAssert room.tick == 2 and decode(room.history[1]).commands.len == 0
let token = relay.guest(first).token
relay.disconnect(1)
doAssert room.phase == Playing
relay.receive(3, RoomMessage(kind: Keepalive), 0.15)
relay.advance(0.15)
doAssert room.tick == 3
relay.receive(1, RoomMessage(
  kind: Hello, identity: GameIdentity(game: "test-chess", gameplay: 7, protocol: 1),
  name: "Restored", token: token
), 0.15)
relay.flush()
doAssert relay.guest(first).connection == 1
relay.send(1, RoomMessage(kind: Catchup, match: room.match, tick: 0))
relay.send(1, RoomMessage(kind: AppliedTick, match: room.match, tick: 2))
# The other client may also reconnect while ticks continue.
relay.disconnect(2)
relay.receive(2, RoomMessage(
  kind: Hello, identity: GameIdentity(game: "test-chess", gameplay: 7, protocol: 1),
  name: "Restored", token: relay.guest(second).token
), 0.15)
relay.flush()
relay.send(2, RoomMessage(kind: AppliedTick, match: room.match, tick: 2))
relay.advance(0.2)
relay.flush()
doAssert room.phase == Playing
for tick in room.tick + 1 .. 24'u32:
  relay.advance(float64(tick) / 10.0)
  relay.flush()
  for connection in 1 .. 2:
    relay.send(connection, RoomMessage(
      kind: AppliedTick, match: room.match, tick: room.tick
    ))
# Keepalives use synthetic zero time, so prevent heartbeat timeout in this loop.
doAssert room.tick == 24
relay.send(1, RoomMessage(kind: ReportHash, match: room.match, tick: 24, hash: 10))
relay.send(2, RoomMessage(kind: ReportHash, match: room.match, tick: 24, hash: 11))
relay.advance(2.5)
doAssert room.phase == Desynced
relay.flush()
relay.send(3, RoomMessage(
  kind: CreateRoom, name: "Racing", number: 1, tickRate: 60,
  payload: "\x01totally different configuration"
))
let race = relay.rooms[1]
relay.send(3, RoomMessage(kind: ClaimSeat, seat: 0, name: "Car"))
relay.start(3, race)
relay.send(3, RoomMessage(kind: ReportHash, match: race.match, tick: 0, hash: 55))
relay.advance(0.02)
doAssert race.tick == 1
for length in 0 ..< 24:
  var failed = false
  try:
    discard decode(newString(length))
  except RoomsError:
    failed = true
  doAssert failed
var malformed = RoomMessage(kind: Keepalive).encode()
malformed.add 'x'
var failed = false
try:
  discard decode(malformed)
except RoomsError:
  failed = true
doAssert failed
# A second exact version cannot join an existing room.
relay.receive(4, RoomMessage(
  kind: Hello, identity: GameIdentity(game: "test-racing", gameplay: 8, protocol: 1),
  name: "Wrong version"
), 0)
relay.flush()
relay.expectError(4, RoomMessage(kind: JoinRoom, room: race.id))
echo "Room protocol, ordering, reconnect, empty ticks and desync checks passed"

# A missing hash never blocks the timeline.
relay.send(3, RoomMessage(kind: AppliedTick, match: race.match, tick: 1))
for tick in 2'u32 .. 60'u32:
  relay.advance(float64(tick) / 10)
  relay.flush()
  relay.send(3, RoomMessage(
    kind: AppliedTick, match: race.match, tick: race.tick
  ))
doAssert race.tick == 60
relay.advance(6.1)
relay.flush()
doAssert race.tick == 61 and race.phase == Playing
relay.send(3, RoomMessage(
  kind: ReportHash, match: race.match, tick: 60, hash: 123
))
relay.advance(6.2)
relay.flush()
doAssert race.phase == Playing
# Late spectators are compared with immutable historical hash checkpoints.
discard relay.connect(5, "test-racing")
relay.send(5, RoomMessage(kind: JoinRoom, room: race.id))
relay.send(5, RoomMessage(
  kind: ReportHash, match: race.match, tick: 0, hash: 55
))
relay.send(5, RoomMessage(
  kind: ReportHash, match: race.match, tick: 60, hash: 124
))
doAssert race.phase == Desynced
let stoppedTick = race.tick
relay.advance(6.3)
doAssert race.tick == stoppedTick

# Starting another match cannot preserve old simulation checkpoints.
relay.send(3, RoomMessage(kind: ReturnLobby))
relay.start(3, race)
relay.send(3, RoomMessage(
  kind: ReportHash, match: race.match, tick: 0, hash: 999
))
doAssert race.phase == Playing
# Exhausted queues fail visibly instead of dropping accepted commands.
for sequence in 1 .. MaxCommandsPerTick + 1:
  relay.send(3, RoomMessage(
    kind: SubmitCommand, match: race.match, seat: 0,
    sequence: uint64(sequence), payload: "x"
  ))
doAssert race.phase == Desynced

echo "Startup, asynchronous historical and final hash checks passed"

relay = Relay()
discard relay.connect(1, "test-puzzle")
discard relay.connect(2, "test-puzzle")
relay.send(1, RoomMessage(
  kind: CreateRoom, name: "Hash checks", number: 2, tickRate: 24
))
let hashRoom = relay.rooms[0]
relay.send(2, RoomMessage(kind: JoinRoom, room: hashRoom.id))
for connection in 1 .. 2:
  relay.send(connection, RoomMessage(
    kind: ClaimSeat, seat: uint32(connection - 1), name: "Seat"
  ))
relay.start(1, hashRoom)
for connection in 1 .. 2:
  relay.send(connection, RoomMessage(kind: ReportHash,
    match: hashRoom.match, tick: 0, hash: uint64(connection)))
doAssert hashRoom.phase == Desynced and hashRoom.tick == 0
relay.send(1, RoomMessage(kind: ReturnLobby))
relay.start(1, hashRoom)
for connection in 1 .. 2:
  relay.send(connection, RoomMessage(kind: ReportHash,
    match: hashRoom.match, tick: 0, hash: 1))
relay.advance(0.05)
relay.flush()
relay.send(1, RoomMessage(
  kind: FinishMatch, match: hashRoom.match, tick: 1, hash: 20
))
relay.send(2, RoomMessage(
  kind: FinishMatch, match: hashRoom.match, tick: 1, hash: 21
))
doAssert hashRoom.phase == Desynced

# A valid reconnect token can replace a half-open socket before its close event.
let
  oldToken = relay.guest(hashRoom.owner).token
  oldName = relay.guest(hashRoom.owner).name
relay.receive(9, RoomMessage(
  kind: Hello, identity: hashRoom.identity, name: "Restored", token: oldToken
), 0)
doAssert relay.guest(hashRoom.owner).connection == 9
doAssert relay.guest(hashRoom.owner).name == oldName
doAssert relay.guest(hashRoom.owner).token == oldToken
relay.disconnect(1)
doAssert relay.guest(hashRoom.owner).connection == 9
relay.flush()

# The live roster releases departed controllers, while initial setup stays fixed.
let historicalSeats = @[hashRoom.seats[0], hashRoom.seats[1]]
relay.send(2, RoomMessage(kind: LeaveRoom))
doAssert hashRoom.seats[1].owner == 0
discard relay.connect(8, "test-puzzle")
relay.receive(8, RoomMessage(kind: JoinRoom, room: hashRoom.id), 0)
var receivedInitial = false
for output in relay.outgoing:
  if output.connection == 8 and output.bytes.len > 0:
    let message = decode(output.bytes)
    if message.kind == BeginMatch:
      doAssert message.seats == historicalSeats
      doAssert message.hash == setupHash(message)
      receivedInitial = true
doAssert receivedInitial
relay.flush()
relay.send(9, RoomMessage(kind: ReturnLobby))
doAssert hashRoom.seats[1].owner == 0
# Reconnection preserves setup only while another connected watcher keeps it alive.
discard relay.connect(11, "test-puzzle")
relay.send(11, RoomMessage(kind: JoinRoom, room: hashRoom.id))
let
  lobbySeats = hashRoom.seats
  lobbyRevision = hashRoom.revision
relay.disconnect(9)
relay.receive(10, RoomMessage(
  kind: Hello, identity: hashRoom.identity, name: "Restored", token: oldToken
), 0)
doAssert relay.guest(hashRoom.owner).name == "Restored"
doAssert hashRoom.seats == lobbySeats
doAssert hashRoom.revision == lobbyRevision + 1

# Explicit pause freezes the timeline; hash comparisons remain asynchronous.
relay = Relay()
let pauseOwner = relay.connect(1, "pause-test")
discard relay.connect(2, "pause-test")
relay.send(1, RoomMessage(
  kind: CreateRoom, name: "Pause test", number: 1, tickRate: 1
))
let pausedRoom = relay.rooms[0]
relay.send(1, RoomMessage(kind: ClaimSeat, seat: 0, name: "Bot", seatKind: BotSeat))
relay.send(2, RoomMessage(kind: JoinRoom, room: pausedRoom.id))
relay.start(1, pausedRoom)
relay.send(1, RoomMessage(kind: ReportHash,
  match: pausedRoom.match, tick: 0, hash: 10))
relay.expectError(2, RoomMessage(
  kind: PauseMatch, match: pausedRoom.match, flag: true
))
relay.expectError(1, RoomMessage(kind: PauseMatch, match: 999, flag: true))
relay.advance(1.1)
relay.flush()
doAssert pausedRoom.tick == 1
relay.send(1, RoomMessage(
  kind: PauseMatch, match: pausedRoom.match, flag: true
))
doAssert pausedRoom.paused and pausedRoom.phase == Waiting
relay.send(1, RoomMessage(
  kind: AppliedTick, match: pausedRoom.match, tick: 1
))
relay.advance(2)
relay.flush()
doAssert pausedRoom.tick == 1
# Unpausing resumes without waiting for a missing hash.
relay.send(1, RoomMessage(
  kind: PauseMatch, match: pausedRoom.match, flag: false
))
relay.advance(3)
relay.flush()
doAssert pausedRoom.tick == 1 and pausedRoom.phase == Playing
relay.send(1, RoomMessage(
  kind: ReportHash, match: pausedRoom.match, tick: 1, hash: 11
))
relay.send(1, RoomMessage(
  kind: PauseMatch, match: pausedRoom.match, flag: true
))
# Pending commands remain assigned to the next tick during pause.
relay.send(1, RoomMessage(
  kind: SubmitCommand, match: pausedRoom.match, seat: 0,
  seatKind: BotSeat, sequence: 1, payload: "pending"
))
let reconnectToken = relay.guest(pauseOwner).token
relay.disconnect(1)
relay.advance(4)
relay.flush()
relay.receive(3, RoomMessage(
  kind: Hello, identity: pausedRoom.identity,
  name: "Reconnected", token: reconnectToken
), 4)
relay.flush()
relay.send(3, RoomMessage(
  kind: AppliedTick, match: pausedRoom.match, tick: 1
))
relay.advance(5)
relay.flush()
doAssert pausedRoom.paused and pausedRoom.tick == 1
let pausedState = relay.state(pausedRoom)
doAssert decode(pausedState.encode()).flag
relay.send(3, RoomMessage(
  kind: PauseMatch, match: pausedRoom.match, flag: false
))
relay.advance(6)
relay.flush()
doAssert pausedRoom.phase == Playing and pausedRoom.tick == 1
relay.advance(7.1)
relay.flush()
doAssert pausedRoom.tick == 2
let afterPause = decode(pausedRoom.history[1])
doAssert afterPause.commands.len == 1
doAssert afterPause.commands[0].payload == "pending"
relay.send(3, RoomMessage(
  kind: PauseMatch, match: pausedRoom.match, flag: true
))
relay.send(3, RoomMessage(
  kind: ReportHash, match: pausedRoom.match, tick: 2, hash: 12
))
relay.send(2, RoomMessage(
  kind: ReportHash, match: pausedRoom.match, tick: 2, hash: 13
))
doAssert pausedRoom.phase == Desynced
relay.expectError(3, RoomMessage(
  kind: PauseMatch, match: pausedRoom.match, flag: false
))
relay.send(3, RoomMessage(kind: ReturnLobby))
doAssert not pausedRoom.paused

# Boolean values and old outer versions cannot silently change pause meaning.
var badPause = RoomMessage(kind: PauseMatch, flag: true).encode()
badPause[RoomHeaderBytes] = char(2)
var rejectedPause = false
try:
  discard decode(badPause)
except RoomsError:
  rejectedPause = true
doAssert rejectedPause
badPause = RoomMessage(kind: Keepalive).encode()
badPause[4] = char(1)
rejectedPause = false
try:
  discard decode(badPause)
except RoomsError:
  rejectedPause = true
doAssert rejectedPause

echo "Pause, resume, reconnect and asynchronous hash checks passed"
