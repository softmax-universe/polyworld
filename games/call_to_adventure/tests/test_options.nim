import
  std/os,
  polyworld/cli,
  ../options, ../content

proc rejects(arguments: seq[string]): bool =
  ## Checks invalid launch options without creating a game or renderer.
  try:
    discard parseGameOptions(arguments)
  except CliError:
    return true

echo "Testing Call to Adventure common argument forms"
block:
  for arguments in [
    @["--bots", "bots/base.bas:4", "--record", "replays/match.replay",
      "--seed", "17", "--ticks", "48"],
    @["--bots=bots/base.bas:4", "--record=replays/match.replay", "--seed=17",
      "--ticks=48"],
    @["--bots:bots/base.bas:4", "--record:replays/match.replay", "--seed:17",
      "--ticks:48"]
  ]:
    let launch = parseGameOptions(arguments)
    doAssert launch.options.botGroups.botCount == PartySize
    doAssert launch.options.botGroups[0].path == absolutePath("bots/base.bas")
    doAssert launch.options.recordPath == absolutePath("replays/match.replay")
    doAssert launch.options.seed == 17
    doAssert launch.options.maximumTicks == 48
    doAssert not launch.arena.enabled

echo "Testing Call to Adventure graphical playback options"
block:
  for visual in [
    @["--speed", "4", "--play", "false"],
    @["--speed=4", "--play=false"],
    @["--speed:4", "--play:false"]
  ]:
    let arguments = @["--bot", "base.bas:4"] & visual
    when defined(headless):
      doAssert rejects(arguments)
    else:
      let launch = parseGameOptions(arguments)
      doAssert launch.options.speed == 4
      doAssert launch.options.pauseOnStart

echo "Testing Call to Adventure human and bot slot selection"
block:
  when not defined(headless):
    for arguments in [
      @["--player", "2", "--name", "Ada", "--bot", "base.bas:3"],
      @["--player=2", "--name=Ada", "--bot=base.bas:3"],
      @["--player:2", "--name:Ada", "--bot:base.bas:3"]
    ]:
      let launch = parseGameOptions(arguments)
      doAssert launch.options.playerSlot == 2
      doAssert launch.options.playerName == "Ada"
      doAssert launch.options.botGroups.botCount == 3
    let first = parseGameOptions(@["--player", "--bot", "base.bas:3"])
    doAssert first.options.playerSlot == 1
  else:
    doAssert rejects(@["--player", "--bot", "base.bas:3"])

echo "Testing Call to Adventure replay input and portable launch settings"
block:
  for arguments in [
    @["--replay", "replays/saved.replay"],
    @["--replay=replays/saved.replay"],
    @["--replay:replays/saved.replay"]
  ]:
    let launch = parseGameOptions(arguments)
    doAssert launch.options.replayPath == absolutePath("replays/saved.replay")
    doAssert launch.options.botGroups.len == 0
  let launch = parseGameOptions(@[
    "--bot", "one.bas", "--bots", "two.bas:3", "--minutes:2",
    "--mute", "--verbose=true"
  ])
  doAssert launch.options.botGroups.len == 2
  doAssert launch.options.maximumTicks == 2 * 60 * SharedTickRate
  doAssert launch.options.soundMuted
  doAssert launch.options.soundOverride
  doAssert launch.options.verbose
  doAssert launch.options.headlessTickRate == 0
  doAssert not launch.options.waitForLlm
  let windowArguments = @[
    "--bot", "base.bas:4", "--windowSize=960x720", "--vsync", "off"
  ]
  when defined(headless):
    doAssert rejects(windowArguments)
  else:
    let window = parseGameOptions(windowArguments).options
    doAssert window.windowWidth == 960
    doAssert window.windowHeight == 720
    doAssert not window.vsync

echo "Testing tick pacing requires the headless runner"
block:
  for flags in [
    @["--headless-tick-rate", "24"],
    @["--headless-tick-rate=24"],
    @["--headless-tick-rate:24"],
    @["--headless-tick-rate", "0"]
  ]:
    let arguments = @["--bot", "base.bas:4"] & flags
    when defined(headless):
      let launch = parseGameOptions(arguments)
      doAssert launch.options.headlessTickRate ==
        (if flags[^1] == "0": 0 else: 24)
    else:
      doAssert rejects(arguments)

echo "Testing LLM mode requires the headless request barrier"
block:
  for flags in [
    @["--llm-mode", "barrier"],
    @["--llm-mode=barrier"],
    @["--llm-mode:barrier"],
    @["--llm-mode", "async"]
  ]:
    let arguments = @["--bot", "base.bas:4"] & flags
    when defined(headless):
      let launch = parseGameOptions(arguments)
      doAssert launch.options.waitForLlm == (flags[^1] != "async")
    else:
      doAssert rejects(arguments)

echo "Testing Call to Adventure arena configuration stays local to a parse"
block:
  let arena = parseGameOptions(@[
    "--bot", "base.bas:4", "--arena", "--hero", "fighter",
    "--monster=dustling", "--monsters:3"
  ])
  doAssert arena.arena.enabled
  doAssert arena.arena.heroes == @[FighterClass]
  doAssert arena.arena.arenaMonsters().len == 3
  let ordinary = parseGameOptions(@["--bot", "base.bas:4"])
  doAssert not ordinary.arena.enabled
  doAssert ordinary.arena.count == 10

echo "Testing Call to Adventure rejects conflicting and unsupported options"
block:
  for arguments in [
    @["--bot", "base.bas:3"],
    @["--bot", "base.bas:4", "--name", "Ada"],
    @["--bot", "base.bas:4", "--server", "ws://localhost:9911/ws"],
    @["--bot", "base.bas:4", "--room", "ABCD"],
    @["--replay", "saved.replay", "--record", "copy.replay"],
    @["--replay", "saved.replay", "--bots", "base.bas:4"],
    @["--replay", "saved.replay", "--ticks", "3"],
    @["--replay", "saved.replay", "--seed", "17"],
    @["--arena", "--bot", "base.bas:4", "--record", "arena.replay"],
    @["--bot", "base.bas:4", "--player", "Ada"],
    @["--bot", "base.bas:4", "--speed", "0"]
  ]:
    doAssert rejects(arguments)

echo "Call to Adventure command-line tests passed"
