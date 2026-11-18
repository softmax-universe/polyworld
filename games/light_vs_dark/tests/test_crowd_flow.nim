## Clumps keep advancing while neighbors push and turn toward their routes.
import trafficfixture, polyworld/bodies

block turnWhileWalking:
  let fixture = trafficFixture(2, "opposing")
  let unit = fixture.world.units[0]
  fixture.world.tickWorld(nil)
  unit.body.facing = FixedPi
  let before = unit.body.pos
  fixture.world.tickWorld(nil)
  doAssert unit.body.pos.x > before.x,
    "Facing changes must not pause a clear movement step"

proc clumpFixture(opposing: bool, spreadGoals = false): TrafficFixture =
  ## Packs exact goals and starts more closely than an exclusive tile grid.
  result = trafficFixture(0, "opposing")
  let w = result.world
  for i in 0 ..< 100:
    let
      group = if opposing: i div 50 else: 0
      rank = if opposing: i mod 50 else: i
      column = rank mod 10
      row = rank div 10
      start = fixedVec2(
        (if group == 0: 24.5'fx else: 48.5'fx) +
          fixed(column.int32) * 0.4'fx,
        34.5'fx + fixed(row.int32) * 0.4'fx
      )
      goal =
        if spreadGoals:
          fixedVec2(46.5'fx + fixed(column.int32),
            34.5'fx + fixed(row.int32))
        else:
          start + fixedVec2(
            (if group == 0: 24'fx else: -24'fx), FixedZero
          )
      id = w.spawnUnit(0, SoldierUnit, tile2(whole(start.x), whole(start.y)))
      unit = w.units[w.unitIndex(id)]
      goalTile = tile2(whole(goal.x), whole(goal.y))
    unit.body.pos = start
    unit.tile = tile2(whole(start.x), whole(start.y))
    result.ids.add id
    result.starts.add start
    result.goals.add goal
    doAssert w.applyMove(
      0, id, goalTile.x.int32, goalTile.y.int32,
      goal - fixedVec2(fixed(goalTile.x.int32) + FixedHalf,
        fixed(goalTile.y.int32) + FixedHalf)
    )

for scenario in ["together", "opposing", "building", "overpacked-building"]:
  let fixture = clumpFixture(
    scenario == "opposing", spreadGoals = scenario == "building"
  )
  if scenario in ["building", "overpacked-building"]:
    for y in 32'i32 .. 39'i32:
      for x in 35'i32 .. 41'i32:
        fixture.world.blocker[fixture.world.map.tileIndex(x, y)] = TreeBlocker
  let peer = fixture.world.clone()
  var
    stalled = 0
    reached = newSeq[bool](fixture.world.units.len)
  for tick in 0 ..< 900:
    var before: seq[FixedVec2]
    for unit in fixture.world.units:
      before.add unit.body.pos
    fixture.world.tickWorld(nil)
    peer.tickWorld(nil)
    doAssert Game(world: fixture.world).stateHash() ==
      Game(world: peer).stateHash(), "Local flow must survive alternating worlds"
    for i, unit in fixture.world.units:
      if length(unit.body.pos - fixture.goals[i]) <= 0.4'fx:
        reached[i] = true
      doAssert not unit.orderFailed,
        "Crowd contact must never abandon the destination"
      for dx in [-unit.body.radius, unit.body.radius]:
        for dy in [-unit.body.radius, unit.body.radius]:
          let corner = unit.body.pos + fixedVec2(dx, dy)
          doAssert fixture.world.tileOpen(whole(corner.x), whole(corner.y)),
            "Pushed clumps must keep their entire footprints outside buildings"
      doAssert length(unit.body.pos - before[i]) < 0.2'fx,
        "Combined movement and pressure must remain bounded"
      if unit.hasGoal and length(unit.body.pos - fixture.goals[i]) > 1'fx and
          unit.body.pos == before[i]:
        inc stalled
  var
    completed = 0
    maximumDistance = FixedZero
  for i, unit in fixture.world.units:
    let distance = length(unit.body.pos - fixture.goals[i])
    maximumDistance = max(maximumDistance, distance)
    if distance <= 0.4'fx:
      inc completed
    doAssert reached[i], "Every actor must reach its destination area"
  echo "Clump ", scenario, " completed=", completed,
    " stationary unit-ticks=", stalled, " max distance=", maximumDistance
  if scenario == "overpacked-building":
    # These goals are 0.4 tiles apart for circles 0.44 tiles wide. The real
    # formation planner reserves distinct tiles, as in the building case.
    # This stress case checks arrival and bounded dispersal, not impossible
    # exact resting positions for intersecting circles.
    doAssert maximumDistance <= 1'fx,
      "An overpacked clump must remain near its destination after yielding"
  else:
    doAssert completed >= 95,
      "A dense clump must follow its route and settle at its destinations"
  doAssert stalled < 1000,
    "Crowd steering must not repeatedly pause for facing or lateral waits"

block tileDestinationsSettle:
  let fixture = trafficFixture(100, "opposing")
  for tick in 0 ..< 900:
    fixture.world.tickWorld(nil)
  for i, unit in fixture.world.units:
    doAssert not unit.orderFailed
    doAssert length(unit.body.pos - fixture.goals[i]) <= 0.4'fx,
      "Whole-tile moves must settle close enough to survive passing traffic"

echo "Crowd flow tests passed"
