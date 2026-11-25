import
  polyworld/[pathing, tapes],
  ../[content, maps, replays, sim]

proc enter(hero: Hero, area: BaseArea) =
  ## Places the hero on an open tile of the requested generated region.
  for z in 0 ..< mapTiles():
    for x in 0 ..< mapTiles():
      if baseArea(x, z) == area and isWalkable(GroundLayer, x, z):
        hero.place(WorldPoint(
          x: (x - mapTiles() div 2).int32 * WorldScale + WorldScale div 2,
          z: (z - mapTiles() div 2).int32 * WorldScale + WorldScale div 2
        ))
        hero.navLayer = GroundLayer
        return
  doAssert false, "No open floor in " & $area

proc quietGame(items: openArray[Item] = []): Game =
  ## Purchases real equipment before isolating one hero from combat and spawn.
  result = newGame(generateMap(54), 100_000, 10, false, ReplayData(),
    drafting = false)
  result.world.spawnTimerTicks = 100_000
  result.world.heroTurnTicks = 100_000
  for hero in result.world.heroes:
    hero.state = Dying
    hero.deathTicks = -100_000
    hero.hp = 0
  for building in result.world.buildings.mitems:
    building.hp = 0
  let hero = result.world.heroes[0]
  hero.state = Marching
  hero.hp = hero.maxHp
  hero.gold = 10_000
  for item in items:
    doAssert result.world.applyBuyItem(hero.id, item.ord.int32)
  hero.enter(OutsideBase)
  hero.hp = 1
  hero.mana = 0
  doAssert not hero.inOwnSpawn

proc step(game: Game, ticks: int) =
  ## Advances the production tick pipeline without bot commands.
  for i in 0 ..< ticks:
    game.tickWorld(nil)

echo "Equipment recovers the stated rates while ordinary mana stays unchanged"
for item in [NoItem, IronbarkPauldrons, KnightArmor, ThornwoodStaff,
    ArcaneSpellbook]:
  let
    game = if item == NoItem: quietGame() else: quietGame([item])
    hero = game.world.heroes[0]
    spec = item.itemSpec
  game.step(10 * TickRate)
  doAssert hero.hp == 1 + 10 * spec.healthRegen
  doAssert hero.mana == 10 * (TickRate div 6 + spec.manaRegen)
  doAssert not hero.inOwnSpawn

echo "Different sustain items add together in every inventory slot"
block:
  let
    game = quietGame([IronbarkPauldrons, KnightArmor, ThornwoodStaff,
      ArcaneSpellbook])
    world = game.world
    hero = world.heroes[0]
  doAssert world.applySwapItems(hero.id, 0, 5)
  doAssert world.applySwapItems(hero.id, 1, 4)
  game.step(10 * TickRate)
  doAssert hero.hp == 41
  doAssert hero.mana == 70
  hero.enter(RedKeep)
  doAssert hero.canShop and not hero.inOwnSpawn
  doAssert world.applySellItem(hero.id, 2)
  doAssert world.applySellItem(hero.id, 3)
  let health = hero.hp
  hero.mana = 0
  game.step(10 * TickRate)
  doAssert hero.hp == health + 30
  doAssert hero.mana == 40
  doAssert world.applySellItem(hero.id, 4)
  doAssert world.applySellItem(hero.id, 5)
  let remaining = hero.hp
  game.step(TickRate)
  doAssert hero.hp == remaining

echo "Sustain continues while stunned, casting, and channeling a portal"
for mode in 0 .. 2:
  let
    game = quietGame([ThornwoodStaff])
    world = game.world
    hero = world.heroes[0]
    ends = 2 * TickRate
  case mode
  of 0:
    hero.controls[StunControl].ends = ends
  of 1:
    hero.castPoseUntil = ends
  else:
    hero.portalEnds = ends
  game.step(TickRate)
  doAssert hero.hp == 2 and hero.mana == 5

echo "Equipment recovery caps at maximum resources and never revives the dead"
block:
  let
    game = quietGame([KnightArmor, ThornwoodStaff, ArcaneSpellbook])
    hero = game.world.heroes[0]
  hero.hp = hero.maxHp - 1
  hero.mana = hero.maxMana - 1
  game.step(3 * TickRate)
  doAssert hero.hp == hero.maxHp and hero.mana == hero.maxMana
  hero.hp = 0
  hero.mana = 0
  game.step(1)
  doAssert hero.state == Dying and hero.hp == 0
  game.step(3 * TickRate)
  doAssert hero.hp == 0 and hero.mana == 0

echo "Regeneration resumes identically from snapshots and serialized replays"
block:
  let
    game = quietGame([IronbarkPauldrons, KnightArmor, ThornwoodStaff,
      ArcaneSpellbook])
    initial = game.world.clone()
  game.recorder = initReplayRecorder(game.currentSetup(uint32(10 * TickRate)),
    game.map.preset)
  game.step(13)
  let checkpoint = game.world.clone()
  game.step(10 * TickRate - 13)
  let
    finalHash = game.stateHash()
    replay = decodeReplay(game.recorder.data.encodeReplay())
    playback = newGame(generateMap(replay.config.seed, replay.config.mapPreset),
      replay.config.spawnIntervalTicks, 0, true, replay)
  game.recorder = nil
  game.world.restore(checkpoint)
  game.step(10 * TickRate - 13)
  doAssert game.stateHash() == finalHash
  playback.historyPlayback = true
  playback.replayPlayer = initReplayPlayer(replay)
  playback.world.restore(initial)
  for tick in 0 ..< replay.hashes.len:
    playback.tickWorld(nil)
    doAssert playback.hashCheck.mismatches == 0, playback.hashCheck.error
  doAssert playback.stateHash() == finalHash

echo "GOTA equipment regeneration tests passed"
