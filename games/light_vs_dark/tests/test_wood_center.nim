## Woodcutters keep the original clicked tree as their harvesting center.
import trafficfixture

proc plant(w: World, at: Tile2, amount = WoodPerTrip): int32 =
  ## Adds a controlled tree to the open test arena.
  result = w.map.tileIndex(at)
  w.treeWood[result] = amount.int16
  w.blocker[result] = TreeBlocker
  inc w.pathTerrainRevision

proc peon(w: World, at: Tile2): Unit =
  ## Adds one worker without an initial resource assignment.
  let id = w.spawnUnit(0, PeonUnit, at)
  w.units[w.unitIndex(id)]

proc hall(w: World): int32 =
  ## Finds the worker's real starting resource depot.
  for structure in w.buildings:
    if structure.kind == TownHallBuilding and structure.owner == 0:
      return structure.id
  doAssert false, "The fixture must contain a town hall"

block consecutiveDepletionStaysCentered:
  let
    w = trafficFixture(0, "miners").world
    original = tile2(35, 40)
    left = tile2(34, 40)
    drifting = tile2(33, 40)
    nearby = tile2(35, 41)
    target = w.plant(original)
    leftIndex = w.plant(left)
    driftingIndex = w.plant(drifting)
    nearbyIndex = w.plant(nearby)
    unit = w.peon(tile2(34, 39))
  doAssert w.applyHarvest(0, unit.id, target, 1)
  let peer = w.clone()
  var
    selectedNearby = false
    depositedManually = false
  for tick in 0 ..< 4000:
    w.tickWorld(nil)
    peer.tickWorld(nil)
    doAssert Game(world: w).stateHash() == Game(world: peer).stateHash()
    doAssert not unit.orderFailed
    doAssert unit.harvestCenter == original
    if w.treeWood[leftIndex] == 0 and unit.carryWood > 0 and
        not depositedManually:
      let depot = w.hall()
      doAssert w.applyDeposit(0, unit.id, depot)
      doAssert peer.applyDeposit(0, unit.id, depot)
      doAssert unit.harvestCenter == original
      depositedManually = true
    if w.treeWood[target] == 0 and w.treeWood[leftIndex] == 0 and
        unit.targetTile != left:
      doAssert unit.targetTile == nearby,
        "After two depleted trees, choose nearest to the original click"
      selectedNearby = true
      break
  doAssert selectedNearby
  doAssert depositedManually
  doAssert w.treeWood[driftingIndex] == WoodPerTrip
  doAssert w.treeWood[nearbyIndex] == WoodPerTrip
  doAssert w.players[0].woodGathered == 2 * WoodPerTrip

echo "Consecutive tree depletion stays centered on the original click"

block harvestCenterIsAuthoritative:
  let
    w = trafficFixture(0, "miners").world
    target = w.plant(tile2(35, 40))
    unit = w.peon(tile2(34, 39))
  doAssert unit.harvestCenter == NoTile
  doAssert w.applyHarvest(0, unit.id, target, 1)
  let peer = w.clone()
  let before = Game(world: w).stateHash()
  doAssert peer.units[0].harvestCenter == unit.harvestCenter
  peer.units[0].harvestCenter = tile2(36, 40)
  doAssert Game(world: peer).stateHash() != before,
    "Different future harvesting centers must produce different hashes"
  doAssert unit.harvestCenter == tile2(35, 40)

block explicitOrdersReplaceOrClearCenter:
  for carrying in [false, true]:
    for replacement in 0 .. 2:
      let
        w = trafficFixture(0, "miners").world
        first = w.plant(tile2(35, 40))
        second = w.plant(tile2(40, 40))
        unit = w.peon(tile2(34, 39))
      doAssert w.applyHarvest(0, unit.id, first, 1)
      if carrying: unit.carryWood = 19
      doAssert w.applyHarvest(0, unit.id, second, 1)
      doAssert unit.harvestCenter == tile2(40, 40)
      doAssert unit.targetTile == tile2(40, 40)
      if carrying:
        doAssert unit.carryWood == 19 and unit.state == UnitToDropWood
      case replacement
      of 0:
        doAssert w.applyCancel(0, unit.id)
      of 1:
        doAssert w.applyMove(0, unit.id, 30, 35)
      else:
        doAssert w.applyHarvest(0, unit.id, FirstMineId, 0)
      doAssert unit.harvestCenter == NoTile
      if carrying: doAssert unit.carryWood == 19

echo "New resource orders reset the center; deposits, clones and hashes retain it"

block targetDisappearsWhileWalking:
  let
    w = trafficFixture(0, "miners").world
    original = tile2(35, 40)
    nearby = tile2(35, 42)
    target = w.plant(original)
    unit = w.peon(tile2(25, 40))
  discard w.plant(nearby)
  discard w.plant(tile2(25, 38))
  doAssert w.applyHarvest(0, unit.id, target, 1)
  w.treeWood[target] = 0
  w.blocker[target] = 0
  inc w.pathTerrainRevision
  for tick in 0 ..< 600:
    w.tickWorld(nil)
    doAssert unit.harvestCenter == original and not unit.orderFailed
    if unit.targetTile != original: break
  doAssert unit.targetTile == nearby,
    "A tree felled by another worker must not end or recenter this assignment"

block blockedTreeChoosesNearestToCenter:
  let
    w = trafficFixture(0, "miners").world
    original = tile2(35, 40)
    nearby = tile2(38, 40)
    target = w.plant(original)
    unit = w.peon(tile2(25, 40))
  discard w.plant(nearby)
  discard w.plant(tile2(26, 38))
  for y in 39'i32 .. 41'i32:
    for x in 34'i32 .. 36'i32:
      w.blocker[w.map.tileIndex(x, y)] = TreeBlocker
  for known in w.explored[0].mitems: known = 1
  w.exploredCount[0] = w.map.side * w.map.side
  doAssert w.applyHarvest(0, unit.id, target, 1)
  doAssert unit.targetTile == nearby,
    "A blocked approach must prefer nearby original wood, not nearby worker wood"
  doAssert unit.harvestCenter == original and not unit.orderFailed

echo "Depleted and blocked targets retain the original harvesting center"

block nearestTreeUsesDistanceAndStableTies:
  let
    w = trafficFixture(0, "miners").world
    center = tile2(35, 40)
    original = w.plant(center)
  doAssert w.nearestTree(center) == original
  w.treeWood[original] = 0
  discard w.plant(tile2(33, 38))
  let closest = w.plant(tile2(35, 38))
  doAssert w.nearestTree(center) == closest,
    "Ring scan order must not beat actual distance to the harvesting center"
  let tie = w.plant(tile2(33, 40))
  doAssert closest < tie and w.nearestTree(center) == closest

echo "Tree distance ranking includes the center and breaks ties deterministically"
