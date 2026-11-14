import
  polyworld/[daycycles, soundassets],
  ../[audios, content, maps, replays, sim]

proc hasCue(events: ArenaSounds, cue: SoundCue): bool =
  ## Checks semantic output without opening a device or reading audio files.
  for event in events:
    if event.cue == cue:
      return true

proc soundWorld(): World =
  ## Creates a visible combat snapshot without navigation or graphics.
  result = World(
    heroes: @[Hero(id: 100, hp: 100, class: VanguardKnight)],
    footmen: @[Footman(id: 1000, hp: 50, camp: 1)],
    buildings: @[Building(id: 10, hp: 500)],
    forts: [Fort(id: 1, hp: 500), Fort(id: 2, hp: 500)]
  )
  for team in Team:
    result.teamVisible[team.ord] = newSeq[uint8](mapTiles() * mapTiles())
    for cell in result.teamVisible[team.ord].mitems:
      cell = 255

echo "Audio follows new ticks, without loading or duplicate playback."
block:
  let world = soundWorld()
  var audio: ArenaAudio
  doAssert audio.collectSounds(world, 0).len == 0
  inc world.tick
  world.heroes[0].hp = 80
  world.attackEffects = @[AttackEffect(style: RangedAttack)]
  let events = audio.collectSounds(world, 0)
  doAssert events.hasCue(ImpactSound)
  doAssert events.hasCue(BowSound)
  doAssert audio.collectSounds(world, 0).len == 0

  inc world.tick
  world.heroes[0].hp = 0
  world.footmen[0].hp = 0
  world.buildings[0].hp = 0
  let deaths = audio.collectSounds(world, 0)
  doAssert deaths.hasCue(HumanDeathSound)
  doAssert deaths.hasCue(CreatureDeathSound)
  doAssert deaths.hasCue(BuildingDeathSound)
  inc world.tick
  doAssert not audio.collectSounds(world, 0).hasCue(HumanDeathSound)

echo "Seeking and fast playback refresh silently without deferred bursts."
block:
  let world = soundWorld()
  var audio: ArenaAudio
  audio.syncAudio(world)
  world.tick = 300
  world.heroes[0].hp = 0
  world.attackEffects = @[AttackEffect(style: MeleeAttack)]
  doAssert audio.collectSounds(world, 0).len == 0
  inc world.tick
  doAssert audio.collectSounds(world, 0, enabled = false).len == 0
  world.attackEffects.setLen(0)
  inc world.tick
  doAssert audio.collectSounds(world, 0).len == 0
  world.tick = 2
  doAssert audio.collectSounds(world, 0).len == 0

echo "Fog suppresses attack, spell, damage and death cues."
block:
  let world = soundWorld()
  var audio: ArenaAudio
  audio.syncAudio(world)
  for cell in world.teamVisible[RedTeam.ord].mitems:
    cell = 0
  inc world.tick
  world.heroes[0].hp = 0
  world.casts = @[SpellCast(ability: MeteorStrike, started: world.tick)]
  world.attackEffects = @[AttackEffect(style: MeleeAttack)]
  doAssert audio.collectSounds(world, 1).len == 0
  for cell in world.teamVisible[RedTeam.ord].mitems:
    cell = 255
  world.attackEffects.setLen(0)
  inc world.tick
  doAssert audio.collectSounds(world, 1).len == 0

echo "Spells, tower launches and match results play only on their transition."
block:
  let world = soundWorld()
  var audio: ArenaAudio
  audio.syncAudio(world)
  inc world.tick
  world.casts = @[
    SpellCast(ability: MeteorStrike, started: world.tick),
    SpellCast(ability: HealingBloom, started: world.tick)
  ]
  world.towerShots = @[TowerShot(started: world.tick)]
  let spells = audio.collectSounds(world, 0)
  doAssert spells.hasCue(FireSound)
  doAssert spells.hasCue(HealSound)
  doAssert spells.hasCue(MagicSound)
  inc world.tick
  doAssert audio.collectSounds(world, 0).len == 0
  world.gameOver = true
  world.winner = BlueTeam
  inc world.tick
  doAssert audio.collectSounds(world, 0, playerTeam = RedTeam.ord).
    hasCue(DefeatSound)
  inc world.tick
  doAssert audio.collectSounds(world, 0, playerTeam = RedTeam.ord).len == 0

echo "Result fanfares follow the local team once, including spectators and draws."
block:
  for winner in Team:
    for playerTeam in [-1, RedTeam.ord, BlueTeam.ord]:
      for draw in [false, true]:
        let world = soundWorld()
        var audio: ArenaAudio
        audio.syncAudio(world)
        world.gameOver = true
        world.winner = winner
        world.draw = draw
        inc world.tick
        let
          events = audio.collectSounds(world, 0, playerTeam = playerTeam)
          expected =
            if draw: ReadySound
            elif playerTeam >= 0 and playerTeam != winner.ord: DefeatSound
            else: VictorySound
        doAssert events.len == 1 and events[0].cue == expected
        doAssert not events[0].spatial,
          "Result fanfares use UI volume without camera attenuation"
        doAssert audio.collectSounds(world, 0, playerTeam = playerTeam).len == 0
        inc world.tick
        doAssert audio.collectSounds(world, 0, playerTeam = playerTeam).len == 0

echo "Completed loads and seeks stay silent, and a new match gets its own fanfare."
block:
  let world = soundWorld()
  world.gameOver = true
  var audio: ArenaAudio
  doAssert audio.collectSounds(world, 0).len == 0,
    "Opening a completed replay must not announce a new result"
  world.gameOver = false
  world.tick = 100
  audio.syncAudio(world)
  world.gameOver = true
  world.tick = 200
  doAssert audio.collectSounds(world, 0).len == 0,
    "Seeking across the final tick must not play the result"
  world.gameOver = false
  world.tick = 100
  doAssert audio.collectSounds(world, 0).len == 0
  world.gameOver = true
  inc world.tick
  doAssert audio.collectSounds(world, 0, enabled = false).len == 0,
    "Muted observation must not leave a delayed result announcement"
  inc world.tick
  doAssert audio.collectSounds(world, 0).len == 0

  let rematch = soundWorld()
  rematch.tick = world.tick + 1
  doAssert audio.collectSounds(rematch, 0).len == 0
  rematch.gameOver = true
  rematch.winner = BlueTeam
  inc rematch.tick
  doAssert audio.collectSounds(rematch, 0, playerTeam = BlueTeam.ord).
    hasCue(VictorySound)
  doAssert audio.collectSounds(rematch, 0, playerTeam = BlueTeam.ord).len == 0

echo "The result fanfare survives a full final combat burst."
block:
  let world = soundWorld()
  world.footmen = newSeq[Footman](100)
  for i in 0 ..< world.footmen.len:
    world.footmen[i] = Footman(id: 1000 + i.int32, hp: 100)
  var audio: ArenaAudio
  audio.syncAudio(world)
  for unit in world.footmen.mitems:
    unit.hp = 0
  world.gameOver = true
  world.winner = RedTeam
  inc world.tick
  let events = audio.collectSounds(world, 0, playerTeam = RedTeam.ord)
  doAssert events.len == 65
  doAssert events[events.len - 1].cue == VictorySound
  doAssert not events[events.len - 1].spatial

echo "The ready horn plays once when preparation ends, not when drafting ends."
block:
  let
    game = newGame(generateMap(2026), 100_000, 10, false, ReplayData())
    world = game.world
  var audio: ArenaAudio
  audio.syncAudio(world)
  while world.phase == Drafting:
    var classId = 0'i32
    while not world.heroAvailable(classId):
      inc classId
    doAssert world.applyDraft(world.draftHeroId(), classId)
  game.tickWorld(nil)
  doAssert world.preparationTicksLeft() > 0
  doAssert not audio.collectSounds(world, 0).hasCue(ReadySound),
    "Completing the draft starts preparation without playing the ready horn"

  world.preparationTicks = PreparationTicks - 1
  world.tick = world.draftTicks + world.preparationTicks
  audio.syncAudio(world)
  game.tickWorld(nil)
  doAssert world.preparationTicksLeft() == 0
  let events = audio.collectSounds(world, 0)
  doAssert events.len == 1 and events[0].cue == ReadySound
  doAssert not events[0].spatial
  doAssert audio.collectSounds(world, 0).len == 0
  game.tickWorld(nil)
  doAssert not audio.collectSounds(world, 0).hasCue(ReadySound),
    "The ready horn must not repeat on later battle ticks"

echo "Casts released during an authoritative tick keep the observed timestamp."
block:
  let
    game = newGame(generateMap(2026), 100_000, 10, false,
      ReplayData(), drafting = false)
    world = game.world
    caster = world.heroes[0]
  world.heroTurnTicks = 1
  caster.class = DruidWarden
  caster.abilityLevels = [1'i32, 1, 1, 1]
  caster.spellsReady = false
  caster.state = Marching
  caster.refreshHeroStats()
  caster.hp = caster.maxHp - 100
  caster.mana = 10_000
  var audio: ArenaAudio
  audio.syncAudio(world)
  game.tickWorld(proc() =
    doAssert world.applyCastTarget(caster.id, PassiveAbility.ord.int32,
      caster.id), $caster.lastActionError
  )
  doAssert world.casts.len > 0
  doAssert world.casts[^1].started == world.tick
  doAssert audio.collectSounds(world, 0).hasCue(HealSound)

  let towerWorld = soundWorld()
  towerWorld.footmen.setLen(0)
  var tower = Building(id: 20, hp: 100, team: BlueTeam,
    attackTicks: TowerAttackTicks, kind: TowerBuilding)
  var towerAudio: ArenaAudio
  towerAudio.syncAudio(towerWorld)
  inc towerWorld.tick
  towerWorld.updateTower(tower)
  doAssert towerWorld.towerShots.len == 1
  doAssert towerWorld.towerShots[0].started == towerWorld.tick
  doAssert towerAudio.collectSounds(towerWorld, 0).hasCue(MagicSound)

echo "Dawn and dusk follow the battle clock once, including draft delays."
block:
  const
    DayTicks = hudDayTicks(TickRate)
    DuskTick = DayTicks * 10 div 24
    DawnTick = DayTicks * 22 div 24
  for (boundary, cue) in [
      (DuskTick, NightfallSound), (DawnTick, DaybreakSound),
      (DuskTick + DayTicks, NightfallSound),
      (DawnTick + DayTicks, DaybreakSound)]:
    let world = soundWorld()
    world.draftTicks = 10 * TickRate
    world.preparationTicks = PreparationTicks
    world.tick = boundary + world.draftTicks + world.preparationTicks - 1
    var audio: ArenaAudio
    doAssert audio.collectSounds(world, 1).len == 0
    for cell in world.teamVisible[RedTeam.ord].mitems:
      cell = 0
    inc world.tick
    let events = audio.collectSounds(world, 1)
    doAssert events.len == 1 and events[0].cue == cue
    doAssert not events[0].spatial,
      "Time announcements remain audible regardless of camera position or fog"
    doAssert audio.collectSounds(world, 1).len == 0
    inc world.tick
    doAssert audio.collectSounds(world, 1).len == 0

  let world = soundWorld()
  var audio: ArenaAudio
  world.tick = DayTicks * 16 div 24 - 1
  audio.syncAudio(world)
  inc world.tick
  doAssert audio.collectSounds(world, 0).len == 0,
    "Midnight remains night and must not produce a new announcement"
  world.tick = DuskTick - 1
  world.draftTicks = 10 * TickRate
  audio.syncAudio(world)
  inc world.tick
  doAssert audio.collectSounds(world, 0).len == 0,
    "Raw simulation time must not announce dusk before the battle clock"

echo "Clock announcements stay silent on load, seek, disabled ticks and reset."
block:
  const
    DuskTick = hudDayTicks(TickRate) * 10 div 24
    DawnTick = hudDayTicks(TickRate) * 22 div 24
  let world = soundWorld()
  world.tick = DuskTick
  var audio: ArenaAudio
  doAssert audio.collectSounds(world, 0).len == 0
  world.tick = DawnTick
  doAssert audio.collectSounds(world, 0).len == 0
  world.tick = DuskTick - 1
  doAssert audio.collectSounds(world, 0).len == 0
  inc world.tick
  doAssert audio.collectSounds(world, 0, enabled = false).len == 0
  inc world.tick
  doAssert audio.collectSounds(world, 0).len == 0
  world.tick = DawnTick - 1
  audio.syncAudio(world)
  let replacement = soundWorld()
  replacement.tick = DawnTick
  doAssert audio.collectSounds(replacement, 0).len == 0,
    "Replacing a world at a consecutive tick establishes a silent baseline"
  inc replacement.tick
  doAssert audio.collectSounds(replacement, 0).len == 0

when defined(nimAllocStats):
  echo "Arena audio reuses storage at full population and with new IDs."
  block:
    let world = soundWorld()
    world.camps = @[Camp(count: 7)]
    var audio: ArenaAudio
    audio.syncAudio(world)
    world.footmen = newSeq[Footman](UnitCap + 7)
    for i in 0 ..< world.footmen.len:
      world.footmen[i] = Footman(
        id: 1_000_000 + i.int32,
        hp: 1000,
        camp: if i < UnitCap: 0 else: 1
      )
    world.attackEffects = @[AttackEffect(style: RangedAttack)]
    world.casts = @[SpellCast(ability: HealingBloom)]
    var hadDamage, hadDeaths: bool
    let before = getAllocStats()
    for tick in 0 ..< 200:
      inc world.tick
      world.casts[0].started = world.tick
      for i in 0 ..< world.footmen.len:
        if tick mod 20 == 0:
          world.footmen[i].id += 10_000
          world.footmen[i].hp = 1000
        elif tick mod 20 == 19:
          world.footmen[i].hp = 0
        else:
          dec world.footmen[i].hp
      let events = audio.collectSounds(world, 0)
      hadDamage = hadDamage or events.hasCue(ImpactSound)
      hadDeaths = hadDeaths or events.hasCue(HumanDeathSound)
      doAssert events.len <= MaxArenaSounds
    let after = getAllocStats()
    doAssert after == before, $(after - before)
    doAssert hadDamage and hadDeaths

    world.attackEffects.setLen(0)
    world.casts.setLen(0)
    world.tick = hudDayTicks(TickRate) * 10 div 24 - 1
    audio.syncAudio(world)
    let beforeTransitions = getAllocStats()
    inc world.tick
    doAssert audio.collectSounds(world, 0).hasCue(NightfallSound)
    world.tick += 100
    doAssert audio.collectSounds(world, 0).len == 0
    inc world.tick
    doAssert audio.collectSounds(world, 0, enabled = false).len == 0
    audio.syncAudio(world)
    doAssert getAllocStats() == beforeTransitions

    let beforeResult = getAllocStats()
    world.gameOver = true
    world.winner = BlueTeam
    inc world.tick
    doAssert audio.collectSounds(world, 0, playerTeam = RedTeam.ord).
      hasCue(DefeatSound)
    inc world.tick
    doAssert audio.collectSounds(world, 0).len == 0
    doAssert getAllocStats() == beforeResult

    let replacement = soundWorld()
    replacement.tick = world.tick + 1
    let beforeReplacement = getAllocStats()
    doAssert audio.collectSounds(replacement, 0).len == 0
    inc replacement.tick
    doAssert audio.collectSounds(replacement, 0).len == 0
    doAssert getAllocStats() == beforeReplacement

    let larger = soundWorld()
    larger.camps = @[Camp(count: 30)]
    audio.syncAudio(larger)
    larger.footmen = newSeq[Footman](UnitCap + 30)
    for i in 0 ..< larger.footmen.len:
      larger.footmen[i] = Footman(id: 1_000_000 + i.int32, hp: 1000)
    let beforeLargerPopulation = getAllocStats()
    inc larger.tick
    discard audio.collectSounds(larger, 0)
    inc larger.tick
    for unit in larger.footmen.mitems:
      dec unit.hp
    doAssert audio.collectSounds(larger, 0).hasCue(ImpactSound)
    doAssert getAllocStats() == beforeLargerPopulation

echo "Arena audio checks passed."
