## Illegal terrain starts recover without discarding intent or crossing walls.
import trafficfixture

proc displace(w: World, unit: Unit, point: FixedVec2) =
  ## Reproduces a bad physical position while keeping tile occupancy coherent.
  w.place(unit, tile2(whole(point.x), whole(point.y)))
  unit.body.pos = point

proc assertClear(w: World, unit: Unit) =
  ## Requires every tile touched by the body to be statically walkable.
  for y in whole(unit.body.pos.y - unit.body.radius) ..
      whole(unit.body.pos.y + unit.body.radius):
    for x in whole(unit.body.pos.x - unit.body.radius) ..
        whole(unit.body.pos.x + unit.body.radius):
      doAssert w.tileOpen(x, y), "Body still overlaps an obstacle"
  doAssert unit.tile == tile2(whole(unit.body.pos.x), whole(unit.body.pos.y))

proc obstruct(w: World, x, y: int32, tree: bool) =
  ## Uses the actual tree or impassable rock collision layer.
  let cell = w.map.tileIndex(x, y)
  if tree:
    w.blocker[cell] = TreeBlocker
    w.treeWood[cell] = WoodPerTree
  else:
    w.map.passable[cell] = 0

block rockAndTreeEdges:
  for tree in [false, true]:
    for point in [fixedVec2(39.9'fx, 40.5'fx),
        fixedVec2(41.1'fx, 40.5'fx), fixedVec2(40.5'fx, 39.9'fx),
        fixedVec2(40.5'fx, 41.1'fx), fixedVec2(39.9'fx, 39.9'fx),
        fixedVec2(40.5'fx, 40.5'fx)]:
      let w = trafficFixture(0, "open").world
      w.obstruct(40, 40, tree)
      let id = w.spawnUnit(0, PeonUnit, tile2(36, 40))
      let unit = w.units[w.unitIndex(id)]
      w.displace(unit, point)
      unit.carryGold = 13
      unit.carryWood = 21
      w.tickWorld(nil)
      w.assertClear(unit)
      doAssert unit.state == UnitIdle and not unit.hasGoal
      doAssert unit.carryGold == 13 and unit.carryWood == 21
      doAssert length(unit.body.pos - point) < 1'fx
echo "PASS rock and tree overlap recovery includes body edges and corners"

block queuedOrdersSurviveRockRecovery:
  let w = trafficFixture(0, "open").world
  w.obstruct(40, 40, false)
  let id = w.spawnUnit(0, PeonUnit, tile2(36, 40))
  let unit = w.units[w.unitIndex(id)]
  doAssert w.applyMove(0, id, 35, 40)
  doAssert w.applyMove(0, id, 35, 44, append = true)
  w.displace(unit, fixedVec2(40.5'fx, 40.5'fx))
  unit.carryWood = 19
  let peer = w.clone()
  for tick in 0 ..< 600:
    w.tickWorld(nil)
    peer.tickWorld(nil)
    w.assertClear(unit)
    doAssert Game(world: w).stateHash() == Game(world: peer).stateHash()
    doAssert unit.carryWood == 19 and not unit.orderFailed
    if unit.state == UnitIdle and unit.orderQueue.len == 0: break
  doAssert unit.state == UnitIdle and unit.orderQueue.len == 0
  doAssert unit.tile == tile2(35, 44)
echo "PASS rock recovery preserves queued orders, cargo and deterministic state"

block foreignBodyDoesNotPreventEscape:
  let w = trafficFixture(0, "open").world
  w.obstruct(40, 40, false)
  let
    first = w.spawnUnit(0, PeonUnit, tile2(36, 40))
    second = w.spawnUnit(1, PeonUnit, tile2(36, 40))
  for id in [first, second]:
    w.displace(w.units[w.unitIndex(id)], fixedVec2(40.5'fx, 40.5'fx))
  w.tickWorld(nil)
  for unit in w.units: w.assertClear(unit)
echo "PASS overlapping foreign bodies can both escape static obstacles"

block adjacentObstaclesAndSealedExit:
  let w = trafficFixture(0, "open").world
  w.obstruct(40, 40, false)
  for y in 39'i32 .. 41'i32:
    for x in 39'i32 .. 41'i32:
      if x != 40 or y != 40: w.obstruct(x, y, true)
  let id = w.spawnUnit(0, PeonUnit, tile2(35, 40))
  let unit = w.units[w.unitIndex(id)]
  doAssert w.applyMove(0, id, 35, 44)
  w.displace(unit, fixedVec2(40.5'fx, 40.5'fx))
  let before = unit.body.pos
  for tick in 0 ..< 10:
    w.tickWorld(nil)
    doAssert unit.body.pos == before, "Recovery must not cross unrelated trees"
    doAssert unit.hasGoal and not unit.orderFailed
  w.blocker[w.map.tileIndex(39, 40)] = 0
  w.treeWood[w.map.tileIndex(39, 40)] = 0
  inc w.pathTerrainRevision
  w.tickWorld(nil)
  w.assertClear(unit)
  doAssert unit.body.pos.x < 40'fx
echo "PASS sealed starts wait without losing orders and escape when opened"

block multipleIntersectedRockCells:
  let w = trafficFixture(0, "open").world
  for y in 40'i32 .. 41'i32:
    for x in 40'i32 .. 41'i32:
      w.obstruct(x, y, false)
  let id = w.spawnUnit(0, PeonUnit, tile2(36, 40))
  let unit = w.units[w.unitIndex(id)]
  w.displace(unit, fixedVec2(41'fx, 41'fx))
  w.tickWorld(nil)
  w.assertClear(unit)
echo "PASS recovery handles several initial rock overlaps together"

block completedBuilderCanLeaveThroughOccupiedExit:
  let w = trafficFixture(0, "open").world
  let id = w.spawnUnit(0, PeonUnit, tile2(40, 40))
  let builder = w.units[w.unitIndex(id)]
  w.players[0].gold = 5000
  w.players[0].wood = 5000
  doAssert w.applyBuild(0, id, LumberMillBuilding.ord.int32, 40, 40)
  let site = w.buildingIndex(builder.targetId)
  w.tickWorld(nil)
  doAssert builder.state == UnitBuilding
  for y in 39'i32 .. 42'i32:
    for x in 39'i32 .. 42'i32:
      if x in 40'i32 .. 41'i32 and y in 40'i32 .. 41'i32: continue
      if x != 39 or y != 40: w.obstruct(x, y, true)
  discard w.spawnUnit(1, PeonUnit, tile2(39, 40))
  w.buildings[site].buildTicks = 1
  w.tickWorld(nil)
  doAssert w.buildings[site].state == BuildingComplete
  doAssert builder.constructionSiteId == NoEntity
  w.assertClear(builder)
echo "PASS builders leave completed shells even when soft bodies fill the exit"
