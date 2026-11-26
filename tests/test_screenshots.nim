import
  std/os,
  polyworld/[cli, screenshots]

const TestRuntimeBenchmark = not (defined(emscripten) or defined(headless) or
  defined(takeScreenshot) or defined(frameBench) or defined(backendBench))
when TestRuntimeBenchmark:
  import std/[json, tempfiles]

proc parseCapture(arguments: openArray[string]): ScreenshotOptions =
  ## Parses capture arguments without requiring a graphical build or window.
  var index = 0
  while index < arguments.len:
    doAssert result.takeCaptureFlag(arguments, index, arguments[index])
    inc index

proc rejectCapture(arguments: openArray[string]) =
  ## Requires malformed capture arguments to raise the shared boundary error.
  var rejected = false
  try:
    discard parseCapture(arguments)
  except ScreenshotError:
    rejected = true
  doAssert rejected

proc rejectWindowSize(arguments: openArray[string]) =
  ## Requires malformed dimensions to fail before a game creates its window.
  var
    width, height: int32
    index = 0
    rejected = false
  try:
    discard takeWindowSizeFlag(width, height, arguments, index, arguments[0])
  except ScreenshotError:
    rejected = true
  doAssert rejected

proc testScreenshotFlags() =
  ## Checks the common capture contract independently of rendering and files.
  echo "Testing shared screenshot defaults and argument spellings"
  let defaults = ScreenshotOptions()
  doAssert defaults.path.len == 0
  doAssert defaults.frames == 30
  doAssert not defaults.framesSpecified
  when not defined(takeScreenshot):
    doAssert not defaults.captureRequested()
  for arguments in [
    @["--screenshot", "shots/a match.png", "--frames", "7"],
    @["--screenshot=shots/a match.png", "--frames=7"],
    @["--screenshot:shots/a match.png", "--frames:7"]
  ]:
    let options = parseCapture(arguments)
    doAssert options.path == "shots/a match.png"
    doAssert options.frames == 7 and options.framesSpecified
    doAssert options.captureRequested()
    options.validateCapture(graphical = true)
  doAssert parseCapture(@["--screenshot", "one.png"]).frames == 30
  let framesOnly = parseCapture(@["--frames:3"])
  doAssert framesOnly.frames == 3 and framesOnly.path.len == 0
  when not defined(takeScreenshot):
    doAssert not framesOnly.captureRequested()
  for argument in [
    "--screenshot:C:\\shots\\match.png", "--screenshot=C:\\shots\\match.png"
  ]:
    doAssert parseCapture(@[argument]).path == "C:\\shots\\match.png"

  echo "Testing missing, invalid, and overflowing capture arguments"
  for arguments in [
    @["--screenshot"], @["--screenshot", ""], @["--screenshot="],
    @["--screenshot:"], @["--screenshot", "--frames", "2"],
    @["--frames"], @["--frames="], @["--frames:0"],
    @["--frames=-1"], @["--frames:1.5"], @["--frames=not-a-number"],
    @["--frames=2147483648"], @["--frames=999999999999999999999999"]
  ]:
    rejectCapture(arguments)
  var
    untouched = ScreenshotOptions(path: "keep.png", frames: 9)
    index = 0
  doAssert not untouched.takeCaptureFlag(@["--game-option"], index,
    "--game-option")
  doAssert index == 0
  doAssert untouched.path == "keep.png" and untouched.frames == 9

  echo "Testing one shared window-size syntax"
  for arguments in [
    @["--windowSize", "1280x720"], @["--windowSize=1280x720"],
    @["--windowSize:1280X720"]
  ]:
    var
      width, height: int32
      position = 0
    doAssert takeWindowSizeFlag(width, height, arguments, position,
      arguments[0])
    doAssert width == 1280 and height == 720
    doAssert position == arguments.high
  for arguments in [
    @["--windowSize"], @["--windowSize="], @["--windowSize:0x720"],
    @["--windowSize:1280x0"], @["--windowSize:-1x720"],
    @["--windowSize:1280"], @["--windowSize:1280x720x1"],
    @["--windowSize:2147483648x720"]
  ]:
    rejectWindowSize(arguments)

  echo "Testing common game flags share capture parsing"
  for arguments in [
    @["--screenshot", "shared.png", "--frames", "12",
      "--windowSize", "800x600"],
    @["--screenshot=shared.png", "--frames=12", "--windowSize=800x600"],
    @["--screenshot:shared.png", "--frames:12", "--windowSize:800x600"]
  ]:
    var
      options = GameOptions()
      position = 0
    while position < arguments.len:
      doAssert options.takeCommonFlag(arguments, position, arguments[position])
      inc position
    doAssert options.capture.path == "shared.png"
    doAssert options.capture.frames == 12
    doAssert options.windowWidth == 800 and options.windowHeight == 600

  echo "Testing nongraphical launches reject screenshot requests"
  var rejected = false
  try:
    ScreenshotOptions(path: "unavailable.png").validateCapture(
      graphical = false
    )
  except ScreenshotError:
    rejected = true
  doAssert rejected
  when not defined(takeScreenshot):
    ScreenshotOptions().validateCapture(graphical = false)
  for frames in [0, -1]:
    rejected = false
    try:
      ScreenshotOptions(path: "invalid.png", frames: frames,
        framesSpecified: true).validateCapture(graphical = true)
    except ScreenshotError:
      rejected = true
    doAssert rejected

proc testScreenshotState() =
  ## Checks explicit startup state and CLI priority without creating a file.
  let
    hadPath = existsEnv("SCREENSHOT_PATH")
    previousPath = getEnv("SCREENSHOT_PATH")
    requested = "shots" / "runtime.png"
  putEnv("SCREENSHOT_PATH", "ignored-environment.png")
  defer:
    if hadPath:
      putEnv("SCREENSHOT_PATH", previousPath)
    else:
      delEnv("SCREENSHOT_PATH")
    configureCapture(ScreenshotOptions(), graphical = true)

  echo "Testing capture startup resolves paths and ignores legacy defaults"
  var zeroed = default(ScreenshotOptions)
  zeroed.path = requested
  zeroed.validateCapture(graphical = true)
  configureCapture(zeroed, graphical = true)
  doAssert captureWaitFrames(2) == 30
  configureCapture(ScreenshotOptions(path: requested), "ignored-default.png",
    graphical = true)
  doAssert captureActive()
  doAssert capturePath("another-default.png") == absolutePath(requested)
  doAssert captureWaitFrames(2) == 30
  doAssert not captureDue(0)
  doAssert not captureDue(29)
  doAssert captureDue(30) and captureDue(31)
  configureCapture(parseCapture(@["--frames=4", "--screenshot", requested]),
    graphical = true)
  doAssert captureWaitFrames(120) == 4
  doAssert not captureDue(3)
  doAssert captureDue(4) and captureDue(5)
  var rejected = false
  try:
    configureCapture(ScreenshotOptions(path: "unavailable.png"),
      graphical = false)
  except ScreenshotError:
    rejected = true
  doAssert rejected
  doAssert capturePath() == absolutePath(requested)
  doAssert captureWaitFrames() == 4

  echo "Testing completed captures cannot become due again"
  doAssert not captureFinished()
  finishCapture()
  doAssert captureFinished()
  doAssert not captureDue(4) and not captureDue(300)
  configureCapture(parseCapture(@["--frames=4", "--screenshot", requested]),
    graphical = true)
  doAssert not captureFinished()
  doAssert captureDue(4)

  echo "Testing disabled startup clears a prior capture request"
  configureCapture(ScreenshotOptions(), graphical = true)
  when not defined(takeScreenshot):
    doAssert not captureActive()
    doAssert not captureDue(300)
  else:
    doAssert captureActive()
    doAssert capturePath() == absolutePath("ignored-environment.png")
    doAssert captureWaitFrames(9) == 9
    configureCapture(ScreenshotOptions(frames: 6, framesSpecified: true),
      graphical = true)
    doAssert captureWaitFrames(9) == 6

testScreenshotFlags()
testScreenshotState()
when TestRuntimeBenchmark:
  proc testBenchmarkCapture() =
    let directory = createTempDir("polyworld-frame-times-", "")
    defer:
      configureCapture(ScreenshotOptions(), graphical = true)
      removeDir(directory)
    let path = directory / "nested" / "frame times.json"
    for separator in ["=", ":"]:
      let options = parseCapture(@["--benchmark" & separator & path,
        "--warmup" & separator & "1", "--frames" & separator & "2"])
      doAssert options.benchmarkPath == path and options.warmup == 1 and options.frames == 2
    for args in [@["--benchmark"], @["--benchmark="], @["--warmup", "0"]]:
      rejectCapture(args)
    for args in [@["--screenshot=a.png", "--benchmark=b.json"], @["--warmup=3"]]:
      var rejected = false
      try: parseCapture(args).validateCapture(graphical = true)
      except ScreenshotError: rejected = true
      doAssert rejected
    let options = parseCapture(@["--benchmark", path, "--warmup", "2", "--frames", "2"])
    var rejected = false
    try: options.validateCapture(graphical = false)
    except ScreenshotError: rejected = true
    doAssert rejected
    configureCapture(options, graphical = true)
    doAssert captureActive() and benchmarkCaptureActive() and not captureDue(100)
    var drains = 0
    proc drain() = inc drains
    for i in 1..4:
      doAssert recordBenchmarkBoundary("test game", 640, 480, drain) == (i == 4)
      doAssert drains == (if i == 4: 2 elif i >= 2: 1 else: 0)
      doAssert captureFinished() == (i == 4) and fileExists(path) == (i == 4)
    let report = parseFile(path)
    doAssert recordBenchmarkBoundary("test game", 640, 480, drain) and drains == 2
    doAssert report["game"].getStr == "test game" and report["frameMs"].len == 2
    doAssert report["summary"]["meanMs"].getFloat ==
      (report["frameMs"][0].getFloat + report["frameMs"][1].getFloat) / 2
    configureCapture(options, graphical = true)
    doAssert not recordBenchmarkBoundary("test game", 640, 480, drain)
    doAssert drains == 2 and not captureFinished()
  testBenchmarkCapture()
echo "Shared screenshot command-line and startup unit tests passed."
