import
  std/importutils,
  polyworld/[rooms, relays, roomclients]

privateAccess(RelayRoom)

const GenericIdentity = GameIdentity(
  game: "unregistered-game/any-rules", gameplay: 0, protocol: 0)

type GenericFixture = object
  relay: Relay
  room: RelayRoom

proc drain(fixture: GenericFixture): seq[RoomMessage] =
  ## Acknowledges bounded deliveries while retaining their decoded contents.
  let outputs = fixture.relay.outgoing
  fixture.relay.outgoing = @[]
  for output in outputs:
    if output.bytes.len == 0 or output.close:
      continue
    let message = decode(output.bytes)
    result.add message
    if message.delivery > 0:
      fixture.relay.receive(output.connection,
        RoomMessage(kind: Received, sequence: message.delivery), 0)

proc send(fixture: GenericFixture, connection: int, message: RoomMessage) =
  ## Exercises wire decoding before dispatching a synthetic client operation.
  fixture.relay.receive(connection, decode(message.encode()), 0)

proc expectRejected(fixture: GenericFixture, connection: int,
    message: RoomMessage) =
  ## Requires invalid administration to fail without hiding other errors.
  var rejected = false
  try:
    fixture.send(connection, message)
  except RoomsError:
    rejected = true
  doAssert rejected

proc newGenericFixture(payload = "{\"arbitrary\":[1,null,\"duration-is-private\"]}",
    occupied = true): GenericFixture =
  ## Creates an unregistered game with three identified room participants.
  result.relay = Relay()
  for connection in 1 .. 3:
    result.send(connection, RoomMessage(kind: Hello, identity: GenericIdentity,
      name: "Participant " & $connection))
    discard result.drain()
  result.send(1, RoomMessage(kind: CreateRoom, name: "Opaque configuration",
    number: 3, tickRate: 24, payload: payload))
  result.room = result.relay.rooms[0]
  for connection in 2 .. 3:
    result.send(connection, RoomMessage(kind: JoinRoom, room: result.room.id))
  if occupied:
    result.send(1, RoomMessage(kind: ClaimSeat, seat: 0,
      seatKind: HumanSeat, name: "Host"))
    result.send(2, RoomMessage(kind: ClaimSeat, seat: 1,
      seatKind: BotSeat, name: "Human"))
  discard result.drain()

proc start(fixture: GenericFixture) =
  ## Starts immediately from only the immutable shared initialization hash.
  let snapshot = fixture.relay.state(fixture.room)
  fixture.send(1, RoomMessage(kind: StartMatch, revision: snapshot.revision,
    hash: snapshot.setupHash()))
  discard fixture.drain()

proc latestAck(messages: openArray[RoomMessage]): RoomMessage =
  ## Finds an acknowledgement emitted for the current synthetic operation.
  for i in countdown(messages.high, 0):
    if messages[i].kind == CommandAck:
      return messages[i]
  doAssert false, "Expected a command acknowledgement"

echo "Testing opaque initialization and uniform cosmetic readiness"
block:
  for payload in ["{}", "[false,null,{\"players\":\"private\"}]",
      "{\"diplomacySettings\":42,\"maxTicks\":999999999999999999}"]:
    let fixture = newGenericFixture(payload)
    var snapshot = fixture.relay.state(fixture.room)
    let original = snapshot.setupHash()
    snapshot.participants[0].ready = true
    snapshot.participants[1].connected = false
    doAssert snapshot.setupHash() == original
    snapshot.payload.add " "
    doAssert snapshot.setupHash() != original
    snapshot = fixture.relay.state(fixture.room)
    snapshot.seats[1].kind = HumanSeat
    doAssert snapshot.setupHash() != original
    snapshot = fixture.relay.state(fixture.room)
    snapshot.participants[1].name = "Renamed controller"
    doAssert snapshot.setupHash() != original
    fixture.relay.disconnect(2)
    discard fixture.drain()
    fixture.start()
    doAssert fixture.room.phase == Playing
    doAssert fixture.room.initial.payload == payload
    doAssert fixture.room.initial.hash == fixture.room.initial.setupHash()
    doAssert not fixture.relay.guest(1).ready
  let empty = newGenericFixture(occupied = false)
  empty.start()
  doAssert empty.room.phase == Playing

block:
  let fixture = newGenericFixture()
  fixture.send(2, RoomMessage(kind: ReadyStatus, flag: true))
  fixture.send(1, RoomMessage(kind: ConfigureRoom, name: "Changed",
    number: 3, tickRate: 24, payload: "{\"any-new-key\":true}"))
  doAssert fixture.relay.guest(2).ready
  fixture.expectRejected(2, RoomMessage(kind: ClaimSeat, seat: 0,
    name: "Steal the host", seatKind: BotSeat))
  fixture.expectRejected(2, RoomMessage(kind: ClaimSeat, seat: 2,
    participant: 3, name: "Assign another player", seatKind: HumanSeat))
  fixture.start()
  fixture.send(1, RoomMessage(kind: ClaimSeat, seat: 1, participant: 3,
    seatKind: HumanSeat, name: "A label is never a permission"))
  doAssert fixture.room.seats[1].owner == 3
  fixture.expectRejected(2, RoomMessage(kind: ReleaseSeat, seat: 1))
  fixture.send(1, RoomMessage(kind: ReleaseSeat, seat: 1))
  fixture.send(2, RoomMessage(kind: ClaimSeat, seat: 1,
    seatKind: BotSeat, name: "Human"))
  fixture.send(2, RoomMessage(kind: ClaimSeat, seat: 2,
    seatKind: BotSeat, name: "Second owned policy"))
  doAssert fixture.room.seats[1].kind == BotSeat
  doAssert fixture.room.seats[2].owner == 2
  fixture.send(2, RoomMessage(kind: ReleaseSeat, seat: 2))
  doAssert fixture.room.seats[2] == Seat()

echo "Testing tick-stamped ownership and revoked command receipts"
block:
  let fixture = newGenericFixture()
  fixture.start()
  let immutable = fixture.room.initial
  fixture.send(2, RoomMessage(kind: SubmitCommand, seatKind: BotSeat,
    match: fixture.room.match,
    seat: 1, sequence: 1, payload: "old controller accepted before transfer"))
  fixture.send(1, RoomMessage(kind: ClaimSeat, seat: 1, participant: 3,
    seatKind: HumanSeat, name: "Replacement"))
  fixture.send(3, RoomMessage(kind: SubmitCommand, match: fixture.room.match,
    seat: 1, sequence: 1, payload: "new controller accepted after transfer"))
  discard fixture.drain()
  fixture.send(2, RoomMessage(kind: SubmitCommand, seatKind: BotSeat,
    match: fixture.room.match,
    seat: 1, sequence: 1, payload: "old controller accepted before transfer"))
  let admittedAck = fixture.drain().latestAck()
  doAssert not admittedAck.flag and admittedAck.tick == 1
  fixture.send(2, RoomMessage(kind: SubmitCommand, seatKind: BotSeat,
    match: fixture.room.match,
    seat: 1, sequence: 2, payload: "revoked in flight"))
  let rejectedAck = fixture.drain().latestAck()
  doAssert rejectedAck.flag and rejectedAck.tick == 0
  fixture.send(2, RoomMessage(kind: SubmitCommand, seatKind: BotSeat,
    match: fixture.room.match,
    seat: 1, sequence: 2, payload: "revoked in flight"))
  doAssert fixture.drain().latestAck().flag
  fixture.expectRejected(2, RoomMessage(kind: SubmitCommand,
    match: fixture.room.match, seat: 1, seatKind: BotSeat,
    sequence: 2, payload: "changed retry"))
  fixture.send(2, RoomMessage(kind: ClaimSeat, seat: 2,
    seatKind: BotSeat, name: "New owned slot"))
  fixture.send(2, RoomMessage(kind: SubmitCommand, seatKind: BotSeat,
    match: fixture.room.match,
    seat: 2, sequence: 3, payload: "stream continues after rejection"))
  fixture.relay.advance(0.05)
  discard fixture.drain()
  let packet = decode(fixture.room.history[0])
  doAssert packet.commands.len == 3
  doAssert packet.commands[0].participant == 2
  doAssert packet.commands[0].seatKind == BotSeat
  doAssert packet.commands[1].participant == 3
  doAssert packet.commands[1].seatKind == HumanSeat
  doAssert packet.commands[2].sequence == 3
  doAssert packet.seats[1].owner == 3
  doAssert fixture.room.initial == immutable
  var client = RoomClient(snapshot: fixture.relay.state(fixture.room))
  client.accept(immutable.encode())
  doAssert client.setupSnapshot().seats[1].owner == 2
  doAssert client.appliedSeats[1].owner == 2
  client.accept(packet.encode())
  var taken: RoomMessage
  doAssert client.takeTick(taken)
  doAssert client.appliedSeats[1].owner == 2
  client.appliedTick(taken.tick)
  doAssert client.appliedSeats[1].owner == 3
  doAssert client.setupSnapshot() == immutable

block:
  let fixture = newGenericFixture()
  fixture.start()
  let initial = fixture.room.initial
  fixture.send(1, RoomMessage(kind: ClaimSeat, seat: 1, participant: 3,
    seatKind: HumanSeat, name: "Later owner"))
  fixture.send(3, RoomMessage(kind: LeaveRoom))
  discard fixture.drain()
  fixture.send(3, RoomMessage(kind: JoinRoom, room: fixture.room.id))
  let messages = fixture.drain()
  var found = false
  for message in messages:
    if message.kind == BeginMatch:
      found = true
      doAssert message.payload == initial.payload
      doAssert message.seats == initial.seats
      doAssert message.participants == initial.participants
      doAssert message.hash == initial.hash
  doAssert found
  doAssert fixture.room.seats[1].owner == 0

block:
  let fixture = newGenericFixture()
  fixture.start()
  fixture.send(2, RoomMessage(kind: SubmitCommand, seatKind: BotSeat,
    match: fixture.room.match,
    seat: 1, sequence: 1, payload: "finishing action"))
  fixture.send(1, RoomMessage(kind: ReleaseSeat, seat: 1))
  fixture.relay.advance(0.05)
  discard fixture.drain()
  doAssert fixture.room.seats[1].owner == 0
  fixture.send(2, RoomMessage(kind: FinishMatch, match: fixture.room.match,
    tick: 1, hash: 123))
  fixture.send(2, RoomMessage(kind: LeaveRoom))
  fixture.relay.advance(0.1)
  discard fixture.drain()
  doAssert fixture.room.phase == Ended

block:
  let fixture = newGenericFixture()
  fixture.start()
  fixture.room.historyBytes = MaxHistoryBytes - 64
  fixture.relay.advance(0.05)
  discard fixture.drain()
  doAssert fixture.room.phase == Desynced
  doAssert fixture.room.tick == 0 and fixture.room.history.len == 0
  fixture.send(3, RoomMessage(kind: Catchup, match: fixture.room.match, tick: 0))
  discard fixture.drain()

block:
  let fixture = newGenericFixture()
  fixture.start()
  var client = RoomClient(participant: 1, welcomed: true,
    snapshot: fixture.relay.state(fixture.room))
  client.accept(fixture.room.initial.encode())
  client.outgoing.setLen(0)
  doAssert client.submit(0, "human command racing a controller-kind change")
  let submitted = decode(client.outgoing[^1])
  doAssert submitted.kind == SubmitCommand and submitted.seatKind == HumanSeat
  client.outgoing.setLen(0)
  fixture.send(1, RoomMessage(kind: ClaimSeat, seat: 0, participant: 1,
    seatKind: BotSeat, name: "Same owner, different controller"))
  discard fixture.drain()
  fixture.send(1, submitted)
  var acknowledgement = fixture.drain().latestAck()
  doAssert acknowledgement.flag and fixture.room.pending.len == 0
  acknowledgement.delivery = 0
  acknowledgement.timing = PacketTiming()
  client.accept(acknowledgement.encode())
  var rejected: RoomMessage
  doAssert client.takeRejected(rejected)
  doAssert rejected == submitted
  doAssert not client.takeRejected(rejected)
  doAssert client.rejectedCommands == 1 and client.error.len == 0
  fixture.expectRejected(1, RoomMessage(kind: SubmitCommand,
    match: fixture.room.match, seat: 0, seatKind: BotSeat,
    sequence: 1, payload: submitted.payload))
  client.snapshot = fixture.relay.state(fixture.room)
  doAssert client.submit(0, "bot command after the canceled human command")
  let next = decode(client.outgoing[^1])
  doAssert next.sequence == 2 and next.seatKind == BotSeat
  fixture.send(1, next)
  fixture.relay.advance(0.05)
  discard fixture.drain()
  let packet = decode(fixture.room.history[0])
  doAssert packet.commands.len == 1
  doAssert packet.commands[0].sequence == 2
  doAssert packet.commands[0].seatKind == BotSeat
  client.accept(packet.encode())
  doAssert not client.takeRejected(rejected)

echo "Generic relay boundaries passed"
