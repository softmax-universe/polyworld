## Shared launch options and state for native screenshot and frame-time captures.

import std/[os, strutils]

const DefaultScreenshotFrames* = 30
const DefaultBenchmarkWarmup* = 30
const NativeBenchmarkBuild* = not defined(emscripten) and
  (defined(frameBench) or defined(backendBench))

type
  ScreenshotError* = object of CatchableError
  ScreenshotOptions* = object
    path*: string
    benchmarkPath*: string
    frames*: int = DefaultScreenshotFrames
    framesSpecified*: bool
    warmup*: int = DefaultBenchmarkWarmup
    warmupSpecified*: bool

var
  captureConfigured = false
  captureSettings: ScreenshotOptions
  runtimeCapture = false
  captureCompleted = false
  benchmarkWarmupLeft: int
  previousBenchmarkMs: float64
  benchmarkIntervals: seq[float64]

proc runtimeCaptureRequested*(options: ScreenshotOptions): bool =
  options.path.len > 0 or options.benchmarkPath.len > 0

proc captureRequested*(options: ScreenshotOptions): bool =
  ## Reports whether the viewer should start in hidden capture mode.
  options.runtimeCaptureRequested() or defined(takeScreenshot)

proc captureValue(
  arguments: openArray[string], index: var int, argument, name: string
): string =
  ## Reads one separate or attached value without splitting a path's colons.
  if argument == name:
    if index + 1 >= arguments.len or arguments[index + 1].startsWith("--"):
      raise newException(ScreenshotError, name & " requires a value")
    inc index
    result = arguments[index]
  else:
    result = argument[name.len + 1 .. ^1]
  if result.len == 0:
    raise newException(ScreenshotError, name & " requires a value")

proc positiveCaptureInt(text, name: string): int32 =
  ## Parses one positive capture value that fits the common integer range.
  var value: int64
  try:
    value = parseBiggestInt(text)
  except ValueError:
    raise newException(ScreenshotError, name & " must be a positive integer")
  if value <= 0 or value > int32.high:
    raise newException(ScreenshotError,
      name & " must be between 1 and " & $int32.high)
  value.int32

proc matchesCaptureFlag(argument, name: string): bool =
  ## Recognizes exactly one common option and its two attached-value forms.
  argument == name or argument.startsWith(name & "=") or
    argument.startsWith(name & ":")

proc takeCaptureFlag*(
  options: var ScreenshotOptions, arguments: openArray[string],
  index: var int, argument: string
): bool =
  ## Reads render-capture options without depending on a graphics build.
  if argument.matchesCaptureFlag("--screenshot"):
    options.path = arguments.captureValue(index, argument, "--screenshot")
    if options.frames == 0 and not options.framesSpecified:
      options.frames = DefaultScreenshotFrames
    return true
  if argument.matchesCaptureFlag("--frames"):
    options.frames = positiveCaptureInt(
      arguments.captureValue(index, argument, "--frames"), "--frames"
    ).int
    options.framesSpecified = true
    return true
  if argument.matchesCaptureFlag("--benchmark"):
    options.benchmarkPath = arguments.captureValue(index, argument, "--benchmark")
    return true
  if argument.matchesCaptureFlag("--warmup"):
    options.warmup = positiveCaptureInt(
      arguments.captureValue(index, argument, "--warmup"), "--warmup").int
    options.warmupSpecified = true
    return true

proc takeWindowSizeFlag*(
  width, height: var int32, arguments: openArray[string],
  index: var int, argument: string
): bool =
  ## Parses the common window dimensions in separate, equals, or colon form.
  if not argument.matchesCaptureFlag("--windowSize"):
    return false
  let
    value = arguments.captureValue(index, argument, "--windowSize")
    separator = value.find({'x', 'X'})
  if separator <= 0 or separator >= value.high:
    raise newException(ScreenshotError, "--windowSize must look like 800x600")
  let
    parsedWidth = positiveCaptureInt(value[0 ..< separator], "--windowSize")
    parsedHeight = positiveCaptureInt(value[separator + 1 .. ^1], "--windowSize")
  width = parsedWidth
  height = parsedHeight
  true

proc validateCapture*(
  options: ScreenshotOptions,
  graphical = not defined(headless) and not defined(emscripten)
) =
  ## Rejects unavailable capture targets and invalid directly constructed options.
  if options.frames < 0 or options.frames > int32.high or
    (options.frames == 0 and options.framesSpecified):
      raise newException(ScreenshotError, "--frames must be a positive int32")
  if options.captureRequested() and not graphical:
    let flag = if options.benchmarkPath.len > 0: "--benchmark" else: "--screenshot"
    raise newException(ScreenshotError,
      flag & " requires a native graphical client")
  if options.benchmarkPath.len > 0 and (options.path.len > 0 or
      defined(takeScreenshot) or defined(backendBench) or defined(frameBench)):
    raise newException(ScreenshotError,
      "Use --benchmark on its own in an ordinary graphical build")
  if options.warmupSpecified and options.benchmarkPath.len == 0:
    raise newException(ScreenshotError, "--warmup requires --benchmark")
  if options.warmup < 0 or options.warmup > int32.high or
      (options.warmupSpecified and options.warmup == 0):
    raise newException(ScreenshotError, "--warmup must be a positive int32")

proc configureCapture*(
  options: ScreenshotOptions, defaultPath = "screenshot.png",
  graphical = not defined(headless) and not defined(emscripten)
) =
  ## Configures one viewer explicitly, resolving its output before changing cwd.
  options.validateCapture(graphical)
  var configured = options
  if configured.frames == 0:
    configured.frames = DefaultScreenshotFrames
  if configured.path.len == 0:
    when defined(takeScreenshot):
      configured.path = getEnv("SCREENSHOT_PATH", defaultPath)
  if configured.path.len > 0:
    configured.path = absolutePath(configured.path)
  if configured.benchmarkPath.len > 0:
    configured.benchmarkPath = absolutePath(configured.benchmarkPath)
    if configured.warmup == 0: configured.warmup = DefaultBenchmarkWarmup
  benchmarkWarmupLeft = configured.warmup
  previousBenchmarkMs = 0
  benchmarkIntervals.setLen(0)
  captureSettings = configured
  runtimeCapture = options.path.len > 0
  captureConfigured = true
  captureCompleted = false

proc benchmarkCaptureActive*(): bool =
  captureSettings.benchmarkPath.len > 0

proc captureActive*(): bool =
  ## Reports whether the current viewer should use the hidden fixed-step capture path.
  if captureConfigured:
    captureSettings.path.len > 0 or benchmarkCaptureActive()
  else:
    defined(takeScreenshot)

proc captureWaitFrames*(legacyDefault = DefaultScreenshotFrames): int =
  ## Uses the common runtime frame count while retaining developer capture hooks.
  if captureConfigured and (runtimeCapture or captureSettings.framesSpecified):
    captureSettings.frames
  else:
    max(1, legacyDefault)

proc capturePath*(defaultPath = "screenshot.png"): string =
  ## Resolves the configured output or an unconfigured developer capture path.
  if captureConfigured and captureSettings.path.len > 0:
    captureSettings.path
  else:
    absolutePath(getEnv("SCREENSHOT_PATH", defaultPath))

proc captureDue*(frame: int, waitFrames = DefaultScreenshotFrames): bool =
  ## Checks a rendered-frame count without advancing simulation or reading pixels.
  captureActive() and not benchmarkCaptureActive() and not captureCompleted and
    frame >= captureWaitFrames(waitFrames)

proc captureFinished*(): bool =
  ## Reports a successful capture while allowing the viewer to finish cleanup.
  captureCompleted

proc finishCapture*() =
  ## Marks a successful write so extra native frame callbacks cannot overwrite it.
  captureCompleted = true

when not defined(emscripten) and not defined(headless):
  import std/[json, tempfiles]
  from measurements import benchmarkNow, BenchmarkBackend, distribution

  proc recordBenchmarkBoundary*(game: string, width, height: int,
      drain: proc()): bool =
    ## Called after offscreen submission. Drain only at the two timing boundaries.
    if not benchmarkCaptureActive(): return false
    if captureFinished(): return true
    if benchmarkWarmupLeft > 0:
      dec benchmarkWarmupLeft
      if benchmarkWarmupLeft == 0:
        drain()
        previousBenchmarkMs = benchmarkNow()
      return false
    if benchmarkIntervals.len < captureSettings.frames:
      if benchmarkIntervals.len + 1 == captureSettings.frames: drain()
      let now = benchmarkNow()
      benchmarkIntervals.add(now - previousBenchmarkMs)
      previousBenchmarkMs = now
    if benchmarkIntervals.len != captureSettings.frames: return false
    let
      path = captureSettings.benchmarkPath
      report = %*{"game": game, "backend": BenchmarkBackend, "width": width,
        "height": height, "warmup": captureSettings.warmup,
        "frames": benchmarkIntervals.len, "mode": "offscreen",
        "frameMs": benchmarkIntervals, "summary": distribution(benchmarkIntervals)}
    createDir(path.parentDir)
    let (file, pending) = createTempFile(".benchmark-", ".tmp", path.parentDir)
    defer: removeFile(pending)
    try: file.write($report, "\n")
    finally: file.close()
    moveFile(pending, path)
    finishCapture()
    echo "Saved frame timings: ", path
    true
