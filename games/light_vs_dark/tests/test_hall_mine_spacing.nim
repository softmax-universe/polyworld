## Town halls keep five clear grid tiles around every existing gold mine.
import trafficfixture

proc fixture(): tuple[world: World, peon: Unit, mine: Building] =
  ## Supplies an unobstructed mine and a funded builder outside its buffer.
  result.world = trafficFixture(0, "open").world
  result.world.players[0].gold = 10000
  result.world.players[0].wood = 10000
  let id = result.world.spawnUnit(0, PeonUnit, tile2(20, 20))
  result.peon = result.world.units[result.world.unitIndex(id)]
  result.mine = result.world.buildings[result.world.buildingIndex(FirstMineId)]

proc beside(mine: Building, dx, dy, gap: int32): Tile2 =
  ## Counts empty tiles from the full mine and town hall footprints.
  let
    hall = BuildingTable[TownHallBuilding].footprint
    x =
      if dx < 0: mine.origin.x.int32 - hall.width - gap
      elif dx > 0: mine.origin.x.int32 + mine.footprint.width + gap
      else: mine.origin.x.int32
    y =
      if dy < 0: mine.origin.y.int32 - hall.depth - gap
      elif dy > 0: mine.origin.y.int32 + mine.footprint.depth + gap
      else: mine.origin.y.int32
  tile2(x, y)

block allEdgesAndCornersUseFullFootprints:
  let (w, worker, mine) = fixture()
  for dx in -1'i32 .. 1'i32:
    for dy in -1'i32 .. 1'i32:
      if dx == 0 and dy == 0: continue
      for gap in [0'i32, 4'i32, 5'i32]:
        let
          origin = mine.beside(dx, dy, gap)
          allowed = gap >= 5
        doAssert w.canPlace(TownHallBuilding, origin.x, origin.y) == allowed
        doAssert w.canPlace(0, TownHallBuilding, origin.x, origin.y,
          worker.id) == allowed
        doAssert w.canQueueBuild(0, worker.id, TownHallBuilding.ord.int32,
          origin.x, origin.y) == allowed
  let forbidden = mine.beside(-1, 0, 4)
  w.place(worker, forbidden)
  doAssert not w.canPlace(0, TownHallBuilding, forbidden.x, forbidden.y,
    worker.id), "Standing inside a blueprint cannot bypass mine spacing"

block rejectedBuildsPreserveOrdersResourcesAndWorld:
  let
    (w, worker, mine) = fixture()
    origin = mine.beside(-1, 0, 4)
  doAssert w.applyMove(0, worker.id, 22, 20)
  doAssert w.applyMove(0, worker.id, 24, 20, append = true)
  let before = Game(world: w).stateHash()
  for append in [false, true]:
    doAssert not w.applyBuild(0, worker.id, TownHallBuilding.ord.int32,
      origin.x, origin.y, append = append)
    doAssert Game(world: w).stateHash() == before
  let permitted = mine.beside(-1, 0, 5)
  doAssert w.applyBuild(0, worker.id, TownHallBuilding.ord.int32,
    permitted.x, permitted.y)
  doAssert w.buildings[^1].kind == TownHallBuilding
  doAssert w.players[0].gold == 10000 - BuildingTable[TownHallBuilding].gold
  doAssert w.players[0].wood == 10000 - BuildingTable[TownHallBuilding].wood

block queuedPlansUseTheSameClearance:
  let
    (w, worker, mine) = fixture()
    valid = mine.beside(-1, 0, 5)
    invalid = mine.beside(-1, 0, 4)
    count = w.buildings.len
  doAssert w.applyBuild(0, worker.id, TownHallBuilding.ord.int32,
    valid.x, valid.y, append = true)
  doAssert worker.orderQueue.len == 1 and w.buildings.len == count
  doAssert w.players[0].gold == 10000 and w.players[0].wood == 10000
  worker.orderQueue[0].second = invalid.x.int32
  worker.orderQueue[0].third = invalid.y.int32
  doAssert w.applyMove(0, worker.id, 24, 20, append = true)
  w.players[0].gold = 0
  w.players[0].wood = 0
  for tick in 0 ..< TickRate * 10: w.tickWorld(nil)
  doAssert worker.orderQueue.len == 0 and worker.tile == tile2(24, 20),
    "An invalidated build must skip instead of waiting forever for resources"
  doAssert w.buildings.len == count
  doAssert w.players[0].gold == 0 and w.players[0].wood == 0

block onlyTownHallsAreRestrictedAndDepletedMinesStillCount:
  let
    (w, worker, mine) = fixture()
    origin = mine.beside(-1, 0, 0)
    index = w.buildingIndex(mine.id)
  for kind in [FarmBuilding, LumberMillBuilding]:
    doAssert w.canPlace(0, kind, origin.x, origin.y, worker.id)
  w.buildings[index].goldLeft = 0
  doAssert not w.canPlace(TownHallBuilding, origin.x, origin.y)
  w.buildings[index].state = BuildingDying
  w.buildings[index].hp = 0
  doAssert w.canPlace(TownHallBuilding, origin.x, origin.y)

echo "Town hall mine spacing: boundaries, previews, commands and queues passed"
