import
  std/os,
  polyworld/cli,
  ../[content, options, seeking]

proc rejects(arguments: seq[string]): bool =
  ## Reports argument errors without loading a map, bot, or replay.
  try:
    discard parseLaunchOptions(arguments)
  except ValueError:
    return true

echo "Testing Heartleaf's shared command-line options"
block:
  for arguments in [
    @["--bots", "base.bas:9", "--seed", "7", "--record", "match.replay"],
    @["--bots=base.bas:9", "--seed=7", "--record=match.replay"],
    @["--bots:base.bas:9", "--seed:7", "--record:match.replay"]
  ]:
    let launch = parseLaunchOptions(arguments)
    doAssert launch.common.seed == 7
    doAssert launch.common.botGroups.botCount == VillagerCount
    doAssert launch.common.botGroups[0].path == absolutePath("base.bas")
    doAssert launch.common.recordPath == absolutePath("match.replay")
    doAssert launch.common.maximumTicks == gameLengthTicks(DefaultDayCount)
    doAssert not launch.durationLimited

echo "Testing calendar setup stays independent of the execution limit"
block:
  for arguments in [
    @["--bot", "base.bas:9", "--days", "2", "--ticks", "48"],
    @["--bot=base.bas:9", "--seconds=2", "--days=2"],
    @["--bot:base.bas:9", "--days:2", "--ticks:48"]
  ]:
    let launch = parseLaunchOptions(arguments)
    doAssert launch.dayCount == 2
    doAssert launch.durationLimited
    doAssert launch.common.maximumTicks == 48
    doAssert launch.executionTicks(gameLengthTicks(2)) == 48
    doAssert launch.executionTicks(12) == 12
  let long = parseLaunchOptions(@[
    "--bot", "base.bas:9", "--days", "1", "--minutes", "20"
  ])
  doAssert long.common.maximumTicks == gameLengthTicks(1)

echo "Testing replay playback, seek options, and common presentation flags"
block:
  for arguments in [
    @["--replay", "match.replay", "--seek-tick", "12"],
    @["--replay=match.replay", "--seek-tick=12"],
    @["--replay:match.replay", "--seek-tick:12"]
  ]:
    let launch = parseLaunchOptions(arguments)
    doAssert launch.common.replayPath == absolutePath("match.replay")
    doAssert launch.startupTarget == SeekTarget(kind: TickSeek, value: 12)
    doAssert launch.executionTicks(100) == 100
  let replay = parseLaunchOptions(@["--replay", "long.replay"])
  doAssert replay.executionTicks(gameLengthTicks(28)) == gameLengthTicks(28)
  let launch = parseLaunchOptions(@[
    "--replay", "match.replay", "--seek-event:day:2:dinner",
    "--mute", "--verbose"
  ])
  doAssert launch.startupTarget == SeekTarget(kind: DinnerSeek, value: 2)
  doAssert launch.common.soundMuted
  doAssert launch.common.verbose
  doAssert launch.common.headlessTickRate == 0
  for arguments in [
    @["--replay", "match.replay", "--play", "false", "--speed", "4",
      "--windowSize", "800x600", "--vsync", "off"],
    @["--replay=match.replay", "--play=false", "--speed=4",
      "--windowSize=800x600", "--vsync=off"],
    @["--replay:match.replay", "--play:false", "--speed:4",
      "--windowSize:800x600", "--vsync:off"]
  ]:
    when defined(headless):
      doAssert rejects(arguments)
    else:
      let launch = parseLaunchOptions(arguments)
      doAssert launch.common.pauseOnStart
      doAssert launch.common.speed == 4
      doAssert launch.common.windowWidth == 800
      doAssert launch.common.windowHeight == 600
      doAssert not launch.common.vsync

echo "Testing tick pacing requires the headless runner"
block:
  for flags in [
    @["--headless-tick-rate", "48"],
    @["--headless-tick-rate=48"],
    @["--headless-tick-rate:48"],
    @["--headless-tick-rate", "0"]
  ]:
    let arguments = @["--replay", "match.replay"] & flags
    when defined(headless):
      let launch = parseLaunchOptions(arguments)
      doAssert launch.common.headlessTickRate ==
        (if flags[^1] == "0": 0 else: 48)
    else:
      doAssert rejects(arguments)

echo "Testing human slots have the same one-based meaning"
block:
  for arguments in [
    @["--player", "2", "--bot", "base.bas:8"],
    @["--player=2", "--bot=base.bas:8"],
    @["--player:2", "--bot:base.bas:8"]
  ]:
    when defined(headless):
      doAssert rejects(arguments)
    else:
      let launch = parseLaunchOptions(arguments)
      doAssert launch.common.playerSlot == 2
      doAssert launch.common.botGroups.botCount == 8
  when not defined(headless):
    doAssert parseLaunchOptions(@[
      "--player", "--bot", "base.bas:8"
    ]).common.playerSlot == 1

echo "Testing invalid or unsupported launches are rejected"
block:
  for arguments in [
    @["--bot", "base.bas:8"],
    @["--bot", "base.bas:10"],
    @["--replay", "match.replay", "--record", "copy.replay"],
    @["--replay", "match.replay", "--bot", "base.bas:9"],
    @["--replay", "match.replay", "--name", "Visitor"],
    @["--replay", "match.replay", "--llm-mode", "barrier"],
    @["--replay", "match.replay", "--server", "ws://localhost:9911/ws"],
    @["--replay", "match.replay", "--room", "ABCD"],
    @["--replay", "match.replay", "--ticks", "24"],
    @["--replay", "match.replay", "--days=0"],
    @["--replay", "match.replay", "--days=29"],
    @["--replay", "match.replay", "--ticks=0"],
    @["--replay", "match.replay", "--seek-tick=0", "--seek-tick=1"],
    @["--replay", "match.replay", "--unknown"]
  ]:
    doAssert rejects(arguments), $arguments
  doAssert parseLaunchOptions(@["--help"]).showHelp

echo "Heartleaf command-line tests passed"
