import
  std/[os, strutils],
  polyworld/cli

proc parseCommon(
    arguments: seq[string],
    liveBotCount = 0,
    liveBotMessage = "",
    defaults = GameOptions(seed: 2026)
): GameOptions =
  ## Parses only shared flags, the same way a game loop would.
  result = defaults
  var index = 0
  while index < arguments.len:
    let argument = arguments[index]
    if not result.takeCommonFlag(arguments, index, argument):
      doAssert false, "unexpected argument: " & argument
    inc index
  result.validateGameOptions(liveBotCount, liveBotMessage)

echo "Testing independent pacing and barrier controls"
block:
  let defaults = parseCommon(@[])
  doAssert not defaults.waitForLlm
  doAssert defaults.headlessTickRate == 0
  for flags in [
    @["--headless-tick-rate:24", "--llm-mode:barrier"],
    @["--headless-tick-rate=24", "--llm-mode=barrier"],
    @["--headless-tick-rate", "24", "--llm-mode", "barrier"]
  ]:
    let options = parseCommon(flags)
    doAssert options.waitForLlm
    doAssert options.headlessTickRate == 24
  let disabled = parseCommon(@["--llm-mode:async"])
  doAssert not disabled.waitForLlm

echo "Testing bot path and count parsing"
block:
  var groups: seq[BotGroup]
  groups.addBotSpec("bots/base.bas")
  groups.addBotSpec("bots/other.bas:3")
  doAssert groups.len == 2
  doAssert groups[0].path == "bots/base.bas"
  doAssert groups[0].count == 1
  doAssert groups[1].path == "bots/other.bas"
  doAssert groups[1].count == 3
  doAssert groups.botCount == 4

echo "Testing that a trailing colon count does not eat Windows drives"
block:
  var groups: seq[BotGroup]
  groups.addBotSpec("C:\\bots\\base.bas")
  doAssert groups[0].path == "C:\\bots\\base.bas"
  doAssert groups[0].count == 1
  groups.addBotSpec("C:\\bots\\base.bas:2")
  doAssert groups[1].path == "C:\\bots\\base.bas"
  doAssert groups[1].count == 2

echo "Testing shared flags and defaults"
block:
  let options = parseCommon(
    @["--seed", "7", "--record", "out.replay"]
  )
  doAssert options.seed == 7
  doAssert options.recordPath == "out.replay"
  doAssert options.replayPath.len == 0
  doAssert options.botGroups.len == 0

echo "Testing --bot compact and split forms"
block:
  let options = parseCommon(
    @["--bot:one.bas:2", "--bot", "two.bas"],
    liveBotCount = 3,
    liveBotMessage = "need three bots"
  )
  doAssert options.botGroups.len == 2
  doAssert options.botGroups.botCount == 3
  doAssert options.botGroups[0].path == "one.bas"
  doAssert options.botGroups[1].path == "two.bas"

echo "Testing that unknown flags stay with the game"
block:
  var
    options = GameOptions(seed: 2026)
    index = 0
  doAssert not options.takeCommonFlag(@["--view"], index, "--view")
  doAssert not options.takeCommonFlag(@["--help"], index, "--help")
  doAssert not options.takeCommonFlag(@["--custom"], index, "--custom")
  doAssert index == 0

echo "Testing extra flags in the same loop as shared ones"
block:
  var
    options = GameOptions(seed: 2026, maximumTicks: 100)
    arguments = @["--seed", "9", "--custom-verbose"]
    index = 0
    verbose = false
  while index < arguments.len:
    let argument = arguments[index]
    if options.takeCommonFlag(arguments, index, argument):
      discard
    else:
      case argument
      of "--custom-verbose":
        verbose = true
      else:
        doAssert false, "unexpected argument: " & argument
    inc index
  doAssert options.seed == 9
  doAssert verbose

echo "Testing duration flags write maximumTicks"
block:
  var options = parseCommon(@["--minutes", "20"])
  doAssert options.maximumTicks == DefaultDurationTicks
  doAssert options.seconds == DefaultMinutes * 60
  options = parseCommon(@["--seconds", "60"])
  doAssert options.maximumTicks == 60 * SharedTickRate
  doAssert options.seconds == 60
  options = parseCommon(@["--ticks", "28800"])
  doAssert options.maximumTicks == 28800
  options = parseCommon(@["--minutes=5"])
  doAssert options.maximumTicks == 5 * 60 * SharedTickRate
  options = parseCommon(@["--seconds=90"])
  doAssert options.maximumTicks == 90 * SharedTickRate
  options = parseCommon(@["--ticks=480"])
  doAssert options.maximumTicks == 480

echo "Testing that a leading -- is ignored"
block:
  let options = parseCommon(
    @["--", "--bot:one.bas"],
    liveBotCount = 1,
    liveBotMessage = "need one bot"
  )
  doAssert options.botGroups[0].path == "one.bas"

echo "Testing bot source expansion"
block:
  let path = getTempDir() / "polyworld_cli_bot.bas"
  writeFile(path, "PRINT 1\n")
  var groups: seq[BotGroup]
  groups.addBotSpec(path & ":2")
  let sources = groups.botSources(2)
  doAssert sources[0] == "PRINT 1\n"
  doAssert sources[1] == "PRINT 1\n"
  removeFile(path)

echo "Testing --play=false starts the transport paused"
block:
  when not defined(headless):
    let paused = parseCommon(@["--play=false", "--bot:one.bas"])
    doAssert paused.pauseOnStart
    let playing = parseCommon(@["--play=true", "--bot:one.bas"])
    doAssert not playing.pauseOnStart

echo "Testing --speed is a shared flag"
block:
  when not defined(headless):
    let options = parseCommon(@["--speed", "4", "--bot:one.bas"])
    doAssert options.speed == 4
    let compact = parseCommon(@["--speed=16", "--bot:one.bas"])
    doAssert compact.speed == 16

echo "Testing --player occupies one slot"
block:
  when not defined(headless):
    let options = parseCommon(
      @["--player", "--bot:one.bas:9"],
      liveBotCount = 10,
      liveBotMessage = "need ten bots"
    )
    doAssert options.playerSlot == 1
    doAssert options.botGroups.botCount == 9

echo "Testing --player:N compact and equals forms"
block:
  when not defined(headless):
    let compact = parseCommon(
      @["--player:2", "--bot:one.bas:3"],
      liveBotCount = 4,
      liveBotMessage = "need four bots"
    )
    doAssert compact.playerSlot == 2
    let equals = parseCommon(
      @["--player=1", "--bot:one.bas"],
      liveBotCount = 2,
      liveBotMessage = "need two bots"
    )
    doAssert equals.playerSlot == 1

echo "Testing the first explicit player overrides configured defaults"
block:
  var
    options = GameOptions(playerSlot: 3)
    index = 0
  doAssert options.takeCommonFlag(@["--player", "2"], index, "--player")
  doAssert options.playerSlot == 2
  doAssert options.specifiedFlags == {PlayerFlag}
  index = 0
  var rejected = false
  try:
    discard options.takeCommonFlag(@["--player=1"], index, "--player=1")
  except CliError as error:
    rejected = "only one --player" in error.msg
  doAssert rejected

echo "Testing --vsync is on by default"
block:
  when not defined(headless):
    let options = parseCommon(@["--bot:one.bas"])
    doAssert options.vsync
    let off = parseCommon(@["--vsync:off", "--bot:one.bas"])
    doAssert not off.vsync
    let on = parseCommon(@["--vsync=on", "--bot:one.bas"])
    doAssert on.vsync
    let split = parseCommon(@["--vsync", "off", "--bot:one.bas"])
    doAssert not split.vsync

echo "Testing launch audio uses saved settings unless explicitly overridden"
block:
  let defaults = parseCommon(@[])
  doAssert not defaults.soundMuted
  doAssert not defaults.soundOverride
  for argument in ["--mute", "--mute=true", "--mute=1", "--mute=yes",
      "--mute=on", "--mute:true"]:
    let options = parseCommon(@["--unmute", argument])
    doAssert options.soundMuted and options.soundOverride
  for argument in ["--unmute", "--mute=false", "--mute=0", "--mute=no",
      "--mute=off", "--mute:false"]:
    let options = parseCommon(@["--mute", argument])
    doAssert not options.soundMuted and options.soundOverride
  doAssert parseCommon(@["--unmute", "--mute"]).soundMuted
  doAssert not parseCommon(@["--mute", "--unmute"]).soundMuted
  let options = parseCommon(@["--seed", "7", "--unmute", "--ticks", "24"])
  doAssert options.seed == 7 and options.maximumTicks == 24
  doAssert not options.soundMuted and options.soundOverride
  var soundMuted = true
  doAssert not soundMuted.takeSoundFlag("--music")
  doAssert soundMuted
  for invalid in ["--mute=", "--mute=loud", "--mute:maybe"]:
    var rejected = false
    try:
      discard soundMuted.takeSoundFlag(invalid)
    except ValueError:
      rejected = true
    doAssert rejected, "Invalid mute values must fail without enabling sound"
    doAssert soundMuted

echo "Testing --windowSize is a shared flag"
block:
  when not defined(headless):
    let options = parseCommon(@["--windowSize:800x400", "--bot:one.bas"])
    doAssert options.windowWidth == 800
    doAssert options.windowHeight == 400
    let split = parseCommon(@["--windowSize", "1024x576", "--bot:one.bas"])
    doAssert split.windowWidth == 1024
    doAssert split.windowHeight == 576
    let equals = parseCommon(@["--windowSize=1280x720", "--bot:one.bas"])
    doAssert equals.windowWidth == 1280
    doAssert equals.windowHeight == 720

echo "Testing all shared value forms describe identical options"
block:
  for (flag, value) in [
    ("--bot", "bots/base.bas:2"),
    ("--bots", "C:\\bots\\base.bas:2"),
    ("--name", "Ada Lovelace"),
    ("--replay", "replays/a match.replay"),
    ("--record", "replays/a match.replay"),
    ("--seed", "-7"),
    ("--play", "false"),
    ("--speed", "3"),
    ("--windowSize", "1234x768"),
    ("--vsync", "off"),
    ("--seconds", "2"),
    ("--minutes", "2"),
    ("--ticks", "2"),
    ("--mute", "false"),
    ("--unmute", "false"),
    ("--verbose", "false"),
    ("--headless-tick-rate", "0"),
    ("--llm-mode", "barrier"),
    ("--frames", "3"),
    ("--server", "ws://localhost:9911/ws"),
    ("--room", "123456"),
    ("--join", "123456")
  ]:
    when defined(headless):
      if flag in ["--name", "--play", "--speed", "--windowSize", "--vsync", "--frames"]:
        continue
    let separate = parseCommon(@[flag, value])
    for separator in ["=", ":"]:
      doAssert separate == parseCommon(@[flag & separator & value]), flag
  when not defined(headless):
    for (flag, value) in [("--player", "2"), ("--screenshot", "a shot.png")]:
      let separate = parseCommon(@[flag, value])
      for separator in ["=", ":"]:
        doAssert separate == parseCommon(@[flag & separator & value]), flag

proc rejects(arguments: seq[string], message: string,
    defaults = GameOptions(seed: 2026)) =
  ## Checks invalid launch requests without spawning processes or opening games.
  var rejected = false
  try:
    discard parseCommon(arguments, defaults = defaults)
  except CliError as error:
    rejected = true
    doAssert message in error.msg, error.msg
  doAssert rejected, "Expected a CLI error for " & $arguments

echo "Testing missing values do not consume the next option"
block:
  for flag in ["--bot", "--bots", "--name", "--replay", "--record", "--seed",
      "--speed", "--windowSize", "--seconds", "--minutes", "--ticks",
      "--headless-tick-rate", "--llm-mode", "--screenshot", "--frames",
      "--server", "--room", "--join"]:
    rejects(@[flag], "requires a value")
    rejects(@[flag & "="], "requires a value")
    rejects(@[flag & ":"], "requires a value")
    var
      options: GameOptions
      index = 0
    try:
      discard options.takeCommonFlag(@[flag, "--seed", "7"], index, flag)
      doAssert false
    except CliError:
      doAssert index == 0

echo "Testing common boolean defaults and explicit false values"
block:
  let defaults = parseCommon(@[])
  doAssert defaults.speed == 1 and defaults.vsync
  doAssert not defaults.pauseOnStart and not defaults.verbose
  doAssert defaults.specifiedFlags == {}
  let bare = parseCommon(@["--mute", "--verbose", "--seed", "9"])
  doAssert bare.soundMuted and bare.verbose and bare.seed == 9
  when not defined(headless):
    let visual = parseCommon(@["--play", "--vsync", "--seed", "9"])
    doAssert visual.vsync and not visual.pauseOnStart and visual.seed == 9
  doAssert parseCommon(@["--unmute=false"]).soundMuted
  doAssert not parseCommon(@["--verbose", "false"]).verbose
  for flag in ["--mute", "--unmute", "--verbose", "--play", "--vsync"]:
    rejects(@[flag & "="], "requires a value")
    rejects(@[flag & ":maybe"], "true or false")
    rejects(@[flag, "maybe"], "true or false")

echo "Testing invalid player names, slots, numbers, and bot counts"
block:
  rejects(@["--name", "  "], "nonempty display name")
  rejects(@["--name", repeat("n", 65)], "at most 64 bytes")
  for name in ["Ada\n", "\tAda", "A\x00da", "Ada\x7f"]:
    rejects(@["--name", name], "control characters")
  for name in ["\xff", "\xc3", "\xc0\xaf", "A\x80da"]:
    rejects(@["--name", name], "valid UTF-8")
  when not defined(headless):
    doAssert parseCommon(@["--name", "Игрок🌿"]).playerName == "Игрок🌿"
    doAssert parseCommon(@["--name", repeat("é", 32)]).playerName == repeat("é", 32)
  rejects(@["--name", repeat("é", 33)], "at most 64 bytes")
  rejects(@["--player", "Ada"], "use --name")
  rejects(@["--player=0"], "positive slot number")
  rejects(@["--player", "-1"], "positive slot number")
  rejects(@["--player", "--player"], "only one --player")
  rejects(@["--seed", "2147483648"], "fit int32")
  rejects(@["--seed", "9999999999999999999999999"], "integer")
  rejects(@["--speed", "0"], "positive")
  rejects(@["--headless-tick-rate", "-1"], "0 .. 10000")
  rejects(@["--headless-tick-rate", "10001"], "0 .. 10000")
  rejects(@["--llm-mode", "unknown"], "async or barrier")
  for count in ["0", "-1", "", "bad", "2147483648", "9999999999999999999"]:
    rejects(@["--bot", "bot.bas:" & count], "--bot count")
  rejects(@["--bots", ":2"], "requires a path")
  rejects(@["--bot", "a.bas:2147483647", "--bot", "b.bas"], "must total")
  doAssert parseCommon(@["--bot", "C:2"]).botGroups[0].path == "C:2"
  doAssert parseCommon(@["--headless-tick-rate", "10000"]).headlessTickRate == 10000
  when not defined(headless):
    doAssert parseCommon(@["--name", " Ada "]).playerName == "Ada"

echo "Testing replay incompatibilities and build restrictions"
block:
  rejects(@["--replay", "a.replay", "--bots", "base.bas"], "cannot be used with --bot")
  rejects(@["--replay", "a.replay", "--record", "b.replay"], "cannot be recorded")
  for flag in ["--seconds", "--minutes", "--ticks", "--seed"]:
    rejects(@["--replay", "a.replay", flag, "1"], "cannot be used with " & flag)
  when defined(headless):
    rejects(@["--player"], "requires the graphical client")
    rejects(@["--screenshot", "a.png"], "requires a native graphical client")
    for (flag, value) in [("--name", "Ada"), ("--play", "true"), ("--speed", "1"),
        ("--windowSize", "800x600"), ("--vsync", "false"), ("--frames", "1")]:
      rejects(@[flag, value], "requires the graphical client")
  else:
    rejects(@["--replay", "a.replay", "--player"], "cannot be used with --player")
    var rejected = false
    try:
      discard parseCommon(@["--player", "3", "--bot", "base.bas"], 2)
    except CliError as error:
      rejected = "between 1 and 2" in error.msg
    doAssert rejected

echo "Testing durations use each game's configured simulation rate"
block:
  for rate in [2'i32, 24'i32, 32'i32]:
    let defaults = GameOptions(tickRate: rate)
    doAssert parseCommon(@["--seconds", "3"], defaults = defaults).maximumTicks == 3 * rate
    doAssert parseCommon(@["--minutes:2"], defaults = defaults).maximumTicks == 120 * rate
    doAssert parseCommon(@["--ticks=96"], defaults = defaults).seconds == 96 div rate
    let last = parseCommon(@["--minutes=2", "--ticks", "96"], defaults = defaults)
    doAssert last.maximumTicks == 96 and last.seconds == 96 div rate
  rejects(@["--minutes", "2147483647"], "too large")
  rejects(@["--seconds", "2147483647"], "too large")
  let zeroRate = GameOptions(tickRate: 0)
  doAssert parseCommon(@["--seconds", "2"], defaults = zeroRate).maximumTicks == 2 * SharedTickRate

echo "Testing explicit capabilities remain visible even for false and zero"
block:
  let options = parseCommon(@["--verbose=false", "--headless-tick-rate=0", "--bots", "base.bas"])
  doAssert options.specifiedFlags == {VerboseFlag, HeadlessTickRateFlag, BotFlag}
  options.rejectUnsupportedFlags(AllCommonFlags)
  var rejected = false
  try:
    options.rejectUnsupportedFlags(AllCommonFlags - {VerboseFlag})
  except CliError as error:
    rejected = "--verbose is not supported" in error.msg
  doAssert rejected
  let help = commonUsageFor({BotFlag, RecordFlag})
  doAssert "--bot PATH" in help and "--record PATH" in help
  doAssert "--player" notin help and "--server" notin help
  doAssert "--play [BOOL]" in CommonUsage
  doAssert "--vsync [BOOL]" in CommonUsage
  doAssert parseCommon(@["--room", "123"]) == parseCommon(@["--join=123"])
  doAssert parseCommon(@["--bot", "base.bas:2"]) == parseCommon(@["--bots=base.bas:2"])

echo "Testing launch paths resolve before changes to the working directory"
block:
  var options = parseCommon(@["--bot", "bots/base.bas", "--record", "a match.replay"])
  options.resolveGamePaths()
  doAssert options.botGroups[0].path == absolutePath("bots/base.bas")
  doAssert options.recordPath == absolutePath("a match.replay")
  var replay = parseCommon(@["--replay", "a match.replay"])
  replay.resolveGamePaths()
  doAssert replay.replayPath == absolutePath("a match.replay")

echo "Cli tests passed"
