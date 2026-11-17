import polyworld/[rooms, relays]

proc send(relay: Relay, connection: int, message: RoomMessage) =
  ## Exercise room operations through their encoded protocol envelope.
  relay.receive(connection, decode(message.encode()), 0)

proc lobby(game: string, ready = true): Relay =
  ## Give separate participants human and bot slots in one private room.
  result = Relay()
  for connection in 1 .. 3:
    result.send(connection, RoomMessage(kind: Hello,
      identity: GameIdentity(game: game, gameplay: 3, protocol: 1),
      name: "Guest " & $connection))
  result.send(1, RoomMessage(kind: CreateRoom, name: "Bot removal",
    number: 4, tickRate: 24, payload: "game-owned setup"))
  let room = result.rooms[0]
  for connection in 2 .. 3:
    result.send(connection, RoomMessage(kind: JoinRoom, room: room.id))
  result.send(1, RoomMessage(kind: ClaimSeat, seat: 0, name: "Human"))
  result.send(2, RoomMessage(kind: ClaimSeat, seat: 1, name: "Human"))
  result.send(2, RoomMessage(kind: ClaimSeat, seat: 2, name: "Guest bot"))
  result.send(3, RoomMessage(kind: ClaimSeat, seat: 3, name: "Other bot"))
  if ready:
    for connection in 1 .. 3:
      result.send(connection, RoomMessage(kind: Ready,
        revision: room.revision, hash: 42))
  result.outgoing.setLen(0)

proc expectUnchanged(relay: Relay, connection: int, message: RoomMessage) =
  ## Permission failures preserve every assignment and lobby setting.
  let before = relay.state(relay.rooms[0])
  let outgoing = relay.outgoing.len
  var rejected = false
  try:
    relay.send(connection, message)
  except RoomsError:
    rejected = true
  doAssert rejected
  doAssert relay.state(relay.rooms[0]) == before
  doAssert relay.outgoing.len == outgoing

for game in ["awm", "gods_of_the_arena"]:
  block:
    let
      relay = lobby(game)
      room = relay.rooms[0]
      before = relay.state(room)
    relay.send(1, RoomMessage(kind: ReleaseSeat, seat: 2))
    doAssert room.seats[2] == Seat()
    for index in [0, 1, 3]:
      doAssert room.seats[index] == before.seats[index]
    doAssert room.revision == before.revision + 1
    doAssert room.participants == @[1'u32, 2, 3]
    doAssert relay.guest(2).room == room.id
    doAssert not room.public
    doAssert relay.guest(1).ready and relay.guest(2).ready
    relay.expectUnchanged(1, RoomMessage(kind: StartMatch))

  block:
    let relay = lobby(game)
    relay.expectUnchanged(1, RoomMessage(kind: ReleaseSeat, seat: 1))
    relay.expectUnchanged(2, RoomMessage(kind: ReleaseSeat, seat: 3))
    relay.expectUnchanged(3, RoomMessage(kind: ReleaseSeat, seat: 2))
    relay.expectUnchanged(1,
      RoomMessage(kind: ClaimSeat, seat: 2, name: "Replacement bot"))

  for phase in [Playing, Waiting, Ended, Desynced]:
    let relay = lobby(game)
    relay.rooms[0].phase = phase
    relay.expectUnchanged(1, RoomMessage(kind: ReleaseSeat, seat: 2))

block:
  let relay = lobby("unrelated-game")
  relay.expectUnchanged(1, RoomMessage(kind: ReleaseSeat, seat: 2))

for readiness in [[false, false], [false, true], [true, false], [true, true]]:
  let
    relay = lobby("awm", ready = false)
    room = relay.rooms[0]
  relay.send(2, RoomMessage(kind: ReadyStatus, flag: readiness[0]))
  relay.send(3, RoomMessage(kind: ReadyStatus, flag: readiness[1]))
  doAssert not relay.guest(1).ready
  relay.send(1, RoomMessage(kind: StartMatch,
    revision: room.revision, hash: 42))
  doAssert room.phase == Playing
  doAssert not relay.guest(1).ready
  doAssert relay.guest(2).ready == readiness[0]
  doAssert relay.guest(3).ready == readiness[1]
  var starts = 0
  for outgoing in relay.outgoing:
    let message = decode(outgoing.bytes)
    if message.kind == BeginMatch:
      inc starts
      doAssert message.revision == room.revision
      doAssert message.hash == 42
  doAssert starts == 3
  relay.send(2, RoomMessage(kind: ReportHash,
    match: room.match, tick: 0, hash: 42))
  doAssert room.phase == Playing
  relay.send(3, RoomMessage(kind: ReportHash,
    match: room.match, tick: 0, hash: 43))
  doAssert room.phase == Desynced

block:
  let
    relay = lobby("awm", ready = false)
    room = relay.rooms[0]
  relay.expectUnchanged(2, RoomMessage(kind: StartMatch,
    revision: room.revision, hash: 42))
  relay.expectUnchanged(1, RoomMessage(kind: StartMatch,
    revision: room.revision - 1, hash: 42))
  relay.guest(2).connection = 0
  relay.expectUnchanged(1, RoomMessage(kind: StartMatch,
    revision: room.revision, hash: 42))

block:
  let
    relay = lobby("unrelated-game", ready = false)
    room = relay.rooms[0]
  relay.expectUnchanged(1, RoomMessage(kind: StartMatch,
    revision: room.revision, hash: 42))

echo "CaC starts with cosmetic readiness and validates its host checkpoint."
echo "CaC and GotA hosts preserve bot ownership rules."
