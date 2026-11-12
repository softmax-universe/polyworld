import std/unittest
import polyworld/[rooms, relays]

proc send(r: Relay, c: int, m: RoomMessage) =
  r.receive(c, decode(m.encode()), 0)

suite "Adapter-scoped cosmetic readiness":
  test "host starts unready controllers after automatic preparation":
    for identity in [
        GameIdentity(game: "light_vs_dark", gameplay: 1, protocol: 3),
        GameIdentity(game: "galcon", gameplay: 1, protocol: 2)]:
      let r = Relay()
      for c in 1..2:
        r.send(c, RoomMessage(kind: Hello, name: "Human " & $c,
          identity: identity))
      r.send(1, RoomMessage(kind: CreateRoom, name: "No consent gate", number: 2,
        tickRate: 24, payload: "setup"))
      let room = r.rooms[0]
      r.send(2, RoomMessage(kind: JoinRoom, room: room.id))
      for c in 1..2:
        r.send(c, RoomMessage(kind: ClaimSeat, seat: uint32(c-1), name: "Human"))
      r.send(1, RoomMessage(kind: StartMatch))
      check room.phase == Lobby
      for c in 1..2:
        r.send(c, RoomMessage(kind: Prepared, revision: room.revision, hash: 42))
      check room.phase == Playing
      for c in 1..2:
        check not r.guest(uint32(c)).ready

  test "generic protocol 1 still requires explicit ready":
    let r = Relay()
    for c in 1..2:
      r.send(c, RoomMessage(kind: Hello, name: "Human " & $c,
        identity: GameIdentity(game: "ready-test", gameplay: 1, protocol: 1)))
    r.send(1, RoomMessage(kind: CreateRoom, name: "Legacy", number: 2,
      tickRate: 24, payload: "setup"))
    let room = r.rooms[0]
    r.send(2, RoomMessage(kind: JoinRoom, room: room.id))
    for c in 1..2:
      r.send(c, RoomMessage(kind: ClaimSeat, seat: uint32(c-1), name: "Human"))
    expect RoomsError: r.send(1, RoomMessage(kind: StartMatch))
    for c in 1..2:
      r.send(c, RoomMessage(kind: Prepared, revision: room.revision, hash: 42))
    expect RoomsError: r.send(1, RoomMessage(kind: StartMatch))
    check room.phase == Lobby
    for c in 1..2:
      r.send(c, RoomMessage(kind: Ready, revision: room.revision, hash: 42))
    r.send(1, RoomMessage(kind: StartMatch))
    check room.phase == Playing
