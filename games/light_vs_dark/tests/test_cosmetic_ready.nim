import std/unittest
import networkfixtures
import ../lobbyreadiness

suite "LvD cosmetic readiness":
  test "readiness is visible to the host but changes no setup":
    let f = newFixture()
    let before = f.clients[0].snapshot
    check not f.clients[1].cosmeticReady()
    f.clients[1].toggleCosmeticReady()
    f.exchange()
    check f.clients[1].cosmeticReady()
    check f.clients[0].snapshot.participants[1].ready
    check f.clients[0].snapshot.revision == before.revision
    check f.clients[0].snapshot.setupHash() == before.setupHash()
    check f.clients[0].events.len == 0
    f.clients[1].toggleCosmeticReady()
    f.exchange()
    check not f.clients[0].snapshot.participants[1].ready

  test "host starts with every readiness indicator false":
    let f = newFixture()
    f.begin()
    for i, client in f.clients:
      check not client.cosmeticReady()
      check f.sessions[i].started
      check client.error.len == 0
      check client.snapshot.phase == Playing
