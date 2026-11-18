## Idle defenders return to their exact starting point after automatic combat.
import trafficfixture

proc soldier(w: World): Unit =
  ## Creates a defender at a fractional position in the open test arena.
  let id = w.spawnUnit(0, SoldierUnit, tile2(40, 30))
  result = w.units[w.unitIndex(id)]
  result.body.pos = fixedVec2(40.67'fx, 30.23'fx)

proc victim(w: World): Unit =
  ## Creates a passive enemy whose death requires an actual combat hit.
  let id = w.spawnUnit(1, PeonUnit, tile2(44, 30))
  result = w.units[w.unitIndex(id)]
  result.hp = 1

proc engage(w: World, unit: Unit) =
  ## Waits for genuine automatic acquisition and a visible chase displacement.
  let home = unit.body.pos
  w.rebuildVision()
  for tick in 0 ..< 80:
    w.tickWorld(nil)
    if length(unit.body.pos - home) > 0.75'fx: return
  doAssert false, "The idle defender did not start chasing"

proc settle(w: World, unit: Unit) =
  ## Runs an accepted movement or combat order through its idle transition.
  for tick in 0 ..< 500:
    w.tickWorld(nil)
    if unit.state == UnitIdle: return
  doAssert false, "The defender did not finish its order"

block killReturnsToFractionalOrigin:
  for centered in [false, true]:
    let
      w = trafficFixture(0, "open").world
      unit = w.soldier()
      enemy = w.victim()
    if centered: unit.body.pos = fixedVec2(40.5'fx, 30.5'fx)
    let home = unit.body.pos
    w.rebuildVision()
    var moved = false
    for tick in 0 ..< 400:
      w.tickWorld(nil)
      if length(unit.body.pos - home) > 1'fx: moved = true
      if not w.entityAlive(enemy.id) and unit.state == UnitIdle: break
    doAssert moved and not w.entityAlive(enemy.id)
    doAssert unit.state == UnitIdle and not unit.autoAttacking
    doAssert length(unit.body.pos - home) <= 0.001'fx,
      "An idle defender must return to its exact pre-combat position"

echo "Automatic combat kills return to the original fractional position"

block fleeingEnemyStaysVisibleThroughScout:
  let
    w = trafficFixture(0, "open").world
    unit = w.soldier()
    enemy = w.victim()
    home = unit.body.pos
  enemy.hp = 1000
  w.engage(unit)
  doAssert unit.autoAttacking and unit.autoAttackOrigin == home
  discard w.spawnUnit(0, PeonUnit, tile2(49, 32))
  w.place(enemy, tile2(49, 30))
  w.rebuildVision()
  doAssert w.visible(0, enemy.tile)
  w.tickWorld(nil)
  doAssert unit.state == UnitMoving and unit.targetId == NoEntity,
    "A visible enemy fleeing beyond the original guard area must end pursuit"
  w.settle(unit)
  doAssert length(unit.body.pos - home) <= 0.001'fx
  doAssert w.entityAlive(enemy.id)

block changedAllegianceEndsAutomaticFight:
  let
    w = trafficFixture(0, "open").world
    unit = w.soldier()
    enemy = w.victim()
    home = unit.body.pos
  enemy.hp = 1000
  w.engage(unit)
  w.diplomacy.pairs[w.diplomacy.pairIndex(0, 1)].state = Allied
  w.settle(unit)
  doAssert length(unit.body.pos - home) <= 0.001'fx

echo "Fleeing enemies and ended hostilities return defenders home"

block newOrdersOverrideAutomaticReturn:
  for command in 0 .. 3:
    let
      w = trafficFixture(0, "open").world
      unit = w.soldier()
      enemy = w.victim()
      home = unit.body.pos
    w.engage(unit)
    let stopped = unit.body.pos
    case command
    of 0:
      doAssert w.applyMove(0, unit.id, 40, 36)
      w.damageEntity(enemy.id, 10000)
    of 1:
      doAssert w.applyCancel(0, unit.id)
      w.damageEntity(enemy.id, 10000)
    of 2:
      doAssert w.applyAttack(0, unit.id, enemy.id)
    else:
      doAssert w.applyAttackMove(0, unit.id, 46, 32)
    doAssert not unit.autoAttacking
    w.settle(unit)
    case command
    of 0:
      doAssert unit.tile == tile2(40, 36)
    of 1:
      doAssert unit.body.pos == stopped
    of 2:
      doAssert not w.entityAlive(enemy.id)
      doAssert length(unit.body.pos - home) > 1'fx,
        "An explicit attack must not inherit automatic return behavior"
    else:
      doAssert not w.entityAlive(enemy.id)
      doAssert unit.tile == tile2(46, 32),
        "Attack-move must resume its commanded destination"

echo "Move, Stop, direct attack and attack-move override automatic return"

block rememberedOriginIsAuthoritative:
  let
    w = trafficFixture(0, "open").world
    unit = w.soldier()
    enemy = w.victim()
    home = unit.body.pos
  w.engage(unit)
  doAssert unit.autoAttacking and unit.autoAttackOrigin == home
  let peer = w.clone()
  let baseline = Game(world: w).stateHash()
  peer.units[0].autoAttackOrigin.x += 0.25'fx
  doAssert Game(world: peer).stateHash() != baseline
  peer.restore(w)
  peer.units[0].autoAttacking = false
  doAssert Game(world: peer).stateHash() != baseline
  peer.restore(w)
  doAssert Game(world: peer).stateHash() == baseline
  for tick in 0 ..< 400:
    w.tickWorld(nil)
    peer.tickWorld(nil)
    doAssert Game(world: w).stateHash() == Game(world: peer).stateHash()
    if not w.entityAlive(enemy.id) and unit.state == UnitIdle: break
  doAssert not w.entityAlive(enemy.id) and unit.state == UnitIdle
  doAssert length(unit.body.pos - home) <= 0.001'fx

echo "Automatic return state survives clones and participates in peer hashes"
