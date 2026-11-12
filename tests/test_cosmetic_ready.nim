import std/unittest
import polyworld/[rooms, relays]

proc send(r: Relay, c: int, m: RoomMessage) =
  r.receive(c, decode(m.encode()), 0)

suite "Cosmetic readiness":
  test "host starts unready controllers after automatic preparation":
    let r = Relay()
    for c in 1..2:
      r.send(c, RoomMessage(kind: Hello, name: "Human " & $c,
        identity: GameIdentity(game: "ready-test", gameplay: 1, protocol: 1)))
    r.send(1, RoomMessage(kind: CreateRoom, name: "No consent gate", number: 2,
      tickRate: 24, payload: "setup"))
    let room = r.rooms[0]
    r.send(2, RoomMessage(kind: JoinRoom, room: room.id))
    for c in 1..2:
      r.send(c, RoomMessage(kind: ClaimSeat, seat: uint32(c-1), name: "Human"))
    # The host can request Start even while automatic preparation is loading.
    r.send(1, RoomMessage(kind: StartMatch))
    check room.phase == Lobby
    # Preparation reports are independent from the visible ready status.
    for c in 1..2:
      r.send(c, RoomMessage(kind: Prepared, revision: room.revision, hash: 42))
    check room.phase == Playing
    for c in 1..2:
      check not r.guest(uint32(c)).ready
