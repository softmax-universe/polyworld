import std/unittest
import networkfixtures
import ../[sim, controls, replays]

suite "LvD live controller changes":
  test "accepted old-owner commands survive newer room ownership snapshots":
    let f = newFixture()
    f.begin()
    let oldHash = f.clients[0].initialSnapshot.setupHash()
    let unit = f.sessions[0].game.world.units[0]
    queueMove(0, unit.id, int32(unit.tile.x), int32(unit.tile.y))
    f.sessions[0].flushSubmissions()
    f.exchange()
    f.clients[0].send(RoomMessage(kind: ClaimSeat, seat: 0,
      participant: f.clients[1].participant, seatKind: BotSeat, name: "Idle bot"))
    f.exchange()
    check f.clients[0].snapshot.seats[0].owner == f.clients[1].participant
    check f.clients[0].initialSnapshot.setupHash() == oldHash
    f.now += 1.0
    f.relay.advance(f.now)
    f.exchange()
    for session in f.sessions: check session.advance()
    check f.sessions[0].game.stateHash() == f.sessions[1].game.stateHash()
    check f.sessions[0].game.recorder.data.actions.len == 1
    check f.sessions[0].humanPlayerFor(f.clients[0].participant) == -1
    check f.sessions[1].humanPlayerFor(f.clients[1].participant) == 1

  test "newly occupied slots reserve the next match without spawning a kingdom":
    let f = newFixture()
    f.begin()
    f.clients[0].send(RoomMessage(kind: ClaimSeat, seat: 2,
      participant: f.clients[1].participant, seatKind: BotSeat, name: "Next match"))
    f.exchange()
    f.now += 1.0
    f.relay.advance(f.now)
    f.exchange()
    for session in f.sessions:
      check session.advance()
      check session.nextMatchSeats() == @[2]
      check session.game.world.players.len == 2
    check f.sessions[0].game.stateHash() == f.sessions[1].game.stateHash()

  test "host removal leaves the guest match while connection loss permits recovery":
    let f = newFixture()
    f.begin()
    f.clients[1].lost()
    check not f.sessions[1].reopenedLobby()
    f.clients[1].connected = true
    f.clients[1].welcomed = true
    f.clients[0].send(RoomMessage(kind: KickParticipant,
      participant: f.clients[1].participant))
    f.exchange()
    check f.sessions[1].reopenedLobby()
    check not f.sessions[0].reopenedLobby()

  test "a live bot takeover switches only the local command producer":
    let f = newFixture()
    f.clients[0].send(RoomMessage(kind: ClaimSeat, seat: 0,
      seatKind: BotSeat, name: "Idle bot"))
    f.exchange()
    f.sessions[0] = f.clients[0].requestStart(["a = 1"])
    f.exchange()
    f.sessions[1] = prepareNetworkMatch(f.clients[1], [])
    for i in 0 ..< 2:
      f.sessions[i].start(f.clients[i].events[0])
      f.clients[i].events.setLen(0)
    f.exchange()
    check f.sessions[0].game.brains[0] != nil
    check f.sessions[1].game.brains[0] == nil
    f.sessions[1].setBotSource(0, "a = 1")
    f.clients[0].send(RoomMessage(kind: ClaimSeat, seat: 0,
      participant: f.clients[1].participant, seatKind: BotSeat, name: "Idle bot"))
    f.exchange()
    f.now += 1.0
    f.relay.advance(f.now)
    f.exchange()
    for session in f.sessions: check session.advance()
    check f.sessions[0].game.brains[0] == nil
    check f.sessions[1].game.brains[0] != nil
    check f.sessions[0].game.stateHash() == f.sessions[1].game.stateHash()

  test "discarded disconnected input releases its local production reservation":
    let f = newFixture()
    f.begin()
    let session = f.sessions[0]
    let world = session.game.world
    var hall = NoEntity
    for building in world.buildings:
      if building.owner == 0 and building.kind == TownHallBuilding:
        hall = building.id
    require hall != NoEntity
    world.players[0].gold = unitOf(0, PeonUnit).gold
    world.players[0].foodCap = 100
    require world.queueSelectedTrain(0, [hall], PeonUnit)
    f.clients[0].lost()
    session.flushSubmissions()
    check session.game.submissions.len == 0
    check world.selectedProducer(0, [hall], PeonUnit) == hall

  test "wire ownership rejection retires the exact pending production reservation":
    let f = newFixture()
    f.begin()
    let session = f.sessions[0]
    let world = session.game.world
    var hall = NoEntity
    for building in world.buildings:
      if building.owner == 0 and building.kind == TownHallBuilding:
        hall = building.id
    require hall != NoEntity
    world.players[0].gold = unitOf(0, PeonUnit).gold
    world.players[0].foodCap = 100
    # Ownership changes at the relay before this still-unaware client submits.
    f.clients[0].send(RoomMessage(kind: ClaimSeat, seat: 0,
      participant: f.clients[1].participant, seatKind: BotSeat, name: "Idle bot"))
    require world.queueSelectedTrain(0, [hall], PeonUnit)
    session.flushSubmissions()
    check world.selectedProducer(0, [hall], PeonUnit) == NoEntity
    f.exchange()
    check f.clients[0].rejectedCommands == 1
    session.flushSubmissions()
    check world.selectedProducer(0, [hall], PeonUnit) == hall
