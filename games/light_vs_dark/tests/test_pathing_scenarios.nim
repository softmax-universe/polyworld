## Pathing scenes exercise real paths, legal footprints, and deterministic resets.

import polyworld/pathing, pathingscenarios

for scenario in PathingScenario:
  let
    scene = createScene(scenario)
    repeated = createScene(scenario)
  doAssert scene.world.units.len == PathingUnitCount
  doAssert scene.starts.len == PathingUnitCount
  doAssert scene.goals.len == PathingUnitCount
  doAssert scene.groups.len == PathingUnitCount
  let terrain = scene.world.map.terrain[0]
  doAssert terrain.originX + scene.world.map.side.int div 2 == GridTiles div 2
  doAssert terrain.originZ + scene.world.map.side.int div 2 == GridTiles div 2
  for obstacle in scene.obstacles:
    for y in obstacle.y ..< obstacle.y + obstacle.height:
      for x in obstacle.x ..< obstacle.x + obstacle.width:
        let index = scene.world.map.tileIndex(x, y)
        if scenario == NarrowChoke:
          doAssert scene.world.blocker[index] == TreeBlocker
          doAssert scene.world.treeWood[index] == WoodPerTree
          doAssert scene.world.map.kinds[index] == TreeTile.uint8
          doAssert terrain.tiles[index].kind == TreeTile
        else:
          let building = scene.world.buildingIndex(scene.world.blocker[index])
          doAssert building >= 0
          doAssert scene.world.buildings[building].state == BuildingComplete
  doAssert scene.world.pathQueue.len == PathingUnitCount
  doAssert Game(world: scene.world).stateHash() ==
    Game(world: repeated.world).stateHash()
  var reached = newSeq[bool](PathingUnitCount)
  for tick in 0 ..< PathingDurationTicks:
    scene.world.tickWorld(nil)
    repeated.world.tickWorld(nil)
    doAssert not scene.world.over
    doAssert Game(world: scene.world).stateHash() ==
      Game(world: repeated.world).stateHash()
    for i, unit in scene.world.units:
      doAssert not unit.orderFailed,
        ScenarioNames[scenario] & ": a pathing order failed"
      doAssert unit.body.pos.x >= fixed(scene.bounds.x)
      doAssert unit.body.pos.x < fixed(scene.bounds.x + scene.bounds.width)
      doAssert unit.body.pos.y >= fixed(scene.bounds.y)
      doAssert unit.body.pos.y < fixed(scene.bounds.y + scene.bounds.height)
      for dx in [-unit.body.radius, unit.body.radius]:
        for dy in [-unit.body.radius, unit.body.radius]:
          let point = unit.body.pos + fixedVec2(dx, dy)
          doAssert scene.world.tileOpen(whole(point.x), whole(point.y)),
            ScenarioNames[scenario] & ": a body entered an obstacle"
      if length(unit.body.pos - scene.goals[i]) <= 0.4'fx:
        reached[i] = true
  var settled = 0
  for i, unit in scene.world.units:
    doAssert reached[i],
      ScenarioNames[scenario] & ": unit " & $i & " never reached its goal"
    if length(unit.body.pos - scene.goals[i]) <= 0.4'fx:
      inc settled
  echo ScenarioNames[scenario], ": all ", PathingUnitCount,
    " reached; ", settled, " settled; identical reset hashes"

echo "Manual pathing test scenes passed"
