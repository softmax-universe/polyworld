## Shared native screenshot options, argument parsing, and capture state.

import std/[os, strutils]

const DefaultScreenshotFrames* = 30

type
  ScreenshotError* = object of CatchableError
  ScreenshotOptions* = object
    path*: string
    frames*: int = DefaultScreenshotFrames
    framesSpecified*: bool

var
  captureConfigured = false
  captureSettings: ScreenshotOptions
  runtimeCapture = false
  captureCompleted = false

proc captureRequested*(options: ScreenshotOptions): bool =
  ## Reports whether a launch requests a native screenshot.
  options.path.len > 0 or defined(takeScreenshot)

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
  ## Reads screenshot and frame options without depending on a graphics build.
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
    raise newException(ScreenshotError,
      "--screenshot requires a native graphical client")

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
  captureSettings = configured
  runtimeCapture = options.path.len > 0
  captureConfigured = true
  captureCompleted = false

proc captureActive*(): bool =
  ## Reports whether the current viewer should render a hidden fixed-step shot.
  if captureConfigured:
    captureSettings.path.len > 0
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
  captureActive() and not captureCompleted and
    frame >= captureWaitFrames(waitFrames)

proc captureFinished*(): bool =
  ## Reports a successful capture while allowing the viewer to finish cleanup.
  captureCompleted

proc finishCapture*() =
  ## Marks a successful write so extra native frame callbacks cannot overwrite it.
  captureCompleted = true
