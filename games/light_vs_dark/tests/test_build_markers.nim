## Queued construction ghosts follow only the selected peons' future plans.
import trafficfixture
import ../[ordermarkers, replays]

proc worker(world: World, owner = 0'i32, x = 30'i32, y = 30'i32): Unit =
  ## Spawns one worker in the open fixture.
  let id = world.spawnUnit(owner, PeonUnit, tile2(x, y))
  world.units[world.unitIndex(id)]

proc plan(x, y: int32, kind = FarmBuilding): UnitOrder =
  ## Encodes a future building's type and footprint origin.
  UnitOrder(kind: ActionBuild, first: kind.ord.int32, second: x, third: y)

proc ghost(x, y: int32, kind = FarmBuilding, owner = 0'i32): BuildMarker =
  ## Builds an expected ghost for a selected peon's deferred construction.
  BuildMarker(owner: owner, kind: kind, origin: tile2(x, y))

block selectionScopeAndReselection:
  let
    world = trafficFixture(0, "open").world
    first = world.worker()
    second = world.worker(x = 30, y = 33)
    enemy = world.worker(owner = 1, x = 30, y = 36)
  first.orderQueue = @[plan(34, 30), plan(38, 30, LumberMillBuilding)]
  second.orderQueue = @[plan(34, 30), plan(34, 34)]
  enemy.orderQueue = @[plan(34, 30)]
  let
    firstGhosts = @[ghost(34, 30), ghost(38, 30, LumberMillBuilding)]
    secondGhosts = @[ghost(34, 30), ghost(34, 34)]
    selected = @[first.id, second.id, first.id, enemy.id,
      FirstBuildingId, 123456789'i32]
    before = Game(world: world).stateHash()
  doAssert world.selectedBuildMarkers(@[first.id], 0) == firstGhosts
  doAssert world.selectedBuildMarkers(@[], 0).len == 0
  doAssert world.selectedBuildMarkers(@[second.id], 0) == secondGhosts
  doAssert world.selectedBuildMarkers(@[first.id], 0) == firstGhosts
  doAssert world.selectedBuildMarkers(selected, 0) ==
    firstGhosts & @[ghost(34, 34)]
  doAssert world.selectedBuildMarkers(selected, 1) ==
    @[ghost(34, 30, owner = 1)]
  doAssert world.selectedBuildMarkers(selected, -1) ==
    firstGhosts & @[ghost(34, 34), ghost(34, 30, owner = 1)]
  doAssert World(nil).selectedBuildMarkers(selected, 0).len == 0
  doAssert Game(world: world).stateHash() == before
echo "Build ghosts follow selection, owner scope and reselection without writes"

block malformedPlansAndUnavailableWorkers:
  let
    world = trafficFixture(0, "open").world
    unit = world.worker()
    side = world.map.side
    selected = @[unit.id]
  unit.orderQueue = @[
    plan(34, 30), plan(34, 30),
    plan(34, 30, LumberMillBuilding),
    plan(-1, 30), plan(34, -1), plan(side, 30), plan(34, side),
    plan(side - 1, 30), plan(34, side - 1),
    plan(high(int32), 30), plan(34, high(int32)),
    plan(34, 30, GoldMineBuilding),
    UnitOrder(kind: ActionBuild, first: -1, second: 34, third: 30),
    UnitOrder(kind: ActionBuild, first: high(int32), second: 34, third: 30),
    UnitOrder(kind: ActionBuild, first: FarmBuilding.ord.int32,
      second: 34, third: 30, offset: fixedVec2(FixedHalf, FixedZero)),
    UnitOrder(kind: ActionMove, first: 34, second: 30),
    UnitOrder(kind: ActionHarvest, first: 34, second: 30)]
  doAssert world.selectedBuildMarkers(selected, 0) ==
    @[ghost(34, 30), ghost(34, 30, LumberMillBuilding)]
  unit.state = UnitInMine
  doAssert world.selectedBuildMarkers(selected, 0) ==
    @[ghost(34, 30), ghost(34, 30, LumberMillBuilding)]
  unit.state = UnitDying
  doAssert world.selectedBuildMarkers(selected, 0).len == 0
  unit.state = UnitIdle
  unit.hp = 0
  doAssert world.selectedBuildMarkers(selected, 0).len == 0
  unit.hp = 100
  unit.kind = SoldierUnit
  doAssert world.selectedBuildMarkers(selected, 0).len == 0
echo "Invalid footprints and unavailable or non-peon selections have no ghosts"

block buildQueueLifecycle:
  let
    world = trafficFixture(0, "open").world
    unit = world.worker()
    selected = @[unit.id]
    buildingsBefore = world.buildings.len
  world.players[0].gold = 10000
  world.players[0].wood = 10000
  doAssert world.applyMove(0, unit.id, 32, 30)
  doAssert world.applyBuild(0, unit.id, FarmBuilding.ord.int32, 34, 30,
    append = true)
  doAssert world.applyBuild(0, unit.id, FarmBuilding.ord.int32, 38, 30,
    append = true)
  doAssert world.buildings.len == buildingsBefore
  doAssert world.selectedBuildMarkers(selected, 0) ==
    @[ghost(34, 30), ghost(38, 30)]
  var firstActivated, secondActivated, completed = false
  for tick in 0 ..< TickRate * 120:
    world.tickWorld(nil)
    let markers = world.selectedBuildMarkers(selected, 0)
    if world.buildings.len == buildingsBefore + 1:
      doAssert markers == @[ghost(38, 30)]
      firstActivated = true
    elif world.buildings.len == buildingsBefore + 2:
      doAssert markers.len == 0
      secondActivated = true
    if secondActivated and unit.state == UnitIdle:
      completed = true
      break
  doAssert firstActivated and secondActivated and completed
  doAssert world.selectedBuildMarkers(selected, 0).len == 0
  doAssert world.applyBuild(0, unit.id, FarmBuilding.ord.int32, 42, 30,
    append = true)
  doAssert world.selectedBuildMarkers(selected, 0) == @[ghost(42, 30)]
  doAssert world.applyCancel(0, unit.id)
  doAssert world.selectedBuildMarkers(selected, 0).len == 0
  doAssert world.applyBuild(0, unit.id, FarmBuilding.ord.int32, 42, 30,
    append = true)
  doAssert world.applyMove(0, unit.id, 45, 30)
  doAssert world.selectedBuildMarkers(selected, 0).len == 0
echo "Build ghosts disappear as sites activate, finish, cancel or are replaced"
