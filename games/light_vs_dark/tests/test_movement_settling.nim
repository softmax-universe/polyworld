## Final approaches preserve fractional goals and settle when bodies claim them.
import trafficfixture

proc peon(w: World, owner: int32, tile: Tile2): Unit =
  ## Creates one mobile body without automatic combat acquisition.
  let id = w.spawnUnit(owner, PeonUnit, tile)
  w.units[w.unitIndex(id)]

block sharedFractionalGoal:
  let
    w = trafficFixture(0, "open").world
    first = w.peon(0, tile2(37, 40))
    second = w.peon(0, tile2(43, 40))
    goal = fixedVec2(40.6'fx, 40.6'fx)
  for unit in [first, second]:
    doAssert w.applyMove(0, unit.id, 40, 40, fixedVec2(0.1'fx, 0.1'fx))
  for tick in 0 ..< 400:
    w.tickWorld(nil)
  for unit in [first, second]:
    doAssert unit.state == UnitIdle and not unit.hasGoal
    doAssert unit.animation == IdleAnimation
    doAssert not unit.orderFailed
    doAssert length(unit.body.pos - goal) < 0.7'fx
  doAssert length(first.body.pos - second.body.pos) >= 0.439'fx
  echo "PASS shared fractional destinations settle without running in place"

block occupiedNeutralDestination:
  let
    w = trafficFixture(0, "open").world
    mover = w.peon(0, tile2(35, 40))
    occupant = w.peon(1, tile2(40, 40))
    goal = occupant.body.pos
  w.diplomacy.pairs[w.diplomacy.pairIndex(0, 1)].state = Neutral
  doAssert w.applyMove(0, mover.id, 40, 40)
  for tick in 0 ..< 400:
    w.tickWorld(nil)
  doAssert mover.state == UnitIdle and not mover.orderFailed
  doAssert mover.animation == IdleAnimation
  doAssert length(mover.body.pos - goal) <= 0.7'fx
  doAssert length(mover.body.pos - occupant.body.pos) >= 0.439'fx
  echo "PASS occupied neutral goals settle on nearby open ground"

block queuedMoveAfterCrowdedArrival:
  let
    w = trafficFixture(0, "open").world
    mover = w.peon(0, tile2(37, 40))
    occupant = w.peon(0, tile2(40, 40))
    finalGoal = fixedVec2(43.7'fx, 43.3'fx)
  doAssert w.applyMove(0, mover.id, 40, 40)
  doAssert w.applyMove(
    0, mover.id, 43, 43, fixedVec2(0.2'fx, -0.2'fx), append = true
  )
  for tick in 0 ..< 400:
    w.tickWorld(nil)
  doAssert mover.state == UnitIdle and mover.orderQueue.len == 0
  doAssert length(mover.body.pos - finalGoal) <= 0.001'fx
  doAssert occupant.state == UnitIdle
  echo "PASS crowded arrival releases the next queued move"

block nearbyGoalAcrossTileBoundary:
  let
    w = trafficFixture(0, "open").world
    unit = w.peon(0, tile2(39, 40))
    goal = fixedVec2(40.35'fx, 40.63'fx)
  unit.body.pos = fixedVec2(39.97'fx, 40.4'fx)
  doAssert w.applyMove(0, unit.id, 40, 40, fixedVec2(-0.15'fx, 0.13'fx))
  w.pathQueue.setLen(0)
  unit.repathCooldown = 60
  for tick in 0 ..< 30:
    w.tickWorld(nil)
  doAssert unit.state == UnitIdle
  doAssert length(unit.body.pos - goal) <= 0.001'fx
  echo "PASS clear final approaches cross tile boundaries without a path slot"

block pathWaitUsesIdlePose:
  let
    w = trafficFixture(0, "open").world
    unit = w.peon(0, tile2(35, 40))
  doAssert w.applyMove(0, unit.id, 45, 40)
  for tick in 0 ..< 10:
    w.tickWorld(nil)
  doAssert unit.animation == RunAnimation
  unit.path.setLen(0)
  w.pathQueue.setLen(0)
  unit.repathCooldown = 60
  let before = unit.body.pos
  w.tickWorld(nil)
  doAssert unit.body.pos == before and unit.state == UnitMoving
  doAssert unit.animation == IdleAnimation
  echo "PASS waiting for a route cannot retain a running animation"

block transientPeerDoesNotClaimDestination:
  let
    w = trafficFixture(0, "open").world
    mover = w.peon(0, tile2(39, 40))
    passer = w.peon(0, tile2(40, 40))
    goal = fixedVec2(40.6'fx, 40.6'fx)
  mover.body.pos = fixedVec2(40.05'fx, 40.6'fx)
  mover.tile = tile2(40, 40)
  passer.body.pos = goal
  doAssert w.applyMove(0, mover.id, 40, 40, fixedVec2(0.1'fx, 0.1'fx))
  doAssert w.applyMove(0, passer.id, 45, 40)
  w.tickWorld(nil)
  doAssert mover.state == UnitMoving and mover.hasGoal,
    "A passing peer with a distinct destination must not claim the goal"
  for tick in 0 ..< 300:
    w.tickWorld(nil)
  doAssert mover.state == UnitIdle and not mover.orderFailed
  doAssert length(mover.body.pos - goal) <= 0.001'fx
  echo "PASS transient peers do not truncate distinct fractional destinations"
