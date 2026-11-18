import std/unittest
import networkfixtures
import ../lobbyreadiness

suite "LvD immediate host start":
  test "no preparation messages or readiness acknowledgements are required":
    let f = newFixture()
    let revision = f.clients[0].snapshot.revision
    f.clients[0].send(RoomMessage(kind: StartMatch, revision: revision,
      hash: f.clients[0].snapshot.setupHash()))
    f.exchange()
    for client in f.clients:
      check client.events.len == 1
      check client.snapshot.phase == Playing
      check client.events[0].revision == revision
      check not client.cosmeticReady()

  test "roster edits need no retained start intent or automatic retry":
    let f = newFixture()
    f.clients[0].send(RoomMessage(kind: ClaimSeat, seat: 2,
      seatKind: BotSeat, name: "Idle bot"))
    f.exchange()
    let session = f.clients[0].requestStart(["", "", ""])
    f.exchange()
    check f.clients[0].events.len == 1
    session.start(f.clients[0].events[0])
    check session.started

  test "guests cannot start the host's game":
    let f = newFixture()
    f.clients[1].send(RoomMessage(kind: StartMatch,
      revision: f.clients[1].snapshot.revision,
      hash: f.clients[1].snapshot.setupHash()))
    f.exchange()
    check f.clients[1].error.len > 0
    check f.clients[0].snapshot.phase == Lobby
    check f.clients[0].events.len == 0
