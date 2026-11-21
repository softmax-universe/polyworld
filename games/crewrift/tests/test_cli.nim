import ../[game, sim]

when defined(headless):
  import std/strutils

echo "Testing Crewrift shared command-line options"
block:
  let options = parseOptions(@[])
  doAssert options.player == -1
  doAssert options.speed == 1
  doAssert options.vsync
  doAssert not options.pauseOnStart
  doAssert not options.soundMuted
  doAssert not options.seedSpecified

for arguments in [
  @["--seed", "-1"], @["--seed=-1"], @["--seed:-1"]
]:
  let options = parseOptions(arguments)
  doAssert options.seed == -1 and options.seedSpecified
doAssert parseOptions(@["--seed", "-2147483648"]).seed == int32.low.int

for arguments in [
  @["--seed", "17", "--bot", "first.bas:2", "--bots", "second.bas:6",
    "--record", "output/crew replay.json", "--ticks", "240",
    "--verbose"],
  @["--seed=17", "--bot=first.bas:2", "--bots=second.bas:6",
    "--record=output/crew replay.json", "--ticks=240",
    "--verbose=true"],
  @["--seed:17", "--bot:first.bas:2", "--bots:second.bas:6",
    "--record:output/crew replay.json", "--ticks:240",
    "--verbose:true"]
]:
  let options = parseOptions(arguments)
  doAssert options.seed == 17
  doAssert options.seedSpecified
  doAssert options.botGroups.len == 2
  doAssert options.botGroups[0].path == "first.bas"
  doAssert options.botGroups[0].count == 2
  doAssert options.botGroups[1].path == "second.bas"
  doAssert options.botGroups[1].count == 6
  doAssert options.player == -1
  doAssert options.record == "output/crew replay.json"
  doAssert options.ticks == 240
  doAssert options.headlessTickRate == 0
  doAssert options.name.len == 0
  doAssert options.verbose

for arguments in [
  @["--headless-tick-rate", "24"], @["--headless-tick-rate=24"],
  @["--headless-tick-rate:24"]
]:
  when defined(headless):
    doAssert parseOptions(arguments).headlessTickRate == 24
  else:
    var rejected = false
    try:
      discard parseOptions(arguments)
    except CrewriftError:
      rejected = true
    doAssert rejected

for arguments in [
  @["--speed", "4", "--play", "false", "--vsync", "off"],
  @["--speed=4", "--play=false", "--vsync=off"],
  @["--speed:4", "--play:false", "--vsync:off"]
]:
  when defined(headless):
    var rejected = false
    try:
      discard parseOptions(arguments)
    except CrewriftError:
      rejected = true
    doAssert rejected
  else:
    let options = parseOptions(arguments)
    doAssert options.speed == 4
    doAssert options.pauseOnStart and not options.vsync

for arguments in [
  @["--replay", "C:\\recordings\\crew replay.json"],
  @["--replay=C:\\recordings\\crew replay.json"],
  @["--replay:C:\\recordings\\crew replay.json"]
]:
  let options = parseOptions(arguments)
  doAssert options.replay == "C:\\recordings\\crew replay.json"
  doAssert options.player == -1

block:
  doAssert parseOptions(@["--seconds", "10"]).ticks == 240
  doAssert parseOptions(@["--minutes=2"]).ticks == 2880
  doAssert parseOptions(@["--minutes:2", "--ticks", "12"]).ticks == 12
  doAssert parseOptions(@["--players", "12"]).players == 12
  doAssert parseOptions(@["--players=12"]).players == 12
  doAssert parseOptions(@["--players:12"]).players == 12
  doAssert parseOptions(@["--capture-ticks", "0"]).captureTicks == 0

when not defined(headless):
  for arguments in [
    @["--player", "2"], @["--player=2"], @["--player:2"]
  ]:
    doAssert parseOptions(arguments).player == 1
  doAssert parseOptions(@["--player"]).player == 0
  let named = parseOptions(@["--player", "--name", "Pilot", "--role", "crew"])
  doAssert named.player == 0 and named.name == "Pilot"
  doAssert named.role == "crew"
  let human = parseOptions(@["--player", "2", "--bots", "base.bas:7"])
  doAssert human.player == 1
  doAssert human.botGroups[0].count == 7
  for arguments in [
    @["--player", "2", "--name", "Crew Name"],
    @["--player=2", "--name=Crew Name"],
    @["--player:2", "--name:Crew Name"]
  ]:
    let named = parseOptions(arguments)
    doAssert named.player == 1 and named.name == "Crew Name"

for arguments in [
  @["--record"], @["--record", "--seed", "9"], @["--replay="],
  @["--replay", "old.json", "--record", "new.json"],
  @["--replay", "old.json", "--bots", "base.bas"],
  @["--replay", "old.json", "--player"],
  @["--player", "Pilot"], @["--player", "17"],
  @["--spectate", "--player"], @["--role", "crew"],
  @["--name", "Crew Name"], @["--name=Crew Name"],
  @["--name:Crew Name"], @["--spectate", "--name", "Crew Name"],
  @["--bots", "base.bas:8", "--name", "Crew Name"],
  @["--bot", "base.bas:17"], @["--bots=base.bas:0"],
  @["--bot", "base.bas:2"],
  @["--player", "--bot", "base.bas:6"],
  @["--bot", "base.bas:999999999999999999999999"],
  @["--llm-mode", "async"], @["--server", "ws://localhost:9911/ws"],
  @["--room", "ABCD"], @["--players", "--ticks", "20"]
]:
  var rejected = false
  try:
    discard parseOptions(arguments)
  except CrewriftError as error:
    rejected = error.msg.len > 0
  doAssert rejected, "Invalid launch must fail: " & $arguments

when defined(headless):
  var rejected = false
  try:
    discard parseOptions(@["--player"])
  except CrewriftError as error:
    rejected = "graphical" in error.msg
  doAssert rejected

echo "Crewrift shared CLI checks passed"
