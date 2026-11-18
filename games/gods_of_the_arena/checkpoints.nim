## Gods of the Arena checkpoint save and restore (game world + Bassy VM state).

import
  std/[base64, json, os, sets, strformat, strutils, tables, uri],
  jsony,
  bassy, fixxy,
  polyworld/[bodies, mailboxes, metrics, pathing, rngs],
  content, events, maps, motions, presets, replays, sim, structures

type
  VmScalarSnapshot* = object
    kind*: string
    intVal*: int32
    strVal*: string

  VmArraySnapshot* = object
    kind*: string
    intVals*: seq[int32]
    fixedIndices*: seq[int]
    strVals*: seq[string]

  HeroVmSnapshot* = object
    schema*: string
    sourceSha256*: string
    forceRestore*: bool
    failed*: bool
    lastError*: string
    decisions*: int
    savedSlots*: OrderedTable[string, int32]
    savedStates*: OrderedTable[string, int32]
    savedTexts*: OrderedTable[string, string]
    persistedNames*: seq[string]
    globals*: OrderedTable[string, VmScalarSnapshot]
    arrays*: OrderedTable[string, VmArraySnapshot]

  HeroSnapshot* = object
    id*: int32
    team*: Team
    slot*: int
    lane*: int
    class*: HeroClass
    drafted*: bool
    position*: WorldPoint
    spawnPosition*: WorldPoint
    facing*: Heading
    velocity*: Heading
    body*: Body
    hp*: int32
    maxHp*: int32
    mana*: int32
    maxMana*: int32
    level*: int
    xp*: int
    totalXp*: int
    creepXpRemainder*: int
    gold*: int
    deaths*: int32
    state*: FootmanState
    waypointIndex*: int
    targetFootmanId*: int32
    targetHeroId*: int32
    targetBuildingId*: int32
    attackingFort*: bool
    swingClip*: int
    swingTicks*: int32
    damageLanded*: bool
    attacksLanded*: int32
    animClip*: int
    animTicks*: int32
    deathTicks*: int32
    surfaceHint*: int32
    navLayer*: int32
    attackObjectId*: int32
    attackMoving*: bool
    movePath*: seq[WorldPoint]
    movePathLayers*: seq[int32]
    movePathIndex*: int
    moveTileX*: int
    moveTileY*: int
    moveOffset*: FixedVec2
    hasMoveTarget*: bool
    moveRevision*: int32
    stuckTicks*: int32
    inventory*: array[InventorySlots, Item]
    itemCounts*: array[InventorySlots, int32]
    abilityLevels*: array[HeroAbilitySlot, int32]
    cooldowns*: array[HeroAbilitySlot, int32]
    charges*: array[HeroAbilitySlot, int32]
    recharges*: array[HeroAbilitySlot, int32]
    spellsReady*: bool
    potionCooldownEnds*: array[RecoveryKind, int32]
    recoveryItems*: array[RecoveryKind, Item]
    recoveryStarted*, recoveryApplied*: array[RecoveryKind, int32]
    portalEnds*, portalCooldownEnds*, portalTowerId*: int32
    portalDestination*: WorldPoint
    controls*: array[ControlEffect, ControlTimer]
    lastActionError*: ActionError

  CombatStatsSnapshot* = object
    values*: seq[MetricValues]
    teams*: seq[int]
    hits*: seq[int32]

  MailboxSnapshot* = object
    ids*: seq[int32]
    messages*: seq[string]
    first*, count*: int
    lastId*: int32

  WorldSnapshot* = object
    heroSpawns*: array[2, WorldPoint]
    casts*: seq[SpellCast]
    towerShots*: seq[TowerShot]
    stats*: CombatStatsSnapshot
    footmen*: seq[Footman]
    camps*: seq[Camp]
    heroes*: seq[HeroSnapshot]
    forts*: array[2, Fort]
    buildings*: seq[Building]
    occupancy*: seq[seq[int16]]
    navigationRevision*: int32
    spawnIntervalTicks*: int32
    spawnTimerTicks*: int32
    gameOver*: bool
    draw*: bool
    winner*: Team
    rng*: Rng
    matchSeed*: int32
    nextFootmanId*: int32
    tick*: int32
    phase*: MatchPhase
    draftMode*: DraftMode
    drafting*: bool
    draftOrder*: seq[int]
    draftTurn*: int
    draftTicks*: int32
    draftTurnTicks*: int32
    heroTurnTicks*: int32
    heroTurnStart*: int
    teamHeroKills*: array[2, int]
    teamHeroDeaths*: array[2, int]
    teamVisible*: array[2, seq[uint8]]
    teamExplored*: array[2, seq[uint8]]

  GameSnapshot* = object
    schema*: string
    world*: WorldSnapshot
    inboxes*: seq[MailboxSnapshot]
    history*: MetricHistory
    replayBase64*: string

  CheckpointSchedule* = object
    enabled*: bool
    snapshotDir*: string
    everyTicks*: int32
    explicitTicks*: HashSet[int32]

proc dumpHook*(s: var string, v: Fixed) =
  s.add $int32(v)

proc parseHook*(s: string, i: var int, v: var Fixed) =
  var raw: int32
  parseHook(s, i, raw)
  v = Fixed(raw)

proc saveHeroVm*(vm: HeroVm): string =
  ## Serializes one seat's Bassy VM globals and mutable DIM arrays by symbol name.
  var savedSlots = initOrderedTable[string, int32]()
  if vm != nil:
    for k, v in vm.savedSlots:
      savedSlots[$k] = v
  var snap = HeroVmSnapshot(
    schema: "bassy-vm-state/1",
    sourceSha256: (if vm != nil: vm.sourceSha256 else: ""),
    forceRestore: false,
    failed: vm != nil and vm.failed,
    lastError: (if vm != nil: vm.lastError else: ""),
    decisions: (if vm != nil: vm.decisions else: 0),
    savedSlots: savedSlots,
    savedStates: (if vm != nil: vm.savedStates else: initOrderedTable[string, int32]()),
    savedTexts: (if vm != nil: vm.savedTexts else: initOrderedTable[string, string]()),
    persistedNames: (if vm != nil: vm.persistedNames else: @[]),
    globals: initOrderedTable[string, VmScalarSnapshot](),
    arrays: initOrderedTable[string, VmArraySnapshot]()
  )
  if vm != nil and vm.runtime != nil:
    for name in vm.globalNames:
      let val = vm.runtime.getGlobalValue(name)
      case val.kind
      of IntegerValue:
        snap.globals[name] = VmScalarSnapshot(kind: "int", intVal: val.asInt)
      of FixedValue:
        snap.globals[name] = VmScalarSnapshot(kind: "fixed", intVal: int32(val.asFixed))
      of StringValue:
        snap.globals[name] = VmScalarSnapshot(kind: "str", strVal: vm.runtime.getStringGlobal(name))
      else:
        discard
    for name in vm.arrayNames:
      let length = int(vm.runtime.arrayLength(name))
      if name.endsWith("$"):
        var vals = newSeq[string](length)
        for idx in 0 ..< length:
          vals[idx] = vm.runtime.getStringArray(name, int32(idx))
        snap.arrays[name] = VmArraySnapshot(kind: "str", strVals: vals)
      else:
        var
          vals = newSeq[int32](length)
          fixedIndices: seq[int]
        for idx in 0 ..< length:
          let item = vm.runtime.getArrayValue(name, int32(idx))
          if item.kind == FixedValue:
            fixedIndices.add(idx)
            vals[idx] = int32(item.asFixed)
          else:
            vals[idx] = item.asInt
        snap.arrays[name] = VmArraySnapshot(
          kind: (if fixedIndices.len > 0: "mixed" else: "int"),
          intVals: vals,
          fixedIndices: fixedIndices
        )
  snap.toJson()

proc restoreHeroSymbol(vm: HeroVm, snap: HeroVmSnapshot, name: string): bool =
  let key = name.toLowerAscii()
  if key in snap.globals and key in vm.globalNames:
    let entry = snap.globals[key]
    try:
      case entry.kind
      of "str":
        vm.runtime.setGlobal(key, entry.strVal)
      of "fixed":
        vm.runtime.setGlobal(key, toValue(Fixed(entry.intVal)))
      else:
        vm.runtime.setGlobal(key, toValue(entry.intVal))
      return true
    except BasicError:
      return false
  if key in snap.arrays and key in vm.arrayNames:
    let arrSnap = snap.arrays[key]
    let length = int(vm.runtime.arrayLength(key))
    try:
      if arrSnap.kind == "str":
        for idx in 0 ..< min(length, arrSnap.strVals.len):
          vm.runtime.setArray(key, int32(idx), arrSnap.strVals[idx])
      else:
        let fixedSet = toHashSet(arrSnap.fixedIndices)
        for idx in 0 ..< min(length, arrSnap.intVals.len):
          if arrSnap.kind == "fixed" or idx in fixedSet:
            vm.runtime.setArray(key, int32(idx), toValue(Fixed(arrSnap.intVals[idx])))
          else:
            vm.runtime.setArray(key, int32(idx), toValue(arrSnap.intVals[idx]))
      return true
    except BasicError:
      return false
  false

proc loadHeroVm*(vm: HeroVm, jsonBytes: string) =
  ## Restores matching globals and mutable DIM arrays by symbol name into ``vm``.
  if vm == nil or vm.runtime == nil or jsonBytes.strip().len == 0:
    return
  let snap = jsonBytes.fromJson(HeroVmSnapshot)
  vm.restoredFromCheckpoint = true
  vm.decisions = snap.decisions
  vm.savedSlots.clear()
  for k, v in snap.savedSlots:
    try:
      vm.savedSlots[int32(parseInt(k))] = v
    except ValueError:
      discard
  vm.savedStates = snap.savedStates
  vm.savedTexts = snap.savedTexts
  var loadedPersisted = initHashSet[string]()
  vm.persistLoader = proc(name: string): bool =
    let key = name.toLowerAscii()
    if key in loadedPersisted:
      return true
    loadedPersisted.incl(key)
    restoreHeroSymbol(vm, snap, key)
  if snap.sourceSha256.len > 0 and snap.sourceSha256 != vm.sourceSha256 and not snap.forceRestore:
    return
  vm.runtime.restart()
  vm.failed = snap.failed
  vm.lastError = snap.lastError
  vm.persistedNames = snap.persistedNames
  for name, _ in snap.globals:
    discard restoreHeroSymbol(vm, snap, name)
  for name, _ in snap.arrays:
    discard restoreHeroSymbol(vm, snap, name)

proc toHeroSnapshot(hero: Hero): HeroSnapshot =
  for name, field in result.fieldPairs:
    when compiles(getattr(hero, name)):
      discard
  result.id = hero.id
  result.team = hero.team
  result.slot = hero.slot
  result.lane = hero.lane
  result.class = hero.class
  result.drafted = hero.drafted
  result.position = hero.position
  result.spawnPosition = hero.spawnPosition
  result.facing = hero.facing
  result.velocity = hero.velocity
  result.body = hero.body
  result.hp = hero.hp
  result.maxHp = hero.maxHp
  result.mana = hero.mana
  result.maxMana = hero.maxMana
  result.level = hero.level
  result.xp = hero.xp
  result.totalXp = hero.totalXp
  result.creepXpRemainder = hero.creepXpRemainder
  result.gold = hero.gold
  result.deaths = hero.deaths
  result.state = hero.state
  result.waypointIndex = hero.waypointIndex
  result.targetFootmanId = hero.targetFootmanId
  result.targetHeroId = hero.targetHeroId
  result.targetBuildingId = hero.targetBuildingId
  result.attackingFort = hero.attackingFort
  result.swingClip = hero.swingClip
  result.swingTicks = hero.swingTicks
  result.damageLanded = hero.damageLanded
  result.attacksLanded = hero.attacksLanded
  result.animClip = hero.animClip
  result.animTicks = hero.animTicks
  result.deathTicks = hero.deathTicks
  result.surfaceHint = hero.surfaceHint
  result.navLayer = hero.navLayer
  result.attackObjectId = hero.attackObjectId
  result.attackMoving = hero.attackMoving
  result.movePath = hero.movePath
  result.movePathLayers = hero.movePathLayers
  result.movePathIndex = hero.movePathIndex
  result.moveTileX = hero.moveTileX
  result.moveTileY = hero.moveTileY
  result.moveOffset = hero.moveOffset
  result.hasMoveTarget = hero.hasMoveTarget
  result.moveRevision = hero.moveRevision
  result.stuckTicks = hero.stuckTicks
  result.inventory = hero.inventory
  result.itemCounts = hero.itemCounts
  result.abilityLevels = hero.abilityLevels
  result.cooldowns = hero.cooldowns
  result.charges = hero.charges
  result.recharges = hero.recharges
  result.spellsReady = hero.spellsReady
  result.potionCooldownEnds = hero.potionCooldownEnds
  result.recoveryItems = hero.recoveryItems
  result.recoveryStarted = hero.recoveryStarted
  result.recoveryApplied = hero.recoveryApplied
  result.portalEnds = hero.portalEnds
  result.portalCooldownEnds = hero.portalCooldownEnds
  result.portalTowerId = hero.portalTowerId
  result.portalDestination = hero.portalDestination
  result.controls = hero.controls
  result.lastActionError = hero.lastActionError

proc fromHeroSnapshot(snap: HeroSnapshot): Hero =
  result = Hero()
  result.id = snap.id
  result.team = snap.team
  result.slot = snap.slot
  result.lane = snap.lane
  result.class = snap.class
  result.drafted = snap.drafted
  result.position = snap.position
  result.spawnPosition = snap.spawnPosition
  result.facing = snap.facing
  result.velocity = snap.velocity
  result.body = snap.body
  result.hp = snap.hp
  result.maxHp = snap.maxHp
  result.mana = snap.mana
  result.maxMana = snap.maxMana
  result.level = snap.level
  result.xp = snap.xp
  result.totalXp = snap.totalXp
  result.creepXpRemainder = snap.creepXpRemainder
  result.gold = snap.gold
  result.deaths = snap.deaths
  result.state = snap.state
  result.waypointIndex = snap.waypointIndex
  result.targetFootmanId = snap.targetFootmanId
  result.targetHeroId = snap.targetHeroId
  result.targetBuildingId = snap.targetBuildingId
  result.attackingFort = snap.attackingFort
  result.swingClip = snap.swingClip
  result.swingTicks = snap.swingTicks
  result.damageLanded = snap.damageLanded
  result.attacksLanded = snap.attacksLanded
  result.animClip = snap.animClip
  result.animTicks = snap.animTicks
  result.deathTicks = snap.deathTicks
  result.surfaceHint = snap.surfaceHint
  result.navLayer = snap.navLayer
  result.attackObjectId = snap.attackObjectId
  result.attackMoving = snap.attackMoving
  result.movePath = snap.movePath
  result.movePathLayers = snap.movePathLayers
  result.movePathIndex = snap.movePathIndex
  result.moveTileX = snap.moveTileX
  result.moveTileY = snap.moveTileY
  result.moveOffset = snap.moveOffset
  result.hasMoveTarget = snap.hasMoveTarget
  result.moveRevision = snap.moveRevision
  result.stuckTicks = snap.stuckTicks
  result.inventory = snap.inventory
  result.itemCounts = snap.itemCounts
  result.abilityLevels = snap.abilityLevels
  result.cooldowns = snap.cooldowns
  result.charges = snap.charges
  result.recharges = snap.recharges
  result.spellsReady = snap.spellsReady
  result.potionCooldownEnds = snap.potionCooldownEnds
  result.recoveryItems = snap.recoveryItems
  result.recoveryStarted = snap.recoveryStarted
  result.recoveryApplied = snap.recoveryApplied
  result.portalEnds = snap.portalEnds
  result.portalCooldownEnds = snap.portalCooldownEnds
  result.portalTowerId = snap.portalTowerId
  result.portalDestination = snap.portalDestination
  result.controls = snap.controls
  result.lastActionError = snap.lastActionError

proc saveGameSnapshot*(game: Game): string =
  let w = game.world
  var heroes = newSeq[HeroSnapshot](w.heroes.len)
  for i, h in w.heroes:
    heroes[i] = toHeroSnapshot(h)
  var inboxes = newSeq[MailboxSnapshot](game.inboxes.len)
  for i, mb in game.inboxes:
    if mb != nil:
      inboxes[i] = MailboxSnapshot(
        ids: @(mb.ids),
        messages: @(mb.messages),
        first: mb.first,
        count: mb.count,
        lastId: mb.lastId
      )
  let snap = GameSnapshot(
    schema: "gota-game-snapshot/1",
    world: WorldSnapshot(
      heroSpawns: w.heroSpawns,
      casts: w.casts,
      towerShots: w.towerShots,
      stats: CombatStatsSnapshot(
        values: w.stats.values,
        teams: w.stats.teams,
        hits: w.stats.hits
      ),
      footmen: w.footmen,
      camps: w.camps,
      heroes: heroes,
      forts: w.forts,
      buildings: w.buildings,
      occupancy: w.occupancy,
      navigationRevision: w.navigationRevision,
      spawnIntervalTicks: w.spawnIntervalTicks,
      spawnTimerTicks: w.spawnTimerTicks,
      gameOver: w.gameOver,
      draw: w.draw,
      winner: w.winner,
      rng: w.rng,
      matchSeed: w.matchSeed,
      nextFootmanId: w.nextFootmanId,
      tick: w.tick,
      phase: w.phase,
      draftMode: w.draftMode,
      drafting: w.drafting,
      draftOrder: w.draftOrder,
      draftTurn: w.draftTurn,
      draftTicks: w.draftTicks,
      draftTurnTicks: w.draftTurnTicks,
      heroTurnTicks: w.heroTurnTicks,
      heroTurnStart: w.heroTurnStart,
      teamHeroKills: w.teamHeroKills,
      teamHeroDeaths: w.teamHeroDeaths,
      teamVisible: w.teamVisible,
      teamExplored: w.teamExplored
    ),
    inboxes: inboxes,
    history: game.history,
    replayBase64: (if game.recorder != nil: base64.encode(encodeReplay(game.recorder.data)) else: "")
  )
  snap.toJson()

proc mergePatch(target: JsonNode, patch: JsonNode): JsonNode =
  ## Applies RFC 7396 JSON Merge Patch.
  if patch.kind != JObject:
    return patch
  result = if target.kind == JObject: target.copy() else: newJObject()
  for key, value in patch:
    if value.kind == JNull:
      result.delete(key)
    elif result.hasKey(key):
      result[key] = mergePatch(result[key], value)
    else:
      result[key] = mergePatch(newJObject(), value)

proc loadGameSnapshot*(game: Game, jsonBytes: string, patchJson = "") =
  let payload =
    if patchJson.strip().len > 0:
      $mergePatch(parseJson(jsonBytes), parseJson(patchJson))
    else:
      jsonBytes
  let snap = payload.fromJson(GameSnapshot)
  let ws = snap.world
  var restored = game.world.clone()
  restored.heroSpawns = ws.heroSpawns
  restored.casts = ws.casts
  restored.towerShots = ws.towerShots
  restored.stats = CombatStats(
    values: ws.stats.values,
    teams: ws.stats.teams,
    hits: ws.stats.hits
  )
  restored.footmen = ws.footmen
  restored.camps = ws.camps
  restored.heroes = newSeq[Hero](ws.heroes.len)
  for i, hs in ws.heroes:
    restored.heroes[i] = fromHeroSnapshot(hs)
  restored.forts = ws.forts
  restored.buildings = ws.buildings
  restored.occupancy = ws.occupancy
  restored.navigationRevision = ws.navigationRevision
  restored.spawnIntervalTicks = ws.spawnIntervalTicks
  restored.spawnTimerTicks = ws.spawnTimerTicks
  restored.gameOver = ws.gameOver
  restored.draw = ws.draw
  restored.winner = ws.winner
  restored.rng = ws.rng
  restored.matchSeed = ws.matchSeed
  restored.nextFootmanId = ws.nextFootmanId
  restored.tick = ws.tick
  restored.phase = ws.phase
  restored.draftMode = ws.draftMode
  restored.drafting = ws.drafting
  restored.draftOrder = ws.draftOrder
  restored.draftTurn = ws.draftTurn
  restored.draftTicks = ws.draftTicks
  restored.draftTurnTicks = ws.draftTurnTicks
  restored.heroTurnTicks = ws.heroTurnTicks
  restored.heroTurnStart = ws.heroTurnStart
  restored.teamHeroKills = ws.teamHeroKills
  restored.teamHeroDeaths = ws.teamHeroDeaths
  restored.teamVisible = ws.teamVisible
  restored.teamExplored = ws.teamExplored
  game.world.restore(restored)
  game.history = snap.history
  for i in 0 ..< min(game.inboxes.len, snap.inboxes.len):
    let mb = game.inboxes[i]
    let ms = snap.inboxes[i]
    if mb != nil:
      for j in 0 ..< min(MaxMailboxMessages, ms.ids.len):
        mb.ids[j] = ms.ids[j]
      for j in 0 ..< min(MaxMailboxMessages, ms.messages.len):
        mb.messages[j] = ms.messages[j]
      mb.first = ms.first
      mb.count = ms.count
      mb.lastId = ms.lastId
  if snap.replayBase64.len > 0 and game.recorder != nil:
    let decoded = decodeReplay(base64.decode(snap.replayBase64))
    game.recorder.data.actions = decoded.actions
    game.recorder.data.hashes = decoded.hashes
    game.recorder.data.metrics = decoded.metrics

proc resolveLocalUri(uriOrPath: string): string =
  if uriOrPath.startsWith("file://"):
    let parsed = parseUri(uriOrPath)
    decodeUrl(parsed.path, decodePlus = false)
  else:
    uriOrPath

proc parseCheckpointSchedule*(): CheckpointSchedule =
  let raw = getEnv("COGAME_CHECKPOINT_TICKS").strip()
  let dir = getEnv("COGAME_SNAPSHOT_DIR", "/workspace/snapshots").strip()
  if raw.len == 0 or dir.len == 0:
    return CheckpointSchedule(enabled: false)
  result.enabled = true
  result.snapshotDir = resolveLocalUri(dir)
  if raw.startsWith("every:"):
    result.everyTicks = int32(parseInt(raw["every:".len .. ^1]))
  else:
    for part in raw.split(','):
      let trimmed = part.strip()
      if trimmed.len > 0:
        result.explicitTicks.incl(int32(parseInt(trimmed)))

proc shouldSave*(schedule: CheckpointSchedule, tick: int32): bool =
  if not schedule.enabled or tick <= 0:
    return false
  if schedule.everyTicks > 0 and (tick mod schedule.everyTicks) == 0:
    return true
  tick in schedule.explicitTicks

proc writeFileAtomic(path, contents: string) =
  createDir(path.parentDir)
  let tmp = path & ".tmp"
  writeFile(tmp, contents)
  moveFile(tmp, path)

proc writeCheckpoint*(game: Game, schedule: CheckpointSchedule) =
  let tick = game.world.tick
  let tickDir = schedule.snapshotDir / &"tick_{tick:06d}"
  let seatsDir = tickDir / "seats"
  createDir(seatsDir)
  writeFileAtomic(tickDir / "game.snapshot", saveGameSnapshot(game))
  for slot, vm in game.heroVms:
    writeFileAtomic(seatsDir / &"seat_{slot}.snapshot", saveHeroVm(vm))
  let manifest = %*{
    "schema": "coworld-game-checkpoint/1",
    "tick": tick,
    "format": "gota-json/1"
  }
  writeFileAtomic(tickDir / "manifest.json", $manifest)

proc restoreCheckpointIfRequested*(game: Game) =
  let loadUri = getEnv("COGAME_LOAD_SNAPSHOT_URI").strip()
  if loadUri.len == 0:
    return
  let resolved = resolveLocalUri(loadUri)
  let
    restoreDir = if dirExists(resolved): resolved else: resolved.parentDir
    gameSnapPath = if dirExists(resolved): resolved / "game.snapshot" else: resolved
    patchPath = restoreDir / "game_patch.json"
    patchJson = if fileExists(patchPath): readFile(patchPath) else: ""
  loadGameSnapshot(game, readFile(gameSnapPath), patchJson)
  let reseedRaw = getEnv("COGAME_RESEED").strip()
  if reseedRaw.len > 0:
    let reseed = int32(parseInt(reseedRaw))
    game.world.rng = initRng(reseed)
  let seatsDir = restoreDir / "seats"
  if dirExists(seatsDir):
    for slot in 0 ..< game.heroVms.len:
      let seatPath = seatsDir / &"seat_{slot}.snapshot"
      if fileExists(seatPath):
        loadHeroVm(game.heroVms[slot], readFile(seatPath))
