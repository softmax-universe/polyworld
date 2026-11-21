import
  std/[os, tempfiles],
  ../[brains, common, options]

echo "Monster shares screenshot arguments and rejects invalid captures"
block:
  let defaults = parseOptions(@[])
  doAssert defaults.capture.path.len == 0
  doAssert defaults.capture.frames == 30
  doAssert defaults.width == 1440 and defaults.height == 900

when not defined(headless) and not defined(emscripten):
  for arguments in [
    @["--screenshot", "shot.png", "--frames", "7",
      "--windowSize", "800x600"],
    @["--screenshot=shot.png", "--frames=7", "--windowSize=800x600"],
    @["--screenshot:shot.png", "--frames:7", "--windowSize:800x600"]
  ]:
    let capture = parseOptions(arguments)
    doAssert capture.capture.path == "shot.png"
    doAssert capture.capture.frames == 7
    doAssert capture.width == 800 and capture.height == 600
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
