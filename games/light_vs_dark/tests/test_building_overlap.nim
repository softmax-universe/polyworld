## Buildings must recover illegal body starts without discarding unit intent.
import trafficfixture

proc addMill(w: World, at: Tile2): Building =
  ## Registers a solid mill in the open traffic arena.
  result = Building(id: w.nextBuildingId, owner: 0,
    kind: LumberMillBuilding, state: BuildingComplete,
    hp: BuildingTable[LumberMillBuilding].hp,
    maxHp: BuildingTable[LumberMillBuilding].hp,
    origin: at, footprint: BuildingTable[LumberMillBuilding].footprint)
  inc w.nextBuildingId
  let slot = w.map.mines.len + int(result.id - FirstBuildingId)
  while w.buildingSlot.len <= slot: w.buildingSlot.add -1
  w.buildingSlot[slot] = w.buildings.len.int32
  w.buildings.add result
  for y in at.y.int32 ..< at.y.int32 + result.footprint.depth:
    for x in at.x.int32 ..< at.x.int32 + result.footprint.width:
      w.blocker[w.map.tileIndex(x, y)] = result.id
  inc w.pathTerrainRevision

proc displace(w: World, unit: Unit, point: FixedVec2) =
  ## Reproduces a bad physical position while keeping occupancy consistent.
  w.place(unit, tile2(whole(point.x), whole(point.y)))
  unit.body.pos = point

proc assertBodyOpen(w: World, unit: Unit) =
  ## Checks the entire body extent against terrain and all building tiles.
  let radius = unit.body.radius
  for y in whole(unit.body.pos.y - radius) .. whole(unit.body.pos.y + radius):
    for x in whole(unit.body.pos.x - radius) .. whole(unit.body.pos.x + radius):
      doAssert w.tileOpen(x, y),
        "Body remains in static obstruction at " & $unit.body.pos
  doAssert unit.tile == tile2(whole(unit.body.pos.x), whole(unit.body.pos.y))
  doAssert w.occupancy[w.map.tileIndex(unit.tile)] == unit.id

block shallowEdgesAndCorners:
  for point in [fixedVec2(39.9'fx, 40.5'fx),
      fixedVec2(42.1'fx, 40.5'fx), fixedVec2(40.5'fx, 39.9'fx),
      fixedVec2(40.5'fx, 42.1'fx), fixedVec2(39.9'fx, 39.9'fx)]:
    let w = trafficFixture(0, "opposing").world
    discard w.addMill(tile2(40, 40))
    let id = w.spawnUnit(0, PeonUnit, tile2(36, 40))
    let unit = w.units[w.unitIndex(id)]
    w.displace(unit, point)
    unit.carryGold = 17
    unit.carryWood = 23
    unit.sourceId = FirstMineId
    unit.targetTile = tile2(35, 35)
    w.tickWorld(nil)
    w.assertBodyOpen(unit)
    doAssert length(unit.body.pos - point) < 0.5'fx,
      "A shallow overlap should not eject the peon to a distant tile"
    doAssert unit.state == UnitIdle and not unit.hasGoal
    doAssert unit.carryGold == 17 and unit.carryWood == 23
    doAssert unit.sourceId == FirstMineId and unit.targetTile == tile2(35, 35)

echo "Shallow building overlaps clear the whole body and retain cargo"

block deepIdleOverlap:
  let w = trafficFixture(0, "opposing").world
  discard w.addMill(tile2(40, 40))
  let id = w.spawnUnit(0, PeonUnit, tile2(36, 40))
  let unit = w.units[w.unitIndex(id)]
  w.displace(unit, fixedVec2(40.8'fx, 40.8'fx))
  w.tickWorld(nil)
  w.assertBodyOpen(unit)
  doAssert unit.state == UnitIdle and not unit.hasGoal

block deepOverlapAndQueuedMoves:
  for kind in [PeonUnit, SoldierUnit, CatapultUnit]:
    let w = trafficFixture(0, "opposing").world
    discard w.addMill(tile2(40, 40))
    let id = w.spawnUnit(0, kind, tile2(36, 40))
    let unit = w.units[w.unitIndex(id)]
    doAssert w.applyMove(0, id, 34, 40)
    doAssert w.applyMove(0, id, 34, 44, append = true)
    w.displace(unit, fixedVec2(40.8'fx, 40.8'fx))
    unit.carryWood = 29
    let peer = w.clone()
    var arrived = false
    for tick in 0 ..< 600:
      w.tickWorld(nil)
      peer.tickWorld(nil)
      doAssert Game(world: w).stateHash() == Game(world: peer).stateHash()
      w.assertBodyOpen(unit)
      doAssert not unit.orderFailed
      doAssert unit.carryWood == 29
      if unit.state == UnitIdle and unit.orderQueue.len == 0:
        arrived = true
        break
    doAssert arrived and unit.tile == tile2(34, 44),
      "Recovery must preserve and finish the queued movement orders"

echo "Deep overlaps retain movement, FIFO and clone determinism"

block neighboringObstaclesAndMapEdge:
  for variant in 0 .. 2:
    let w = trafficFixture(0, "opposing").world
    let at = if variant == 2: tile2(0, 40) else: tile2(40, 40)
    discard w.addMill(at)
    if variant == 0:
      discard w.addMill(tile2(38, 40))
    elif variant == 1:
      for y in 35'i32 .. 45'i32:
        w.blocker[w.map.tileIndex(39, y)] = TreeBlocker
    let id = w.spawnUnit(0, PeonUnit, tile2(36, 35))
    let unit = w.units[w.unitIndex(id)]
    w.displace(unit, fixedVec2(fixed(at.x.int32) + 0.5'fx, 40.5'fx))
    w.tickWorld(nil)
    w.assertBodyOpen(unit)
    doAssert length(unit.body.pos -
      fixedVec2(fixed(at.x.int32) + 0.5'fx, 40.5'fx)) < 3'fx

echo "Recovery respects neighboring structures, terrain and map bounds"

block temporarilySealedFootprint:
  let w = trafficFixture(0, "opposing").world
  discard w.addMill(tile2(40, 40))
  let id = w.spawnUnit(0, PeonUnit, tile2(35, 40))
  let unit = w.units[w.unitIndex(id)]
  doAssert w.applyMove(0, id, 35, 40)
  doAssert w.applyMove(0, id, 35, 44, append = true)
  w.displace(unit, fixedVec2(40.8'fx, 40.8'fx))
  unit.carryGold = 31
  for y in 39'i32 .. 42'i32:
    for x in 39'i32 .. 42'i32:
      if x in 40'i32 .. 41'i32 and y in 40'i32 .. 41'i32: continue
      w.blocker[w.map.tileIndex(x, y)] = TreeBlocker
  let before = unit.body.pos
  for tick in 0 ..< 10:
    w.tickWorld(nil)
    doAssert unit.body.pos == before,
      "A sealed footprint must not eject through unrelated terrain"
    doAssert unit.state == UnitMoving and unit.goal == tile2(35, 40)
    doAssert unit.orderQueue.len == 1 and not unit.orderFailed
    doAssert unit.carryGold == 31
  w.blocker[w.map.tileIndex(39, 40)] = 0
  w.blocker[w.map.tileIndex(39, 41)] = 0
  inc w.pathTerrainRevision
  w.tickWorld(nil)
  w.assertBodyOpen(unit)

block staleConstructionAssociationOutsideCentre:
  let w = trafficFixture(0, "opposing").world
  let mill = w.addMill(tile2(40, 40))
  let id = w.spawnUnit(0, PeonUnit, tile2(39, 40))
  let unit = w.units[w.unitIndex(id)]
  w.displace(unit, fixedVec2(39.9'fx, 40.5'fx))
  unit.constructionSiteId = mill.id
  unit.carryWood = 11
  w.tickWorld(nil)
  w.assertBodyOpen(unit)
  doAssert unit.constructionSiteId == NoEntity
  doAssert unit.carryWood == 11 and unit.state == UnitIdle

echo "Blocked exits preserve intent and stale construction links recover"

block constructionStartsBesideOverlappingBuilder:
  let w = trafficFixture(0, "opposing").world
  let id = w.spawnUnit(0, PeonUnit, tile2(39, 40))
  let unit = w.units[w.unitIndex(id)]
  w.displace(unit, fixedVec2(39.9'fx, 40.5'fx))
  w.players[0].gold = 5000
  w.players[0].wood = 5000
  doAssert w.applyBuild(0, id, LumberMillBuilding.ord.int32, 40, 40)
  let siteIndex = w.buildingIndex(unit.targetId)
  doAssert unit.constructionSiteId == NoEntity
  for tick in 0 ..< BuildingTable[LumberMillBuilding].buildTicks + 100:
    w.tickWorld(nil)
    w.assertBodyOpen(unit)
    doAssert not unit.orderFailed
    if w.buildings[siteIndex].state == BuildingComplete: break
  doAssert w.buildings[siteIndex].state == BuildingComplete,
    "The overlapping perimeter builder must recover and finish its mill"

echo "A real mill placement no longer strands its perimeter builder"

block legitimateInteriorBuilder:
  for interrupted in [false, true]:
    let w = trafficFixture(0, "opposing").world
    let id = w.spawnUnit(0, PeonUnit, tile2(40, 40))
    let unit = w.units[w.unitIndex(id)]
    w.players[0].gold = 5000
    w.players[0].wood = 5000
    doAssert w.applyBuild(0, id, LumberMillBuilding.ord.int32, 40, 40)
    let siteIndex = w.buildingIndex(unit.targetId)
    let inside = unit.body.pos
    w.tickWorld(nil)
    doAssert unit.body.pos == inside and unit.state == UnitBuilding
    doAssert unit.constructionSiteId == w.buildings[siteIndex].id
    if interrupted:
      doAssert w.applyMove(0, id, 35, 40)
    else:
      w.buildings[siteIndex].buildTicks = 1
    for tick in 0 ..< 120:
      w.tickWorld(nil)
      if unit.constructionSiteId == NoEntity: break
    doAssert unit.constructionSiteId == NoEntity
    w.assertBodyOpen(unit)
    if not interrupted: doAssert w.buildings[siteIndex].state == BuildingComplete
    else:
      doAssert unit.state == UnitMoving and unit.goal == tile2(35, 40)
      doAssert not unit.orderFailed

block genuineMineInterior:
  let w = trafficFixture(0, "miners").world
  let mine = w.buildings[w.buildingIndex(FirstMineId)]
  let id = w.spawnUnit(0, PeonUnit,
    tile2(mine.origin.x.int32 - 1, mine.origin.y.int32))
  let unit = w.units[w.unitIndex(id)]
  doAssert w.applyHarvest(0, id, mine.id, 0)
  w.tickWorld(nil)
  doAssert unit.state == UnitInMine
  w.place(unit, mine.origin)
  let inside = unit.body.pos
  w.tickWorld(nil)
  doAssert unit.state == UnitInMine and unit.body.pos == inside

echo "Intentional builder and mine interiors retain their normal lifecycle"
