## Routes and precise clicks must leave room for a peon's whole footprint.
import trafficfixture

proc assertFootprintOpen(w: World, unit: Unit) =
  ## Checks the same square footprint that constrains movement at walls.
  for dx in [-unit.body.radius, unit.body.radius]:
    for dy in [-unit.body.radius, unit.body.radius]:
      let point = unit.body.pos + fixedVec2(dx, dy)
      doAssert w.tileOpen(whole(point.x), whole(point.y)),
        "The unit footprint entered a building or terrain blocker"

proc finishMove(w: World, unit: Unit, ticks = 600) =
  ## Requires arrival without terrain penetration or abandoned move intent.
  for tick in 0 ..< ticks:
    w.tickWorld(nil)
    w.assertFootprintOpen(unit)
    doAssert not unit.orderFailed
    if unit.state == UnitIdle:
      return
  doAssert false, "Unit stalled at " & $unit.body.pos &
    " while moving to " & $unit.goal

block displacedStartsAtBuildingCorners:
  let w = trafficFixture(0, "opposing").world
  for y in 40'i32 .. 41'i32:
    for x in 40'i32 .. 41'i32:
      w.blocker[w.map.tileIndex(x, y)] = TreeBlocker
  let id = w.spawnUnit(0, PeonUnit, tile2(43, 39))
  let unit = w.units[w.unitIndex(id)]
  let cases = [
    (fixedVec2(43.706'fx, 39.909'fx), tile2(35, 40)),
    (fixedVec2(42.809'fx, 40.731'fx), tile2(35, 40)),
    (fixedVec2(39.156'fx, 40.470'fx), tile2(45, 40))
  ]
  for entry in cases:
    w.place(unit, tile2(whole(entry[0].x), whole(entry[0].y)))
    unit.body.pos = entry[0]
    doAssert w.applyMove(0, id, entry[1].x.int32, entry[1].y.int32)
    pathSearches = 0
    w.finishMove(unit)
    let goal = fixedVec2(fixed(entry[1].x.int32) + FixedHalf,
      fixed(entry[1].y.int32) + FixedHalf)
    doAssert length(unit.body.pos - goal) <= 0.35'fx
    doAssert pathSearches == 1,
      "A clear route around one building must not require repeated replanning"

block pushedOffPulledSegment:
  let w = trafficFixture(0, "opposing").world
  for y in 0'i32 .. 79'i32:
    if y in 39'i32 .. 40'i32:
      continue
    for x in 39'i32 .. 40'i32:
      w.blocker[w.map.tileIndex(x, y)] = TreeBlocker
  let
    id = w.spawnUnit(0, SoldierUnit, tile2(24, 39))
    unit = w.units[w.unitIndex(id)]
  doAssert w.applyMove(0, id, 54, 43)
  w.tickWorld(nil)
  doAssert unit.path.len > 0
  # Retain the route while reproducing a crowd shove at the lower entrance.
  w.place(unit, tile2(38, 40))
  unit.body.pos = fixedVec2(38.779'fx, 40.979'fx)
  w.assertFootprintOpen(unit)
  w.finishMove(unit)
  doAssert length(unit.body.pos - fixedVec2(54.5'fx, 43.5'fx)) <= 0.35'fx,
    "A shove must not leave the old pulled path pointing through a wall"

block wallFacingFractionalGoals:
  let w = trafficFixture(0, "opposing").world
  for y in 40'i32 .. 41'i32:
    for x in 40'i32 .. 41'i32:
      w.blocker[w.map.tileIndex(x, y)] = TreeBlocker
  let id = w.spawnUnit(0, PeonUnit, tile2(35, 40))
  let unit = w.units[w.unitIndex(id)]
  let cases = [
    (tile2(35, 40), tile2(39, 40), fixedVec2(0.49'fx, 0.1'fx)),
    (tile2(45, 40), tile2(42, 40), fixedVec2(-0.49'fx, 0.1'fx)),
    (tile2(40, 35), tile2(40, 39), fixedVec2(0.1'fx, 0.49'fx)),
    (tile2(40, 45), tile2(40, 42), fixedVec2(0.1'fx, -0.49'fx))
  ]
  for entry in cases:
    w.place(unit, entry[0])
    doAssert w.applyMove(0, id, entry[1].x.int32, entry[1].y.int32,
      entry[2])
    let goal = fixedVec2(fixed(entry[1].x.int32) + FixedHalf,
      fixed(entry[1].y.int32) + FixedHalf) + unit.goalOffset
    if abs(entry[2].x) > 0.4'fx:
      doAssert unit.goalOffset.y == entry[2].y
      doAssert abs(unit.goalOffset.x) <= FixedHalf - unit.body.radius
    else:
      doAssert unit.goalOffset.x == entry[2].x
      doAssert abs(unit.goalOffset.y) <= FixedHalf - unit.body.radius
    w.finishMove(unit)
    doAssert length(unit.body.pos - goal) <= 0.001'fx

block diagonalOnlyBlocker:
  let w = trafficFixture(0, "opposing").world
  w.blocker[w.map.tileIndex(40, 40)] = TreeBlocker
  let id = w.spawnUnit(0, PeonUnit, tile2(35, 35))
  let unit = w.units[w.unitIndex(id)]
  let offset = fixedVec2(0.49'fx, 0.49'fx)
  doAssert w.applyMove(0, id, 39, 39, offset)
  let goal = fixedVec2(39.5'fx, 39.5'fx) + unit.goalOffset
  doAssert unit.goalOffset.x == offset.x or unit.goalOffset.y == offset.y,
    "An isolated diagonal blocker should preserve the other click axis"
  w.finishMove(unit)
  doAssert length(unit.body.pos - goal) <= 0.001'fx

block legalFractionalGoalBehindCorner:
  let w = trafficFixture(0, "opposing").world
  for y in 40'i32 .. 41'i32:
    for x in 40'i32 .. 41'i32:
      w.blocker[w.map.tileIndex(x, y)] = TreeBlocker
  let id = w.spawnUnit(0, PeonUnit, tile2(35, 41))
  let unit = w.units[w.unitIndex(id)]
  let offset = fixedVec2(-0.25'fx, 0.25'fx)
  doAssert w.applyMove(0, id, 40, 39, offset)
  doAssert unit.goalOffset == offset, "A legal precise click must be preserved"
  w.finishMove(unit)
  doAssert length(unit.body.pos - fixedVec2(40.25'fx, 39.75'fx)) <=
    0.001'fx

echo "Building corner and precise destination tests passed"
