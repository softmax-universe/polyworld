import
  fixxy, vmath,
  polyworld/[daycycles, soundassets],
  content, maps, sim, rendervisibility

const
  MaxBattleSounds* = 64
  # Sword_Attack is 1.533 seconds, with its downstroke around 0.4 seconds.
  ChopSoundTicks = 37'i32
  ChopSoundLeadTicks = 10'i32
  MineSoundLeadTicks = 6'i32

type
  UnitSoundState = object
    id, hp, cooldown, healCooldown: int32
    state: UnitState
    stateTicks, carryGold, carryWood: int32
  BuildingSoundState = object
    id, hp, cooldown: int32
    state: BuildingState
    buildTicks, buildTotal: int32
  BattleSound* = object
    cue*: SoundCue
    position*: Vec3
    global*: bool
  BattleSoundEvents* = object
    len*: int
    events: array[MaxBattleSounds, BattleSound]
  BattleSounds* = object
    world: World
    tick: int32
    over: bool
    units: seq[UnitSoundState]
    buildings: seq[BuildingSoundState]
    unitCount, buildingCount: int

iterator items*(events: BattleSoundEvents): BattleSound =
  ## Iterates the occupied part of the fixed frame-event buffer.
  for index in 0 ..< events.len:
    yield events.events[index]

proc `[]`*(events: BattleSoundEvents, index: int): BattleSound =
  ## Reads a frame event without exposing unused storage.
  doAssert index in 0 ..< events.len
  events.events[index]

proc resetBattleSounds*(state: var BattleSounds) =
  ## Establishes a new baseline while retaining all reserved snapshot storage.
  state.world = nil
  state.tick = 0
  state.over = false
  state.unitCount = 0
  state.buildingCount = 0

proc prepareBattleSounds*(
    state: var BattleSounds, world: World,
    unitCapacity = 0, buildingCapacity = 0
) =
  ## Reserves match bounds before playback; custom fixtures can request more.
  doAssert unitCapacity >= 0 and buildingCapacity >= 0
  var
    smallestFootprint = high(int32)
    livingUnits, livingBuildings: int
  for unit in world.units:
    if unit.hp > 0:
      inc livingUnits
  for building in world.buildings:
    if building.hp > 0 and building.state != BuildingDying:
      inc livingBuildings
  for stats in BuildingTable:
    smallestFootprint = min(smallestFootprint,
      stats.footprint.width * stats.footprint.depth)
  doAssert smallestFootprint > 0
  for owner in 0'i32 ..< FactionCount.int32:
    for kind in UnitKind:
      doAssert unitOf(owner, kind).food >= 1,
        "Audio's living-unit capacity requires food-reserved units"
  # Training reserves food before spawn. Corpses and rubble need no history.
  # Living building footprints do not overlap, so map area bounds their count.
  let
    units = max(unitCapacity,
      max(livingUnits, world.players.len * FoodCapMax.int))
    buildings = max(buildingCapacity,
      max(livingBuildings,
        world.map.side.int * world.map.side.int div smallestFootprint.int))
  if state.units.len < units:
    state.units.setLen(units)
  if state.buildings.len < buildings:
    state.buildings.setLen(buildings)
  state.resetBattleSounds()

proc attackSound(kind: UnitKind): SoundCue =
  ## Matches the weapon shown by each combat role.
  case kind
  of ArcherUnit: BowSound
  of MageUnit, ClericUnit: MagicSound
  of CatapultUnit, SummonUnit: FireSound
  of PeonUnit, SoldierUnit, KnightUnit: SwordSound

proc deathSound(kind: UnitKind): SoundCue =
  ## Gives summoned creatures and siege engines distinct deaths.
  case kind
  of SummonUnit: CreatureDeathSound
  of CatapultUnit: BuildingDeathSound
  else: HumanDeathSound

proc soundPriority(event: BattleSound): int =
  ## Keeps deaths and player notifications above dense combat noise.
  if event.cue in {VictorySound, DefeatSound}: 4
  elif event.global: 3
  elif event.cue in {HumanDeathSound, CreatureDeathSound, BuildingDeathSound}: 2
  elif event.cue in {ChopSound, MineSound, DeliverGoldSound, DeliverWoodSound}: -1
  elif event.cue in {ImpactSound, BuildingHitSound, BuildPlaceSound}: 0
  else: 1

proc workSoundBeat(unit: Unit, previous: UnitSoundState,
    total, period, lead: int32): bool =
  ## Follows the work countdown, never wall time or a stationary work pose.
  let elapsed = total - unit.stateTicks
  previous.state == unit.state and unit.stateTicks < previous.stateTicks and
    unit.stateTicks >= 0 and elapsed >= lead and
    (elapsed - lead) mod period == 0

proc miningVisible(world: World, viewMode: int32,
    unit: Unit, mine: Building): bool =
  ## Neutral mine art is global, but enemy activity requires current sight.
  if viewMode notin 0 .. world.players.len.int32:
    return false
  if viewMode == 0 or unit.owner == viewMode - 1:
    return true
  for y in mine.origin.y.int32 ..< mine.origin.y.int32 + mine.footprint.depth:
    for x in mine.origin.x.int32 ..< mine.origin.x.int32 + mine.footprint.width:
      if world.renderTileVisible(viewMode, x, y):
        return true

proc soundPosition(building: Building, half: float32): Vec3 =
  ## Centers source audio on the structure rather than a hidden worker body.
  vec3(building.origin.x.float32 + building.footprint.width.float32 / 2 - half,
    0, building.origin.y.float32 + building.footprint.depth.float32 / 2 - half)

proc addBattleSound(events: var BattleSoundEvents, event: BattleSound) =
  ## Bounds each tick while preserving the most significant events first.
  let priority = event.soundPriority
  var index = 0
  while index < events.len and events.events[index].soundPriority >= priority:
    inc index
  if index >= MaxBattleSounds:
    return
  let last = min(events.len, MaxBattleSounds - 1)
  for shifted in countdown(last, index + 1):
    events.events[shifted] = events.events[shifted - 1]
  events.events[index] = event
  events.len = min(events.len + 1, MaxBattleSounds)

proc observeBattleSounds*(
    state: var BattleSounds,
    world: World,
    viewMode: int32,
    player = -1'i32,
    enabled = true
): BattleSoundEvents =
  ## Observes each tick once, silently rebasing on seek, pause, or replacement.
  let continuous = state.world == world and world.tick == state.tick + 1
  if state.world == world and world.tick == state.tick:
    return
  if state.world != world:
    state.prepareBattleSounds(world)
  let half = world.map.side.float32 / 2
  if continuous and enabled:
    let
      previousNight = isNight(clockHour(state.tick, TickRate))
      currentNight = isNight(clockHour(world.tick, TickRate))
    if currentNight != previousNight:
      result.addBattleSound BattleSound(
        cue: (if currentNight: NightfallSound else: DaybreakSound),
        global: true
      )
    var unitSlot = 0
    for unit in world.units:
      while unitSlot < state.unitCount and
          state.units[unitSlot].id < unit.id:
        inc unitSlot
      if unitSlot == state.unitCount or state.units[unitSlot].id != unit.id:
        if unit.owner == player and unit.hp > 0 and
            world.renderUnitVisible(viewMode, unit):
          result.addBattleSound BattleSound(cue: ReadySound, global: true)
        continue
      let previous = state.units[unitSlot]
      if unit.kind == PeonUnit and unit.hp > 0 and
          unit.state == UnitInMine and unit.stateTicks > 0 and
          unit.workSoundBeat(previous, MineTicks, TickRate, MineSoundLeadTicks):
        let index = world.buildingIndex(unit.sourceId)
        if index >= 0:
          let mine = world.buildings[index]
          if mine.kind == GoldMineBuilding and mine.hp > 0 and
              mine.state == BuildingComplete and mine.goldLeft > 0 and
              world.miningVisible(viewMode, unit, mine):
            result.addBattleSound BattleSound(cue: MineSound,
              position: mine.soundPosition(half))
      if not world.renderUnitVisible(viewMode, unit):
        continue
      let position = vec3(toFloat32(unit.body.pos.x) - half, 0,
        toFloat32(unit.body.pos.y) - half)
      if previous.hp > 0 and unit.hp <= 0:
        result.addBattleSound BattleSound(
          cue: deathSound(unit.kind), position: position)
      elif unit.hp > 0:
        if unit.kind == PeonUnit:
          if unit.state == UnitChopping and
              unit.workSoundBeat(previous, ChopTicks, ChopSoundTicks,
                ChopSoundLeadTicks) and
              world.map.inGrid(unit.targetTile) and
              world.treeWood[world.map.tileIndex(unit.targetTile)] > 0:
            result.addBattleSound BattleSound(cue: ChopSound, position: position)
          if previous.state in {UnitDepositGold, UnitDepositWood} and
              previous.stateTicks == 0:
            if previous.carryGold > 0 and unit.carryGold == 0:
              result.addBattleSound BattleSound(
                cue: DeliverGoldSound, position: position)
            elif previous.carryWood > 0 and unit.carryWood == 0:
              result.addBattleSound BattleSound(
                cue: DeliverWoodSound, position: position)
        if unit.hp < previous.hp:
          result.addBattleSound BattleSound(cue: ImpactSound, position: position)
        if unit.state == UnitAttacking and unit.cooldown > previous.cooldown:
          result.addBattleSound BattleSound(
            cue: attackSound(unit.kind), position: position)
        if unit.healCooldown > previous.healCooldown:
          result.addBattleSound BattleSound(cue: HealSound, position: position)
    var buildingSlot = 0
    for building in world.buildings:
      while buildingSlot < state.buildingCount and
          state.buildings[buildingSlot].id < building.id:
        inc buildingSlot
      if not world.renderBuildingVisible(viewMode, building):
        continue
      let position = building.soundPosition(half)
      if buildingSlot == state.buildingCount or
          state.buildings[buildingSlot].id != building.id:
        if building.hp > 0 and building.state == BuildingUnderConstruction:
          result.addBattleSound BattleSound(
            cue: (if building.buildTotal > 0 and
                building.buildTicks < building.buildTotal: BuildStartSound
              else: BuildPlaceSound),
            position: position)
        continue
      let
        previous = state.buildings[buildingSlot]
      if previous.hp > 0 and building.hp <= 0:
        result.addBattleSound BattleSound(
          cue: BuildingDeathSound, position: position)
      elif building.hp > 0:
        if previous.state == BuildingUnderConstruction and
            previous.buildTotal > 0 and
            previous.buildTicks == previous.buildTotal and
            building.buildTicks < building.buildTotal:
          result.addBattleSound BattleSound(
            cue: BuildStartSound, position: position)
        if building.hp < previous.hp:
          result.addBattleSound BattleSound(
            cue: BuildingHitSound, position: position)
        if building.cooldown > previous.cooldown:
          result.addBattleSound BattleSound(cue: FireSound, position: position)
        if building.owner == player and
            previous.state == BuildingUnderConstruction and
            building.state == BuildingComplete:
          result.addBattleSound BattleSound(cue: ReadySound, global: true)
    if world.over and not state.over:
      let cue =
        if world.winner < 0: ReadySound
        elif player < 0 or player == world.winner: VictorySound
        else: DefeatSound
      result.addBattleSound BattleSound(cue: cue, global: true)
  state.world = world
  state.tick = world.tick
  state.over = world.over
  state.unitCount = 0
  state.buildingCount = 0
  for unit in world.units:
    if unit.hp <= 0:
      continue
    if state.unitCount == state.units.len:
      raise newException(LvdError,
        "Unit audio capacity exceeded; prepare custom match capacity first")
    state.units[state.unitCount] = UnitSoundState(id: unit.id, hp: unit.hp,
      cooldown: unit.cooldown, healCooldown: unit.healCooldown,
      state: unit.state, stateTicks: unit.stateTicks,
      carryGold: unit.carryGold, carryWood: unit.carryWood)
    inc state.unitCount
  for building in world.buildings:
    if building.hp <= 0 or building.state == BuildingDying:
      continue
    if state.buildingCount == state.buildings.len:
      raise newException(LvdError,
        "Building audio capacity exceeded; prepare custom match capacity first")
    state.buildings[state.buildingCount] = BuildingSoundState(
      id: building.id, hp: building.hp,
      cooldown: building.cooldown, state: building.state,
      buildTicks: building.buildTicks, buildTotal: building.buildTotal)
    inc state.buildingCount
