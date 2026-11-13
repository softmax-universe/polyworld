## Drafted matches get a live 30-second opening before the first wave.
import polyworld/[cli, pathing]
import ../[bots, content, maps, replays, sim]

proc draftedGame(): Game =
  result = newGame(generateMap(2026), 10 * TickRate, 10, false,
    ReplayData())
  result.world.camps.setLen(0)
  while result.world.phase == Drafting:
    var classId = 0'i32
    while not result.world.heroAvailable(classId): inc classId
    doAssert result.world.applyDraft(result.world.draftHeroId(), classId)

echo "Testing no first wave before the complete 30-second preparation"
block:
  let game = draftedGame()
  doAssert game.world.preparationTicksLeft() == PreparationTicks
  for tick in 1 ..< 30 * TickRate:
    game.tickWorld(nil)
    doAssert game.world.footmen.len == 0,
      "The first wave must wait for 30 full seconds after the final pick"
    doAssert game.world.tick == tick
    doAssert game.world.preparationTicksLeft() == PreparationTicks - tick
    doAssert game.world.battleTick() == 0
  game.tickWorld(nil)
  doAssert game.world.footmen.len > 0
  doAssert game.world.preparationTicksLeft() == 0
  doAssert game.world.battleTick() == 0
  doAssert game.world.spawnTimerTicks == game.world.spawnIntervalTicks,
    "Subsequent waves must retain the full configured interval"
  echo "First wave appeared at tick ", game.world.tick

echo "Testing preparation gates physically block both teams' base exits"
block:
  let game = draftedGame()
  var checked = 0
  # The middle lane crosses each base's outer wall. Its default terrain stays
  # open; the match's dynamic occupancy must close it during preparation.
  for team in Team:
    let start = game.map.layout.spawns[team.ord]
    var route: seq[PathTile]
    game.world.bindNavigation()
    discard fillTilePath(PathQuery(
      startLayer: 0,
      startX: start.x div PathUnitsPerTile + mapTiles().int32 div 2,
      startZ: start.z div PathUnitsPerTile + mapTiles().int32 div 2,
      finishLayer: 0, finishX: mapTiles().int32 div 2,
      finishZ: mapTiles().int32 div 2, walkable: navigationOpen), route)
    doAssert route.len == 0, "Closed gates must not permit an exit path"
    inc checked
  doAssert checked == 2
  doAssert game.map.preparationGates.len > 0
  for tile in game.map.preparationGates:
    doAssert isWalkable(tile.layer, tile.x, tile.z)
    doAssert not navigationOpen(tile.layer, tile.x, tile.z)
    for team in Team:
      doAssert not game.world.knownWalkable(team, tile.layer, tile.x, tile.z),
        "Bot terrain queries must expose the same closed gates"
  for i in 0 ..< PreparationTicks:
    game.tickWorld(nil)
  doAssert not game.world.preparationGatesClosed
  for team in Team:
    let start = game.map.layout.spawns[team.ord]
    var route: seq[PathTile]
    game.world.bindNavigation()
    discard fillTilePath(PathQuery(startLayer: 0,
      startX: start.x div PathUnitsPerTile + mapTiles().int32 div 2,
      startZ: start.z div PathUnitsPerTile + mapTiles().int32 div 2,
      finishLayer: 0, finishX: mapTiles().int32 div 2,
      finishZ: mapTiles().int32 div 2, walkable: navigationOpen), route)
    doAssert route.len > 0, "Both bases open on the first-wave tick"

echo "Testing shopping and movement remain live inside each base"
for team in Team:
  let game = draftedGame()
  let hero = game.world.heroes[team.ord * 5]
  let start = hero.position
  let gold = hero.gold
  doAssert game.world.applyBuyItem(hero.id, HealthPotion.ord.int32)
  doAssert hero.gold == gold - HealthPotion.itemSpec.cost
  let x = mapCoordinate(start.x)
  let z = mapCoordinate(start.z)
  doAssert game.world.applyWalkTo(hero.id, x + 2, z)
  for i in 0 ..< TickRate:
    game.tickWorld(nil)
  doAssert hero.position != start, "Prep must not freeze walking or simulation"
  doAssert game.world.preparationTicksLeft() == PreparationTicks - TickRate

echo "Testing body collision cannot cross a closed gate on either side"
for team in Team:
  let game = draftedGame()
  let hero = game.world.heroes[team.ord * 5]
  var exercised = false
  for tile in game.map.preparationGates:
    if exercised: break
    if (tile.x < mapTiles() div 2) != (team == BlueTeam): continue
    if game.world.occupancy[tile.layer][int(tile.z) * mapTiles() + int(tile.x)] != 1:
      continue
    for dz in -1 .. 1:
      if exercised: break
      for dx in -1 .. 1:
        if abs(dx) + abs(dz) != 1: continue
        let x = tile.x + dx.int32
        let z = tile.z + dz.int32
        if not navigationOpen(0, x, z): continue
        if not lineClear(PathTile(layer: 0, x: x, z: z), tile): continue
        let p = pathPoint(0, x, z)
        let target = pathPoint(0, tile.x, tile.z)
        hero.place(WorldPoint(x: p.x * (WorldScale div PathUnitsPerTile),
          y: p.y * (WorldScale div PathUnitsPerTile),
          z: p.z * (WorldScale div PathUnitsPerTile)))
        # A stale/forged path bypasses A* so this tests actual steering collision.
        hero.hasMoveTarget = true
        hero.moveRevision = game.world.navigationRevision
        hero.movePath = @[WorldPoint(
          x: target.x * (WorldScale div PathUnitsPerTile),
          y: target.y * (WorldScale div PathUnitsPerTile),
          z: target.z * (WorldScale div PathUnitsPerTile))]
        hero.movePathLayers = @[0'i32]
        hero.movePathIndex = 0
        for i in 0 ..< TickRate div 2:
          game.tickWorld(nil)
          doAssert mapCoordinate(hero.position.x) != tile.x or
            mapCoordinate(hero.position.z) != tile.z,
            "Steering/collision must reject closed gate tiles"
        exercised = true
        break
  doAssert exercised, "Need a collision probe for each team's actual gate"

echo "Testing countdown and gate state survive clone/restore and hash"
block:
  let game = draftedGame()
  for i in 0 ..< 17: game.tickWorld(nil)
  let snapshot = game.world.clone()
  let hash = game.stateHash()
  inc game.world.preparationTicks
  doAssert game.stateHash() != hash, "Countdown belongs to authoritative hash"
  game.world.restore(snapshot)
  doAssert game.stateHash() == hash
  for i in 17 ..< PreparationTicks: game.tickWorld(nil)
  doAssert not game.world.preparationGatesClosed
  game.world.restore(snapshot)
  doAssert game.world.preparationGatesClosed
  doAssert game.world.preparationTicksLeft() == PreparationTicks - 17
  doAssert game.stateHash() == hash
  for tile in game.map.preparationGates:
    doAssert not navigationOpen(tile.layer, tile.x, tile.z)

echo "Testing portal scrolls cannot bypass preparation gates"
for team in Team:
  let game = draftedGame()
  var destination: WorldPoint
  var towerId: int32
  game.tickWorld(nil)
  var tested = false
  for i in 0 ..< game.world.buildings.len:
    let building = game.world.buildings[i]
    if building.team != team or building.kind != TowerBuilding or
        building.tier != OuterTower: continue
    doAssert not game.world.portalLanding(team, building.position,
      destination, towerId, building.id),
      "Outer tower teleport must not let bots escape before gates open"
    tested = true
  doAssert tested

echo "Testing real rushing bots stay inside closed bases"
block:
  let game = draftedGame()
  game.loadBots([BotGroup(path:
    "games/gods_of_the_arena/players/rusher.bas", count: 10)])
  for tick in 1 ..< PreparationTicks:
    game.tickWorld(proc() = game.runBotDecisions())
    if tick mod TickRate != 0: continue
    for hero in game.world.heroes:
      game.world.bindNavigation()
      let start = game.map.layout.spawns[hero.team.ord]
      let route = findTilePath(PathQuery(startLayer: 0,
        startX: start.x div PathUnitsPerTile + mapTiles().int32 div 2,
        startZ: start.z div PathUnitsPerTile + mapTiles().int32 div 2,
        finishLayer: hero.navLayer,
        finishX: mapCoordinate(hero.position.x),
        finishZ: mapCoordinate(hero.position.z), walkable: navigationOpen))
      doAssert route.tiles.len > 0, "Rushing bots must stay in their sealed base"
  for vm in game.heroVms:
    doAssert not vm.failed, vm.lastError

echo "GotA preparation checks passed"
