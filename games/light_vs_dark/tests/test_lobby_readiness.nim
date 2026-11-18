import std/unittest
import networkfixtures
import ../[lobbyreadiness, sim]

suite "LvD initialization agreement":
  test "host setup is independent of private preparation and Ready":
    let f = newFixture(4)
    check f.sessions[1] == nil
    f.begin()
    check f.sessions[0].playerSeats == @[0, 1]
    check f.sessions[1].playerSeats == @[0, 1]
    check f.sessions[0].game.networkHash() == f.sessions[1].game.networkHash()
    check f.clients[0].initialSnapshot.setupHash() ==
      f.clients[1].initialSnapshot.setupHash()

  test "initialization hashes bind slot responsibilities and opaque game config":
    let f = newFixture()
    let original = f.clients[0].snapshot.setupHash()
    f.clients[0].send(RoomMessage(kind: ClaimSeat, seat: 2,
      seatKind: BotSeat, name: "Idle bot"))
    f.exchange()
    check f.clients[0].snapshot.setupHash() != original
    let botHash = f.clients[0].snapshot.setupHash()
    f.clients[0].send(RoomMessage(kind: ReleaseSeat, seat: 2))
    f.exchange()
    check f.clients[0].snapshot.setupHash() == original
    check botHash != original

  test "cosmetic readiness never overrides a stale initialization hash":
    let f = newFixture()
    f.clients[1].toggleCosmeticReady()
    f.exchange()
    f.clients[0].send(RoomMessage(kind: StartMatch,
      revision: f.clients[0].snapshot.revision,
      hash: f.clients[0].snapshot.setupHash() xor 1))
    f.exchange()
    check f.clients[0].error.len > 0
    check f.clients[0].snapshot.phase == Lobby

  test "a different generated world is caught by tick-zero hashes":
    let f = newFixture()
    f.sessions[0] = f.clients[0].requestStart([])
    f.exchange()
    f.sessions[1] = prepareNetworkMatch(f.clients[1], [])
    inc f.sessions[1].game.world.players[0].gold
    for i in 0 ..< 2:
      f.sessions[i].start(f.clients[i].events[0])
      f.clients[i].events.setLen(0)
    f.exchange()
    check f.clients[0].snapshot.phase == Desynced
    check f.clients[1].snapshot.phase == Desynced
