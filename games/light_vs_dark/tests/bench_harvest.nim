## Measures deposited resources with normal movement and harvesting rules.
import std/strformat
import ../[content, maps, sim]

const Seconds = 180'i32

proc measure(goldWorkers, woodWorkers: int, mill: bool) =
  ## Runs one fixed opening assignment without bots, spending, or combat.
  let w = newWorld(generateMap(DefaultSeed), TickRate * (Seconds + 1))
  var hall, mine: Building
  var distance = int32.high
  for building in w.buildings:
    if building.owner == 0 and building.kind == TownHallBuilding:
      hall = building
  for building in w.buildings:
    if building.kind == GoldMineBuilding:
      let candidate = tileDistance(hall.origin, building.origin)
      if candidate < distance:
        mine = building
        distance = candidate
  let
    tree = w.nearestTree(hall.origin)
    treeTile = tile2(tree mod w.map.side, tree div w.map.side)
  doAssert tree >= 0
  if mill:
    let worker = w.units[0]
    var origin = NoTile
    distance = int32.high
    for y in 0 ..< w.map.side:
      for x in 0 ..< w.map.side:
        let candidate = tile2(x, y)
        let nearby = tileDistance(treeTile, candidate)
        if nearby < distance and w.canPlace(0, LumberMillBuilding, x, y,
            worker.id):
          origin = candidate
          distance = nearby
    doAssert origin != NoTile
    w.players[0].gold = 10000
    w.players[0].wood = 10000
    doAssert w.applyBuild(0, worker.id, LumberMillBuilding.ord.int32,
      origin.x.int32, origin.y.int32)
    w.buildings[^1].state = BuildingComplete
    w.buildings[^1].hp = w.buildings[^1].maxHp
    w.buildings[^1].builderId = NoEntity
    echo &"  nearby mill origin={origin}"
  w.units.setLen(0)
  for slot in w.unitSlot.mitems: slot = -1
  for tile in w.occupancy.mitems: tile = 0
  for index in 0 ..< goldWorkers + woodWorkers:
    let id = w.spawnUnit(0, PeonUnit,
      w.freeTileAround(hall.origin, hall.footprint))
    doAssert w.applyHarvest(0, id,
      (if index < goldWorkers: mine.id else: tree),
      (if index < goldWorkers: 0 else: 1))
  var
    priorGold, priorWood: int64
    firstGold, firstWood, lastGold, lastWood, goldTrips, woodTrips: int32
  for tick in 1 .. TickRate * Seconds:
    w.tickWorld(nil)
    if w.players[0].goldGathered != priorGold:
      if firstGold == 0: firstGold = tick
      lastGold = tick
      goldTrips += int32((w.players[0].goldGathered - priorGold) div GoldPerTrip)
      priorGold = w.players[0].goldGathered
    if w.players[0].woodGathered != priorWood:
      if firstWood == 0: firstWood = tick
      lastWood = tick
      woodTrips += int32((w.players[0].woodGathered - priorWood) div WoodPerTrip)
      priorWood = w.players[0].woodGathered
  echo &"gold workers={goldWorkers}, wood workers={woodWorkers}, mill={mill}"
  echo &"  hall={hall.origin}, mine={mine.origin}, tree={treeTile}"
  echo &"  {Seconds}s deposits: gold={priorGold}, wood={priorWood}"
  echo &"  per minute: gold={priorGold.float64 * 60 / Seconds.float64:.1f}, wood={priorWood.float64 * 60 / Seconds.float64:.1f}"
  if goldTrips > 1:
    echo &"  gold first deposit={firstGold.float64 / TickRate.float64:.2f}s, mean deposit interval={(lastGold - firstGold).float64 / (TickRate * (goldTrips - 1)).float64:.2f}s"
  if woodTrips > 1:
    echo &"  wood first deposit={firstWood.float64 / TickRate.float64:.2f}s, mean deposit interval={(lastWood - firstWood).float64 / (TickRate * (woodTrips - 1)).float64:.2f}s"

echo &"TickRate={TickRate}, gold load={GoldPerTrip}, mine ticks={MineTicks}, wood load={WoodPerTrip}, chop ticks={ChopTicks}"
measure(1, 0, false)
measure(0, 1, false)
measure(6, 1, false)
measure(0, 1, true)
measure(6, 1, true)
