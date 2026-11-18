## Queued construction waits, adoption, capacity, and resource previews.
import trafficfixture, ../controls

proc buildingWorld(): World =
  ## Creates an open arena with ample construction resources.
  result = trafficFixture(0, "open").world
  result.players[0].gold = 10000
  result.players[0].wood = 10000

proc peon(w: World, x = 20'i32, y = 20'i32): Unit =
  ## Adds a builder away from the starting halls.
  let id = w.spawnUnit(0, PeonUnit, tile2(x, y))
  w.units[w.unitIndex(id)]

proc plan(w: World, unit: Unit, x, y: int32): bool =
  ## Appends a farm without starting construction immediately.
  w.applyBuild(0, unit.id, FarmBuilding.ord.int32, x, y, append = true)

block temporaryOccupancyWaitsButStaticObstructionsSkip:
  let
    w = buildingWorld()
    unit = w.peon()
    buildingsBefore = w.buildings.len
  doAssert w.plan(unit, 24, 20)
  let blocker = w.peon(24, 20)
  for tick in 0 ..< TickRate: w.tickWorld(nil)
  doAssert unit.state == UnitIdle and unit.orderQueue.len == 1
  doAssert w.buildings.len == buildingsBefore
  w.place(blocker, tile2(24, 24))
  w.tickWorld(nil)
  doAssert w.buildings.len == buildingsBefore + 1
  doAssert unit.orderQueue.len == 0
  doAssert w.applyCancel(0, unit.id)
  doAssert w.plan(unit, 28, 20)
  doAssert w.applyMove(0, unit.id, 16, 20, append = true)
  w.blocker[w.map.tileIndex(28, 20)] = TreeBlocker
  w.players[0].gold = 0
  w.players[0].wood = 0
  for tick in 0 ..< TickRate * 10: w.tickWorld(nil)
  doAssert w.buildings.len == buildingsBefore + 1
  doAssert unit.orderQueue.len == 0 and unit.tile == tile2(16, 20)

block queueCapacityOverlapAndThirdCoordinateHash:
  let
    w = buildingWorld()
    unit = w.peon(12, 12)
    other = w.peon(14, 12)
  doAssert w.plan(unit, 20, 20)
  doAssert not w.plan(other, 21, 20)
  let hashBefore = Game(world: w).stateHash()
  inc unit.orderQueue[0].third
  doAssert Game(world: w).stateHash() != hashBefore
  dec unit.orderQueue[0].third
  for index in 1 ..< MaxUnitOrders:
    doAssert w.plan(unit, 20 + (index.int32 mod 8) * 4,
      20 + (index.int32 div 8) * 4)
  doAssert unit.orderQueue.len == MaxUnitOrders
  doAssert not w.plan(unit, 20, 40)
  doAssert not w.applyMove(0, unit.id, -1, -1)
  doAssert unit.orderQueue.len == MaxUnitOrders
  doAssert w.applyCancel(0, unit.id)
  doAssert unit.orderQueue.len == 0

block queuedBuilderAdoptsStalledSiteWithoutPayingAgain:
  let
    w = buildingWorld()
    unit = w.peon()
    replacement = w.peon(20, 24)
  doAssert w.applyBuild(0, unit.id, FarmBuilding.ord.int32, 24, 20)
  doAssert not w.plan(replacement, 24, 20)
  let site = w.buildingIndex(unit.targetId)
  doAssert w.applyCancel(0, unit.id)
  w.players[0].gold = 0
  w.players[0].wood = 0
  let buildingsBefore = w.buildings.len
  doAssert w.plan(replacement, 24, 20)
  doAssert replacement.state == UnitIdle
  for tick in 0 ..< TickRate * 30:
    w.tickWorld(nil)
    if w.buildings[site].state == BuildingComplete: break
  doAssert w.buildings[site].state == BuildingComplete
  doAssert w.buildings.len == buildingsBefore
  doAssert w.players[0].gold == 0 and w.players[0].wood == 0

block pendingPlansDoNotReserveProductionResources:
  let
    w = buildingWorld()
    unit = w.peon()
    stats = unitOf(0, PeonUnit)
  var hallId = NoEntity
  for building in w.buildings:
    if building.owner == 0 and building.kind == TownHallBuilding:
      hallId = building.id
  w.players[0].gold = stats.gold
  w.players[0].wood = stats.wood
  w.players[0].foodUsed = 1
  w.players[0].foodCap = 5
  clearPlayerCommands()
  doAssert w.selectedProducer(0, [hallId], PeonUnit) == hallId
  queueBuild(0, unit.id, FarmBuilding.ord.int32, 24, 20, append = true)
  doAssert w.selectedProducer(0, [hallId], PeonUnit) == hallId
  clearPlayerCommands()
  queueBuild(0, unit.id, FarmBuilding.ord.int32, 24, 20)
  doAssert w.selectedProducer(0, [hallId], PeonUnit) == NoEntity
  clearPlayerCommands()

echo "Build queue tests passed."
