import std/unittest
import polyworld/[rooms, relays]

proc send(relay: Relay, connection: int, message: RoomMessage) =
  ## Exercises the wire envelope without loading a game.
  relay.receive(connection, decode(message.encode()), 0)

proc lobby(): Relay =
  ## Creates independent controllers and cosmetic readiness.
  result = Relay()
  for connection in 1 .. 2:
    result.send(connection, RoomMessage(
      kind: Hello, name: "Guest " & $connection,
      identity: GameIdentity(game: "resize-test", gameplay: 1, protocol: 1)
    ))
  result.send(1, RoomMessage(kind: CreateRoom, name: "Original", number: 3,
    tickRate: 24, payload: "{\"players\":\"game-owned\"}", flag: false))
  let room = result.rooms[0]
  result.send(2, RoomMessage(kind: JoinRoom, room: room.id))
  result.send(1, RoomMessage(kind: ClaimSeat, seat: 0, name: "Host"))
  result.send(2, RoomMessage(kind: ClaimSeat, seat: 1, name: "Guest bot",
    seatKind: BotSeat))
  for connection in 1 .. 2:
    result.send(connection, RoomMessage(kind: ReadyStatus, flag: true))
  result.outgoing = @[]

proc configure(count: uint32): RoomMessage =
  ## Replaces game-owned settings without exposing their schema.
  RoomMessage(kind: ConfigureRoom, name: "Resized", number: count,
    tickRate: 30, payload: "{\"teams\":[99],\"duration\":\"unbounded\"}",
    flag: true)

proc resize(room: RelayRoom, count: uint32): RoomMessage =
  ## Changes shared roster metadata while preserving the game setup.
  RoomMessage(kind: ResizeRoom, name: "Resized", number: count,
    tickRate: room.tickRate, payload: room.payload, flag: true)

proc start(relay: Relay) =
  ## Starts from the exact generic initialization envelope.
  let room = relay.rooms[0]
  relay.send(1, RoomMessage(kind: StartMatch, revision: room.revision,
    hash: relay.state(room).setupHash()))

proc expectUnchanged(relay: Relay, connection: int, message: RoomMessage) =
  ## Requires rejected operations to preserve state and outgoing deliveries.
  let
    room = relay.rooms[0]
    before = relay.state(room).encode()
    wasPublic = room.public
    outgoingCount = relay.outgoing.len
  expect RoomsError:
    relay.send(connection, message)
  check relay.state(room).encode() == before
  check room.public == wasPublic
  check relay.outgoing.len == outgoingCount

suite "Generic relay roster resize":
  test "owner grows with empty slots and preserves cosmetic readiness":
    let
      relay = lobby()
      room = relay.rooms[0]
      before = relay.state(room)
      message = configure(5)
    relay.send(1, message)
    check room.seats.len == 5
    check room.seats[0 ..< 3] == before.seats
    check room.seats[3 ..< 5] == @[Seat(), Seat()]
    check room.revision == before.revision + 1
    check room.payload == message.payload
    check room.name == message.name
    check room.tickRate == message.tickRate
    check room.public
    for id in room.participants:
      check relay.guest(id).ready
    check relay.outgoing.len == 2
    for output in relay.outgoing:
      let snapshot = decode(output.bytes)
      check snapshot.kind == RoomState
      check snapshot.seats == room.seats
      check snapshot.payload == message.payload
      check snapshot.revision == room.revision
      for participant in snapshot.participants:
        check participant.ready
    relay.send(1, RoomMessage(kind: ClaimSeat, seat: 4, name: "New bot",
      seatKind: BotSeat))
    check room.seats[4] == Seat(owner: room.owner, name: "New bot",
      kind: BotSeat)

  test "host may shrink away another controller's slots":
    let
      relay = lobby()
      room = relay.rooms[0]
      before = relay.state(room)
    relay.send(1, configure(1))
    check room.seats == @[before.seats[0]]
    check room.participants == @[1'u32, 2'u32]
    check room.revision == before.revision + 1
    relay.send(1, configure(3))
    check room.seats == @[before.seats[0], Seat(), Seat()]

  test "disconnected controllers do not prevent host roster management":
    let
      relay = lobby()
      room = relay.rooms[0]
    relay.disconnect(2)
    relay.send(1, configure(1))
    check room.seats.len == 1
    check room.seats[0].owner == 1

  test "growth accepts MaxSeats without changing old assignments":
    let
      relay = lobby()
      room = relay.rooms[0]
      before = relay.state(room)
    relay.send(1, configure(uint32(MaxSeats)))
    check room.seats.len == MaxSeats
    check room.seats[0 ..< 3] == before.seats
    for index in 3 ..< MaxSeats:
      check room.seats[index] == Seat()

  test "opaque JSON changes invalidate a stale start envelope":
    let
      relay = lobby()
      room = relay.rooms[0]
      before = relay.state(room)
    relay.send(1, configure(3))
    check room.seats == before.seats
    check relay.state(room).setupHash() != before.setupHash()
    relay.expectUnchanged(1, RoomMessage(kind: StartMatch,
      revision: before.revision, hash: before.setupHash()))
    relay.expectUnchanged(1, RoomMessage(kind: StartMatch,
      revision: room.revision, hash: before.setupHash()))
    relay.start()
    check room.phase == Playing

  test "invalid counts and settings leave the configuration untouched":
    for count in [0'u32, uint32(MaxSeats + 1), uint32.high]:
      let relay = lobby()
      relay.expectUnchanged(1, configure(count))
    for count in [2'u32, 3'u32, 5'u32]:
      for tickRate in [0'u32, 121'u32]:
        let relay = lobby()
        var message = configure(count)
        message.tickRate = tickRate
        relay.expectUnchanged(1, message)
      let relay = lobby()
      var message = configure(count)
      message.name = ""
      relay.expectUnchanged(1, message)

  test "nonowner cannot grow shrink or reconfigure":
    for count in [1'u32, 3'u32, 5'u32]:
      let relay = lobby()
      relay.expectUnchanged(2, configure(count))
      relay.expectUnchanged(2, resize(relay.rooms[0], count))

  test "host live resizing preserves the immutable initialization":
    let
      relay = lobby()
      room = relay.rooms[0]
      initial = relay.state(room)
    relay.start()
    relay.outgoing.setLen(0)
    relay.send(1, resize(room, 1))
    check room.phase == Playing
    check room.seats == @[initial.seats[0]]
    relay.advance(0.05)
    var ticks = 0
    for output in relay.outgoing:
      let packet = decode(output.bytes)
      if packet.kind == TickPacket:
        inc ticks
        check packet.seats == room.seats
    check ticks == 2
    relay.send(3, RoomMessage(kind: Hello, name: "Late watcher",
      identity: GameIdentity(game: "resize-test", gameplay: 1, protocol: 1)))
    relay.outgoing.setLen(0)
    relay.send(3, RoomMessage(kind: JoinRoom, room: room.id))
    var found = false
    for output in relay.outgoing:
      let packet = decode(output.bytes)
      if output.connection == 3 and packet.kind == BeginMatch:
        found = true
        check packet.seats == initial.seats
        check packet.payload == initial.payload
        check packet.tickRate == initial.tickRate
        check packet.hash == initial.setupHash()
    check found

  test "live resize cannot rewrite game configuration or clock rate":
    for phase in [Playing, Waiting, Ended, Desynced]:
      let relay = lobby()
      let room = relay.rooms[0]
      relay.start()
      room.phase = phase
      relay.expectUnchanged(1, configure(5))
      var message = resize(room, 5)
      message.payload = "{\"new-game\":true}"
      relay.expectUnchanged(1, message)
      message = resize(room, 5)
      message.tickRate = 30
      relay.expectUnchanged(1, message)
      relay.send(1, resize(room, 5))
      check room.seats.len == 5
