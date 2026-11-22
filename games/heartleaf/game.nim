## Heartleaf match setup, command line, and the headless runner.
##
## Owns the one live world and decides where each tick's commands come from:
## nine BASIC villagers in a live game, or the recorded action stream when
## replaying. Everything else about a tick is identical between the two,
## which is what makes a replay reproduce its game exactly.

import
  std/[os, strformat, times],
  polyworld/[cli, controllers, profiles, tapes, timings],
  content,
  maps as mapgen,
  sim,
  bots,
  controls,
  replays, seeking,
  options as launches

proc usage() =
  ## Prints the command-line and compile-time configuration surface.
  echo "Heartleaf, a village dinner-party week between nine BASIC villagers."
  echo commonUsageFor(HeartleafCommonFlags)
  echo """
  --days N         Days in the week (default 7).
  --seek-tick N    Fast-forward to an absolute tick (zero is initial state).
  --seek-event S   Fast-forward to day:N:morning|dinner|scorecard.
  --help           Show this message.

Supply nine bots, or one human in slot 1 .. 9 and eight bots.
--days sets the calendar; shared duration options can end a new match earlier.
Heartleaf has fixed villager names, no LLM requests, and no audio output.
Compile with -d:headless for a command-line game.
Compile with -d:emscripten for the web backend.
Screenshot captures use the bundled bots when no roster is supplied.
Use --seek-tick or --seek-event with --play=false to capture that state."""

proc readLaunchOptions(): LaunchOptions =
  ## Reports command-line errors without initializing the game world.
  try:
    result = parseLaunchOptions(commandLineParams())
  except ValueError as error:
    fail(error.msg)

let
  parsed = readLaunchOptions()
  options* = parsed.common
  startupTarget* = parsed.startupTarget

if parsed.showHelp:
  usage()
  quit(0)

var run*: Game

block:
  startGameProfile()
  var
    mapSeed = options.seed
    dayCount = parsed.dayCount
  if options.replayPath.len > 0:
    var replayData: ReplayData
    profileBlock "replay":
      replayData = loadReplay(options.replayPath)
    mapSeed = replayData.header.setup.mapSeed
    dayCount = int32(replayData.header.setup.dayCount)
    var gameMap: MapData
    profileBlock "map":
      gameMap = generateMap(mapSeed)
    gameMap.validateMap()
    if replayData.header.setup.mapHash != gameMap.hash:
      raise newException(ReplayError,
        "this replay was recorded on a different map generator")
    if replayData.header.setup.contentHash != contentHash():
      raise newException(ReplayError,
        "this replay was recorded against different game tuning")
    run = newGame(gameMap, dayCount)
    run.maximumTicks = int32(replayData.hashes.len)
    run.replayMode = true
    run.replayData = replayData
    run.replayPlayer = initReplayPlayer(replayData)
    run.historyPlayback = true
  else:
    var gameMap: MapData
    profileBlock "map":
      gameMap = generateMap(mapSeed)
    gameMap.validateMap()
    run = newGame(gameMap, dayCount)
    run.maximumTicks = parsed.executionTicks(run.maximumTicks)
    let
      kinds = controllerKinds(VillagerCount, options.playerSlot)
      expanded = options.botGroups.expandBotSources(kinds)
    loadBots(run, expanded)
    run.recorder = initReplayRecorder(Setup(
      mapSeed: mapSeed,
      tickRate: uint16(TickRate),
      gridTiles: uint16(GridSide),
      decisionTicks: uint16(DecisionTicks),
      dayCount: uint16(dayCount),
      maximumTicks: uint32(gameLengthTicks(dayCount)),
      mapHash: gameMap.hash,
      contentHash: contentHash()
    ))
    run.recorder.data.config = localGameConfig(options, VillagerCount)
    run.recorder.data.config.dayCount = dayCount
    run.recorder.data.config.maxTicks = gameLengthTicks(dayCount)
    run.replayPlayer = ReplayPlayer(data: run.recorder.data)

startupTarget.validate(run.world.dayCount, run.maximumTicks)

proc decide(w: World) =
  ## Supplies one decision tick's commands from whichever source owns them.
  if run.historyPlayback:
    if run.recorder != nil:
      run.replayPlayer.data = run.recorder.data
    var action: ReplayAction
    while run.replayPlayer.takeActionAt(uint32(w.tick), action):
      w.applyReplayAction(action)
  else:
    flushPlayerCommands(run)
    runBotDecisions(run)

proc verifyTick(game: Game) =
  ## Compares one tick against its recorded fingerprint.
  let hashes =
    if game.recorder != nil: game.recorder.data.hashes
    else: game.replayPlayer.data.hashes
  hashes.checkReplayHash(
    uint32(game.world.tick),
    game.stateHash(),
    game.hashCheck
  )

proc advanceGame*() =
  ## Advances the live world by one tick and verifies it when replaying.
  run.world.tickWorld(decide)
  if run.historyPlayback:
    run.verifyTick()
  elif run.recorder != nil:
    run.recorder.recordHash(run.stateHash())

proc seekStartup*(afterTick: proc() {.closure.} = nil) =
  ## Advances to the requested scene without changing the recorded setup.
  if startupTarget.kind == NoSeek:
    return
  while not startupTarget.reached(run.world):
    if run.world.over or run.world.tick >= run.maximumTicks:
      fail("seek target was not reached before this recording ended")
    advanceGame()
    if afterTick != nil:
      afterTick()
  if run.hashCheck.mismatches > 0:
    fail("replay diverged while seeking")

proc saveRecording*(path = options.recordPath) =
  ## Saves every recorded tick, keeping the original match setup.
  if run.recorder == nil or path.len == 0:
    return
  let directory = path.parentDir
  if directory.len > 0:
    createDir(directory)
  saveReplay(path, run.recorder.data)

proc describeResult*(): string =
  ## One line naming the villager with the best week.
  if not run.world.over:
    return "game unfinished"
  var
    best = 0
    tied = false
  for slot in 1 ..< VillagerCount:
    if run.world.villagers[slot].score >
        run.world.villagers[best].score:
      best = slot
      tied = false
    elif run.world.villagers[slot].score ==
        run.world.villagers[best].score:
      tied = true
  if tied:
    &"a tie at {run.world.villagers[best].score} points"
  else:
    &"{VillagerNames[best]} wins with " &
      &"{run.world.villagers[best].score} points"

proc runHeadless*() =
  ## Runs a whole game with no renderer, as fast as the machine allows.
  startGameProfile()
  defer:
    finishGameProfile()
  let started = epochTime()
  var pacer = initTickPacer(options.headlessTickRate)
  seekStartup(proc() = pacer.pace())
  while startupTarget.kind == NoSeek and
      run.world.tick < run.maximumTicks and not run.world.over:
    advanceGame()
    pacer.pace()
    if profileShouldDump(run.world.tick):
      finishGameProfile()
    if options.verbose and run.world.tick mod (TickRate * 30) == 0:
      echo &"tick {run.world.tick}/{run.maximumTicks}, " &
        &"day {run.world.day}, {run.world.phase}"
  let
    elapsed = max(epochTime() - started, 0.000001)
    simulated = run.world.tick.float64 / TickRate.float64

  echo &"seed {run.mapSeed}  ticks {run.world.tick}/{run.maximumTicks}  " &
    &"{simulated:.1f}s simulated in {elapsed:.2f}s " &
    &"({simulated / elapsed:.0f}x real time)"
  for slot in 0 ..< VillagerCount:
    let v = run.world.villagers[slot]
    echo &"  {VillagerNames[slot]:>8}  score {v.score:>4}  " &
      &"carrying {v.carriedTotal():>3}  hosted points " &
      &"{run.world.lastTally[slot].hostPoints:>3} on the last night"
  if not run.replayMode:
    for slot in 0 ..< VillagerCount:
      let brain = run.brains[slot]
      if brain == nil:
        continue
      if brain.failed:
        echo &"  {VillagerNames[slot]:>8}  script FAILED: {brain.lastError}"
  echo "  ", describeResult()
  echo &"  {pathSearches} path searches, {pathExpansions} expansions"

  if startupTarget.kind != NoSeek:
    echo &"  destination: tick {run.world.tick}, day {run.world.day}, {run.world.phase}"
    for slot, report in run.world.dailyReports:
      var eating = ""
      for bite in 0 ..< report.biteCount:
        let food = report.bites[bite]
        eating.add &" {VeggieNames[food.veggie]} +{food.points}"
      let tally =
        if run.world.phase == DaytimePhase: DinnerReport()
        else: run.world.lastTally[slot]
      echo &"  {VillagerNames[slot]}: hosting {report.hostingPoints}" &
        &" ({tally.pantry} veg x {tally.visitors} guests)," &
        &" eating [{eating}], curfew -{report.penalty}," &
        &" today {run.world.villagers[slot].score - report.startingScore}," &
        &" total {run.world.villagers[slot].score}"
    if not run.replayMode:
      saveRecording()
    return
  if run.replayMode:
    if not run.replayPlayer.finished:
      echo "error: the replay still had commands left to run"
      quit(1)
    run.hashCheck.requireReplayComplete(
      uint32(run.world.tick),
      run.replayData.hashes.len
    )
    echo "  replay verified: every tick matched its recorded hash"
  else:
    saveRecording()
    if options.recordPath.len > 0:
      echo &"  recorded {run.recorder.data.actions.len} commands to " &
        options.recordPath
