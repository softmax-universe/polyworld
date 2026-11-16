import
  polyworld/[daycycles, soundassets],
  trafficfixture,
  ../battlesounds

proc hasCue(events: BattleSoundEvents, cue: SoundCue): bool =
  ## Finds a cue without depending on simultaneous event ordering.
  for event in events:
    if event.cue == cue:
      return true

block realCombat:
  let world = trafficFixture(0, "open").world
  let soldier = world.spawnUnit(0, SoldierUnit, tile2(39, 40))
  let target = world.spawnUnit(1, SoldierUnit, tile2(40, 40))
  world.units[world.unitIndex(target)].hp = 1
  world.rebuildVision()
  var state: BattleSounds
  doAssert state.observeBattleSounds(world, 1).len == 0
  doAssert world.applyAttack(0, soldier, target)
  var attack, death: bool
  for _ in 0 ..< TickRate * 10:
    world.tickWorld(nil)
    let hashBefore = Game(world: world).stateHash()
    let events = state.observeBattleSounds(world, 1)
    attack = attack or events.hasCue(SwordSound)
    death = death or events.hasCue(HumanDeathSound)
    doAssert Game(world: world).stateHash() == hashBefore
    doAssert state.observeBattleSounds(world, 1).len == 0
    if death: break
  doAssert attack, "A real sword attack produces a weapon cue"
  doAssert death, "A real lethal hit produces one death cue"
  world.tickWorld(nil)
  doAssert not state.observeBattleSounds(world, 1).hasCue(HumanDeathSound)

block fogPauseAndSeek:
  let world = trafficFixture(0, "open").world
  let id = world.spawnUnit(1, MageUnit, tile2(65, 65))
  let unit = world.units[world.unitIndex(id)]
  world.rebuildVision()
  var state: BattleSounds
  discard state.observeBattleSounds(world, 1)
  inc world.tick
  unit.state = UnitAttacking
  unit.cooldown = 5
  doAssert state.observeBattleSounds(world, 1).len == 0,
    "Unseen enemy attacks must not reveal information through sound"
  inc world.tick
  unit.cooldown = 10
  doAssert state.observeBattleSounds(world, 0).hasCue(MagicSound)
  inc world.tick
  unit.cooldown = 15
  doAssert state.observeBattleSounds(world, 0, enabled = false).len == 0
  inc world.tick
  doAssert state.observeBattleSounds(world, 0).len == 0,
    "Muted fast-forward transitions are not replayed on resume"
  world.tick += 50
  unit.hp = 0
  doAssert state.observeBattleSounds(world, 0).len == 0
  world.tick = 0
  unit.hp = 1
  doAssert state.observeBattleSounds(world, 0).len == 0
  let replacement = trafficFixture(0, "open").world
  doAssert state.observeBattleSounds(replacement, 0).len == 0

block boundedPriority:
  let world = trafficFixture(200, "crossing").world
  var state: BattleSounds
  discard state.observeBattleSounds(world, 0)
  for unit in world.units:
    dec unit.hp
  world.units[^1].hp = 0
  inc world.tick
  let events = state.observeBattleSounds(world, 0)
  doAssert events.len == MaxBattleSounds
  doAssert events[0].cue == HumanDeathSound,
    "Deaths take priority over the burst of ordinary damage"

block dayAndNightTransitions:
  let
    world = trafficFixture(0, "open").world
    dayTicks = hudDayTicks(TickRate)
    dusk = (dayTicks * 10 + 23) div 24
    dawn = (dayTicks * 22 + 23) div 24
    midnight = (dayTicks * 16 + 23) div 24
  var state: BattleSounds
  for (boundary, cue) in [(dusk, NightfallSound), (dawn, DaybreakSound),
      (dayTicks + dusk, NightfallSound),
      (dayTicks + dawn, DaybreakSound)]:
    world.tick = boundary - 1
    doAssert state.observeBattleSounds(world, 1).len == 0
    let before = hudClock(world.tick, TickRate)
    doAssert before.hour == (if cue == NightfallSound: 17 else: 5)
    inc world.tick
    let
      hashBefore = Game(world: world).stateHash()
      events = state.observeBattleSounds(world, 1)
      after = hudClock(world.tick, TickRate)
    doAssert after.hour == (if cue == NightfallSound: 18 else: 6)
    doAssert Game(world: world).stateHash() == hashBefore
    doAssert events.len == 1 and events[0].cue == cue
    doAssert events[0].global, "Dawn and dusk are audible outside vision"
    doAssert state.observeBattleSounds(world, 1).len == 0
    inc world.tick
    doAssert state.observeBattleSounds(world, 1).len == 0

  world.tick = midnight - 1
  discard state.observeBattleSounds(world, 1)
  inc world.tick
  doAssert state.observeBattleSounds(world, 1).len == 0,
    "Midnight does not repeat the nightfall announcement"

  state = BattleSounds()
  world.tick = dusk
  doAssert state.observeBattleSounds(world, 1).len == 0,
    "Loading a match at dusk must stay silent"
  world.tick = dawn - 1
  discard state.observeBattleSounds(world, 1)
  inc world.tick
  doAssert state.observeBattleSounds(world, 1, enabled = false).len == 0
  inc world.tick
  doAssert state.observeBattleSounds(world, 1).len == 0,
    "Paused or fast-forwarded dawn is not replayed on resume"
  world.tick = dayTicks + dusk + 1
  doAssert state.observeBattleSounds(world, 1).len == 0,
    "Seeking across dusk must stay silent"
  inc world.tick
  doAssert state.observeBattleSounds(world, 1).len == 0
  world.tick = dusk - 1
  discard state.observeBattleSounds(world, 1)
  let replacement = trafficFixture(0, "open").world
  replacement.tick = dusk
  doAssert state.observeBattleSounds(replacement, 1).len == 0,
    "Replacing a world at a matching boundary must stay silent"

block winnerNotifications:
  for negotiated in [false, true]:
    for sameTeam in [false, true]:
      for player in 0'i32 ..< 2'i32:
        let world = trafficFixture(0, "open").world
        world.diplomacy.settings.enabled = negotiated
        world.diplomacy.settings.teams =
          if sameTeam: @[4'i32, 4'i32]
          else: @[4'i32, 9'i32]
        var state: BattleSounds
        discard state.observeBattleSounds(world, 0, player)
        world.over = true
        world.winner = 0
        inc world.tick
        let expected =
          if world.scores()[player] > 0: VictorySound else: DefeatSound
        let events = state.observeBattleSounds(world, 0, player)
        doAssert events.len == 1 and events[0].cue == expected,
          "Winner announcements must match negotiated and fixed-team scoring"
        doAssert events[0].global,
          "Result fanfares must use UI volume without distance attenuation"
        doAssert state.observeBattleSounds(world, 0, player).len == 0,
          "Repeated result-screen frames must not repeat a fanfare"
        inc world.tick
        doAssert state.observeBattleSounds(world, 0, player).len == 0

block spectatorAndDrawNotifications:
  for winner in [-1'i32, 0'i32, 1'i32]:
    let world = trafficFixture(0, "open").world
    var state: BattleSounds
    discard state.observeBattleSounds(world, 0)
    world.over = true
    world.winner = winner
    inc world.tick
    let
      events = state.observeBattleSounds(world, 0)
      expected =
        if winner < 0:
          ReadySound
        else:
          VictorySound
    doAssert events.len == 1 and events[0].cue == expected,
      "Spectators hear the winner; draws use neutral completion feedback"

block resultPriority:
  let world = trafficFixture(0, "open").world
  var state: BattleSounds
  discard state.observeBattleSounds(world, 0, player = 0)
  for index in 0 ..< MaxBattleSounds + 1:
    discard world.spawnUnit(
      0, SoldierUnit, tile2(20 + int32(index mod 10), 20 + int32(index div 10))
    )
  world.over = true
  world.winner = 0
  inc world.tick
  let events = state.observeBattleSounds(world, 0, player = 0)
  doAssert events.len == MaxBattleSounds
  doAssert events[0].cue == VictorySound,
    "Result fanfares must survive a full buffer of unit-ready notifications"

block resultSeeksAndRematches:
  let world = trafficFixture(0, "open").world
  var state: BattleSounds
  world.over = true
  world.winner = 0
  doAssert state.observeBattleSounds(world, 0, player = 0).len == 0,
    "Loading an already finished match must stay silent"
  inc world.tick
  doAssert state.observeBattleSounds(world, 0, player = 0).len == 0

  world.over = false
  world.tick = 10
  discard state.observeBattleSounds(world, 0, player = 0)
  world.over = true
  world.tick += 50
  doAssert state.observeBattleSounds(world, 0, player = 0).len == 0,
    "Seeking across the end must not announce a result"
  inc world.tick
  doAssert state.observeBattleSounds(world, 0, player = 0).len == 0

  world.over = false
  world.tick = 10
  discard state.observeBattleSounds(world, 0, player = 0)
  world.over = true
  inc world.tick
  doAssert state.observeBattleSounds(
    world, 0, player = 0, enabled = false
  ).len == 0
  inc world.tick
  doAssert state.observeBattleSounds(world, 0, player = 0).len == 0,
    "Hidden or fast-forwarded results must not queue a delayed fanfare"

  let replacement = trafficFixture(0, "open").world
  doAssert state.observeBattleSounds(replacement, 0, player = 0).len == 0
  replacement.over = true
  replacement.winner = 1
  inc replacement.tick
  let events = state.observeBattleSounds(replacement, 0, player = 0)
  doAssert events.len == 1 and events[0].cue == DefeatSound,
    "A new match must announce its own result once"
  state.resetBattleSounds()
  doAssert state.observeBattleSounds(replacement, 0, player = 0).len == 0

echo "Battle audio: combat, fog, seeks, bursts, day and result transitions passed"

when defined(nimAllocStats):
  block allocationFreeObservation:
    let
      world = trafficFixture(0, "open").world
      replacement = trafficFixture(0, "open").world
    var state: BattleSounds
    state.prepareBattleSounds(world)
    discard state.observeBattleSounds(world, 0, player = 0)

    # Simulation mutations happen outside each measured observer call.
    for i in 0 ..< 100:
      discard world.spawnUnit(int32(i mod 2), SoldierUnit,
        tile2(20 + int32(i mod 10), 20 + int32(i div 10)))
      inc world.tick
      let before = getAllocStats()
      let events = state.observeBattleSounds(world, 0, player = 0)
      let after = getAllocStats()
      doAssert after == before,
        "Growing armies must reuse their prepared audio snapshots"
      doAssert events.hasCue(ReadySound) == (i mod 2 == 0)

    for i in 0 ..< 12:
      world.buildings.add Building(
        id: world.nextBuildingId, owner: 0, kind: FarmBuilding,
        origin: tile2(30 + int32(i mod 6) * 2, 40 + int32(i div 6) * 2),
        footprint: (2'i32, 2'i32), hp: 100, state: BuildingUnderConstruction
      )
      inc world.nextBuildingId
      inc world.tick
      let before = getAllocStats()
      discard state.observeBattleSounds(world, 0, player = 0)
      let after = getAllocStats()
      doAssert after == before,
        "New construction must reuse map-sized audio snapshot storage"

    for unit in world.units:
      unit.hp = 100_000
      unit.state = UnitAttacking
    for building in world.buildings.mitems:
      building.hp = 100_000
    inc world.tick
    discard state.observeBattleSounds(world, 0, player = 0)
    for frame in 0 ..< 1000:
      inc world.tick
      for unit in world.units:
        dec unit.hp
        inc unit.cooldown
        inc unit.healCooldown
      for building in world.buildings.mitems:
        dec building.hp
        inc building.cooldown
      let before = getAllocStats()
      let events = state.observeBattleSounds(world, 0, player = 0)
      let after = getAllocStats()
      doAssert events.len == MaxBattleSounds
      doAssert after == before,
        "Dense combat events must not allocate or free snapshot/event storage"

    inc world.tick
    world.units[0].hp = 0
    world.buildings[^1].hp = 0
    world.over = true
    world.winner = 0
    let beforeResult = getAllocStats()
    let resultEvents = state.observeBattleSounds(world, 0, player = 0)
    let afterResult = getAllocStats()
    doAssert afterResult == beforeResult,
      "Deaths and victory must not allocate a scores sequence"
    doAssert resultEvents.hasCue(HumanDeathSound)
    doAssert resultEvents.hasCue(BuildingDeathSound)
    doAssert resultEvents.hasCue(VictorySound)

    # Retained corpses and rubble exceed the prepared live-entity bounds.
    for _ in 0 ..< 250:
      world.units.add Unit(id: world.nextUnitId, hp: 0, state: UnitDying)
      inc world.nextUnitId
    for _ in 0 ..< 1700:
      world.buildings.add Building(
        id: world.nextBuildingId, hp: 0, state: BuildingDying
      )
      inc world.nextBuildingId
    world.over = false
    world.tick = hudDayTicks(TickRate) * 10 div 24 - 1
    let beforeSeek = getAllocStats()
    doAssert state.observeBattleSounds(world, 0).len == 0
    inc world.tick
    doAssert state.observeBattleSounds(world, 0).hasCue(NightfallSound)
    state.resetBattleSounds()
    doAssert state.observeBattleSounds(world, 0).len == 0
    doAssert state.observeBattleSounds(replacement, 0).len == 0
    let afterSeek = getAllocStats()
    doAssert afterSeek == beforeSeek,
      "Seeking/resetting must not reserve extra storage for corpses or rubble"

  echo "LVD audio observer: zero allocations and frees after preparation"
