## Presentation-only sound events derived from consecutive world snapshots.

import
  std/tables,
  polyworld/[daycycles, soundassets],
  content, sim

const MaxArenaSounds* = 66
  ## The existing 64-event world limit plus preparation and result notices.

type
  ArenaAudioError* = object of CatchableError
  ArenaSound* = object
    cue*: SoundCue
    position*: WorldPoint
    spatial*: bool
  ArenaSounds* = object
    len*: int
    events: array[MaxArenaSounds, ArenaSound]
  ArenaAudio* = object
    world: World
    ready: bool
    tick: int32
    hp: Table[int32, int32]
    snapshotCapacity: int
    gameOver, preparing, night: bool

iterator items*(sounds: ArenaSounds): ArenaSound =
  ## Iterates only populated entries in the fixed event buffer.
  for i in 0 ..< sounds.len:
    yield sounds.events[i]

proc `[]`*(sounds: ArenaSounds, index: int): ArenaSound {.inline.} =
  ## Reads one populated event without allocating a sequence.
  doAssert index >= 0 and index < sounds.len
  sounds.events[index]

proc add(sounds: var ArenaSounds, event: ArenaSound) {.inline.} =
  ## Appends within the fixed world and notification event budget.
  doAssert sounds.len < sounds.events.len
  sounds.events[sounds.len] = event
  inc sounds.len

proc prepareAudio*(
    audio: var ArenaAudio, world: World, footmanCapacity = 0
) =
  ## Reserves the match's maximum snapshot before entering playback.
  doAssert footmanCapacity >= 0
  var campMembers = 0
  for camp in world.camps:
    campMembers += camp.count
  let capacity = world.heroes.len + world.buildings.len + world.forts.len +
    max(max(world.footmen.len, UnitCap + campMembers), footmanCapacity)
  if audio.snapshotCapacity < capacity:
    audio.hp = initTable[int32, int32](capacity)
    audio.snapshotCapacity = capacity
  audio.ready = false

proc syncAudio*(audio: var ArenaAudio, world: World) =
  ## Establishes a silent baseline after loading, seeking, or fast forwarding.
  if audio.snapshotCapacity == 0 or audio.world != world:
    audio.prepareAudio(world)
  let count = world.heroes.len + world.footmen.len + world.buildings.len +
    world.forts.len
  if count > audio.snapshotCapacity:
    raise newException(ArenaAudioError,
      "Arena audio snapshot exceeds its prepared match capacity")
  audio.world = world
  audio.ready = true
  audio.tick = world.tick
  audio.gameOver = world.gameOver
  audio.preparing = world.preparationTicksLeft() > 0
  audio.night = isNight(clockHour(world.battleTick(), TickRate))
  audio.hp.clear()
  for hero in world.heroes:
    audio.hp[hero.id] = hero.hp
  for unit in world.footmen:
    audio.hp[unit.id] = unit.hp
  for building in world.buildings:
    audio.hp[building.id] = building.hp
  for fort in world.forts:
    audio.hp[fort.id] = fort.hp

proc spellSound*(ability: Ability): SoundCue =
  ## Selects an elemental or restorative cue for the spell's actual theme.
  if ability.abilitySpec.kind in {Heal, Restore}:
    return HealSound
  case ability
  of FirebrandSword, InfernoAegis, BlazingBlade, MeteorStrike,
      ArcaneMeteor, MoltenFist, VolcanicEruption:
    FireSound
  else:
    MagicSound

proc collectSounds*(
    audio: var ArenaAudio,
    world: World,
    viewMode: int32,
    enabled = true,
    playerTeam = -1
): ArenaSounds =
  ## Emits fresh visible events once; skipped ticks never replay an audio burst.
  if audio.ready and audio.world == world and world.tick == audio.tick:
    return
  if not audio.ready or audio.world != world or not enabled or
      world.tick != audio.tick + 1:
    audio.syncAudio(world)
    return

  let night = isNight(clockHour(world.battleTick(), TickRate))
  if night != audio.night:
    result.add ArenaSound(
      cue: if night: NightfallSound else: DaybreakSound
    )

  template emit(cueValue: SoundCue, point: WorldPoint) =
    if result.len < 64 and (viewMode == 0 or
        world.visible(Team(viewMode - 1), point)):
      result.add ArenaSound(cue: cueValue, position: point, spatial: true)

  template changedHealth(id, current: int32, point: WorldPoint,
      deathCue, hitCue: SoundCue, deaths: bool) =
    let previous = audio.hp.getOrDefault(id, current)
    if previous > 0 and current <= 0:
      if deaths:
        emit(deathCue, point)
    elif not deaths and current > 0 and current < previous:
      emit(hitCue, point)

  # Deaths precede routine hits so busy fights retain their most useful cues.
  for deaths in [true, false]:
    for hero in world.heroes:
      changedHealth(hero.id, hero.hp, hero.position,
        HumanDeathSound, ImpactSound, deaths)
    for unit in world.footmen:
      changedHealth(unit.id, unit.hp, unit.position,
        (if unit.camp > 0: CreatureDeathSound else: HumanDeathSound),
        ImpactSound, deaths)
    for building in world.buildings:
      changedHealth(building.id, building.hp, building.position,
        BuildingDeathSound, BuildingHitSound, deaths)
    for fort in world.forts:
      changedHealth(fort.id, fort.hp, fort.center,
        BuildingDeathSound, BuildingHitSound, deaths)

  for spell in world.casts:
    if spell.started == world.tick:
      emit(spell.ability.spellSound, spell.origin)
  for use in world.itemUses:
    let cue =
      if use.item == PoisonPotion: MagicSound
      elif use.item == PortalScroll: MagicSound
      else: HealSound
    emit(cue, use.position)
  for hit in world.attackEffects:
    # A visible impact must not expose a hidden attacker by its weapon sound.
    if viewMode != 0 and
        not world.visible(Team(viewMode - 1), hit.origin):
      continue
    let cue =
      case hit.style
      of MeleeAttack: SwordSound
      of RangedAttack: BowSound
      of MagicAttack: MagicSound
    if viewMode == 0 or world.visible(Team(viewMode - 1), hit.position):
      emit(cue, hit.origin)
  for shot in world.towerShots:
    if shot.started == world.tick:
      emit(MagicSound, shot.previous)
  if audio.preparing and world.preparationTicksLeft() == 0:
    result.add ArenaSound(cue: ReadySound)
  if world.gameOver and not audio.gameOver:
    let cue =
      if world.draw: ReadySound
      elif playerTeam >= 0 and playerTeam != world.winner.ord: DefeatSound
      else: VictorySound
    result.add ArenaSound(cue: cue)
  audio.syncAudio(world)
