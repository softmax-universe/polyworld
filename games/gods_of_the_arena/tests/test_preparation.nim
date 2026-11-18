## Drafted matches allow roaming while creeps wait for the opening countdown.
import
  polyworld/[cli, pathing],
  ../[bots, content, maps, replays, sim]

proc draftedGame(): Game =
  ## Completes a full draft without advancing the preparation countdown.
  result = newGame(
    generateMap(2026),
    10 * TickRate,
    10,
    false,
    ReplayData()
  )
  while result.world.phase == Drafting:
    var classId = 0'i32
    while not result.world.heroAvailable(classId):
      inc classId
    doAssert result.world.applyDraft(result.world.draftHeroId(), classId)

proc laneCreeps(world: World): int =
  ## Counts lane units independently of neutral camp members.
  for creep in world.footmen:
    if creep.camp == 0:
      inc result

echo "Testing all creeps wait for the complete 30-second preparation"
block:
  let game = draftedGame()
  doAssert game.world.preparationTicksLeft() == PreparationTicks
  doAssert game.world.camps.len > 0
  for tick in 1 ..< PreparationTicks:
    game.tickWorld(nil)
    doAssert game.world.footmen.len == 0,
      "Lane and neutral creeps must wait until preparation ends"
    doAssert game.world.tick == tick
    doAssert game.world.preparationTicksLeft() == PreparationTicks - tick
    doAssert game.world.battleTick() == 0
  game.tickWorld(nil)
  let firstWave = game.world.laneCreeps()
  doAssert firstWave > 0
  doAssert game.world.footmen.len > firstWave,
    "Neutral camps start on the same tick as the first lane wave"
  doAssert game.world.preparationTicksLeft() == 0
  doAssert game.world.battleTick() == 0
  doAssert game.world.spawnTimerTicks == game.world.spawnIntervalTicks,
    "Subsequent waves must retain the full configured interval"
  let nextId = game.world.nextFootmanId
  for i in 1 ..< game.world.spawnIntervalTicks:
    game.tickWorld(nil)
    doAssert game.world.nextFootmanId == nextId,
      "The second wave must wait for the full configured interval"
  game.tickWorld(nil)
  doAssert game.world.nextFootmanId > nextId
  doAssert game.world.spawnTimerTicks == game.world.spawnIntervalTicks

echo "Testing both teams can walk out to mid during preparation"
for team in Team:
  let
    game = draftedGame()
    hero = game.world.heroes[team.ord * 5]
    middle = mapTiles().int32 div 2
  game.world.bindNavigation()
  let route = findTilePath(PathQuery(
    startLayer: hero.navLayer,
    startX: mapCoordinate(hero.position.x),
    startZ: mapCoordinate(hero.position.z),
    finishLayer: 0,
    finishX: middle,
    finishZ: middle,
    walkable: navigationOpen
  ))
  doAssert route.tiles.len > 0, "Both base exits must stay open"
  for tile in route.tiles:
    doAssert game.world.knownWalkable(team, tile.layer, tile.x, tile.z),
      "Bot terrain queries must expose the same open route"
  doAssert game.world.applyWalkTo(hero.id, middle, middle)
  for i in 1 ..< PreparationTicks:
    game.tickWorld(nil)
    doAssert game.world.footmen.len == 0
  doAssert within(hero.position, WorldPoint(), 10 * WorldScale),
    "Heroes must leave their base and reach mid before the first creep wave"
  doAssert game.world.preparationTicksLeft() == 1

echo "Testing shopping and movement remain live during preparation"
for team in Team:
  let
    game = draftedGame()
    hero = game.world.heroes[team.ord * 5]
    start = hero.position
    gold = hero.gold
  doAssert game.world.applyBuyItem(hero.id, HealthPotion.ord.int32)
  doAssert hero.gold == gold - HealthPotion.itemSpec.cost
  let
    x = mapCoordinate(start.x)
    z = mapCoordinate(start.z)
  doAssert game.world.applyWalkTo(hero.id, x + 2, z)
  for i in 0 ..< TickRate:
    game.tickWorld(nil)
  doAssert hero.position != start, "Preparation must not freeze walking"
  doAssert game.world.preparationTicksLeft() == PreparationTicks - TickRate

echo "Testing countdown and creep timing survive clone/restore and hash"
block:
  let game = draftedGame()
  for i in 0 ..< 17:
    game.tickWorld(nil)
  let
    snapshot = game.world.clone()
    hash = game.stateHash()
  inc game.world.preparationTicks
  doAssert game.stateHash() != hash, "Countdown belongs to authoritative hash"
  game.world.restore(snapshot)
  doAssert game.stateHash() == hash
  for i in 17 ..< PreparationTicks:
    game.tickWorld(nil)
  let openedHash = game.stateHash()
  doAssert game.world.preparationTicksLeft() == 0
  doAssert game.world.footmen.len > 0
  game.world.restore(snapshot)
  doAssert game.world.footmen.len == 0
  doAssert game.world.preparationTicksLeft() == PreparationTicks - 17
  doAssert game.stateHash() == hash
  for i in 17 ..< PreparationTicks:
    game.tickWorld(nil)
  doAssert game.stateHash() == openedHash,
    "Restoring preparation must reproduce the same first-wave state"

echo "Testing allied tower portal landings are available during preparation"
for team in Team:
  let game = draftedGame()
  var
    destination: WorldPoint
    towerId: int32
    tested = false
  game.tickWorld(nil)
  for building in game.world.buildings:
    if building.team != team or building.kind != TowerBuilding or
      building.tier != OuterTower:
        continue
    doAssert game.world.portalLanding(
      team,
      building.position,
      destination,
      towerId,
      building.id
    ), "Preparation must allow normal allied tower teleports"
    doAssert towerId == building.id
    tested = true
  doAssert tested

echo "Testing rushing bots keep running while creeps wait"
block:
  let game = draftedGame()
  game.loadBots([BotGroup(
    path: "games/gods_of_the_arena/players/rusher.bas",
    count: 10
  )])
  for tick in 1 ..< PreparationTicks:
    game.tickWorld(proc() = game.runBotDecisions())
    doAssert game.world.footmen.len == 0
  for vm in game.heroVms:
    doAssert not vm.failed, vm.lastError

echo "GotA preparation checks passed"
