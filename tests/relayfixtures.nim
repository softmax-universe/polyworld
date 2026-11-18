import polyworld/[rooms, relays]

proc send*(relay: Relay, connection: int, message: RoomMessage) =
  ## Exercises the complete wire envelope without a game adapter.
  relay.receive(connection, decode(message.encode()), 0)

proc lobby*(game = "fixture-game", protocol = 19'u32,
    slots = 4, payload = "{\"seed\":17}"): Relay =
  ## Creates a room with one host, two guests and two occupied slots.
  result = Relay()
  for connection in 1 .. 3:
    result.send(connection, RoomMessage(kind: Hello,
      identity: GameIdentity(game: game, gameplay: 42, protocol: protocol),
      name: "Guest " & $connection))
  result.send(1, RoomMessage(kind: CreateRoom, name: "Fixture",
    number: uint32(slots), tickRate: 24, payload: payload))
  let room = result.rooms[0]
  for connection in 2 .. 3:
    result.send(connection, RoomMessage(kind: JoinRoom, room: room.id))
  result.send(1, RoomMessage(kind: ClaimSeat, seat: 0,
    name: "Host", seatKind: HumanSeat))
  result.send(2, RoomMessage(kind: ClaimSeat, seat: 1,
    name: "Guest", seatKind: HumanSeat))
  result.outgoing.setLen(0)

proc startMessage*(relay: Relay, room: RelayRoom): RoomMessage =
  ## Binds the host request to the current shared setup and roster.
  RoomMessage(kind: StartMatch, revision: room.revision,
    hash: setupHash(relay.state(room)))

proc start*(relay: Relay, connection = 1) =
  ## Starts the participant's room using its exact current setup.
  let room = relay.room(relay.guest(uint32(connection)).room)
  relay.send(connection, relay.startMessage(room))

proc expectUnchanged*(relay: Relay, connection: int, message: RoomMessage) =
  ## Rejected operations must not partially mutate room state.
  let room = relay.room(relay.guest(uint32(connection)).room)
  let before = relay.state(room)
  var rejected = false
  try:
    relay.send(connection, message)
  except RoomsError:
    rejected = true
  doAssert rejected
  doAssert relay.state(room) == before

proc begins*(relay: Relay): seq[RoomMessage] =
  ## Extracts delivered initial snapshots for contract assertions.
  for output in relay.outgoing:
    if output.bytes.len > 0:
      let message = decode(output.bytes)
      if message.kind == BeginMatch:
        result.add message
