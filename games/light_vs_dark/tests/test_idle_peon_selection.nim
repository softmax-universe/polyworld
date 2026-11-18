## Idle-worker cycling selects owned available peons without changing the world.
import trafficfixture
import ../[replays, unitselection]

block stableCycleAndReadOnlySelection:
  let
    w = trafficFixture(0, "open").world
    first = w.spawnUnit(0, PeonUnit, tile2(30, 30))
    foreign = w.spawnUnit(1, PeonUnit, tile2(31, 30))
    soldier = w.spawnUnit(0, SoldierUnit, tile2(32, 30))
    second = w.spawnUnit(0, PeonUnit, tile2(33, 30))
    last = w.spawnUnit(0, PeonUnit, tile2(34, 30))
  w.units[w.unitIndex(last)].carryWood = 17
  let before = Game(world: w).stateHash()
  doAssert w.nextIdlePeon(0, NoEntity) == first
  doAssert w.nextIdlePeon(0, first) == second
  doAssert w.nextIdlePeon(0, second) == last
  doAssert w.nextIdlePeon(0, last) == first
  doAssert w.nextIdlePeon(0, soldier) == second
  doAssert w.nextIdlePeon(1, NoEntity) == foreign
  doAssert w.nextIdlePeon(0, FirstBuildingId) == first
  for i in 0 ..< 20:
    discard w.nextIdlePeon(0, first)
  doAssert Game(world: w).stateHash() == before,
    "Cycling selection must not issue orders or change simulation state"
  w.units[w.unitIndex(second)].hp = 0
  doAssert w.nextIdlePeon(0, first) == last

echo "Idle peons cycle in stable order, wrap and preserve simulation state"

block busyAndQueuedPeonsAreExcluded:
  for state in [UnitMoving, UnitChasing, UnitBuilding, UnitToBuild,
      UnitToTree, UnitChopping, UnitToMine, UnitInMine, UnitToDropWood,
      UnitDepositWood, UnitDying]:
    let
      w = trafficFixture(0, "open").world
      id = w.spawnUnit(0, PeonUnit, tile2(30, 30))
    w.units[w.unitIndex(id)].state = state
    doAssert w.nextIdlePeon(0, NoEntity) == NoEntity
  let
    w = trafficFixture(0, "open").world
    id = w.spawnUnit(0, PeonUnit, tile2(30, 30))
    unit = w.units[w.unitIndex(id)]
  unit.hasGoal = true
  doAssert w.nextIdlePeon(0, NoEntity) == NoEntity
  unit.hasGoal = false
  unit.orderQueue = @[UnitOrder(kind: ActionMove, first: 35, second: 30)]
  doAssert w.nextIdlePeon(0, NoEntity) == NoEntity,
    "An idle transition before a queued order is not an available worker"
  unit.orderQueue.setLen(0)
  doAssert w.nextIdlePeon(0, id) == id
  unit.hp = 0
  doAssert w.nextIdlePeon(0, NoEntity) == NoEntity

block invalidScopesAndEmptySelection:
  let w = trafficFixture(0, "open").world
  doAssert World(nil).nextIdlePeon(0, NoEntity) == NoEntity
  doAssert w.nextIdlePeon(0, NoEntity) == NoEntity
  discard w.spawnUnit(0, PeonUnit, tile2(30, 30))
  doAssert w.nextIdlePeon(-1, NoEntity) == NoEntity
  doAssert w.nextIdlePeon(w.players.len.int32, NoEntity) == NoEntity

echo "Busy, dead, queued and out-of-scope workers are excluded"
