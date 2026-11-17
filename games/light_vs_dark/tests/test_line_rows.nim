## Short line formations grow in depth and include every eligible selected unit.
import std/[algorithm, sets]
import trafficfixture
import ../[controls, linemoves]

proc group(w: World, count: int): seq[int32] =
  ## Creates an army in open ground with separate starting cells.
  for i in 0 ..< count:
    result.add w.spawnUnit(0, SoldierUnit,
      tile2(24 + (i div 5).int32, 30 + (i mod 5).int32))

proc assertComplete(w: World, ids: seq[int32],
    plan: seq[LineDestination]) =
  ## Requires a distinct legal destination for each selected unit.
  doAssert plan.len == ids.len
  var cells = initHashSet[Tile2]()
  var assigned = initHashSet[int32]()
  for target in plan:
    doAssert target.unitId in ids and target.unitId notin assigned
    doAssert w.tileOpen(target.tile) and target.tile notin cells
    assigned.incl target.unitId
    cells.incl target.tile

block selectedUnitSharingFriendlyCellStillMoves:
  let
    w = trafficFixture(0, "open").world
    ids = w.group(2)
    first = w.units[w.unitIndex(ids[0])]
  discard w.spawnUnit(0, PeonUnit, first.tile)
  let plan = w.planLineMove(0, ids,
    [linePoint(35.5, 35.5), linePoint(39.5, 35.5)])
  w.assertComplete(ids, plan)

echo "A selected unit sharing a friendly cell keeps its line destination"

block shortHorizontalStrokeAddsRows:
  for count in [12, 20]:
    let
      w = trafficFixture(0, "open").world
      ids = w.group(count)
      stroke = [linePoint(35.5, 35.5), linePoint(39.5, 35.5)]
      plan = w.planLineMove(0, ids, stroke)
    w.assertComplete(ids, plan)
    var rows = initHashSet[int16]()
    for target in plan:
      doAssert target.tile.x in 35'i16 .. 39'i16,
        "A full line must grow in depth rather than extend its endpoints"
      rows.incl target.tile.y
    doAssert rows.len == (count + 4) div 5
    var reordered = ids
    reordered.reverse()
    doAssert plan == w.planLineMove(0, reordered, stroke)

block longStrokeRemainsOneRow:
  let
    w = trafficFixture(0, "open").world
    ids = w.group(4)
    plan = w.planLineMove(0, ids,
      [linePoint(35.5, 35.5), linePoint(43.5, 35.5)])
  w.assertComplete(ids, plan)
  for target in plan: doAssert target.tile.y == 35

block diagonalAndCurvedRowsRemainComplete:
  for stroke in [
      @[linePoint(35.5, 35.5), linePoint(38.5, 38.5)],
      @[linePoint(35.5, 35.5), linePoint(37.5, 35.5),
        linePoint(37.5, 37.5)]]:
    let
      w = trafficFixture(0, "open").world
      ids = w.group(20)
      plan = w.planLineMove(0, ids, stroke)
    w.assertComplete(ids, plan)

echo "Short strokes grow multiple rows while long strokes retain one row"

block allRowsUseTheOrdinaryCommandPipeline:
  for attack in [false, true]:
    clearPlayerCommands()
    let
      w = trafficFixture(0, "open").world
      game = Game(world: w)
      ids = w.group(12)
      first = linePoint(35.5, 35.5)
      last = linePoint(39.5, 35.5)
    var gesture: LineGesture
    gesture.beginLine(w, 0, ids, first, linePoint(0, 0),
      attackMove = attack)
    gesture.updateLine(w, ids, last, linePoint(100, 0))
    let preview = gesture.targets
    w.assertComplete(ids, preview)
    doAssert gesture.releaseLine(w, ids) == LineCommitted
    game.flushPlayerCommands()
    for target in preview:
      let unit = w.units[w.unitIndex(target.unitId)]
      doAssert unit.state == UnitMoving and unit.goal == target.tile
      doAssert unit.attackMove == attack
    var arrived = false
    for tick in 0 ..< 1200:
      w.tickWorld(nil)
      arrived = true
      for target in preview:
        let unit = w.units[w.unitIndex(target.unitId)]
        doAssert not unit.orderFailed
        if unit.state != UnitIdle or unit.tile != target.tile:
          arrived = false
      if arrived: break
    doAssert arrived, "Every row must arrive at its displayed destination"
    clearPlayerCommands()

echo "Every unit receives and completes plain and attack formation movement"

block stationaryPreviewIncludesNewlyAvailableUnit:
  let
    w = trafficFixture(0, "open").world
    ids = w.group(2)
    returning = w.units[w.unitIndex(ids[1])]
    first = linePoint(35.5, 35.5)
    last = linePoint(39.5, 35.5)
  returning.state = UnitInMine
  var gesture: LineGesture
  gesture.beginLine(w, 0, ids, first, linePoint(0, 0))
  gesture.updateLine(w, ids, last, linePoint(100, 0))
  doAssert gesture.targets.len == 1
  returning.state = UnitIdle
  gesture.updateLine(w, ids, last, linePoint(100, 0))
  w.assertComplete(ids, gesture.targets)

block partialPreviewCannotSilentlyMoveOnlySomeUnits:
  clearPlayerCommands()
  let w = trafficFixture(0, "open").world
  let ids = @[
    w.spawnUnit(0, SoldierUnit, tile2(30, 30)),
    w.spawnUnit(0, SoldierUnit, tile2(30, 30))]
  for tile in [tile2(29, 30), tile2(31, 30),
      tile2(30, 29), tile2(30, 31)]:
    w.blocker[w.map.tileIndex(tile)] = TreeBlocker
  var gesture: LineGesture
  gesture.beginLine(w, 0, ids, linePoint(35.5, 35.5), linePoint(0, 0))
  gesture.updateLine(w, ids, linePoint(39.5, 35.5), linePoint(100, 0))
  doAssert gesture.targets.len < ids.len
  doAssert gesture.releaseLine(w, ids) == LineCancelled
  Game(world: w).flushPlayerCommands()
  for id in ids: doAssert w.units[w.unitIndex(id)].state == UnitIdle
  clearPlayerCommands()

block friendlyOccupantInvalidatesDisplayedDestination:
  clearPlayerCommands()
  let
    w = trafficFixture(0, "open").world
    ids = w.group(2)
    other = w.spawnUnit(0, PeonUnit, tile2(50, 50))
  var gesture: LineGesture
  gesture.beginLine(w, 0, ids, linePoint(35.5, 35.5), linePoint(0, 0))
  gesture.updateLine(w, ids, linePoint(39.5, 35.5), linePoint(100, 0))
  let preview = gesture.targets
  w.assertComplete(ids, preview)
  w.place(w.units[w.unitIndex(other)], preview[0].tile)
  doAssert gesture.targets == preview
  doAssert gesture.releaseLine(w, ids) == LineCancelled,
    "A newly occupied preview must not commit stale or unseen destinations"
  Game(world: w).flushPlayerCommands()
  for id in ids: doAssert w.units[w.unitIndex(id)].state == UnitIdle
  clearPlayerCommands()

echo "Stationary previews track eligibility and partial formations never commit"
