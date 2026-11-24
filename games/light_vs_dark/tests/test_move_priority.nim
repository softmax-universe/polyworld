## Active direct moves win; successful completion restores ordinary idle combat.
import trafficfixture

block moveDoesNotDetourThenReacquires:
  let
    world = trafficFixture(0, "open").world
    soldierId = world.spawnUnit(0, SoldierUnit, tile2(38, 30))
    enemyId = world.spawnUnit(1, PeonUnit, tile2(43, 30))
    soldier = world.units[world.unitIndex(soldierId)]
    enemy = world.units[world.unitIndex(enemyId)]
  world.rebuildVision()
  doAssert world.applyAttack(0, soldierId, enemyId)
  doAssert world.applyMove(0, soldierId, 40, 30)
  let hp = enemy.hp
  var arrived = false
  for tick in 0 ..< TickRate * 12:
    world.tickWorld(nil)
    doAssert soldier.targetId == NoEntity
    doAssert enemy.hp == hp
    if soldier.state == UnitIdle:
      arrived = true
      break
    doAssert soldier.state == UnitMoving and soldier.holdPosition
  doAssert arrived and not soldier.holdPosition
  doAssert length(soldier.body.pos - fixedVec2(40.5'fx, 30.5'fx)) <= 0.4'fx
  let peer = world.clone()
  doAssert Game(world: world).stateHash() == Game(world: peer).stateHash()
  soldier.holdPosition = true
  doAssert Game(world: world).stateHash() != Game(world: peer).stateHash()
  world.restore(peer)
  for tick in 0 ..< TickRate * 8:
    world.tickWorld(nil)
  doAssert not world.hasUnit(enemyId) or
    world.units[world.unitIndex(enemyId)].hp < hp

block unreachableMoveDoesNotResumeChasing:
  let
    world = trafficFixture(0, "open").world
    id = world.spawnUnit(0, SoldierUnit, tile2(40, 30))
    enemyId = world.spawnUnit(1, PeonUnit, tile2(43, 30))
    unit = world.units[world.unitIndex(id)]
    enemy = world.units[world.unitIndex(enemyId)]
    origin = unit.body.pos
  # Keep the enemy visible beyond the sealed ring without another combatant.
  discard world.spawnUnit(0, PeonUnit, tile2(44, 30))
  for y in 29'i32 .. 31'i32:
    for x in 39'i32 .. 41'i32:
      # Enclose legal ground; starts inside obstacles recover separately.
      if x == 40 and y == 30:
        continue
      world.blocker[world.map.tileIndex(x, y)] = TreeBlocker
  world.rebuildVision()
  doAssert world.visible(0, enemy.tile)
  doAssert world.applyAttack(0, id, enemyId)
  doAssert world.applyMove(0, id, 50, 30)
  let hp = enemy.hp
  for tick in 0 ..< TickRate * 4:
    world.tickWorld(nil)
    # A sealed route may wait for terrain changes or fail. Neither outcome
    # may restore the chase that the direct move replaced.
    doAssert unit.state in {UnitIdle, UnitMoving} and unit.holdPosition
    doAssert unit.targetId == NoEntity
    doAssert unit.body.pos == origin and unit.animation == IdleAnimation
    doAssert enemy.hp == hp
  doAssert world.applyAttackMove(0, id, 50, 30)
  doAssert not unit.holdPosition
  var reacquired = false
  for tick in 0 ..< TickRate:
    world.tickWorld(nil)
    if unit.targetId == enemyId:
      reacquired = true
      break
  doAssert reacquired

echo "Direct move priority, completed acquisition and blocked-move hold passed"
