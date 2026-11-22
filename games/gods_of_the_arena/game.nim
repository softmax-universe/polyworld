## Gods of the Arena match setup, command line, and the headless runner.
##
## Owns the one live match and decides where each tick's hero commands
## come from: ten BASIC programs, or the recorded action stream when
## replaying.

import
  std/[math, os, strformat, strutils, times],
  polyworld/[cli, controllers, metrics, profiles, tapes, timings],
  content,
  maps,
  sim,
  bots,
  controls,
  replays, matchnotices

when defined(coworld):
  import polyworld/coworld

const SupportedFlags =
  when defined(headless):
    AllCommonFlags - GraphicalFlags - {NameFlag, ServerFlag, RoomFlag}
  else:
    AllCommonFlags - {HeadlessTickRateFlag, LlmModeFlag}

var
  matchConfig* = GotaConfig(seed: ArenaSeed)
  serverAddress*: string
  playerNameOverride*: string
  localPlayerName*: string

proc usage() =
  ## Prints the command-line and compile-time configuration surface.
  echo "Gods of the Arena"
  echo commonUsageFor(SupportedFlags)
  echo "Live matches use ten slots; a human takes one slot, leaving nine bots."
  echo "The duration covers battle time (default 1200 seconds)."
  echo "Drafting allows 10 seconds per pick, separate from battle time."
  echo "Draft deadlines always advance; --play=false pauses after the draft."
  echo "The match seed controls draft order, bots, and combat; the arena stays fixed."
  echo "  --map-seed NUMBER       Regenerate the arena from another seed (the"
  echo "                          league always plays the preset's own seed)."
  echo "  --draft-mode MODE       unique (default), team, or open."
  echo "  --config PATH           JSON match settings, including mapPreset."
  echo "  --spawn-interval NUMBER Seconds between waves."
  echo "Compile with -d:headless for command-line simulation."
  echo "Compile with -d:emscripten for the web backend."

proc parseGameOptions*(
    arguments: seq[string], validateMatch = false
): GameOptions =
  ## Parses runtime game, bot, replay, and simulation configuration.
  var index = 0
  while index < arguments.len:
    if arguments[index] == "--config":
      matchConfig = loadConfig(arguments.argumentValue(index, "--config"))
    inc index
  result = GameOptions(
    seed: matchConfig.seed,
    seconds: matchConfig.maxTicks div TickRate,
    maximumTicks: matchConfig.maxTicks,
    spawnIntervalTicks: matchConfig.spawnIntervalTicks,
    playerSlot: matchConfig.playerSlot,
    headlessTickRate: matchConfig.headlessTickRate,
    waitForLlm: matchConfig.waitForLlm,
    speed: 1
  )
  index = 0
  while index < arguments.len:
    let argument = arguments[index]
    if result.takeCommonFlag(arguments, index, argument):
      discard
    else:
      case argument
      of "--config":
        discard arguments.argumentValue(index, "--config")
      of "--draft-mode":
        matchConfig.draftMode = parseDraftMode(
          arguments.argumentValue(index, "--draft-mode")
        )
      of "--map-seed":
        matchConfig.mapPreset.seed = parseInt32(
          arguments.argumentValue(index, "--map-seed"),
          "--map-seed"
        )
      of "--spawn-interval":
        var seconds: float64
        try:
          seconds = parseFloat(
            arguments.argumentValue(index, "--spawn-interval")
          )
        except ValueError:
          fail("--spawn-interval must be a number")
        if seconds <= 0:
          fail("--spawn-interval must be positive")
        if seconds > int32.high.float64 / TickRate.float64:
          fail("--spawn-interval is too large")
        result.spawnIntervalTicks = int32(round(
          seconds * TickRate.float64
        ))
        if result.spawnIntervalTicks <= 0:
          fail("--spawn-interval must be positive")
      of "--help", "-h":
        usage()
        quit(0)
      else:
        fail("unknown argument: " & argument)
    inc index
  result.rejectUnsupportedFlags(SupportedFlags)
  result.resolveGamePaths()
  serverAddress = result.serverUrl
  playerNameOverride = result.playerName
  if serverAddress.len > 0 or result.roomCode.len > 0:
    when defined(headless):
      fail("--server and --room require the graphical client")
    else:
      if result.botGroups.len > 0 or result.replayPath.len > 0 or
        result.playerSlot > 0:
          fail("--server and --room use lobby seats; " &
            "select players and bots in the lobby")
  result.validateGameOptions(
    if validateMatch or result.botGroups.len > 0 or result.playerSlot > 0:
      HeroClassCount
    else:
      0,
    "live games require exactly 10 slots"
  )

var
  options*: GameOptions
  run*: Game

proc initializeOptions*() =
  ## Parses startup arguments without constructing a match on import.
  when defined(coworld):
    options = coworldOptions(10)
    matchConfig = parseConfig(readLocal(getEnv("COGAME_CONFIG_URI")))
  else:
    options = parseGameOptions(commandLineParams(), defined(headless))
  if options.verbose:
    echo "GotA launch: seed=", options.seed,
      " bots=", options.botGroups.botCount,
      " player=", options.playerSlot,
      " replay=", options.replayPath

proc initializeMatch*() =
  ## Creates a fresh local or replay session from explicit startup settings.
  startGameProfile()
  var
    replayMode = options.replayPath.len > 0
    mapSeed = options.seed
    replayData: ReplayData
  if replayMode:
    profileBlock "replay":
      replayData = loadReplay(options.replayPath)
    mapSeed = replayData.config.seed
    options.maximumTicks = int32(replayData.hashes.len)
  var gameMap: MapData
  profileBlock "map":
    gameMap =
      if replayMode:
        generateMap(mapSeed, replayData.config.mapPreset)
      else:
        generateMap(mapSeed, matchConfig.mapPreset)
  run = newGame(
    gameMap,
    if replayMode:
      replayData.config.spawnIntervalTicks
    else:
      options.spawnIntervalTicks,
    if replayMode: 0 else: HeroClassCount,
    replayMode,
    replayData,
    draftMode = matchConfig.draftMode
  )
  if replayMode:
    run.replayPlayer = initReplayPlayer(replayData)
    run.historyPlayback = true
  else:
    loadBots(run, options.botGroups, options.playerSlot)
    run.recorder = initReplayRecorder(
      currentSetup(run, uint32(options.maximumTicks)), gameMap.preset
    )
    run.recorder.data.config =
      when defined(coworld):
        coworld.config.withMapPreset(gameMap.preset, matchConfig.draftMode)
      else:
        block:
          var config = localGameConfig(options, HeroClassCount)
          if matchConfig.players.len > 0:
            config.players = matchConfig.players
          if options.playerSlot > 0 and
            options.playerSlot.int <= config.players.len and
            localPlayerName.len > 0:
              config.players[options.playerSlot - 1].name = localPlayerName
          config.withMapPreset(gameMap.preset, matchConfig.draftMode)
    run.recorder.data.config.validateConfig(HeroClassCount)
    run.replayPlayer = ReplayPlayer(data: run.recorder.data)

proc advanceGame*() =
  ## Advances one tick, including live BASIC decisions.
  when defined(gotaTestRoom):
    run.prepareTestTick()
  tickWorld(run, proc() =
    when not defined(gotaTestRoom):
      let draftTurn = run.world.draftHeroId()
    flushPlayerCommands(run)
    when not defined(gotaTestRoom):
      if draftTurn == 0 or draftTurn == run.world.draftHeroId():
        runBotDecisions(run)
  )
  if not run.replayMode and not run.historyPlayback and run.matchNoticeDue():
    run.recorder.record(ReplayAction(
      tick: uint32(run.world.tick), kind: ActionSystemNotice,
      first: -2, text: ThreeMinuteNotice))
  when defined(gotaTestRoom):
    run.finishTestTick()
  else:
    run.sampleMetrics(run.finished() or
      (run.replayMode and run.world.tick == run.replayData.hashes.len))
    run.metrics.finishTick(run.world.tick)

## Headless reporting and replay recording.

proc teamHeroLevels(team: Team): string =
  ## Formats the current hero levels for one team.
  for hero in run.world.heroes:
    if hero.team != team:
      continue
    if result.len > 0:
      result.add " "
    result.add "L" & $hero.level

proc teamHeroXp(team: Team): int =
  ## Returns all lifetime XP earned by one team's heroes.
  for hero in run.world.heroes:
    if hero.team == team:
      result += hero.totalXp

proc teamHeroXps(team: Team): string =
  ## Formats each hero's lifetime XP for one team, in slot order.
  for hero in run.world.heroes:
    if hero.team != team:
      continue
    if result.len > 0:
      result.add " "
    result.add $hero.totalXp

proc teamHeroGold(team: Team): int =
  ## Returns all unspent gold earned by one team's heroes.
  for hero in run.world.heroes:
    if hero.team == team:
      result += hero.gold

proc teamTowerCount(team: Team): int =
  ## Returns the number of standing towers owned by one team.
  for tower in run.world.buildings:
    if tower.kind == TowerBuilding and tower.team == team and tower.hp > 0:
      inc result

proc heroVmStatus*(): tuple[active, decisions: int] =
  ## Reports live VM decisions or consumed gameplay commands, excluding chat.
  if run.replayMode:
    result.active = run.world.heroes.len
    result.decisions = run.replayCommandCount()
  else:
    for vm in run.heroVms:
      if vm != nil and not vm.failed:
        inc result.active
      if vm != nil:
        result.decisions += vm.decisions

proc startReplayRecording*(maximumTicks: uint32) =
  ## Starts the in-memory action tape for a live match.
  var config = run.config
  config.maxTicks = int32(maximumTicks)
  run.recorder = initReplayRecorder(
    currentSetup(run, maximumTicks), config.mapPreset
  )
  run.recorder.data.config = config
  run.replayPlayer = ReplayPlayer(data: run.recorder.data)

proc recordingData*(): ReplayData =
  ## Captures the complete recorded timeline even when viewing an earlier tick.
  if run == nil or run.recorder == nil or run.replayMode:
    raise newException(ReplayError, "There is no live match replay to save.")
  if run.recordingError.len > 0:
    raise newException(ReplayError, run.recordingError)
  if run.world.tick == run.recorder.data.hashes.len:
    run.sampleMetrics(true)
  result = run.recorder.data
  result.metrics = run.history.replayMetrics()

proc saveRecording*(path = options.recordPath) =
  ## Finalizes and saves a requested action replay.
  if run.recorder == nil or path.len == 0:
    return
  saveReplay(path, recordingData())
  echo &"replay saved: {path} " &
    &"({run.recorder.data.actions.len} actions)"

when defined(headless):
  const HeadlessTickRate = TickRate

  proc printHeadlessSummary(steps: int, started: float64) =
    ## Prints the deterministic result and measured execution speed.
    let
      elapsed = max(epochTime() - started, 0.000001)
      simulated = steps.float64 / HeadlessTickRate.float64
      draftSeconds = run.world.draftTicks.float64 / HeadlessTickRate.float64
      battleSeconds = run.world.battleTick().float64 / HeadlessTickRate.float64
      speedup = simulated / elapsed
      vmStatus = heroVmStatus()
      redFortHp = max(run.world.forts[0].hp, 0'i32)
      blueFortHp = max(run.world.forts[1].hp, 0'i32)
      outcome =
        if run.world.draw:
          "draw"
        elif run.world.gameOver:
          if run.world.winner == RedTeam: "red won" else: "blue won"
        elif run.world.phase == Drafting:
          "draft incomplete"
        else:
          "time limit"
    echo &"result: {outcome}"
    echo &"seeds: match {run.map.seed}, map {run.map.preset.seed}"
    echo &"simulated: {simulated:.2f} s in {elapsed:.4f} s " &
      &"({speedup:.1f}x real time)"
    echo &"draft: {draftSeconds:.2f} s, battle: {battleSeconds:.2f} s"
    echo &"gods: red {redFortHp} hp, blue {blueFortHp} hp"
    echo &"towers: red {teamTowerCount(RedTeam)}, " &
      &"blue {teamTowerCount(BlueTeam)}"
    echo &"hash: {run.stateHash().toHex(16)} map " &
      &"{run.map.hash.toHex(16)}"
    echo &"heroes: red {teamHeroLevels(RedTeam)}, " &
      &"blue {teamHeroLevels(BlueTeam)}"
    echo &"economy: red {teamHeroXp(RedTeam)} XP / " &
      &"{teamHeroGold(RedTeam)} gold, blue {teamHeroXp(BlueTeam)} XP / " &
      &"{teamHeroGold(BlueTeam)} gold"
    echo &"xp: red {teamHeroXps(RedTeam)}, blue {teamHeroXps(BlueTeam)}"
    if run.replayMode:
      echo &"replay: {vmStatus.decisions} gameplay actions"
      if run.hashCheck.mismatches > 0:
        echo &"replay hashes: {run.hashCheck.mismatches} mismatches"
    else:
      echo &"scripts: {vmStatus.active}/{run.world.heroes.len} active, " &
        &"{vmStatus.decisions} decisions"

  proc runHeadless*() =
    ## Runs fixed simulation ticks with optional pacing and request barriers.
    let started = epochTime()
    if not run.replayMode:
      startReplayRecording(uint32(options.maximumTicks))
    startGameProfile()
    defer:
      finishGameProfile()
    var
      steps = 0
      pacer = initTickPacer(options.headlessTickRate)
      pollers: seq[RequestPoll]
    if options.waitForLlm and not run.replayMode:
      for vm in run.heroVms:
        if vm != nil:
          pollers.add vm.pollRequests
    while (if run.replayMode: steps < run.replayData.hashes.len
        else: not run.finished()) and
        run.recordingError.len == 0:
      advanceGame()
      waitForRequests(pollers)
      pacer.pace()
      inc steps
      if profileShouldDump(steps):
        finishGameProfile()
    if run.recordingError.len > 0:
      raise newException(ReplayError, run.recordingError)
    if run.replayMode:
      run.hashCheck.requireReplayComplete(
        uint32(run.world.tick),
        run.replayData.hashes.len
      )
      if not run.replayPlayer.finished:
        raise newException(
          ReplayError,
          "replay simulation did not consume every action"
        )
    else:
      saveRecording()
    printHeadlessSummary(steps, started)

proc initializeLocalMatch*(
    config: GotaConfig, sources: openArray[string], humanSeat: int
) =
  ## Builds a menu-configured local match without changing private policy files.
  matchConfig = config
  options.seed = config.seed
  options.maximumTicks = config.maxTicks
  options.spawnIntervalTicks = config.spawnIntervalTicks
  options.playerSlot = int32(humanSeat + 1)
  options.replayPath = ""
  clearPlayerCommands()
  var activeSeats: seq[int]
  var packedSources: seq[string]
  var packedConfig = config
  packedConfig.players = newSeq[PlayerConfig](HeroClassCount)
  options.playerSlot = 0
  for i in 0 ..< HeroClassCount:
    if i == humanSeat or (i < sources.len and sources[i].len > 0):
      if i == humanSeat:
        options.playerSlot = int32(activeSeats.len + 1)
      if i < config.players.len:
        packedConfig.players[activeSeats.len] = config.players[i]
      activeSeats.add i
      packedSources.add(if i == humanSeat or i >= sources.len: "" else: sources[i])
  if activeSeats.len == 0:
    raise newException(GotaConfigError, "Assign a human or bot before starting")
  let map = generateMap(config.seed, config.mapPreset)
  run = newGame(
    map, config.spawnIntervalTicks, HeroClassCount, false, ReplayData(),
    draftMode = config.draftMode, activeSeats = activeSeats
  )
  run.loadBotSources(packedSources)
  run.recorder = initReplayRecorder(
    currentSetup(run, uint32(config.maxTicks)), map.preset
  )
  run.recorder.data.config = packedConfig
  run.recorder.data.config.playerSlot = options.playerSlot
  run.replayPlayer = ReplayPlayer(data: run.recorder.data)
