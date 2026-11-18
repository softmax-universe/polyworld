## Newly trained workers inherit their producer's resource rally assignment.
import trafficfixture, ../[multiplayer, replays]

proc fixture(): tuple[world: World, hall: int32] =
  ## Keeps real producers and resource footprints in a clear arena.
  result.world = trafficFixture(0, "open").world
  result.world.players[0].gold = 10000
  result.world.players[0].wood = 10000
  result.world.players[0].foodUsed = 0
  for building in result.world.buildings:
    if building.owner == 0 and building.kind == TownHallBuilding:
      result.hall = building.id

proc nextTrained(w: World): Unit =
  ## Waits for the actual production queue to create its next unit.
  let before = w.units.len
  for tick in 0 ..< TickRate * 30:
    w.tickWorld(nil)
    if w.units.len > before:
      return w.units[^1]
  doAssert false, "The queued unit must finish training"

proc addTree(w: World, tile: Tile2) =
  ## Adds a standing tree with its real collision footprint.
  let index = w.map.tileIndex(tile)
  w.treeWood[index] = WoodPerTree
  w.blocker[index] = TreeBlocker

block successivePeonsMineAndDepositAutomatically:
  let
    (w, hall) = fixture()
    mine = w.buildings[w.buildingIndex(FirstMineId)]
  doAssert w.applySetRally(0, hall,
    mine.origin.x.int32 + 1, mine.origin.y.int32 + 1)
  for count in 0 ..< 2:
    doAssert w.applyTrain(0, hall, PeonUnit.ord.int32)
  for count in 0 ..< 2:
    let unit = w.nextTrained()
    doAssert unit.kind == PeonUnit and unit.state == UnitToMine
    doAssert unit.sourceId == mine.id and unit.targetId == mine.id
  for tick in 0 ..< TickRate * 120:
    w.tickWorld(nil)
    if w.players[0].goldGathered >= GoldPerTrip * 2: break
  doAssert w.players[0].goldGathered >= GoldPerTrip * 2

block woodRallyKeepsItsOriginalCenterAfterTheTreeIsGone:
  let
    (w, hall) = fixture()
    center = tile2(20, 20)
    nearby = tile2(21, 20)
    closerToHall = tile2(9, 9)
  for tile in [center, nearby, closerToHall]: w.addTree(tile)
  doAssert w.applySetRally(0, hall, center.x.int32, center.y.int32)
  doAssert w.applyTrain(0, hall, PeonUnit.ord.int32)
  let first = w.nextTrained()
  doAssert first.state == UnitToTree
  doAssert first.targetTile == center and first.harvestCenter == center
  let original = w.map.tileIndex(center)
  w.treeWood[original] = 0
  w.blocker[original] = 0
  inc w.pathTerrainRevision
  doAssert w.applyTrain(0, hall, PeonUnit.ord.int32)
  let second = w.nextTrained()
  doAssert second.state == UnitToTree
  doAssert second.targetTile == nearby
  doAssert second.harvestCenter == center
  for tick in 0 ..< TickRate * 90:
    w.tickWorld(nil)
    if w.players[0].woodGathered > 0: break
  doAssert w.players[0].woodGathered > 0
  doAssert w.applySetRally(0, hall, center.x.int32, center.y.int32)
  doAssert w.applyTrain(0, hall, PeonUnit.ord.int32)
  let clearedGround = w.nextTrained()
  doAssert clearedGround.state == UnitMoving
  doAssert clearedGround.goal == center
  doAssert clearedGround.harvestCenter == NoTile

block groundAndDepletedResourcesAreSafe:
  let
    (w, hall) = fixture()
    destination = tile2(15, 15)
  doAssert w.applySetRally(0, hall, destination.x.int32, destination.y.int32)
  doAssert w.applyTrain(0, hall, PeonUnit.ord.int32)
  let mover = w.nextTrained()
  doAssert mover.state == UnitMoving and mover.goal == destination
  doAssert mover.sourceId == NoEntity and mover.harvestCenter == NoTile
  let mine = w.buildingIndex(FirstMineId)
  let origin = w.buildings[mine].origin
  doAssert w.applySetRally(0, hall, origin.x.int32, origin.y.int32)
  w.buildings[mine].goldLeft = 0
  doAssert w.applyTrain(0, hall, PeonUnit.ord.int32)
  let emptyMine = w.nextTrained()
  doAssert emptyMine.state notin {UnitToMine, UnitInMine}
  doAssert emptyMine.sourceId == NoEntity

block soldiersNeverReceiveHarvestAssignments:
  let
    w = fixture().world
    worker = w.spawnUnit(0, PeonUnit, tile2(12, 12))
    tree = tile2(20, 20)
  w.addTree(tree)
  doAssert w.applyBuild(0, worker, BarracksBuilding.ord.int32, 12, 12)
  var barracks = NoEntity
  for tick in 0 ..< TickRate * 30:
    w.tickWorld(nil)
    for building in w.buildings:
      if building.kind == BarracksBuilding and
          building.state == BuildingComplete:
        barracks = building.id
    if barracks != NoEntity: break
  doAssert barracks != NoEntity
  doAssert w.applySetRally(0, barracks, tree.x.int32, tree.y.int32)
  doAssert w.applyTrain(0, barracks, SoldierUnit.ord.int32)
  let soldier = w.nextTrained()
  doAssert soldier.kind == SoldierUnit
  doAssert soldier.state == UnitMoving
  doAssert soldier.sourceId == NoEntity and soldier.harvestCenter == NoTile

block serializedRalliesAndTrainingRemainDeterministic:
  for wood in [false, true]:
    let
      (w, hall) = fixture()
      target = if wood: tile2(20, 20)
        else: w.buildings[w.buildingIndex(FirstMineId)].origin
    if wood: w.addTree(target)
    let
      a = Game(world: w)
      b = Game(world: w.clone())
    for action in [
      ReplayAction(kind: ActionSetRally, entityId: hall,
        first: target.x.int32, second: target.y.int32),
      ReplayAction(kind: ActionTrain, entityId: hall,
        first: PeonUnit.ord.int32)
    ]:
      doAssert a.world.applyReplayAction(action)
      doAssert b.world.applyReplayAction(decodeSubmission(action.encodeSubmission()))
      doAssert a.stateHash() == b.stateHash()
    let
      index = b.world.buildingIndex(hall)
      kind = b.world.buildings[index].rallyKind
    b.world.buildings[index].rallyKind = RallyMove
    doAssert a.stateHash() != b.stateHash()
    b.world.buildings[index].rallyKind = kind
    doAssert a.stateHash() == b.stateHash()
    for tick in 0 ..< TickRate * 120:
      a.world.tickWorld(nil)
      b.world.tickWorld(nil)
      doAssert a.stateHash() == b.stateHash()
      if a.world.players[0].goldGathered + a.world.players[0].woodGathered > 0:
        break
    doAssert a.world.players[0].goldGathered + a.world.players[0].woodGathered > 0

echo "Resource rallies train miners, woodcutters, and ordinary movers"
