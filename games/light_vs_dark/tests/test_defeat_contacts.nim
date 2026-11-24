## Body recovery is independent of diplomacy, ownership, or defeat status.
import trafficfixture

proc advanceTogether(world, peer: World, ticks: int) =
  ## Checks deterministic simulation while contact pressure resolves overlaps.
  for tick in 0 ..< ticks:
    world.tickWorld(nil)
    peer.tickWorld(nil)
    doAssert Game(world: world).stateHash() == Game(world: peer).stateHash(),
      "Contact recovery diverged at tick " & $world.tick

proc overlappingPair(relation: RelationState): World =
  ## Starts foreign owners at one exact point without autonomous combat.
  result = trafficFixture(0, "open").world
  let pair = result.diplomacy.pairIndex(0, 1)
  result.diplomacy.pairs[pair].state = relation
  for owner in 0'i32 .. 1'i32:
    let id = result.spawnUnit(owner, PeonUnit, tile2(40, 40))
    result.units[result.unitIndex(id)].holdPosition = true

for relation in [Neutral, Allied, AtWar]:
  block foreignBodiesSeparate:
    let
      world = overlappingPair(relation)
      peer = world.clone()
    world.advanceTogether(peer, 120)
    let first = world.units[0]
    let second = world.units[1]
    doAssert length(first.body.pos - second.body.pos) >=
      first.body.radius + second.body.radius - 0.002'fx,
      "Coincident foreign units remained stuck in relation " & $relation
    doAssert first.state == UnitIdle and second.state == UnitIdle
    doAssert first.hp > 0 and second.hp > 0
echo "PASS coincident enemies, allies and neutrals separate deterministically"

block denseMixedOwnersSeparate:
  let world = trafficFixture(0, "open").world
  world.diplomacy.pairs[world.diplomacy.pairIndex(0, 1)].state = Neutral
  let center = fixedVec2(40.5'fx, 40.5'fx)
  for i in 0 ..< 40:
    let id = world.spawnUnit(i.int32 mod 2, PeonUnit, tile2(40, 40))
    world.units[world.unitIndex(id)].holdPosition = true
  let peer = world.clone()
  world.advanceTogether(peer, 600)
  for unit in world.units:
    doAssert length(unit.body.pos - center) > 0.2'fx,
      "Mixed bucket overflow left a unit fixed at its original point"
    doAssert unit.state == UnitIdle and not unit.hasGoal
  var deepestOverlap = FixedZero
  for i in 0 ..< world.units.len:
    for j in i + 1 ..< world.units.len:
      let
        first = world.units[i]
        second = world.units[j]
        overlap = first.body.radius + second.body.radius -
          length(first.body.pos - second.body.pos)
      deepestOverlap = max(deepestOverlap, overlap)
  doAssert deepestOverlap <= 0.01'fx,
    "Dense recovery left body penetration of " & $deepestOverlap
  echo "PASS dense mixed-owner recovery; maximum overlap: ", deepestOverlap

block defeatedArmySeparatesAfterCombat:
  var map = trafficFixture(0, "open").world.map
  map.hallOrigin.add tile2(3, 72)
  let world = newWorld(map, 10000, DiplomacySettings(enabled: true))
  world.units.setLen(0)
  for slot in world.unitSlot.mitems:
    slot = -1
  for tile in world.occupancy.mitems:
    tile = 0
  let
    attacker = world.spawnUnit(0, SoldierUnit, tile2(40, 40))
    defender = world.spawnUnit(1, SoldierUnit, tile2(40, 40))
  world.rebuildVision()
  doAssert world.applyAttack(0, attacker, defender)
  doAssert world.applyAttack(1, defender, attacker)
  var hall = NoEntity
  for building in world.buildings:
    if building.owner == 1 and building.kind == TownHallBuilding:
      hall = building.id
  doAssert hall != NoEntity
  world.damageEntity(hall, world.buildings[world.buildingIndex(hall)].hp)
  # Grace duration is covered separately; exercise its exact expiry here.
  world.players[1].hallLossDeadline = world.tick + 1
  let peer = world.clone()
  world.advanceTogether(peer, 1)
  doAssert world.players[1].defeated
  doAssert not world.atWar(0, 1)
  doAssert not world.over, "The third player keeps simulation running"
  world.advanceTogether(peer, 120)
  let
    first = world.units[world.unitIndex(attacker)]
    second = world.units[world.unitIndex(defender)]
  doAssert first.hp > 0 and second.hp > 0
  doAssert first.state == UnitIdle and second.state == UnitIdle
  doAssert length(first.body.pos - second.body.pos) >=
    first.body.radius + second.body.radius - 0.002'fx,
    "Combatants stayed embedded after the defeated army became neutral"
  doAssert world.applyMove(0, attacker, 45, 40)
  doAssert peer.applyMove(0, attacker, 45, 40)
  world.advanceTogether(peer, 240)
  doAssert first.state == UnitIdle and not first.hasGoal,
    "Post-defeat mover remained " & $first.state & " at " & $first.body.pos &
    " with goal " & $first.goal & " and blocked ticks " & $first.blockedTicks
  doAssert length(first.body.pos - fixedVec2(45.5'fx, 40.5'fx)) < 0.4'fx,
    "A survivor could not leave its former opponent after elimination"
  echo "PASS hall defeat releases combatants and permits subsequent movement"

block opposingForeignBodiesPassWithoutPhasing:
  let
    fixture = trafficFixture(2, "opposing")
    world = fixture.world
  world.units[1].owner = 1
  for unit in world.units:
    unit.kind = PeonUnit
  let peer = world.clone()
  var closest = 10'fx
  for tick in 0 ..< 240:
    world.advanceTogether(peer, 1)
    let separation = length(world.units[0].body.pos - world.units[1].body.pos)
    closest = min(closest, separation)
    doAssert separation >=
      world.units[0].body.radius + world.units[1].body.radius - 0.002'fx,
      "Foreign movers crossed through each other's bodies"
  for i, unit in world.units:
    doAssert length(unit.body.pos - fixture.goals[i]) <= 0.4'fx,
      "Foreign movers must finish by walking around each other"
  echo "PASS opposing foreign movement; closest separation: ", closest
