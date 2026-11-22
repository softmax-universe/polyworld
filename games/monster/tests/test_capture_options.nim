import
  std/[os, strutils, tempfiles],
  ../[brains, common, options]

echo "Monster shares screenshot arguments and rejects invalid captures"
block:
  let defaults = parseOptions(@[])
  doAssert defaults.game.capture.path.len == 0
  doAssert defaults.game.capture.frames == 30
  doAssert defaults.game.windowWidth == 1440
  doAssert defaults.game.windowHeight == 900
  doAssert defaults.game.seed == 42
  doAssert defaults.game.speed == 1 and defaults.game.vsync
  doAssert not defaults.game.pauseOnStart
  doAssert not defaults.conversation

echo "Monster uses shared values for seed, audio and diagnostic output"
for arguments in [
  @["--seed", "17", "--mute", "--verbose"],
  @["--seed=17", "--mute=true", "--verbose=true"],
  @["--seed:17", "--mute:true", "--verbose:true"]
]:
  let settings = parseOptions(arguments)
  doAssert settings.game.seed == 17
  doAssert settings.game.soundMuted and settings.game.soundOverride
  doAssert settings.game.verbose
  doAssert settings.saveDir.endsWith("17")

when not defined(headless):
  echo "Monster uses shared values for graphical transport and display"
  for arguments in [
    @["--play", "false", "--speed", "4", "--vsync", "off"],
    @["--play=false", "--speed=4", "--vsync=off"],
    @["--play:false", "--speed:4", "--vsync:off"]
  ]:
    let settings = parseOptions(arguments)
    doAssert settings.game.pauseOnStart and settings.game.speed == 4
    doAssert not settings.game.vsync
else:
  echo "Headless Monster rejects graphical transport and display options"
  for arguments in [
    @["--play", "false"], @["--speed", "4"], @["--vsync", "off"],
    @["--windowSize", "800x600"], @["--frames", "7"]
  ]:
    var rejected = false
    try:
      discard parseOptions(arguments)
    except MonsterError:
      rejected = true
    doAssert rejected, $arguments

echo "Monster audio flags do not opt into a microphone conversation"
block:
  let unmuted = parseOptions(@["--unmute"])
  doAssert not unmuted.game.soundMuted
  doAssert unmuted.game.soundOverride
  doAssert not unmuted.conversation
  let speaking = parseOptions(@["--conversation", "--unmute"])
  doAssert speaking.conversation and not speaking.game.soundMuted
  let muted = parseOptions(@["--unmute", "--mute"])
  doAssert muted.game.soundMuted and not muted.conversation

echo "Monster-specific values use the same three value forms"
for arguments in [
  @["--model", "example:model", "--prompt", "Wait here.",
    "--select", "moss", "--save-dir", "profiles/moss"],
  @["--model=example:model", "--prompt=Wait here.", "--select=moss",
    "--save-dir=profiles/moss"],
  @["--model:example:model", "--prompt:Wait here.", "--select:moss",
    "--save-dir:profiles/moss"]
]:
  let settings = parseOptions(arguments)
  doAssert settings.model == "example:model"
  doAssert settings.prompt == "Wait here." and settings.selection == "moss"
  doAssert settings.saveDir == absolutePath("profiles/moss")

echo "Monster rejects unsupported match flags and malformed options"
for arguments in [
  @["--bot", "player.bas"], @["--bots", "player.bas:2"],
  @["--player"], @["--name", "Moss"], @["--replay", "input.replay"],
  @["--record", "output.replay"], @["--ticks", "20"],
  @["--server", "ws://localhost:9911/ws"], @["--room", "ABCD"],
  @["--headless-tick-rate", "30"], @["--llm-mode", "barrier"],
  @["--width", "800"], @["--height", "600"],
  @["--model"], @["--prompt", "--offline"], @["--seed=large"],
  @["--play=maybe"], @["--conversation=false"]
]:
  var rejected = false
  try:
    discard parseOptions(arguments)
  except MonsterError:
    rejected = true
  doAssert rejected, $arguments

when not defined(headless) and not defined(emscripten):
  for arguments in [
    @["--screenshot", "shot.png", "--frames", "7",
      "--windowSize", "800x600"],
    @["--screenshot=shot.png", "--frames=7", "--windowSize=800x600"],
    @["--screenshot:shot.png", "--frames:7", "--windowSize:800x600"]
  ]:
    let capture = parseOptions(arguments)
    doAssert capture.game.capture.path == "shot.png"
    doAssert capture.game.capture.frames == 7
    doAssert capture.game.windowWidth == 800
    doAssert capture.game.windowHeight == 600
  block:
    let prompt = parseOptions(@[
      "--screenshot", "shot.png", "--prompt:Wait here."
    ])
    doAssert prompt.prompt == "Wait here."
else:
  var rejected = false
  try:
    discard parseOptions(@["--screenshot", "shot.png"])
  except MonsterError:
    rejected = true
  doAssert rejected

for arguments in [
  @["--screenshot"], @["--screenshot="], @["--frames", "0"],
  @["--frames", "-1"], @["--frames", "later"],
  @["--windowSize", "800"], @["--windowSize", "100x100"]
]:
  var rejected = false
  try:
    discard parseOptions(arguments)
  except MonsterError:
    rejected = true
  doAssert rejected

echo "Monster capture memory is loaded without overwriting saved history"
block:
  let
    directory = createTempDir("monster-capture-memory-", "")
    path = directory / "conversation.json"
  defer: removeDir(directory)
  let original = newBrain(path, enabled = false)
  original.addEvent("Before capture")
  original.close()
  let
    saved = readFile(path)
    captured = newBrain(path, enabled = false)
  doAssert captured.messages.len == 1
  captured.disableSaving()
  captured.addEvent("Temporary capture event")
  captured.close()
  doAssert readFile(path) == saved

echo "Monster capture argument and read-only memory checks passed"
