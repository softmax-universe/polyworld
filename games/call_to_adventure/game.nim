## Call to Adventure match setup, command line, and the headless runner.
##
## Owns the one live expedition and decides where each tick's hero commands
## come from: four BASIC programs, or the recorded action stream when
## replaying.

import
  std/[strformat, strutils, times],
  polyworld/[cli, controllers, metrics, profiles, tapes, timings],
  content,
  maps,
  sim,
  bots,
  controls,
  replays,
  options as launchoptions

export launchoptions

when defined(coworld):
  import polyworld/coworld

var
  arenaOptions* = defaultArenaOptions()
  options*: GameOptions
  run*: Game

proc tapeHashes(game: Game): seq[uint64] =
  ## Returns the live tape when recording, otherwise the loaded replay.
  if game.recorder != nil:
    game.recorder.data.hashes
  else:
    game.replayPlayer.data.hashes

proc decideHeroSlot(game: Game, slot: int32) =
  ## Supplies one hero's command from its VM or the replay action stream.
  let actor = game.world.actors[slot]
  if not actor.alive or actor.busy:
    return
  if game.historyPlayback:
    if game.recorder != nil:
      game.replayPlayer.data = game.recorder.data
    var action: ReplayAction
    while game.replayPlayer.takeActionAt(
        uint32(game.world.tick),
        actor.id,
        action
    ):
      if action.kind != ActionChat:
        # Mailboxes were consumed by private VMs; only their commands replay.
        discard game.applyHeroAction(slot, action)
    return
  if isPlayerIndex(options.playerSlot, slot):
    flushPlayerCommands(game)
    return
  runBotDecisions(game, slot)

proc verifyTick(game: Game) =
  ## Compares one tick against its recorded fingerprint.
  game.tapeHashes().checkReplayHash(
    uint32(game.world.tick),
    game.stateHash(),
    game.hashCheck
  )

proc advanceGame*() =
  ## Advances the live expedition by one tick and verifies it when replaying.
  run.tickWorld(decideHeroSlot)
  if run.historyPlayback:
    run.verifyTick()
  elif run.recorder != nil:
    run.recorder.recordHash(run.stateHash())
  run.sampleMetrics(
    run.world.outcome != RunningOutcome or
      (run.replayMode and run.world.tick >= run.replayData.hashes.len)
  )
  run.metrics.finishTick(run.world.tick)

proc saveRecording*(path = options.recordPath) =
  ## Finalizes and writes a requested action replay.
  if run.recorder == nil or path.len == 0:
    return
  if run.world.tick == run.recorder.data.hashes.len:
    run.sampleMetrics(true)
  run.recorder.data.metrics = run.history.replayMetrics()
  saveReplay(path, run.recorder.data)
  echo &"replay saved: {path} " &
    &"({run.recorder.data.actions.len} actions)"

proc summarize*(game: Game) =
  ## Prints the current expedition outcome and surviving party state.
  echo ""
  echo "tick ", game.world.tick,
    "  phase ", game.world.phase,
    "  deepest ", game.world.deepest, " (",
    Themes[game.world.deepest].name, ")"
  echo "  monsters killed ", game.world.killed,
    "  treasure taken ", game.world.collected,
    "  carried ", game.partyGold(), " gold"
  echo "  banked ", game.world.banked
  var alive = 0
  for slot in 0 ..< PartySize:
    let actor = game.world.actors[slot]
    if actor.alive:
      inc alive
      echo &"  {HeroClass(actor.class)}: {actor.hp}/" &
        &"{actor.maxHp} hp, level {actor.home.level}, " &
        &"{actor.carriedValue} gold, {actor.carriedWeight} weight"
    else:
      echo &"  slot {slot}: dead"
  echo "  party alive ", alive

proc arenaMatchup(): string =
  ## Names the two sides of the debug fight, such as
  ## "Wizard, Fighter vs 10 Dustling".
  var heroes: seq[string]
  for class in arenaOptions.heroes:
    heroes.add class.heroName
  var counts: array[Species, int]
  for species in arenaOptions.arenaMonsters():
    inc counts[species]
  var monsters: seq[string]
  for species in arenaOptions.species:
    if counts[species] > 0:
      monsters.add $counts[species] & " " & SpeciesNames[species]
      counts[species] = 0
  heroes.join(", ") & " vs " & monsters.join(", ")

proc summarizeArena(game: Game) =
  ## Prints who won the debug fight, how long it took, and who is left.
  echo ""
  if game.world.arenaDecided == 0:
    echo &"result: no winner after {game.world.tick} ticks"
  else:
    let
      ticks = game.world.arenaDecided
      seconds = ticks.float64 / TickRate.float64
      winners = if game.world.partyAlive() > 0: "heroes" else: "monsters"
    echo &"result: the {winners} won in {seconds:.2f} s ({ticks} ticks)"
  var heroes: seq[string]
  for class in arenaOptions.heroes:
    let actor = game.world.actors[class.ord]
    heroes.add class.heroName & " " & (
      if actor.alive: &"{actor.hp}/{actor.maxHp} hp" else: "dead")
  echo "heroes: ", heroes.join(", ")
  echo &"monsters: {game.monstersOn(ArenaLevel)} of {arenaOptions.count} left"

proc runHeadless*() =
  ## Runs fixed simulation ticks with optional pacing and request barriers.
  echo "Call to Adventure, seed ", run.world.setup.seed
  if run.world.isArena:
    echo "arena: ", arenaMatchup(), " in a ", ArenaSize, "x", ArenaSize,
      " room"
  else:
    echo "dungeon: ", LevelCount, " levels, ", run.dungeon.ramps.len, " ramps"
    var monsters = 0
    for level in 0 ..< LevelCount:
      monsters += run.monstersOn(level)
    echo "monsters: ", monsters
    echo "party enters at ", run.dungeon.entrance

  startGameProfile()
  defer:
    finishGameProfile()
  let started = epochTime()
  var
    reported = 0
    pacer = initTickPacer(options.headlessTickRate)
    pollers: seq[RequestPoll]
  if options.waitForLlm and not run.replayMode:
    for vm in run.heroVms:
      if vm != nil:
        pollers.add vm.pollRequests
  while run.world.tick < options.maximumTicks and
      run.world.phase notin {EscapedPhase, WipedPhase}:
    advanceGame()
    waitForRequests(pollers)
    pacer.pace()
    if profileShouldDump(run.world.tick):
      finishGameProfile()
    if options.verbose:
      while reported < run.log.len:
        echo "[", run.world.tick, "] ", run.log[reported]
        inc reported
      if run.world.tick mod (TickRate * 30) == 0:
        run.summarize()
  let
    elapsed = max(epochTime() - started, 0.000001)
    simulated = run.world.tick.float64 / TickRate.float64
  if run.world.isArena:
    run.summarizeArena()
  else:
    run.summarize()
    case run.world.phase
    of EscapedPhase:
      echo "result: the party escaped with ", run.world.banked, " gold"
    of WipedPhase:
      echo "result: the party was wiped out on level ", run.world.deepest
    else:
      echo "result: ran out of time on level ", run.partyLevel()
  echo &"simulated: {simulated:.2f} s in {elapsed:.4f} s " &
    &"({simulated / elapsed:.1f}x real time)"
  echo &"hash: {run.stateHash().toHex(16)}"
  if run.replayMode:
    echo &"replay: {run.replayPlayer.actionIndex}/" &
      &"{run.replayData.actions.len} actions"
    if not run.replayPlayer.finished:
      raise newException(
        ReplayError,
        "replay simulation did not consume every action"
      )
    run.hashCheck.requireReplayComplete(
      uint32(run.world.tick),
      run.replayData.hashes.len
    )
    echo "replay verified: every tick matched"
  else:
    saveRecording()
    for slot in 0 ..< PartySize:
      if run.heroVms[slot] != nil and run.heroVms[slot].failed:
        when not defined(coworld):
          echo &"hero {100 + slot} script FAILED: {run.heroVms[slot].lastError}"

when defined(coworld):
  options = coworldOptions(4)
else:
  try:
    let parsed = parseGameOptions()
    options = parsed.options
    arenaOptions = parsed.arena
  except CliError as error:
    fail(error.msg)

startGameProfile()
if options.replayPath.len > 0:
  var replayData: ReplayData
  profileBlock "replay":
    replayData = loadReplay(options.replayPath)
  options.seed = replayData.config.seed
  options.maximumTicks = int32(replayData.hashes.len)
  profileBlock "map":
    run = newGame(
      options.seed,
      int32(replayData.header.setup.maximumTicks)
    )
  run.replayMode = true
  run.replayData = replayData
  run.replayPlayer = initReplayPlayer(replayData)
  run.historyPlayback = true
  if replayData.header.setup != run.world.setup:
    raise newException(
      ReplayError,
      "the replay setup does not match this Call to Adventure build"
    )
else:
  profileBlock "map":
    run =
      if arenaOptions.enabled:
        newArenaGame(
          options.seed,
          options.maximumTicks,
          arenaOptions.heroes,
          arenaOptions.arenaMonsters()
        )
      else:
        newGame(options.seed, options.maximumTicks)
  loadBots(run, options.botGroups, options.playerSlot)
  run.recorder = initReplayRecorder(run.world.setup)
  run.recorder.data.config =
    when defined(coworld):
      coworld.config
    else:
      localGameConfig(options, PartySize)
  run.replayPlayer = ReplayPlayer(data: run.recorder.data)
