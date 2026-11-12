## Construction cancellation refunds the paid cost exactly once.
import std/unittest
import trafficfixture

proc siteFixture(): tuple[w: World, builder: Unit, siteIndex: int] =
  result.w = trafficFixture(0, "open").world
  let w = result.w
  w.players[0].gold = 10000
  w.players[0].wood = 10000
  let id = w.spawnUnit(0, PeonUnit, tile2(40, 30))
  result.builder = w.units[w.unitIndex(id)]
  doAssert w.applyBuild(0, id, FarmBuilding.ord.int32, 40, 30)
  result.siteIndex = w.buildings.high

suite "Cancel unfinished site":
  test "partial construction refunds all paid gold and wood once and releases queued builder":
    let (w, builder, siteIndex) = siteFixture()
    doAssert w.applyMove(0, builder.id, 48, 30, append = true)
    for _ in 0 ..< TickRate.int * 2: w.tickWorld(nil)
    require w.buildings[siteIndex].state == BuildingUnderConstruction
    require w.buildings[siteIndex].buildTicks < w.buildings[siteIndex].buildTotal
    require builder.constructionSiteId == w.buildings[siteIndex].id
    check w.players[0].gold == 10000 - BuildingTable[FarmBuilding].gold
    check w.players[0].wood == 10000 - BuildingTable[FarmBuilding].wood
    require w.applyCancel(0, w.buildings[siteIndex].id)
    check w.players[0].gold == 10000
    check w.players[0].wood == 10000
    check w.buildings[siteIndex].state == BuildingDying
    check builder.constructionSiteId == NoEntity
    check builder.orderQueue.len == 1
    for blocker in w.blocker: check blocker != w.buildings[siteIndex].id
    let hash = Game(world: w).stateHash()
    check not w.applyCancel(0, w.buildings[siteIndex].id)
    check Game(world: w).stateHash() == hash
    for _ in 0 ..< TickRate.int * 8: w.tickWorld(nil)
    check builder.tile == tile2(48, 30)
    check builder.state == UnitIdle

  test "enemy, completed and destroyed sites do not refund":
    block enemy:
      let (w, builder, siteIndex) = siteFixture()
      let hash = Game(world: w).stateHash()
      check not w.applyCancel(1, w.buildings[siteIndex].id)
      check Game(world: w).stateHash() == hash
    block completed:
      let (w, builder, siteIndex) = siteFixture()
      for _ in 0 ..< BuildingTable[FarmBuilding].buildTicks.int + 100:
        w.tickWorld(nil)
      require w.buildings[siteIndex].state == BuildingComplete
      let hash = Game(world: w).stateHash()
      check not w.applyCancel(0, w.buildings[siteIndex].id)
      check Game(world: w).stateHash() == hash
    block destroyed:
      let (w, builder, siteIndex) = siteFixture()
      w.damageEntity(w.buildings[siteIndex].id, w.buildings[siteIndex].maxHp + 1, 1)
      let hash = Game(world: w).stateHash()
      check not w.applyCancel(0, w.buildings[siteIndex].id)
      check Game(world: w).stateHash() == hash
      check w.players[0].gold == 10000 - BuildingTable[FarmBuilding].gold

  test "cancel abandoned site preserves the former builder newer assignment":
    let (w, builder, siteIndex) = siteFixture()
    for _ in 0 ..< TickRate.int: w.tickWorld(nil)
    doAssert w.applyMove(0, builder.id, 48, 30)
    doAssert w.applyMove(0, builder.id, 48, 34, append = true)
    require w.applyCancel(0, w.buildings[siteIndex].id)
    check builder.state == UnitMoving
    check builder.goal == tile2(48, 30)
    check builder.orderQueue.len == 1
    check builder.constructionSiteId == NoEntity
    for _ in 0 ..< TickRate.int * 10: w.tickWorld(nil)
    check builder.tile == tile2(48, 34)
