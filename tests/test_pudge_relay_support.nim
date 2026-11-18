import polyworld/[relays, rooms]

const
  Identity = GameIdentity(game: "pudge_wars", gameplay: 1, protocol: 1)
  TickRate = 28'u32
  WarningTicks = 180'u32 * TickRate

proc send(relay: Relay, connection: int, message: RoomMessage, now = 0.0) =
  ## Exercises the wire format and the shared relay.
  relay.receive(connection, decode(message.encode()), now)

proc settings(kind: MessageKind, size: uint32, seed = 7): RoomMessage =
  ## Builds the portion of the Pudge Wars setup understood by the relay.
  RoomMessage(kind: kind, name: "Pudge Wars", number: size * 2,
    tickRate: TickRate, payload: """{"teamSize":""" & $size &
      ""","seed":""" & $seed & "}", flag: true)

proc lobby(): Relay =
  ## Creates a full two-bank layout with two active owners and a spectator.
  result = Relay()
  for connection in 1 .. 3:
    result.send(connection, RoomMessage(kind: Hello, identity: Identity,
      name: "Player " & $connection))
  result.send(1, settings(CreateRoom, 3))
  for connection in 2 .. 3:
    result.send(connection, RoomMessage(kind: JoinRoom, room: result.rooms[0].id))
  result.send(1, RoomMessage(kind: ClaimSeat, seat: 0, name: "Human"))
  result.send(1, RoomMessage(kind: ClaimSeat, seat: 1, name: "West bot"))
  result.send(2, RoomMessage(kind: ClaimSeat, seat: 3, name: "Human"))
  result.send(2, RoomMessage(kind: ClaimSeat, seat: 5, name: "East bot"))
  result.outgoing.setLen(0)

proc proof(relay: Relay, connection: int, duration = WarningTicks + 4,
    hash = 42'u64) =
  ## Prepares one revision for all seats controlled by the sender.
  relay.send(connection, RoomMessage(kind: PreparedDuration,
    revision: relay.rooms[0].revision, hash: hash, durationTicks: duration))

proc rejected(relay: Relay, connection: int, message: RoomMessage): bool =
  ## Detects a protocol error from the real relay receive path.
  try:
    relay.send(connection, message)
  except RoomsError:
    return true

proc packets(relay: Relay, kind: MessageKind): seq[RoomMessage] =
  ## Finds packets of the given kind in the emitted deliveries.
  for output in relay.outgoing:
    if output.bytes.len > 0:
      let message = decode(output.bytes)
      if message.kind == kind:
        result.add message

block:
  let
    relay = lobby()
    room = relay.rooms[0]
    revision = room.revision
  doAssert relay.rejected(2, RoomMessage(kind: StartMatch))
  doAssert relay.rejected(1, RoomMessage(kind: Prepared, revision: revision))
  doAssert relay.rejected(1, RoomMessage(kind: Ready, revision: revision))
  for duration in [0'u32, uint32(MaxHistoryTicks) + 1]:
    doAssert relay.rejected(1, RoomMessage(kind: PreparedDuration,
      revision: revision, hash: 42, durationTicks: duration))
  doAssert relay.rejected(3, RoomMessage(kind: PreparedDuration,
    revision: revision, hash: 42, durationTicks: WarningTicks + 4))
  relay.send(1, RoomMessage(kind: StartMatch))
  relay.send(2, RoomMessage(kind: ReadyStatus, flag: true))
  relay.proof(1)
  doAssert room.phase == Lobby and relay.packets(BeginMatch).len == 0
  relay.send(2, RoomMessage(kind: ReadyStatus, flag: false))
  relay.proof(2)
  doAssert room.phase == Playing and room.match == 1
  doAssert not relay.guest(1).ready and not relay.guest(2).ready
  for message in relay.packets(BeginMatch):
    doAssert message.hash == 42 and message.revision == revision
  doAssert relay.packets(BeginMatch).len == 3

block:
  for mismatch in [false, true]:
    let
      relay = lobby()
      room = relay.rooms[0]
    relay.proof(1)
    if mismatch:
      relay.proof(2, hash = 43)
    else:
      relay.proof(2, duration = WarningTicks + 5)
    doAssert room.phase == Lobby
    relay.send(1, RoomMessage(kind: StartMatch))
    doAssert room.phase == Desynced and relay.packets(BeginMatch).len == 0
    relay.send(1, RoomMessage(kind: ReturnLobby))
    relay.proof(1)
    relay.proof(2)
    doAssert room.phase == Lobby
    relay.send(1, RoomMessage(kind: StartMatch))
    doAssert room.phase == Playing

block:
  let
    relay = lobby()
    room = relay.rooms[0]
    before = relay.state(room)
  for payload in ["{}", "[]", "broken", """{"teamSize":2.0}""",
      """{"teamSize":3}"""]:
    var invalid = settings(ResizeRoom, 2)
    invalid.payload = payload
    doAssert relay.rejected(1, invalid)
  doAssert relay.rejected(1, settings(ResizeRoom, 0))
  doAssert relay.rejected(1, settings(ResizeRoom, 6))
  doAssert relay.rejected(1, settings(ResizeRoom, 2))
  doAssert relay.state(room) == before
  doAssert relay.outgoing.len == 0
  doAssert relay.rejected(1, RoomMessage(kind: ReleaseSeat, seat: 3))
  doAssert relay.rejected(2, RoomMessage(kind: ReleaseSeat, seat: 1))
  relay.send(1, RoomMessage(kind: ReleaseSeat, seat: 5))
  doAssert room.seats[5] == Seat() and relay.guest(2).room == room.id
  relay.send(2, RoomMessage(kind: ReadyStatus, flag: true))
  relay.proof(1)
  relay.send(1, RoomMessage(kind: StartMatch))
  let oldRevision = room.revision
  relay.send(1, settings(ResizeRoom, 5))
  doAssert room.seats[0] == before.seats[0] and room.seats[1] == before.seats[1]
  doAssert room.seats[3] == Seat() and room.seats[5] == before.seats[3]
  doAssert relay.guest(2).ready
  relay.send(1, settings(ResizeRoom, 2))
  doAssert room.seats == @[before.seats[0], before.seats[1],
    before.seats[3], Seat()]
  doAssert relay.rejected(2, RoomMessage(kind: PreparedDuration,
    revision: oldRevision, hash: 42, durationTicks: WarningTicks + 4))
  doAssert relay.guest(2).ready
  relay.proof(2)
  doAssert room.phase == Lobby
  relay.proof(1)
  doAssert room.phase == Playing

block:
  let
    relay = lobby()
    room = relay.rooms[0]
  relay.send(2, RoomMessage(kind: ReadyStatus, flag: true))
  relay.send(1, RoomMessage(kind: StartMatch))
  relay.send(1, settings(ResizeRoom, 4, seed = 20))
  doAssert not relay.guest(2).ready
  relay.proof(1)
  relay.proof(2)
  doAssert room.phase == Lobby
  relay.send(1, RoomMessage(kind: StartMatch))
  doAssert room.phase == Playing

block:
  let
    relay = lobby()
    room = relay.rooms[0]
  relay.proof(1)
  relay.proof(2)
  relay.send(1, RoomMessage(kind: StartMatch))
  relay.outgoing.setLen(0)
  for tick in 1 .. 6:
    relay.advance(float64(tick) * 0.04)
  doAssert room.tick == 6 and relay.packets(ServerNotice).len == 0
  relay.send(3, RoomMessage(kind: AppliedTick, match: 1, tick: 6), 0.25)
  relay.advance(0.25)
  doAssert relay.packets(ServerNotice).len == 0
  relay.send(1, RoomMessage(kind: AppliedTick, match: 1, tick: 3), 0.25)
  relay.advance(0.25)
  doAssert relay.packets(ServerNotice).len == 0
  relay.send(1, RoomMessage(kind: AppliedTick, match: 1, tick: 5), 0.25)
  relay.advance(0.25)
  relay.advance(0.30)
  let notices = relay.packets(ServerNotice)
  doAssert notices.len == 3
  for message in notices:
    doAssert message.tick == 4 and message.noticeCode == ThreeMinutesRemain
    doAssert message.match == 1 and message.noticeId == 1
  let peer = relay.guest(2)
  relay.disconnect(2)
  relay.outgoing.setLen(0)
  relay.send(4, RoomMessage(kind: Hello, identity: Identity, name: peer.name,
    token: peer.token), 0.31)
  doAssert relay.packets(ServerNotice).len == 1

echo "Pudge Wars relay support passed"
