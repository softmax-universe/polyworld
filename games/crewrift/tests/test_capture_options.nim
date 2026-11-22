import
  std/strutils,
  ../[game, sim]

echo "Testing shared Crewrift capture arguments"
block:
  let options = parseOptions(@[])
  doAssert options.capture.path.len == 0
  doAssert options.capture.frames == 30
  doAssert options.captureTicks == 0
  doAssert options.width == 1440 and options.height == 900

for arguments in [
  @["--screenshot", "output/crew shot.png", "--frames", "2",
    "--windowSize", "1280x720", "--seed:19"],
  @["--screenshot=output/crew shot.png", "--frames=2",
    "--windowSize=1280x720", "--seed:19"],
  @["--screenshot:output/crew shot.png", "--frames:2",
    "--windowSize:1280x720", "--seed:19"]
]:
  when defined(headless) or defined(emscripten):
    var rejected = false
    try:
      discard parseOptions(arguments)
    except CrewriftError as error:
      rejected = "graphical" in error.msg or "native" in error.msg
    doAssert rejected, "Capture needs a native graphical client."
  else:
    let options = parseOptions(arguments)
    doAssert options.capture.path == "output/crew shot.png"
    doAssert options.capture.frames == 2
    doAssert options.capture.framesSpecified
    doAssert options.width == 1280 and options.height == 720
    doAssert options.seed == 19
    doAssert options.soundMuted
    doAssert options.captureTicks == 0

for arguments in [
  @["--screenshot"], @["--screenshot="], @["--frames"],
  @["--frames:0"], @["--frames=-1"], @["--frames=bad"],
  @["--windowSize"], @["--windowSize=0x720"],
  @["--windowSize=bad"]
]:
  var rejected = false
  try:
    discard parseOptions(arguments)
  except CrewriftError:
    rejected = true
  doAssert rejected, "Invalid capture arguments must fail: " & $arguments

when not defined(headless) and not defined(emscripten):
  let options = parseOptions(@[
    "--unmute", "--screenshot", "output/crew.png", "--capture-ticks:12"
  ])
  doAssert options.soundMuted
  doAssert options.capture.frames == 30
  doAssert options.captureTicks == 12

echo "Crewrift capture argument checks passed"
