## Town Hall loss is a tick-based grace period, including unfinished halls.
import std/unittest
import trafficfixture

proc hall(w: World, owner: int32): int32 =
  for b in w.buildings:
    if b.owner == owner and b.kind == TownHallBuilding and b.state != BuildingDying:
      return b.id
  NoEntity
proc loseHall(w: World, owner: int32) =
  let id = w.hall(owner)
  doAssert id != NoEntity
  w.damageEntity(id, w.buildings[w.buildingIndex(id)].hp + 1)
proc run(w: World, count: int32) =
  for _ in 0 ..< count: w.tickWorld(nil)

suite "Town Hall defeat grace":
  test "last hall loss defeats at exactly fifteen seconds despite army and other buildings":
    let w = trafficFixture(0, "open").world
    discard w.spawnUnit(1, SoldierUnit, tile2(60, 60))
    discard w.spawnUnit(1, PeonUnit, tile2(63, 60))
    w.loseHall(1)
    w.run(15 * TickRate - 1)
    check not w.players[1].defeated
    check not w.over
    w.tickWorld(nil)
    check w.players[1].defeated
    check w.over and w.winner == 0

  test "an unfinished replacement resets grace and cancel restarts the full interval":
    let w = trafficFixture(0, "open").world
    let builder = w.spawnUnit(1, PeonUnit, tile2(60, 60))
    w.players[1].gold = 20000
    w.players[1].wood = 20000
    w.loseHall(1)
    w.run(15 * TickRate - 1)
    doAssert w.applyBuild(1, builder, TownHallBuilding.ord.int32, 60, 60)
    let replacement = w.buildings[^1].id
    doAssert w.applyCancel(1, builder) # stopped shell still saves its owner
    w.run(15 * TickRate + 1)
    check not w.players[1].defeated
    check not w.over
    doAssert w.applyCancel(1, replacement)
    w.run(15 * TickRate - 1)
    check not w.players[1].defeated
    w.tickWorld(nil)
    check w.players[1].defeated and w.winner == 0

  test "multiple halls and simultaneous expiry produce no premature win":
    let w = trafficFixture(0, "open").world
    let builder = w.spawnUnit(0, PeonUnit, tile2(40, 30))
    w.players[0].gold = 20000
    w.players[0].wood = 20000
    doAssert w.applyBuild(0, builder, TownHallBuilding.ord.int32, 40, 30)
    let second = w.buildings[^1].id
    doAssert w.applyCancel(0, builder)
    w.loseHall(0)
    w.run(15 * TickRate + 1)
    check not w.players[0].defeated and not w.over
    doAssert w.applyCancel(0, second)
    w.loseHall(1)
    w.run(15 * TickRate - 1)
    check not w.over
    w.tickWorld(nil)
    check w.players[0].defeated and w.players[1].defeated
    check w.over and w.winner == -1

  test "deadline is hashed, snapshot-safe, read-only while paused and cleared at build acceptance":
    let w = trafficFixture(0, "open").world
    let builder = w.spawnUnit(1, PeonUnit, tile2(60, 60))
    w.players[1].gold = 20000
    w.players[1].wood = 20000
    w.loseHall(1)
    check w.hallDefeatTicksRemaining(1) == TownHallDefeatGraceTicks
    let peer = w.clone()
    let baseline = Game(world: w).stateHash()
    peer.players[1].hallLossDeadline += 1
    check Game(world: peer).stateHash() != baseline
    peer.restore(w)
    check Game(world: peer).stateHash() == baseline
    for _ in 0 ..< 50:
      check w.hallDefeatTicksRemaining(1) == TownHallDefeatGraceTicks
    check Game(world: w).stateHash() == baseline
    w.run(50)
    peer.run(50)
    check Game(world: peer).stateHash() == Game(world: w).stateHash()
    doAssert w.applyBuild(1, builder, TownHallBuilding.ord.int32, 60, 60)
    check w.players[1].hallLossDeadline == 0
    check w.hallDefeatTicksRemaining(1) == 0
    check w.hallDefeatTicksRemaining(-1) == 0

  test "tick cap with multiple surviving players is not a score victory":
    let w = trafficFixture(0, "open").world
    w.maximumTicks = 2
    w.players[0].goldGathered = 50000
    w.run(2)
    check w.over and w.winner == -1
