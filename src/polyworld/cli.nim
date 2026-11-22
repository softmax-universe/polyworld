## Shared launch options for native Polyworld games.
## Games delegate common arguments here and reject unsupported capabilities.

import
  std/[os, strutils],
  configs, screenshots

from std/unicode import validateUtf8

export configs, screenshots

type
  CliError* = object of ValueError

  CommonFlag* = enum
    BotFlag, PlayerFlag, NameFlag, ReplayFlag, RecordFlag, SeedFlag,
    PlayFlag, SpeedFlag, WindowSizeFlag, VsyncFlag, SecondsFlag,
    MinutesFlag, TicksFlag, SoundFlag, VerboseFlag, HeadlessTickRateFlag,
    LlmModeFlag, ScreenshotFlag, FramesFlag, ServerFlag, RoomFlag

  BotGroup* = object
    path*: string
    count*: int

  GameOptions* = object
    specifiedFlags*: set[CommonFlag]
    capture*: ScreenshotOptions
    botGroups*: seq[BotGroup]
    replayPath*: string
    recordPath*: string
    playerName*: string
      ## Display name, separate from the controlled player slot.
    serverUrl*: string
    roomCode*: string
    seed*: int32
    tickRate*: int32 = SharedTickRate
      ## Simulation ticks per second, configured by the game, not the command line.
    seconds*: int32
      ## Duration in seconds, kept in sync with `maximumTicks`.
    maximumTicks*: int32
      ## Match length in simulation ticks, set by all three duration flags.
    speed*: int32 = 1
      ## Graphical simulation speed multiplier.
    verbose*: bool
    viewMode*: int32
      ## Spectator fog: 0 omniscient, 1 first side, 2 second side.
    spawnIntervalTicks*: int32
    pauseOnStart*: bool
      ## Graphical transport starts paused when true.
    windowWidth*: int32
      ## Graphical window width. Zero keeps the shared default.
    windowHeight*: int32
      ## Graphical window height. Zero keeps the shared default.
    vsync*: bool = true
    soundMuted*: bool
      ## Explicit launch mute choice, applied only when soundOverride is set.
    soundOverride*: bool
      ## False restores saved audio levels without imposing a launch choice.
    playerSlot*: int32
      ## One-based human controller slot. Zero means bots fill every slot.
    headlessTickRate*: int32
      ## Zero runs at unlimited speed; positive values pace wall-clock ticks.
    waitForLlm*: bool
      ## Waits for the whole tick's LLM request batch before advancing.

const
  AllCommonFlags* = {low(CommonFlag) .. high(CommonFlag)}
  DurationFlags* = {SecondsFlag, MinutesFlag, TicksFlag}
  GraphicalFlags* = {
    PlayerFlag, NameFlag, PlayFlag, SpeedFlag, WindowSizeFlag, VsyncFlag,
    ScreenshotFlag, FramesFlag
  }
  CommonNames: array[CommonFlag, string] = [
    "--bot", "--player", "--name", "--replay", "--record", "--seed",
    "--play", "--speed", "--windowSize", "--vsync", "--seconds",
    "--minutes", "--ticks", "--mute", "--verbose", "--headless-tick-rate",
    "--llm-mode", "--screenshot", "--frames", "--server", "--room"
  ]
  CommonHelp: array[CommonFlag, string] = [
    "  --bot PATH[:N]       Add N bots from a program; repeatable (--bots also works).",
    "  --player [N]         Control slot N, one-based; bare --player selects slot 1.",
    "  --name TEXT          Set the human player's display name.",
    "  --replay PATH        Load a recorded match instead of running bots.",
    "  --record PATH        Save this match's replay to PATH.",
    "  --seed N             Set the signed 32-bit random seed.",
    "  --play [BOOL]        Start playing or paused (default true).",
    "  --speed N            Set the positive integer playback speed (default 1).",
    "  --windowSize WxH     Set the graphical window dimensions.",
    "  --vsync [BOOL]       Wait for the display refresh (default true).",
    "  --seconds N          Limit the match to N simulation seconds.",
    "  --minutes N          Limit the match to N simulation minutes.",
    "  --ticks N            Limit the match to N simulation ticks.",
    "  --mute [BOOL]        Mute launch audio; --unmute restores sound.",
    "  --verbose [BOOL]     Enable verbose output (default false).",
    "  --headless-tick-rate N  Pace headless ticks per second; 0 is unlimited.",
    "  --llm-mode MODE      Use async or barrier LLM requests (default async).",
    "  --screenshot PATH    Save one native screenshot and exit.",
    "  --frames N           Capture the Nth rendered frame (default 30).",
    "  --server URL         Set the multiplayer relay address.",
    "  --room CODE          Select a multiplayer room (--join also works)."
  ]

func commonUsageFor*(supported: set[CommonFlag]): string =
  ## Lists the shared syntax for the capabilities implemented by one game.
  for flag in CommonFlag:
    if flag in supported:
      result.add CommonHelp[flag] & "\n"
  result.add "Values accept --flag VALUE, --flag=VALUE, or --flag:VALUE.\n"

const CommonUsage* = commonUsageFor(AllCommonFlags)

proc fail*(message: string) {.noreturn.} =
  ## Prints one command-line error and exits at a game launcher boundary.
  quit(message)

proc cliFail(message: string) {.noreturn.} =
  ## Raises one catchable argument error without terminating an embedding process.
  raise newException(CliError, message)

proc splitFlag*(argument: string): tuple[name, value: string, attached: bool] =
  ## Splits the first attached-value separator without splitting path contents.
  let separator = argument.find({'=', ':'})
  if separator < 0:
    return (argument, "", false)
  (argument[0 ..< separator], argument[separator + 1 .. ^1], true)

proc argumentValue*(
  arguments: openArray[string], index: var int, name: string
): string =
  ## Consumes a required separate value without consuming another option.
  if index + 1 >= arguments.len or arguments[index + 1].startsWith("--") or
    arguments[index + 1].len == 0:
      cliFail(name & " requires a value")
  inc index
  arguments[index]

proc flagValue*(
  arguments: openArray[string], index: var int, argument: string
): string =
  ## Reads a required value in separate, equals, or colon form.
  let flag = splitFlag(argument)
  if not flag.attached:
    return arguments.argumentValue(index, flag.name)
  if flag.value.len == 0:
    cliFail(flag.name & " requires a value")
  flag.value

proc parseInt32*(text, name: string): int32 =
  ## Parses one signed 32-bit integer flag value.
  var value: int64
  try:
    value = parseBiggestInt(text)
  except ValueError:
    cliFail(name & " must be an integer")
  if value < int32.low or value > int32.high:
    cliFail(name & " must fit int32")
  int32(value)

proc parsePositiveInt32*(text, name: string): int32 =
  ## Parses one integer flag value that must be greater than zero.
  result = parseInt32(text, name)
  if result <= 0:
    cliFail(name & " must be positive")

proc addBotSpec*(groups: var seq[BotGroup], specification: string) =
  ## Parses one program path with an optional positive instance count.
  if specification.len == 0:
    cliFail("--bot requires a path")
  var
    path = specification
    count = 1
  let
    separator = specification.rfind(':')
    driveColon = separator == 1 and specification[0] in {'a' .. 'z', 'A' .. 'Z'}
  if separator >= 0 and not driveColon:
    path = specification[0 ..< separator]
    count = parsePositiveInt32(
      specification[separator + 1 .. ^1], "--bot count"
    ).int
  if path.len == 0:
    cliFail("--bot requires a path")
  groups.add BotGroup(path: path, count: count)

proc botCount*(groups: openArray[BotGroup]): int =
  ## Counts configured instances while rejecting invalid or overflowing totals.
  for group in groups:
    if group.count <= 0 or group.count > int32.high - result:
      cliFail("--bot count must total between 1 and " & $int32.high)
    result += group.count

proc botSources*(
  groups: openArray[BotGroup], count: static int
): array[count, string] =
  ## Loads and expands bot files into one source string per slot.
  var slot = 0
  for group in groups:
    let source = readFile(group.path)
    for _ in 0 ..< group.count:
      if slot >= count:
        cliFail("too many bots to expand")
      result[slot] = source
      inc slot
  if slot != count:
    cliFail("bot files do not fill every slot")

proc parseWindowSize*(text, name: string): (int32, int32) =
  ## Parses one positive `WIDTHxHEIGHT` window size.
  let separator = text.find({'x', 'X'})
  if separator <= 0 or separator >= text.high:
    cliFail(name & " must look like 800x400")
  (
    parsePositiveInt32(text[0 ..< separator], name),
    parsePositiveInt32(text[separator + 1 .. ^1], name)
  )

proc simulationTickRate(options: GameOptions): int32 =
  ## Uses the game's configured rate, including zero-initialized nested options.
  if options.tickRate < 0:
    cliFail("simulation tick rate must be positive")
  if options.tickRate == 0: SharedTickRate else: options.tickRate

proc ticksFromCount(count: int32, scale: int64, name: string): int32 =
  ## Converts a positive count into ticks without overflowing the stored range.
  if scale <= 0 or count.int64 > int32.high.int64 div scale:
    cliFail(name & " is too large")
  int32(count.int64 * scale)

proc setMaximumTicks*(options: var GameOptions, ticks: int32) =
  ## Writes the canonical duration using this game's simulation tick rate.
  options.maximumTicks = ticks
  options.seconds = ticks div options.simulationTickRate()

proc parseBoolean(text, name: string): bool =
  ## Parses the same explicit boolean vocabulary for every common switch.
  case text.strip().toLowerAscii()
  of "true", "1", "yes", "on": true
  of "false", "0", "no", "off": false
  else: cliFail(name & " must be true or false")

proc optionalValue(
  arguments: openArray[string], index: var int, argument, fallback: string
): string =
  ## Reads an optional value while leaving the next option for its own parser.
  let flag = splitFlag(argument)
  if flag.attached:
    return arguments.flagValue(index, argument)
  if index + 1 < arguments.len and not arguments[index + 1].startsWith("--"):
    return arguments.argumentValue(index, flag.name)
  fallback

proc takeSoundFlag*(soundMuted: var bool, argument: string): bool =
  ## Reads a standalone audio flag for callers that do not own an argument loop.
  let flag = splitFlag(argument)
  if flag.name notin ["--mute", "--unmute"]:
    return false
  let enabled =
    if flag.attached: parseBoolean(flag.value, flag.name)
    else: true
  soundMuted = if flag.name == "--mute": enabled else: not enabled
  true

proc takeCommonFlag*(
  options: var GameOptions, arguments: openArray[string],
  index: var int, argument: string
): bool =
  ## Handles one common flag and records its capability without consuming unknowns.
  try:
    if options.capture.takeCaptureFlag(arguments, index, argument):
      let flag = splitFlag(argument).name
      options.specifiedFlags.incl(
        if flag == "--frames": FramesFlag else: ScreenshotFlag
      )
      return true
    if takeWindowSizeFlag(
      options.windowWidth, options.windowHeight, arguments, index, argument
    ):
      options.specifiedFlags.incl WindowSizeFlag
      return true
  except ScreenshotError as error:
    cliFail(error.msg)
  let flag = splitFlag(argument)
  template value(): string =
    ## Reads the current required argument at its original position.
    arguments.flagValue(index, argument)
  template optional(fallback: string): string =
    ## Reads the current optional argument without consuming the next option.
    arguments.optionalValue(index, argument, fallback)
  case flag.name
  of "--":
    return not flag.attached
  of "--bot", "--bots":
    options.botGroups.addBotSpec(value())
    options.specifiedFlags.incl BotFlag
  of "--player":
    if PlayerFlag in options.specifiedFlags:
      cliFail("only one --player allowed")
    let text = optional("1")
    try:
      options.playerSlot = parsePositiveInt32(text, "--player")
    except CliError:
      cliFail("--player requires a positive slot number; " &
        "use --name for a display name")
    options.specifiedFlags.incl PlayerFlag
  of "--name":
    let raw = value()
    if validateUtf8(raw) >= 0:
      cliFail("--name must contain valid UTF-8")
    for character in raw:
      if character < ' ' or character == '\x7f':
        cliFail("--name cannot contain control characters")
    let name = raw.strip()
    if name.len == 0 or name.len > 64:
      cliFail("--name requires a nonempty display name of at most 64 bytes")
    options.playerName = name
    options.specifiedFlags.incl NameFlag
  of "--replay":
    options.replayPath = value()
    options.specifiedFlags.incl ReplayFlag
  of "--record":
    options.recordPath = value()
    options.specifiedFlags.incl RecordFlag
  of "--seed":
    options.seed = parseInt32(value(), flag.name)
    options.specifiedFlags.incl SeedFlag
  of "--play":
    options.pauseOnStart = not parseBoolean(optional("true"), flag.name)
    options.specifiedFlags.incl PlayFlag
  of "--speed":
    options.speed = parsePositiveInt32(value(), flag.name)
    options.specifiedFlags.incl SpeedFlag
  of "--vsync":
    options.vsync = parseBoolean(optional("true"), flag.name)
    options.specifiedFlags.incl VsyncFlag
  of "--seconds", "--minutes", "--ticks":
    let count = parsePositiveInt32(value(), flag.name)
    case flag.name
    of "--seconds":
      options.setMaximumTicks(ticksFromCount(
        count, options.simulationTickRate(), flag.name
      ))
      options.specifiedFlags.incl SecondsFlag
    of "--minutes":
      options.setMaximumTicks(ticksFromCount(
        count, 60'i64 * options.simulationTickRate(), flag.name
      ))
      options.specifiedFlags.incl MinutesFlag
    else:
      options.setMaximumTicks(count)
      options.specifiedFlags.incl TicksFlag
  of "--mute", "--unmute":
    let enabled = parseBoolean(optional("true"), flag.name)
    options.soundMuted = if flag.name == "--mute": enabled else: not enabled
    options.soundOverride = true
    options.specifiedFlags.incl SoundFlag
  of "--verbose":
    options.verbose = parseBoolean(optional("true"), flag.name)
    options.specifiedFlags.incl VerboseFlag
  of "--headless-tick-rate":
    let rate = parseInt32(value(), flag.name)
    if rate < 0 or rate > 10000:
      cliFail("--headless-tick-rate must be 0 .. 10000")
    options.headlessTickRate = rate
    options.specifiedFlags.incl HeadlessTickRateFlag
  of "--llm-mode":
    case value().toLowerAscii()
    of "async": options.waitForLlm = false
    of "barrier": options.waitForLlm = true
    else: cliFail("--llm-mode must be async or barrier")
    options.specifiedFlags.incl LlmModeFlag
  of "--server":
    options.serverUrl = value()
    options.specifiedFlags.incl ServerFlag
  of "--room", "--join":
    options.roomCode = value()
    options.specifiedFlags.incl RoomFlag
  else:
    return false
  true

proc rejectUnsupportedFlags*(
  options: GameOptions, supported: set[CommonFlag]
) =
  ## Rejects explicit unsupported requests, including false and zero-valued flags.
  for flag in options.specifiedFlags - supported:
    cliFail(CommonNames[flag] & " is not supported by this game")

proc resolveGamePaths*(options: var GameOptions) =
  ## Resolves launch paths before a game changes its working directory.
  if options.replayPath.len > 0:
    options.replayPath = absolutePath(options.replayPath)
  if options.recordPath.len > 0:
    options.recordPath = absolutePath(options.recordPath)
  for group in options.botGroups.mitems:
    group.path = absolutePath(group.path)

proc validateHeadlessOptions*(options: GameOptions) =
  ## Rejects visual controls in compiled or runtime headless launch modes.
  if options.playerSlot != 0:
    cliFail("--player requires the graphical client")
  for flag in options.specifiedFlags * GraphicalFlags:
    cliFail(CommonNames[flag] & " requires the graphical client")

proc validateGameOptions*(
  options: GameOptions, liveSlotCount = 0, liveBotMessage = ""
) =
  ## Checks replay exclusivity, graphical human control, and the live-game roster.
  try:
    options.capture.validateCapture()
  except ScreenshotError as error:
    cliFail(error.msg)
  when defined(headless):
    options.validateHeadlessOptions()
  discard options.botGroups.botCount
  if options.replayPath.len > 0:
    if options.botGroups.len > 0:
      cliFail("--replay cannot be used with --bot")
    if options.playerSlot != 0:
      cliFail("--replay cannot be used with --player")
    if options.recordPath.len > 0:
      cliFail("--replay cannot be recorded again")
    for flag in options.specifiedFlags * (DurationFlags + {SeedFlag}):
      cliFail("--replay cannot be used with " & CommonNames[flag])
  elif liveSlotCount > 0:
    if options.playerSlot != 0 and
      (options.playerSlot < 1 or options.playerSlot > liveSlotCount):
        cliFail("--player must be between 1 and " & $liveSlotCount)
    let
      needed = if options.playerSlot != 0: liveSlotCount - 1 else: liveSlotCount
      count = options.botGroups.botCount
    if count != needed:
      if options.playerSlot != 0:
        cliFail("live games with --player require " & $needed &
          " bots; configured " & $count)
      cliFail(liveBotMessage & "; configured " & $count)
