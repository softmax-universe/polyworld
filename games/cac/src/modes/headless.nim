## Matches with no window: the headless recorder and checker, and the
## Coworld server, which plays the platform's staged BASIC players and
## publishes their results and replay like the other Polyworld games.
import std/[os, strutils]
import jsony
import polyworld/cli
import ../core/[sim, sessions, bots, match, replays]

when defined(coworld):
  import polyworld/coworld

type
  HeadlessArgs* = object
    options*: GameOptions
    classNames*: seq[string]  ## `--classes`, one per seat; empty without it.

  ConfigClasses = object
    classes: seq[string]

proc seatClasses*(names: openArray[string], seats: int): seq[Seat] =
  ## Parses an explicit class override with one entry per seat. Each seat
  ## plays its class's precon, whatever deck its script lists.
  if names.len != seats:
    raise newException(ValueError, "classes must name one class per player")
  for name in names:
    result.add precon(parseHeroClass(name))

proc configClasses*(config: string): seq[string] =
  ## A Coworld config's optional `classes` override; empty without one. The
  ## shared `GameConfig` reads the other fields.
  config.fromJson(ConfigClasses).classes

proc checkReplay*(path: string) =
  ## Plays a replay back with no window and requires every hash to match.
  let data = loadReplay(path)
  var
    game = newGame(data.header.setup)
    check: ReplayHashCheck
    tick = 0'u32
    cursor = initReplayCursor(data)
  data.applyReplayMailboxes(cursor, tick)
  while tick < data.hashes.len.uint32:
    var action: ReplayAction
    if not data.takeReplayAction(cursor, tick, action):
      raise newException(ReplayError, "Replay gameplay action is missing")
    if not game.applyAction(action):
      raise newException(ReplayError,
        "replay action at tick " & $action.tick & " was refused")
    discard game.takeVisualEvents()
    tick = action.tick
    data.hashes.checkReplayHash(tick, game.stateHash, check)
    data.applyReplayMailboxes(cursor, tick)
  check.requireReplayComplete(tick, data.hashes.len)
  echo "Replay verified: ", data.hashes.len, " ticks, ",
    data.header.setup.classes.len, " players."

proc parseHeadlessArgs*(arguments: seq[string]): HeadlessArgs =
  ## `--bot PATH[:COUNT]` once per group of seats (2 to 7 seats), `--seed`,
  ## `--ticks` (or `--seconds`, `--minutes`), `--classes archer,mage,...`
  ## and `--record PATH`; or `--replay PATH` to verify a recording. Add
  ## `--resume-step N` warms bots through N; duration flags override its limit.
  result.options = GameOptions(seed: DefaultSessionSeed.int32,
    maximumTicks: DefaultDurationTicks)
  var index = 0
  while index < arguments.len:
    let argument = arguments[index]
    if result.options.takeCommonFlag(arguments, index, argument):
      discard
    elif argument == "--classes":
      result.classNames = arguments.argumentValue(index, argument).split(',')
    elif argument.startsWith("--classes="):
      result.classNames = argument["--classes=".len .. ^1].split(',')
    else:
      fail("unknown argument: " & argument)
    inc index
  # Resume runs selected bots against the replay before their handoff.
  result.options.validateGameOptions(0, "")

proc runHeadless*() =
  ## Plays and optionally records one bot match, or verifies a replay.
  let
    parsed = parseHeadlessArgs(commandLineParams())
    options = parsed.options
  if options.replayPath.len > 0 and options.resumeStep < 0:
    checkReplay(options.replayPath)
    return
  let seats = options.botGroups.botCount
  if seats notin 2 .. MaxPlayers:
    fail("supply 2 to " & $MaxPlayers & " bots with --bot PATH[:COUNT]")
  var replayData: ReplayData
  if options.resumeStep >= 0:
    replayData = loadReplay(options.replayPath)
    options.validateResume(replayData.hashes.len,
      replayData.header.setup.classes.len)
    if options.durationOverride and options.maximumTicks < options.resumeStep:
      fail("duration override ends before --resume-step")
    if parsed.classNames.len > 0:
      fail("--resume-step uses the replay's recorded classes and decks")
  var classOverride: seq[Seat]
  if parsed.classNames.len > 0:
    try:
      classOverride = seatClasses(parsed.classNames, seats)
    except ValueError as error:
      fail("--classes: " & error.msg)
  var
    sources: seq[string]
    players: seq[PlayerConfig]
  for group in options.botGroups:
    for _ in 0 ..< group.count:
      sources.add readFile(group.path)
      players.add PlayerConfig(name: group.path.extractFilename)
  let
    bots = loadBots(sources)
    seed =
      if options.resumeStep >= 0: replayData.header.setup.seed
      else: options.seed
    maxTicks =
      if options.resumeStep >= 0:
        replayData.header.setup.maximumTicks
      else: options.maximumTicks.uint32
  for bot in bots:
    if bot != nil:
      bot.warmingPolicies = options.resumeStep >= 0
  let
    selected =
      if classOverride.len == 0 or options.resumeStep >= 0:
        setupBotSeats(bots, seed.int64, options.resumeStep < 0)
      else: classOverride
    seated =
      if options.resumeStep >= 0: replayData.header.setup.seats()
      elif classOverride.len > 0: classOverride
      else: selected
    recorder = initReplayRecorder(
      matchSetup(seated, seed, maxTicks),
      GameConfig(players: players, seed: seed,
        maxTicks: maxTicks.int32))
  for bot in bots:
    if bot != nil:
      bot.warmingPolicies = false
  for player, bot in bots:
    for problem in bot.deckProblems:
      echo "player ", player, " illegal deck: ", problem
  var played = initBotMatch(seated, seed.int64, bots,
    maxTicks, recorder)
  if options.resumeStep >= 0:
    played.replayData = replayData
    played.resumeStep = options.resumeStep.uint32
    if options.durationOverride:
      if options.maximumTicks > MaxReplayHashes:
        fail("duration override exceeds the replay tick limit")
      played.resumeMaximumTicks = options.maximumTicks.uint32
  played.scriptError = proc(player: int, message: string) =
    echo "player ", player, " BASIC error: ", message
  played.run()
  if options.recordPath.len > 0:
    saveReplay(options.recordPath, recorder.data)
  echo "Match ", played.outcomeLabel, " after ", played.tick, " ticks, ",
    played.game.turnNumber, " turns. Scores: ", played.scores

when defined(coworld):
  proc runCoworld*() =
    ## One Coworld episode: every staged player is a BASIC script.
    let
      options = coworldOptions(0)
      seats = coworld.config.players.len
    if seats notin 2 .. MaxPlayers:
      raise newException(CoworldError,
        "CaC plays 2 to " & $MaxPlayers & " players")
    let
      names =
        try:
          readLocal(getEnv("COGAME_CONFIG_URI")).configClasses()
        except JsonError as error:
          raise newException(CoworldError,
            "Invalid Coworld configuration: " & error.msg)
    resetInboxes(seats)
    var vms: seq[BotVm]
    for slot, group in options.botGroups:
      let
        policy = loadPlayerPolicy(readPlayerSource(group.path), slot)
        program = compilePlayer(policy.source, botSchema(), botLimits(), slot)
      vms.add newBotVm(program, slot.int32, playerPrinter(slot))
    let seated =
      if names.len > 0:
        try: seatClasses(names, seats)
        except ValueError as error:
          raise newException(CoworldError, error.msg)
      else:
        # A script's illegal deck is in its own log; the seat starts out.
        var selected: seq[Seat]
        for slot, vm in vms:
          try:
            selected.add vm.setupSeat(seats, options.seed.int64)
          except BasicError as error:
            rejectPlayer(slot, error.msg)
        selected
    let recorder = initReplayRecorder(
      matchSetup(seated, options.seed, options.maximumTicks.uint32),
      coworld.config)
    var played = initBotMatch(seated, options.seed.int64, vms,
      options.maximumTicks.uint32, recorder)
    played.scriptError = proc(player: int, message: string) =
      # A failed decision stops the match without substituting an action.
      vms[player].failed = true
      playerError(player, message)
    played.run()
    saveReplay(options.recordPath, recorder.data)
    finishCoworld(CoworldResults(
      scores: played.scores,
      ticks: played.tick.int32,
      seed: options.seed,
      outcome: played.outcomeLabel
    ))
