import
  std/[os, tempfiles],
  bassy,
  polyworld/[cli, pathing],
  ../[bots, content, maps, replays, sim]

const Artifacts = [StormcoilMaul, AbyssalPearl, Worldbreaker]

proc artifactGame(class = VanguardKnight, item = Worldbreaker): Game =
  ## Purchases an artifact before isolating one hero on open arena ground.
  var preset = defaultConfig()
  preset.roadWidth = 62
  result = newGame(generateMap(2026, preset), 100_000, 10, false,
    ReplayData(), drafting = false)
  let world = result.world
  world.camps.setLen(0)
  world.footmen.setLen(0)
  world.spawnTimerTicks = 100_000
  world.heroTurnTicks = 100_000
  for hero in world.heroes:
    hero.hp = 0
    hero.state = Dying
    hero.deathTicks = -100_000
  for building in world.buildings.mitems:
    building.hp = 0
  world.syncBuildings()
  let hero = world.heroes[0]
  hero.class = class
  hero.gold = 10_000
  if item != NoItem:
    doAssert world.applyBuyItem(hero.id, item.ord.int32)
  hero.refreshHeroStats()
  hero.state = Marching
  hero.hp = hero.maxHp
  let
    x = mapTiles() * 7 div 16
    z = mapTiles() * 9 div 64
    tile = layers[GroundLayer].tiles[z * mapTiles() + x]
  var point = WorldPoint(
    x: (x - mapTiles() div 2).int32 * WorldScale + WorldScale div 2,
    z: (z - mapTiles() div 2).int32 * WorldScale + WorldScale div 2
  )
  for height in tile.tops:
    point.y += height.int32 * WorldScale div 32
  hero.place(point)

proc impact(game: Game, target: int32) =
  ## Issues a real attack and stops on its first landed hit.
  let hero = game.world.heroes[0]
  game.world.rebuildVision()
  doAssert game.world.applyAttackTarget(hero.id, target)
  let before = hero.attacksLanded
  for tick in 0 ..< TickRate * 4:
    game.tickWorld(nil)
    if hero.attacksLanded > before:
      break
  doAssert hero.attacksLanded == before + 1, "Attack failed to land"

proc nearby(hero: Hero): WorldPoint =
  ## Places a target inside every hero's basic attack range.
  result = hero.position
  result.x += WorldScale * 3 div 5

echo "Artifacts cost gold, stack across slots, and work for every hero class"
for class in HeroClass:
  let
    game = artifactGame(class, NoItem)
    world = game.world
    hero = world.heroes[0]
    baseDamage = hero.heroAttackDamage()
  hero.state = Dying
  hero.hp = 0
  hero.gold = StormcoilMaul.itemSpec.cost - 1
  doAssert not world.applyBuyItem(hero.id, StormcoilMaul.ord.int32)
  doAssert hero.inventory[0] == NoItem
  hero.gold = 10_000
  var spent = 0'i32
  var bonus = 0'i32
  for item in Artifacts:
    doAssert world.applyBuyItem(hero.id, item.ord.int32)
    spent += item.itemSpec.cost
    bonus += item.itemSpec.damage
    doAssert hero.gold == 10_000 - spent
    doAssert hero.heroAttackDamage() == baseDamage + bonus
  doAssert not world.applyBuyItem(hero.id, Worldbreaker.ord.int32)
  doAssert hero.lastActionError == ActionAlreadyEquipped
  doAssert hero.gold == 10_000 - spent
  doAssert world.applySwapItems(hero.id, 2, 5)
  doAssert hero.inventory[5] == Worldbreaker
  doAssert hero.heroAttackDamage() == baseDamage + bonus
  doAssert world.sellPrice(hero.id, 5) == Worldbreaker.itemSpec.cost div 2
  doAssert world.applySellItem(hero.id, 5)
  doAssert hero.heroAttackDamage() ==
    baseDamage + bonus - Worldbreaker.itemSpec.damage
  doAssert hero.gold == 10_000 - spent + Worldbreaker.itemSpec.cost div 2

echo "Worldbreaker one-shots full-health level-20 heroes with maximum HP gear"
for class in HeroClass:
  let
    game = artifactGame(class)
    world = game.world
    victim = world.heroes[5]
  victim.class = class
  victim.level = HeroMaxLevel
  var slot = 0
  for item in Item:
    if item.itemSpec.kind == Equipment and item.itemSpec.maxHp > 0:
      doAssert slot < InventorySlots
      victim.inventory[slot] = item
      victim.itemCounts[slot] = 1
      inc slot
  victim.refreshHeroStats()
  victim.state = Marching
  victim.hp = victim.maxHp
  victim.controls[StunControl].ends = 100_000
  victim.place(world.heroes[0].nearby())
  game.impact(victim.id)
  doAssert victim.hp <= 0 and victim.state == Dying,
    $class & " HP " & $victim.hp & " state " & $victim.state

echo "Stormcoil Maul one-shots lane creeps and Worldbreaker slays camp leaders"
for kind in CreepKind:
  let
    game = artifactGame(Arcanist, StormcoilMaul)
    world = game.world
  var creep = Footman(id: 1000, team: BlueTeam, kind: kind, hp: FootmanHp)
  creep.controls[StunControl].ends = 100_000
  creep.place(world.heroes[0].nearby())
  world.footmen.add creep
  game.impact(creep.id)
  doAssert world.footmen[0].hp <= 0
block:
  let
    game = artifactGame(Ranger)
    world = game.world
    position = world.heroes[0].nearby()
  world.camps = @[Camp(center: position, tier: 3,
    started: true, state: RestingCamp)]
  var leader = Footman(id: 1000, team: BlueTeam, camp: 1,
    campTier: 3, leader: true)
  leader.hp = leader.unitMaxHp
  leader.controls[StunControl].ends = 100_000
  leader.place(position)
  world.footmen.add leader
  game.impact(leader.id)
  doAssert world.footmen[0].hp <= 0

echo "Worldbreaker one-shots every exposed structure and preserves protection"
for kind in BuildingKind:
  for tier in TowerTier:
    let
      game = artifactGame(Crossbowman)
      world = game.world
      hp = if kind == TowerBuilding:
        TowerHitPoints[tier] else: BarracksHitPoints
    world.buildings = @[Building(id: 10, kind: kind, team: BlueTeam,
      tier: tier, hp: hp, maxHp: hp, position: world.heroes[0].nearby())]
    doAssert world.buildingExposed(world.buildings[0])
    game.impact(10)
    doAssert world.buildings[0].hp <= 0
for protected in [false, true]:
  let
    game = artifactGame(Arcanist)
    world = game.world
    hero = world.heroes[0]
  if protected:
    var guard = world.buildings[^1]
    guard.team = BlueTeam
    guard.guardsGod = true
    guard.hp = TowerHitPoints[GateTower]
    guard.position.x += 20 * WorldScale
    world.buildings = @[guard]
  world.forts[1].center = hero.nearby()
  if protected:
    world.rebuildVision()
    doAssert not world.fortExposed(BlueTeam)
    doAssert world.applyAttackTarget(hero.id, world.forts[1].id)
    for tick in 0 ..< TickRate * 2:
      game.tickWorld(nil)
    doAssert world.forts[1].hp == FortHp
  else:
    doAssert world.fortExposed(BlueTeam)
    game.impact(world.forts[1].id)
    doAssert world.forts[1].hp == 0
block:
  let
    game = artifactGame(Arcanist)
    world = game.world
    hero = world.heroes[0]
  var distant = hero.position
  distant.x += 20 * WorldScale
  world.buildings = @[
    Building(id: 10, kind: TowerBuilding, team: BlueTeam, lane: 0,
      tier: OuterTower, hp: TowerHitPoints[OuterTower], position: distant),
    Building(id: 11, kind: TowerBuilding, team: BlueTeam, lane: 0,
      tier: InnerTower, hp: TowerHitPoints[InnerTower], position: hero.nearby())
  ]
  world.rebuildVision()
  doAssert not world.buildingExposed(world.buildings[1])
  doAssert world.applyAttackTarget(hero.id, 11)
  for tick in 0 ..< TickRate * 2:
    game.tickWorld(nil)
  doAssert world.buildings[1].hp == TowerHitPoints[InnerTower]
  doAssert world.buildings[0].hp == TowerHitPoints[OuterTower]

echo "Bassy observations include artifact damage after purchase and sale"
block:
  let
    directory = createTempDir("gota-artifacts-", "")
    path = directory / "damage.bas"
    game = artifactGame()
    hero = game.world.heroes[0]
  defer:
    removeDir(directory)
  writeFile(path, "' @gota-structures\n" &
    "legacy = selfAttackDamage\nstructured = self.attackDamage\n")
  game.loadBots([BotGroup(path: path, count: 10)])
  game.runBotDecisions()
  let vm = game.heroVms[0]
  doAssert not vm.failed, vm.lastError
  doAssert vm.runtime.getGlobal("legacy") == hero.heroAttackDamage()
  doAssert vm.runtime.getGlobal("structured") == hero.heroAttackDamage()
  hero.state = Dying
  hero.hp = 0
  doAssert game.world.applySellItem(hero.id, 0)
  hero.state = Marching
  hero.hp = hero.maxHp
  inc game.world.tick
  game.runBotDecisions()
  doAssert not vm.failed, vm.lastError
  doAssert vm.runtime.getGlobal("legacy") == hero.heroAttackDamage()
  doAssert vm.runtime.getGlobal("structured") == hero.heroAttackDamage()

echo "GOTA artifact combat tests passed"
