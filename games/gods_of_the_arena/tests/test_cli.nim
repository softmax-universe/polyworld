import
  std/os,
  polyworld/cli,
  ../[game, presets]

proc parsed(arguments: seq[string]): GameOptions =
  ## Parses a launch without constructing a game or retaining test overrides.
  let
    previousConfig = matchConfig
    previousServer = serverAddress
    previousName = playerNameOverride
  defer:
    matchConfig = previousConfig
    serverAddress = previousServer
    playerNameOverride = previousName
  matchConfig = GotaConfig(seed: previousConfig.seed)
  result = parseGameOptions(arguments)
  doAssert serverAddress == result.serverUrl
  doAssert playerNameOverride == result.playerName

echo "Testing GotA shared command-line forms without starting a match"
let previousRun = run
for commonArguments in [
  @["--bots", "base.bas:10", "--record", "shots/match.replay",
    "--seed", "7", "--ticks", "24", "--verbose"],
  @["--bots=base.bas:10", "--record=shots/match.replay", "--seed=7",
    "--ticks=24", "--verbose"],
  @["--bots:base.bas:10", "--record:shots/match.replay", "--seed:7",
    "--ticks:24", "--verbose"]
]:
  var arguments = commonArguments
  when not defined(headless):
    arguments.add @["--name", "123"]
  let options = parsed(arguments)
  doAssert options.botGroups.botCount == 10
  doAssert options.botGroups[0].path == absolutePath("base.bas")
  doAssert options.recordPath == absolutePath("shots/match.replay")
  doAssert options.seed == 7
  doAssert options.maximumTicks == 24
  when not defined(headless):
    doAssert options.playerName == "123"
  doAssert not options.pauseOnStart and options.speed == 1
  doAssert options.verbose
  doAssert run == previousRun

echo "Testing GotA replay and menu recording paths"
block:
  let replay = parsed(@["--replay=shots/match.replay"])
  doAssert replay.replayPath == absolutePath("shots/match.replay")
  let menu = parsed(@["--record:shots/menu.replay"])
  doAssert menu.recordPath == absolutePath("shots/menu.replay")
  doAssert menu.botGroups.len == 0

when not defined(headless):
  echo "Testing GotA refuses headless pacing and barriers in graphical builds"
  for arguments in [@["--llm-mode", "barrier"],
    @["--headless-tick-rate", "24"]]:
      var rejected = false
      try:
        discard parsed(arguments)
      except CliError:
        rejected = true
      doAssert rejected
  echo "Testing GotA retains menu playback and window choices"
  for arguments in [
    @["--play", "false", "--speed", "3", "--windowSize", "960x640"],
    @["--play=false", "--speed=3", "--windowSize=960x640"],
    @["--play:false", "--speed:3", "--windowSize:960x640"]
  ]:
    let options = parsed(arguments)
    doAssert options.pauseOnStart and options.speed == 3
    doAssert options.windowWidth == 960 and options.windowHeight == 640
  echo "Testing GotA human slot and multiplayer arguments"
  for arguments in [
    @["--player", "2", "--bot", "base.bas:9", "--name", "Alice"],
    @["--player=2", "--bot=base.bas:9", "--name=Alice"],
    @["--player:2", "--bot:base.bas:9", "--name:Alice"]
  ]:
    let options = parsed(arguments)
    doAssert options.playerSlot == 2
    doAssert options.playerName == "Alice"
    doAssert options.botGroups.botCount == 9
  for arguments in [
    @["--server", "ws://localhost:9911/ws", "--room", "ABC123"],
    @["--server=ws://localhost:9911/ws", "--room=ABC123"],
    @["--server:ws://localhost:9911/ws", "--join:ABC123"]
  ]:
    let options = parsed(arguments)
    doAssert options.serverUrl == "ws://localhost:9911/ws"
    doAssert options.roomCode == "ABC123"
else:
  echo "Testing GotA headless pacing and request barriers"
  let headless = parsed(@["--bot", "base.bas:10", "--llm-mode", "barrier",
    "--headless-tick-rate", "24"])
  doAssert headless.waitForLlm and headless.headlessTickRate == 24
  var rejected = false
  try:
    discard parsed(@["--name", "Alice"])
  except CliError:
    rejected = true
  doAssert rejected

echo "Testing GotA rejects ambiguous names and incomplete direct rosters"
for arguments in [
  @["--player", "Alice"],
  @["--player", "--record", "shots/match.replay"],
  @["--replay", "shots/match.replay", "--bot", "base.bas:10"],
  @["--replay", "shots/match.replay", "--record", "shots/other.replay"]
]:
  var rejected = false
  try:
    discard parsed(arguments)
  except CliError:
    rejected = true
  doAssert rejected

echo "GotA command-line tests passed"
