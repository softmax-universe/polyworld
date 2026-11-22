## Actual combat rewards drive disposable presentation events in normal builds.
import
  polyworld/metrics,
  ../[content, maps, replays, sim]

proc arena(): World =
  ## Isolates lethal item impacts without AI turns or scene setup.
  result = World(
    stats: newCombatStats(3),
    heroes: @[
      Hero(id: 100, team: RedTeam, class: Ranger, level: 1, gold: 500),
      Hero(id: 105, team: BlueTeam, class: DruidWarden, level: 1),
      Hero(id: 101, team: RedTeam, class: DruidWarden, level: 1)
    ],
    footmen: @[
      Footman(id: 1000, team: BlueTeam, hp: 1,
        position: WorldPoint(x: WorldScale, y: 4200, z: WorldScale))
    ],
    buildings: @[
      Building(id: 10, team: BlueTeam, hp: 1,
        position: WorldPoint(x: WorldScale, y: 6000))
    ],
    forts: [Fort(id: 1, team: RedTeam, hp: FortHp),
      Fort(id: 2, team: BlueTeam, hp: FortHp)]
  )
  for i, hero in result.heroes:
    hero.refreshHeroStats()
    result.stats.teams[i] = hero.team.ord
    hero.inventory[0] = PoisonPotion
    hero.itemCounts[0] = 3
  for team in Team:
    result.teamVisible[team.ord] = newSeq[uint8](mapTiles() * mapTiles())
    for cell in result.teamVisible[team.ord].mitems:
      cell = 255

proc defeat(world: World, victimId: int32) =
  ## Kills one weakened opponent using the public item command.
  world.heroes[0].attackObjectId = victimId
  doAssert world.applyUseItem(world.heroes[0].id, 0)

proc reward(world: World, heroId, victimId: int32): RewardEffect =
  ## Finds one expected recipient and victim record.
  var count = 0
  for effect in world.rewardEffects:
    if effect.heroId == heroId and effect.victimId == victimId:
      result = effect
      inc count
  doAssert count == 1, "Each recipient has one combined record per victim"

echo "Testing last-hit gold and shared XP use actual recipient amounts"
block:
  let
    world = arena()
    killer = world.heroes[0]
    ally = world.heroes[2]
    victim = world.footmen[0]
    goldBefore = killer.gold
  world.defeat(victim.id)
  doAssert world.rewardEffects.len == 2
  let
    lastHit = world.reward(killer.id, victim.id)
    nearby = world.reward(ally.id, victim.id)
  doAssert lastHit.gold == killer.gold - goldBefore and lastHit.gold == 15
  doAssert lastHit.xp == killer.totalXp and lastHit.xp == 8
  doAssert nearby.gold == 0 and nearby.xp == ally.totalXp and nearby.xp == 6
  doAssert lastHit.position == victim.position
  doAssert nearby.position == victim.position
  doAssert not world.applyUseItem(killer.id, 0)
  doAssert world.rewardEffects.len == 2

echo "Testing simultaneous deaths keep separate positions and combined rewards"
block:
  let world = arena()
  world.footmen.add Footman(id: 1001, team: BlueTeam, hp: 1,
    position: WorldPoint(x: -WorldScale, y: 8000, z: WorldScale))
  world.defeat(1000)
  world.defeat(1001)
  doAssert world.rewardEffects.len == 4
  for victim in world.footmen:
    let effect = world.reward(100, victim.id)
    doAssert effect.position == victim.position and effect.gold == 15
  var totalGold, totalXp: int
  for effect in world.rewardEffects:
    if effect.heroId == 100:
      totalGold += effect.gold
      totalXp += effect.xp
  doAssert totalGold == world.heroes[0].gold - 500
  doAssert totalXp == world.heroes[0].totalXp

echo "Testing hero and building death rewards retain corpse positions"
for heroVictim in [false, true]:
  let
    world = arena()
    victimId = if heroVictim: 105'i32 else: 10'i32
    point = if heroVictim: WorldPoint(x: -WorldScale, y: 12500)
      else: world.buildings[0].position
  world.heroes[1].hp = 1
  world.heroes[1].position = point
  world.defeat(victimId)
  doAssert world.rewardEffects.len == 1
  let effect = world.reward(100, victimId)
  doAssert effect.position == point
  doAssert effect.gold == (if heroVictim: 100 else: 75)
  doAssert effect.xp == (if heroVictim: 150 else: 200)

echo "Testing reward effects clear across ticks and replay snapshots"
block:
  let
    game = newGame(generateMap(2026), 100_000, 10, false,
      ReplayData(), drafting = false)
    world = game.world
    hero = world.heroes[0]
  world.spawnTimerTicks = 100_000
  world.heroTurnTicks = 100_000
  world.footmen.add Footman(id: 1000, team: BlueTeam, hp: 1,
    position: hero.position, navLayer: hero.navLayer)
  for cell in world.teamVisible[hero.team.ord].mitems:
    cell = 255
  hero.inventory[0] = PoisonPotion
  hero.itemCounts[0] = 1
  hero.attackObjectId = 1000
  doAssert world.applyUseItem(hero.id, 0)
  doAssert world.rewardEffects.len > 0
  let
    hash = game.stateHash()
    effects = world.rewardEffects
    snapshot = world.clone()
  doAssert snapshot.rewardEffects.len == 0
  doAssert world.rewardEffects.len == effects.len
  world.rewardEffects = @[]
  doAssert game.stateHash() == hash, "Presentation events are not authoritative"
  world.rewardEffects = effects
  world.restore(snapshot)
  doAssert world.rewardEffects.len == 0 and game.stateHash() == hash
  world.rewardEffects = effects
  game.tickWorld(nil)
  doAssert world.rewardEffects.len == 0
  world.forts[BlueTeam.ord].hp = 0
  game.tickWorld(nil)
  doAssert world.gameOver and world.rewardEffects.len == 5
  for effect in world.rewardEffects:
    doAssert effect.victimId == world.forts[BlueTeam.ord].id
    doAssert effect.position == world.forts[BlueTeam.ord].center
    doAssert effect.xp == 1000 and effect.gold == 0
  world.rewardEffects = effects
  game.tickWorld(nil)
  doAssert world.rewardEffects.len == 0

echo "Reward presentation events passed"
