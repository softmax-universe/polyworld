## Match setup, local controls, fixed ticks, and headless play.

import
  std/[os, strutils],
  bassy,
  polyworld/[cli, policies],
  sim, maps, bots, replays

type
  Options* = object
    seed*, players*, ticks*, player*: int
    speed*: float32
    soundMuted*: bool = true
    role*, name*, record*, replay*, screenshot*: string
    width*, height*, captureTicks*: int
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
  echo "  WASD: move or select vote. E / Space: use, kill, vote."
  echo "  Arrows / middle / right drag: pan. Wheel: zoom. C: action camera."
  echo "  Click / shift-click / box select: follow crew. Ctrl+A: select all."
  echo "  Q: vent. Enter: meeting chat. Tab: map. R: new match."
  echo "  --player:N        Control slot N (1-16, default 1)."
  echo "  --name:NAME       Human player's name in the roster and replay."
  echo "  --spectate        Let local bots play every slot."
  echo "  --bot PATH[:N]    Use a BASIC program for N bot slots (default 1)."
  echo "  --bot:PATH[:N]    Equivalent compact form; other slots use base.bas."
  echo "  --role:crew|imp   Choose your role, or omit for random roles."
  echo "  --players:N       Roster size (8-16, default 8)."
  echo "  --seed:N          Match seed (default 2026)."
  echo "  --ticks:N         Maximum active ticks (default 10000)."
  echo "  --speed:N         Simulation speed (default 1)."
  echo "  --record:PATH     Save an input replay with tick fingerprints."
  echo "  --replay:PATH     Play and verify a saved input replay."
  echo "  --windowSize:WxH  Window size (default 1440x900)."
  echo "  --screenshot:PATH Save a frame and exit."
  echo "  --mute[=BOOL]     Start muted (default true)."
  echo "  --unmute          Start with sound enabled."
  echo "Compile with -d:headless to run and verify without graphics."

proc addBotOption(groups: var seq[BotGroup], specification: string) =
  ## Validates the shared bot syntax using Crewrift's error boundary.
  var path = specification
  let separator = specification.rfind(':')
  if separator >= 0 and separator < specification.high:
    let suffix = specification[separator + 1 .. ^1]
    var numeric = true
    for character in suffix:
      if character notin {'0' .. '9'}:
        numeric = false
        break
    if numeric:
      path = specification[0 ..< separator]
      let count = parseBiggestInt(suffix)
      if count < 1 or count > MaxPlayers:
        raise newException(CrewriftError,
          "Bot count must be between 1 and " & $MaxPlayers & ".")
  if path.len == 0:
    raise newException(CrewriftError, "--bot requires a BASIC source path.")
  groups.addBotSpec(specification)

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

proc parseOptions*(arguments = commandLineParams()): Options =
  ## Parses the shared native and headless command surface.
  result = Options(
    seed: 2026, players: MinPlayers, ticks: MaxTicks,
    player: 0, speed: 1, width: 1440, height: 900,
    captureTicks: RoleRevealTicks + 12
  )
  when defined(headless):
    result.player = -1
  var index = 0
  while index < arguments.len:
    let argument = arguments[index]
    inc index
    let
      parts = argument.split(':', 1)
      flag = parts[0]
      value = if parts.len > 1: parts[1] else: ""
    try:
      if result.soundMuted.takeSoundFlag(argument):
        continue
      if argument == "--bot":
        if index >= arguments.len:
          raise newException(CrewriftError,
            "--bot requires a BASIC source path.")
        result.botGroups.addBotOption(arguments[index])
        inc index
        continue
      if argument.startsWith("--bot="):
        result.botGroups.addBotOption(argument[6 .. ^1])
        continue
      case flag
      of "--bot": result.botGroups.addBotOption(value)
      of "--seed": result.seed = parseInt(value)
      of "--players": result.players = parseInt(value)
      of "--ticks": result.ticks = parseInt(value)
      of "--player": result.player = parseInt(value) - 1
      of "--name": result.name = value.strip()
      of "--spectate": result.player = -1
      of "--speed": result.speed = parseFloat(value).float32
      of "--role": result.role = value
      of "--record": result.record = value
      of "--replay": result.replay = value
      of "--screenshot": result.screenshot = value
      of "--capture-ticks": result.captureTicks = parseInt(value)
      of "--windowSize":
        let size = value.toLowerAscii().split('x')
        if size.len != 2:
          raise newException(CrewriftError, "Expected --windowSize:WxH.")
        result.width = parseInt(size[0])
        result.height = parseInt(size[1])
      of "--help", "-h":
        usage()
        quit(0)
      else:
        raise newException(CrewriftError, "Unknown argument: " & argument)
    except ValueError as error:
      raise newException(CrewriftError, "Invalid option: " & error.msg)
  if result.seed < RandomSeedSentinel or
    result.players < MinPlayers or result.players > MaxPlayers or
    result.player < -1 or result.player >= result.players or
    result.ticks < 1 or result.ticks > 1_000_000 or
    result.captureTicks < 0 or result.captureTicks > 1_000_000 or
    not (result.speed > 0 and result.speed <= 16) or
    result.width < 800 or result.height < 600:
      raise newException(CrewriftError, "Invalid roster, time, or window size.")
  if result.role notin ["", "crew", "imp"]:
    raise newException(CrewriftError, "Role must be crew or imp.")
  if result.record.len > 0 and result.replay.len > 0:
    raise newException(CrewriftError, "Choose recording or replay playback.")
  if result.name.len > 128 or result.name != cleanChatMessage(result.name):
    raise newException(CrewriftError, "Player name must be printable text.")
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
  game.world = initSimServer(config)
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
    result.recording = ReplayData(
      version: ReplayVersion, config: config,
      players: config.minPlayers
    )
    result.loadBotSources(options)
  result.rewind()
  result.recording.config = result.world.config

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
  while not game.finished():
    game.advance(record = options.record.len > 0)
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
