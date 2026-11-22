## Match setup, local controls, fixed ticks, and headless play.

import
  std/[os, strutils],
  bassy,
  polyworld/[cli, policies, screenshots, timings],
  sim, maps, bots, replays

type
  Options* = object
    seed*, players*, ticks*, player*: int
    speed*: int32
    soundMuted*, pauseOnStart*, verbose*, seedSpecified*: bool
    vsync*: bool = true
    headlessTickRate*: int32
    role*, name*, record*, replay*: string
    width*, height*: int32
    captureTicks*: int
    capture*: ScreenshotOptions
    botGroups*: seq[BotGroup]
  Game* = ref object
    world*: SimServer
    ship*: ShipMap
    bots*: seq[Bot]
    botSources*: seq[string]
    nav: Navigator
    previous*: seq[InputState]
    input*: InputState
    choice*: int
    chat*: string
    recording*: ReplayData
    playback*: bool
    frame*: int

proc usage() =
  ## Prints the controls and native or headless launch options.
  echo "Crewrift in Polyworld"
  when not defined(headless):
    echo "  WASD: move or select vote. E / Space: use, kill, vote."
    echo "  Arrows / middle / right drag: pan. Wheel: zoom. C: action camera."
    echo "  Click / shift-click / box select: follow crew. Ctrl+A: select all."
    echo "  Q: vent. Enter: meeting chat. Tab: map. R: new match."
    echo "  --player [N]      Control slot N (1-16, bare flag selects 1)."
    echo "  --name NAME       Human player's name in the roster and replay."
  echo "  --spectate        Let local bots play every slot (the default)."
  echo "  --bot PATH[:N]    Use a BASIC program for N bot slots (default 1)."
  echo "  --bots PATH[:N]   Same as --bot; explicit bots must fill the roster."
  echo "                    Without bot options, every bot uses base.bas."
  when not defined(headless):
    echo "  --role crew|imp   Choose your human role, or omit for random roles."
  echo "  --players N       Roster size (8-16, default 8)."
  echo "  --seed N          Match seed (default 2026)."
  echo "  --ticks N         Maximum active ticks (default 10000)."
  echo "  --seconds N       Same duration in seconds; --minutes N also works."
  when not defined(headless):
    echo "  --speed N         Simulation speed (default 1)."
    echo "  --play BOOL       Start the viewer playing or paused."
  echo "  --record PATH     Save an input replay with tick fingerprints."
  echo "  --replay PATH     Play and verify a saved input replay."
  when not defined(headless):
    echo "  --windowSize WxH  Window size (default 1440x900)."
    echo "  --screenshot PATH Save a PNG and exit after --frames N (default 30)."
    echo "  --capture-ticks:N Advance N ticks before capture frames (default 0)."
    echo "  --vsync BOOL      Enable display synchronization (default true)."
  echo "  --mute[=BOOL]     Request muted audio."
  echo "  --unmute          Start with sound enabled."
  echo "  --verbose         Print the resolved match setup."
  when defined(headless):
    echo "  --headless-tick-rate N  Pace headless ticks (default 0: unlimited)."
  echo "All value flags accept spaces, =, or : separators."
  echo "Compile with -d:headless to run and verify without graphics."

proc validateBots(options: Options) =
  ## Rejects bot groups that cannot fit the live roster before reading files.
  if options.replay.len > 0:
    return
  let available = options.players - int(options.player >= 0)
  var count = 0
  for group in options.botGroups:
    if group.path.len == 0 or group.count < 1:
      raise newException(CrewriftError, "Invalid BASIC bot group.")
    if group.count > available - count:
      raise newException(CrewriftError,
        "Too many bots for " & $available & " available slots.")
    count += group.count
  if options.botGroups.len > 0 and count != available:
    raise newException(CrewriftError,
      "Explicit bots must fill " & $available & " slots; configured " &
        $count & ".")

proc parseOptions*(arguments = commandLineParams()): Options =
  ## Parses the shared native and headless command surface.
  result.players = MinPlayers
  var
    common = GameOptions(seed: 2026, maximumTicks: MaxTicks,
      speed: 1, windowWidth: 1440, windowHeight: 900)
    index = 0
    spectate = false
  try:
    while index < arguments.len:
      let
        argument = arguments[index]
        flag = argument.splitFlag().name
      if common.takeCommonFlag(arguments, index, argument):
        discard
      else:
        case flag
        of "--players", "--role", "--capture-ticks":
          let value = arguments.flagValue(index, argument)
          case flag
          of "--players": result.players = parsePositiveInt32(value, flag).int
          of "--role": result.role = value
          of "--capture-ticks":
            result.captureTicks = parseInt32(value, flag).int
          else: discard
        of "--spectate":
          if argument != flag:
            raise newException(CrewriftError, "--spectate takes no value.")
          spectate = true
        of "--help", "-h":
          usage()
          quit(0)
        else:
          raise newException(CrewriftError, "Unknown argument: " & argument)
      inc index
    if spectate and common.playerSlot != 0:
      raise newException(CrewriftError, "--spectate cannot be used with --player.")
    var supported = AllCommonFlags - {LlmModeFlag, ServerFlag, RoomFlag}
    when not defined(headless):
      supported.excl HeadlessTickRateFlag
    common.rejectUnsupportedFlags(supported)
    common.validateGameOptions(0, "")
    if NameFlag in common.specifiedFlags and common.playerSlot == 0:
      raise newException(CrewriftError, "--name requires --player.")
  except ValueError as error:
    raise newException(CrewriftError, "Invalid option: " & error.msg)
  result.seed = common.seed
  result.seedSpecified = SeedFlag in common.specifiedFlags
  result.ticks = common.maximumTicks
  result.player = common.playerSlot.int - 1
  result.speed = common.speed
  result.soundMuted = common.soundMuted
  result.name = common.playerName
  result.record = common.recordPath
  result.replay = common.replayPath
  result.width = common.windowWidth
  result.height = common.windowHeight
  result.capture = common.capture
  result.botGroups = common.botGroups
  result.pauseOnStart = common.pauseOnStart
  result.vsync = common.vsync
  result.verbose = common.verbose
  result.headlessTickRate = common.headlessTickRate
  if result.players < MinPlayers or result.players > MaxPlayers or
    result.player < -1 or result.player >= result.players or
    result.ticks < 1 or result.ticks > 1_000_000 or
    result.captureTicks < 0 or result.captureTicks > 1_000_000 or
    result.speed <= 0 or result.width <= 0 or result.height <= 0:
      raise newException(CrewriftError, "Invalid roster, time, or window size.")
  if result.role notin ["", "crew", "imp"]:
    raise newException(CrewriftError, "Role must be crew or imp.")
  if result.role.len > 0 and result.player < 0:
    raise newException(CrewriftError, "--role requires --player.")
  if result.name.len > 128 or result.name != cleanChatMessage(result.name):
    raise newException(CrewriftError, "Player name must be printable text.")
  try:
    result.capture.validateCapture()
  except ScreenshotError as error:
    raise newException(CrewriftError, error.msg)
  if result.capture.captureRequested():
    result.soundMuted = true
  result.validateBots()

proc loadBotSources(game: Game, options: Options) =
  ## Caches source and roster names so rewinding never reopens policy files.
  options.validateBots()
  game.botSources = newSeq[string](options.players)
  game.recording.playerNames = newSeq[string](options.players)
  for slot in 0 ..< options.players:
    if slot == options.player:
      game.recording.playerNames[slot] =
        if options.name.len > 0: options.name else: "You"
    else:
      game.botSources[slot] = DefaultBotSource
      game.recording.playerNames[slot] = DefaultBotName
  var slot = 0
  for group in options.botGroups:
    var source: string
    try:
      source = readPolicyBytes(group.path)
    except PolicyError as error:
      raise newException(CrewriftError, error.msg)
    if source.isPackage():
      raise newException(CrewriftError,
        "Crewrift bots require plain BASIC source: " & group.path)
    if source.len == 0:
      raise newException(CrewriftError,
        "BASIC source is empty: " & group.path)
    let name = group.path[group.path.rfind({'/', '\\'}) + 1 .. ^1]
    if name.len == 0 or name.len > 128 or name != cleanChatMessage(name):
      raise newException(CrewriftError,
        "Bot filename must be printable text up to 128 bytes.")
    for _ in 0 ..< group.count:
      if slot == options.player:
        inc slot
      game.botSources[slot] = source
      game.recording.playerNames[slot] = name
      inc slot

proc rewind*(game: Game) =
  ## Restores the resolved match setup while retaining the input tape.
  var config = game.recording.config
  config.minPlayers = game.recording.players
  game.world = initSimServer(config, resolveSeed = false)
  game.world.fitStations()
  game.world.gameEventLoggingEnabled = false
  for i in 0 ..< config.minPlayers:
    discard game.world.addPlayer("crew " & $(i + 1))
  game.world.startGame()
  game.ship = game.world.buildShipMap()
  game.nav = Navigator(layer: game.ship.layer)
  if game.playback:
    game.bots = newSeq[Bot](config.minPlayers)
  else:
    try:
      game.bots = initBots(game.botSources, game.world.config.seed)
    except BasicError as error:
      raise newException(CrewriftError, "Cannot load BASIC bot: " & error.msg)
  game.previous = newSeq[InputState](config.minPlayers)
  game.input = InputState()
  game.choice = -1
  game.chat.setLen(0)
  game.frame = 0

proc newGame*(options: Options): Game =
  ## Creates one full roster and starts the original role reveal.
  result = Game(choice: -1)
  var config = defaultGameConfig()
  config.seed = options.seed
  config.minPlayers = options.players
  config.maxTicks = options.ticks
  if options.role.len > 0 and options.player >= 0:
    config.slots.setLen(options.players)
    config.slots[options.player].hasRole = true
    config.slots[options.player].role =
      if options.role == "imp": Imposter else: Crewmate
  if options.replay.len > 0:
    result.recording = loadReplay(options.replay)
    result.playback = true
  else:
    if not options.seedSpecified:
      config.resolveRandomSeed()
    result.recording = ReplayData(
      version: ReplayVersion, config: config,
      players: config.minPlayers
    )
    result.loadBotSources(options)
  result.rewind()
  result.recording.config = result.world.config
  if options.verbose:
    echo "Crewrift setup: ", result.world.players.len, " players, seed ",
      result.world.config.seed, ", human slot ", options.player + 1,
      ", replay ", result.playback

proc rosterName*(game: Game, slot: int): string =
  ## Labels each crew color with its recorded human or policy identity.
  let
    order = game.world.players[slot].joinOrder
    identity =
      if order < game.recording.playerNames.len:
        game.recording.playerNames[order]
      else: "Unknown"
  playerColorText(game.world.players[slot].color).capitalizeAscii() &
    " (" & identity & ")"

proc finished*(game: Game): bool =
  ## Returns whether the match or the complete replay has ended.
  if game.playback:
    game.frame >= game.recording.frames.len
  else:
    game.world.phase == GameOver

proc playerKills*(world: SimServer, slot: int): int =
  ## Reads the current match kill count from the crew member's reward account.
  for account in world.rewardAccounts:
    if account.slotIndex == world.players[slot].joinOrder:
      return account.kills

proc advance*(game: Game, player = -1, record = false) =
  ## Applies all player and bot commands before one authoritative tick.
  if game.finished():
    return
  var
    inputs = newSeq[InputState](game.world.players.len)
    frame: ReplayFrame
  let history = game.frame < game.recording.frames.len
  if not game.playback:
    for i in 0 ..< inputs.len:
      var
        choice = -1
        chat: string
      if i == player:
        inputs[i] = game.input
        if not history:
          if game.choice >= 0 and game.world.phase == Voting:
            choice = game.choice
            inputs[i].attack = not game.previous[i].attack
            if inputs[i].attack:
              game.choice = -1
          chat = cleanChatMessage(game.chat)
          game.chat.setLen(0)
      else:
        inputs[i] = game.bots[i].decideBot(
          game.nav, game.world, i, game.previous[i]
        )
        choice = game.bots[i].choice
        chat = cleanChatMessage(game.bots[i].chat)
        game.bots[i].choice = -1
        game.bots[i].chat.setLen(0)
      frame.actions.add ReplayAction(
        kind: InputAction, slot: i, mask: inputs[i].inputMask()
      )
      if choice >= 0:
        frame.actions.add ReplayAction(
          kind: VoteAction, slot: i, choice: choice
        )
      if chat.len > 0:
        frame.actions.add ReplayAction(kind: ChatAction, slot: i, text: chat)
  if history:
    frame = game.recording.frames[game.frame]
  for action in frame.actions:
    case action.kind
    of InputAction:
      inputs[action.slot] = readInput(action.mask)
    of VoteAction:
      if game.world.phase == Voting:
        game.world.voteState.cursor[action.slot] = action.choice
    of ChatAction:
      game.world.addVotingChat(action.slot, action.text)
  # Button snapshots are applied simultaneously after ordered side effects.
  game.world.step(inputs, game.previous)
  game.previous = inputs
  if history:
    game.world.verifyFrame(frame)
  elif record:
    frame.hash = game.world.gameHash().toHex(16)
    game.recording.frames.add frame
  inc game.frame

proc runHeadless*(options: Options) =
  ## Runs local policies or verifies all recorded simulation ticks.
  let game = newGame(options)
  var pacer = initTickPacer(options.headlessTickRate)
  while not game.finished():
    game.advance(record = options.record.len > 0)
    pacer.pace()
  saveReplay(options.record, game.recording)
  let outcome =
    if game.world.phase != GameOver: "partial replay"
    elif game.world.timeLimitReached: "time limit"
    elif game.world.winner == Crewmate: "crew win"
    else: "imposter win"
  echo "Crewrift: ", outcome, ", tick ", game.world.tickCount,
    ", tasks left ", game.world.totalTasksRemaining()
  echo "Hash: ", game.world.gameHash().toHex(16)
  if game.playback:
    echo "Replay verified: ", game.frame, " ticks matched."
