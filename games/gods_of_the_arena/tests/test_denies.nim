## Friendly lane denies use explicit basic attacks and no last-hit rewards.

include ../sim

proc denyGame(class = Ranger): Game =
  ## Isolates attack timing without bot decisions or nearby enemy targets.
  var preset = defaultConfig()
  preset.roadWidth = 62
  result = newGame(generateMap(2026, preset), 1000, 10, false,
    ReplayData(), drafting = false)
  result.world.camps.setLen(0)
  result.world.spawnTimerTicks = 100_000
  result.world.heroTurnTicks = 100_000
  for hero in result.world.heroes:
    hero.hp = 0
    hero.state = Dying
    hero.deathTicks = -100_000
  for tower in result.world.buildings.mitems:
    tower.hp = 0
  let
    hero = result.world.heroes[0]
    x = mapTiles() * 7 div 16
    z = mapTiles() * 9 div 64
    tile = layers[GroundLayer].tiles[z * mapTiles() + x]
  hero.class = class
  hero.refreshHeroStats()
  hero.hp = hero.maxHp
  hero.state = Marching
  var point = WorldPoint(
    x: (x - mapTiles() div 2).int32 * WorldScale + WorldScale div 2,
    z: (z - mapTiles() div 2).int32 * WorldScale + WorldScale div 2
  )
  for height in tile.tops:
    point.y += height.int32 * WorldScale div 32
  hero.place(point)
  var creep = Footman(id: 1000, team: hero.team, hp: 29)
  point.x += WorldScale div 2
  creep.place(point)
  creep.controls[StunControl].ends = 100_000
  result.world.footmen.add creep
  for team in Team:
    for cell in result.world.teamVisible[team.ord].mitems:
      cell = 255

proc tickUntilHit(game: Game) =
  ## Runs one real hero attack through the collected combat pipeline.
  let before = game.world.heroes[0].attacksLanded
  for tick in 0 ..< 120:
    game.tickWorld(nil)
    if game.world.heroes[0].attacksLanded > before:
      return
  doAssert false, "The explicit attack must land"

echo "Testing deny eligibility uses strictly below half health"
block:
  let
    game = denyGame()
    world = game.world
    hero = world.heroes[0]
  for health in [60'i32, 31, 30, 29, 1, 0]:
    world.footmen[0].hp = health
    let expected = health > 0 and health < FootmanHp div 2
    doAssert world.canDeny(hero, 1000) == expected
    doAssert world.applyAttackTarget(hero.id, 1000) == expected
  world.footmen[0].hp = 1
  world.footmen[0].state = Dying
  doAssert not world.canDeny(hero, 1000)
  world.footmen[0].state = Marching
  world.footmen[0].team = BlueTeam
  doAssert not world.canDeny(hero, 1000)
  doAssert world.isAttackTarget(hero, 1000)
  world.footmen[0].team = hero.team
  world.footmen[0].camp = 1
  doAssert not world.canDeny(hero, 1000)
  doAssert not world.canDeny(hero, hero.id)
  doAssert not world.canDeny(hero, world.forts[hero.team.ord].id)
  doAssert not world.canDeny(hero, 0)

echo "Testing melee, ranged and magic heroes deny through normal attack timing"
for class in [VanguardKnight, Ranger, Arcanist]:
  let
    game = denyGame(class)
    world = game.world
    hero = world.heroes[0]
    gold = hero.gold
    xp = hero.totalXp
    position = world.footmen[0].position
  world.footmen[0].hp = 1
  doAssert world.applyAttackTarget(hero.id, 1000)
  doAssert world.denyEffects.len == 0
  game.tickUntilHit()
  doAssert world.footmen[0].hp <= 0 and world.footmen[0].state == Dying
  doAssert world.denyEffects.len == 1
  doAssert world.denyEffects[0] == DenyEffect(
    heroId: hero.id, victimId: 1000, position: position)
  doAssert world.rewardEffects.len == 0
  doAssert hero.gold == gold and hero.totalXp == xp
  doAssert hero.attackObjectId == 0
  game.tickWorld(nil)
  doAssert world.denyEffects.len == 0
  doAssert not world.applyAttackTarget(hero.id, 1000)

echo "Testing nonlethal hits persist but do not produce a deny"
block:
  let
    game = denyGame()
    world = game.world
    hero = world.heroes[0]
  doAssert hero.heroAttackDamage < 29
  doAssert world.applyAttackTarget(hero.id, 1000)
  game.tickUntilHit()
  doAssert world.footmen[0].hp == 29 - hero.heroAttackDamage
  doAssert world.denyEffects.len == 0
  doAssert hero.attackObjectId == 1000
  game.tickUntilHit()
  doAssert world.footmen[0].hp <= 0 and world.denyEffects.len == 1

echo "Testing healing during windup cancels the deny"
block:
  let
    game = denyGame()
    world = game.world
    hero = world.heroes[0]
  doAssert world.applyAttackTarget(hero.id, 1000)
  game.tickWorld(nil)
  doAssert hero.swingTicks > 0 and hero.attacksLanded == 0
  world.footmen[0].hp = FootmanHp div 2
  for tick in 0 ..< 60:
    game.tickWorld(nil)
  doAssert world.footmen[0].hp == FootmanHp div 2
  doAssert hero.attackObjectId == 0 and hero.attacksLanded == 0
  doAssert world.denyEffects.len == 0

echo "Testing the final damage boundary rejects healed and non-basic denies"
block:
  let
    game = denyGame()
    world = game.world
    hero = world.heroes[0]
  world.footmen[0].hp = FootmanHp div 2
  world.hitTarget(UnitHit, 1000, 100, hero.id)
  doAssert world.footmen[0].hp == FootmanHp div 2
  world.footmen[0].hp = 1
  for cause in [AbilityEffect, ItemEffect]:
    world.hitTarget(UnitHit, 1000, 100, hero.id, cause)
    doAssert world.footmen[0].hp == 1 and world.denyEffects.len == 0
  hero.hp = 0
  hero.state = Dying
  world.hitTarget(UnitHit, 1000, 100, hero.id)
  doAssert world.denyEffects.len == 1,
    "A valid collected basic attack survives its hero's same-tick death"
  world.hitTarget(UnitHit, 1000, 100, hero.id)
  doAssert world.denyEffects.len == 1

echo "Testing idle and attack-moving heroes never automatically deny"
for attackMoving in [false, true]:
  let
    game = denyGame()
    world = game.world
    hero = world.heroes[0]
  if attackMoving:
    doAssert world.applyAttackMove(hero.id,
      mapCoordinate(hero.position.x) + 2, mapCoordinate(hero.position.z))
  for tick in 0 ..< 60:
    game.tickWorld(nil)
  doAssert world.footmen[0].hp == 29
  doAssert hero.attacksLanded == 0 and world.denyEffects.len == 0

echo "Testing poison cannot damage a selected allied deny target"
block:
  let
    game = denyGame()
    world = game.world
    hero = world.heroes[0]
  hero.inventory[0] = PoisonPotion
  hero.itemCounts[0] = 1
  doAssert world.applyAttackTarget(hero.id, 1000)
  doAssert not world.applyUseItem(hero.id, 0)
  doAssert hero.inventory[0] == PoisonPotion and hero.itemCounts[0] == 1
  doAssert world.footmen[0].hp == 29 and world.denyEffects.len == 0

echo "Testing denied creeps preserve enemy nearby XP without deny rewards"
block:
  let
    game = denyGame()
    world = game.world
    hero = world.heroes[0]
    enemy = world.heroes[5]
    gold = hero.gold
    enemyGold = enemy.gold
  enemy.hp = enemy.maxHp
  enemy.state = Marching
  enemy.controls[StunControl].ends = 100_000
  var point = hero.position
  point.z += 2 * WorldScale
  enemy.place(point)
  world.footmen[0].hp = 1
  doAssert world.applyAttackTarget(hero.id, 1000)
  game.tickUntilHit()
  doAssert hero.gold == gold and hero.totalXp == 0
  doAssert enemy.gold == enemyGold and enemy.totalXp == CreepNearbyXp
  doAssert world.rewardEffects.len == 1
  doAssert world.rewardEffects[0].heroId == enemy.id
  doAssert world.rewardEffects[0].gold == 0

echo "Testing deny events are disposable and attack actions replay identically"
block:
  let
    game = denyGame()
    world = game.world
    hero = world.heroes[0]
    initial = world.clone()
    action = ReplayAction(kind: ActionAttackTarget, heroId: hero.id, first: 1000)
  doAssert world.applyReplayAction(action)
  var hashes: seq[uint64]
  for tick in 0 ..< 60:
    game.tickWorld(nil)
    hashes.add game.stateHash()
  doAssert world.footmen[0].hp <= 0
  world.restore(initial)
  doAssert world.applyReplayAction(action)
  for expected in hashes:
    game.tickWorld(nil)
    doAssert game.stateHash() == expected
  world.denyEffects = @[DenyEffect(heroId: hero.id, victimId: 1000)]
  let
    before = game.stateHash()
    snapshot = world.clone()
  doAssert snapshot.denyEffects.len == 0 and world.denyEffects.len == 1
  world.denyEffects.setLen(0)
  doAssert game.stateHash() == before
  world.denyEffects = @[DenyEffect(heroId: hero.id, victimId: 1000)]
  world.restore(snapshot)
  doAssert world.denyEffects.len == 0 and game.stateHash() == before

echo "Deny simulation tests passed"
