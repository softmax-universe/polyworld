import
  std/os,
  polyworld/cli,
  ../game, ../presets

proc parsed(arguments: seq[string]): GameOptions =
  ## Exercises the game's startup parser without terrain, bots, or a window.
  var
    settings = MapSettings()
    diplomacy = DiplomacySettings()
  parseGameOptions(settings, diplomacy, arguments)

echo "Testing LvD delegates common launch options"
block:
  let previousRun = run
  for arguments in [
    @["--bots", "players/base.bas:2", "--record", "out/match.replay",
      "--seed", "17", "--ticks", "48"],
    @["--bots=players/base.bas:2", "--record=out/match.replay",
      "--seed=17", "--ticks=48"],
    @["--bots:players/base.bas:2", "--record:out/match.replay",
      "--seed:17", "--ticks:48"]
  ]:
    let options = parsed(arguments)
    doAssert options.botGroups.botCount == 2
    doAssert options.botGroups[0].path == absolutePath("players/base.bas")
    doAssert options.recordPath == absolutePath("out/match.replay")
    doAssert options.seed == 17 and options.maximumTicks == 48
    doAssert options.speed == 1 and not options.pauseOnStart
    doAssert run == previousRun

echo "Testing LvD replay paths and menu recording destinations"
block:
  let replay = parsed(@["--replay=recordings/a.replay"])
  doAssert replay.replayPath == absolutePath("recordings/a.replay")
  let menu = parsed(@["--record:out/menu.replay"])
  doAssert menu.recordPath == absolutePath("out/menu.replay")
  doAssert menu.botGroups.len == 0 and menu.playerSlot == 0
  var rejected = false
  try:
    discard parsed(@["--replay", "a.replay", "--record", "b.replay"])
  except CliError:
    rejected = true
  doAssert rejected

when defined(headless):
  echo "Testing LvD headless pacing and LLM barriers"
  block:
    let options = parsed(@["--bot", "players/base.bas:2",
      "--headless-tick-rate=12", "--llm-mode:barrier"])
    doAssert options.headlessTickRate == 12
    doAssert options.waitForLlm
    let defaults = parsed(@["--headless-tick-rate", "0", "--llm-mode", "async"])
    doAssert defaults.headlessTickRate == 0
    doAssert not defaults.waitForLlm
else:
  echo "Testing LvD rejects headless-only options in graphical clients"
  block:
    for arguments in [
      @["--headless-tick-rate=0"], @["--headless-tick-rate", "12"],
      @["--llm-mode:async"], @["--llm-mode", "barrier"]
    ]:
      var rejected = false
      try:
        discard parsed(arguments)
      except CliError:
        rejected = true
      doAssert rejected

  echo "Testing LvD retains graphical launch overrides before menu startup"
  block:
    let options = parsed(@["--record:out/menu.replay", "--play=false",
      "--speed:3", "--windowSize=960x640"])
    doAssert options.pauseOnStart and options.speed == 3
    doAssert options.windowWidth == 960 and options.windowHeight == 640
    doAssert WindowSizeFlag in options.specifiedFlags
    doAssert options.recordPath == absolutePath("out/menu.replay")

  echo "Testing LvD separates human slots from names"
  block:
    for arguments in [
      @["--player", "2", "--name", "Alice", "--bot", "players/base.bas"],
      @["--player=2", "--name=Alice", "--bot=players/base.bas"],
      @["--player:2", "--name:Alice", "--bot:players/base.bas"]
    ]:
      let options = parsed(arguments)
      doAssert options.playerSlot == 2
      doAssert options.playerName == "Alice"
      doAssert options.botGroups.botCount == 1
    doAssert parsed(@["--player"]).playerSlot == 1
    var rejected = false
    try:
      discard parsed(@["--player", "Alice"])
    except CliError:
      rejected = true
    doAssert rejected

  echo "Testing LvD relay and invitation arguments"
  block:
    for arguments in [
      @["--server", "ws://127.0.0.1:9911/ws", "--room", "ExactCase"],
      @["--server=ws://127.0.0.1:9911/ws", "--room=ExactCase"],
      @["--server:ws://127.0.0.1:9911/ws", "--room:ExactCase"]
    ]:
      let options = parsed(arguments)
      doAssert options.serverUrl == "ws://127.0.0.1:9911/ws"
      doAssert options.roomCode == "ExactCase"
      doAssert options.botGroups.len == 0 and options.playerSlot == 0

when defined(headless):
  echo "Testing LvD headless launches reject a graphical display name"
  var rejected = false
  try:
    discard parsed(@["--name", "Alice"])
  except CliError:
    rejected = true
  doAssert rejected

echo "LvD menu CLI options passed"
