## Crowd contacts yield visibly without letting moving bodies pass through.
import trafficfixture, pathingscenarios

block overlappingIdleBodies:
  let
    fixture = trafficFixture(0, "opposing")
    world = fixture.world
    first = world.spawnUnit(0, SoldierUnit, tile2(40, 40))
    second = world.spawnUnit(0, SoldierUnit, tile2(41, 40))
  world.units[world.unitIndex(second)].body.pos = fixedVec2(40.7'fx, 40.5'fx)
  let peer = world.clone()
  for tick in 0 ..< 4:
    world.tickWorld(nil)
    peer.tickWorld(nil)
    doAssert Game(world: world).stateHash() == Game(world: peer).stateHash()
  doAssert length(world.units[world.unitIndex(first)].body.pos -
      world.units[world.unitIndex(second)].body.pos) >= 0.43'fx,
    "Overlapping idle bodies must visibly separate within a few ticks"

block stationaryUnitYields:
  let
    fixture = trafficFixture(2, "opposing")
    world = fixture.world
  doAssert world.applyCancel(0, fixture.ids[1])
  world.units[1].body.pos = fixedVec2(40.5'fx, 40.5'fx)
  world.units[1].tile = tile2(40, 40)
  let stationaryStart = world.units[1].body.pos
  var displaced = FixedZero
  for tick in 0 ..< 150:
    let before = [world.units[0].body.pos, world.units[1].body.pos]
    world.tickWorld(nil)
    displaced = max(displaced, length(world.units[1].body.pos - stationaryStart))
    for i, unit in world.units:
      doAssert length(unit.body.pos - before[i]) < 0.2'fx
      doAssert not unit.orderFailed
  doAssert displaced > 0.05'fx,
    "A stationary friendly unit must physically yield to passing traffic"
  doAssert length(world.units[0].body.pos - fixture.goals[0]) <= 0.4'fx

for scenario in [OpposingStreams, CrossingStreams, NarrowChoke]:
  let scene = createScene(scenario)
  var deepContacts = 0
  for tick in 0 ..< PathingDurationTicks:
    scene.world.tickWorld(nil)
    for i, unit in scene.world.units:
      for j in i + 1 ..< scene.world.units.len:
        let peer = scene.world.units[j]
        if length(unit.body.pos - peer.body.pos) <
            (unit.body.radius + peer.body.radius) / 2:
          inc deepContacts
  echo ScenarioNames[scenario], " deep contact pair-ticks: ", deepContacts
  doAssert deepContacts < PathingUnitCount div 2,
    "Crowd pressure must prevent sustained deep body interpenetration"

echo "Crowd contact pressure passed"
