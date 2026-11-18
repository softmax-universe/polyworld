## Selected order markers follow authoritative orders without simulation writes.
import trafficfixture
import ../[ordermarkers, replays]

proc marker(x, y: int32, attack = false,
    offset = FixedVec2Zero): OrderMarker =
  ## Builds an expected tile-space destination including its formation offset.
  OrderMarker(position: fixedVec2(fixed(x) + FixedHalf,
    fixed(y) + FixedHalf) + offset, attack: attack)

proc worker(world: World, owner = 0'i32, x = 30'i32, y = 30'i32): Unit =
  ## Spawns one passive worker in the open fixture without automatic combat.
  let id = world.spawnUnit(owner, PeonUnit, tile2(x, y))
  world.units[world.unitIndex(id)]

block movementLifecycle:
  let
    world = trafficFixture(0, "open").world
    unit = world.worker()
  doAssert world.applyMove(0, unit.id, 32, 30)
  doAssert world.applyMove(0, unit.id, 35, 30, append = true)
  doAssert world.applyMove(0, unit.id, 35, 34, append = true)
  let expected = @[marker(32, 30), marker(35, 30), marker(35, 34)]
  let before = Game(world: world).stateHash()
  doAssert world.selectedOrderMarkers(@[unit.id], 0) == expected
  doAssert world.selectedOrderMarkers(@[], 0).len == 0
  doAssert world.selectedOrderMarkers(@[unit.id], 0) == expected
  doAssert Game(world: world).stateHash() == before
  var completedFirst = false
  for tick in 0 ..< TickRate * 30:
    world.tickWorld(nil)
    let markers = world.selectedOrderMarkers(@[unit.id], 0)
    if unit.goal == tile2(35, 30) and unit.state == UnitMoving:
      doAssert markers == expected[1 .. 2]
      completedFirst = true
    if unit.state == UnitIdle and unit.orderQueue.len == 0:
      doAssert markers.len == 0
      break
  doAssert completedFirst and unit.state == UnitIdle
  doAssert unit.tile == tile2(35, 34)
  doAssert world.applyMove(0, unit.id, 36, 34)
  doAssert world.applyMove(0, unit.id, 37, 34, append = true)
  doAssert world.applyMove(0, unit.id, 39, 34)
  doAssert world.selectedOrderMarkers(@[unit.id], 0) == @[marker(39, 34)]
  doAssert world.applyCancel(0, unit.id)
  doAssert world.selectedOrderMarkers(@[unit.id], 0).len == 0
echo "Markers track queue completion, cancellation, replacement and reselection"

block fullQueueAndGroupDestinations:
  let
    world = trafficFixture(0, "open").world
    first = world.worker()
    second = world.worker(x = 30, y = 32)
  for unit in [first, second]:
    doAssert world.applyMove(0, unit.id, 31, 30)
    for i in 0 ..< MaxUnitOrders:
      doAssert world.applyMove(0, unit.id, 32 + i.int32, 30, append = true)
  let markers = world.selectedOrderMarkers(@[first.id, second.id, first.id], 0)
  doAssert markers.len == MaxUnitOrders + 1
  for i, target in markers:
    doAssert target == marker(31 + i.int32, 30)
  let
    left = fixedVec2(-0.2'fx, 0.1'fx)
    right = fixedVec2(0.2'fx, 0.1'fx)
  doAssert world.applyMove(0, first.id, 40, 40, left)
  doAssert world.applyMove(0, second.id, 40, 40, right)
  doAssert world.applyMove(0, first.id, 41, 40, right, append = true)
  doAssert world.selectedOrderMarkers(@[first.id, second.id], 0) == @[
    marker(40, 40, offset = left), marker(41, 40, offset = right),
    marker(40, 40, offset = right)]
echo "All 32 queued destinations survive and formations retain exact offsets"

block attackMoveKeepsItsDestinationDuringCombat:
  let
    world = trafficFixture(0, "open").world
    id = world.spawnUnit(0, SoldierUnit, tile2(30, 30))
    unit = world.units[world.unitIndex(id)]
    enemy = world.worker(1, 33, 30)
    offset = fixedVec2(0.2'fx, -0.1'fx)
  enemy.hp = 1
  world.rebuildVision()
  doAssert world.applyAttackMove(0, id, 37, 30, offset)
  doAssert world.applyMove(0, id, 37, 30, offset, append = true)
  doAssert world.applyAttackMove(0, id, 38, 34, append = true)
  let expected = @[marker(37, 30, true, offset),
    marker(37, 30, false, offset), marker(38, 34, true)]
  doAssert world.selectedOrderMarkers(@[id], 0) == expected
  var fought = false
  for tick in 0 ..< TickRate * 15:
    world.tickWorld(nil)
    if unit.state in {UnitChasing, UnitAttacking}:
      doAssert world.selectedOrderMarkers(@[id], 0) == expected
      fought = true
    if fought and not world.entityAlive(enemy.id): break
  doAssert fought and not world.entityAlive(enemy.id)
  doAssert world.selectedOrderMarkers(@[id], 0) == expected
echo "Attack-move markers retain their original goal and attack color in combat"

block selectionScopeAndInvalidDestinations:
  let
    world = trafficFixture(0, "open").world
    owned = world.worker()
    enemy = world.worker(1, 30, 35)
  doAssert world.applyMove(0, owned.id, 31, 30)
  doAssert world.applyMove(1, enemy.id, 31, 35)
  let selected = @[owned.id, enemy.id, FirstBuildingId, 123456789'i32]
  doAssert world.selectedOrderMarkers(selected, 0) == @[marker(31, 30)]
  doAssert world.selectedOrderMarkers(selected, 1) == @[marker(31, 35)]
  doAssert world.selectedOrderMarkers(selected, -1) ==
    @[marker(31, 30), marker(31, 35)]
  doAssert World(nil).selectedOrderMarkers(selected, 0).len == 0
  owned.orderQueue = @[
    UnitOrder(kind: ActionMove, first: -1, second: 30),
    UnitOrder(kind: ActionAttackMove, first: world.map.side, second: 30),
    UnitOrder(kind: ActionMove, first: 31, second: 30,
      offset: fixedVec2(1'fx, 0'fx)),
    UnitOrder(kind: ActionHarvest, first: 35, second: 30),
    UnitOrder(kind: ActionAttack, first: enemy.id),
    UnitOrder(kind: ActionDeposit, first: FirstBuildingId)]
  doAssert world.selectedOrderMarkers(@[owned.id], 0) == @[marker(31, 30)]
  for state in [UnitDying, UnitInMine]:
    owned.state = state
    doAssert world.selectedOrderMarkers(@[owned.id], 0).len == 0
  owned.state = UnitMoving
  owned.hp = 0
  doAssert world.selectedOrderMarkers(@[owned.id], 0).len == 0
  owned.hp = 100
  owned.autoAttacking = true
  doAssert world.selectedOrderMarkers(@[owned.id], 0).len == 0
echo "Selection markers hide foreign, dead, mining and non-movement orders"
