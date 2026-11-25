## Shared graphical viewer bootstrap for Polyworld games.

import
  std/[math, os, strutils, times],
  chroma, pixie, silky, vmath, windy,
  actioncam, assets, fullscreens, player, screenshots, renderer, benchmarks

export screenshots, renderer, benchmarks

when defined(emscripten):
  {.emit: "#include <emscripten.h>".}

const
  DefaultWindowSize* = ivec2(1920, 1080)
  HudIconSize = 64
  SplashName* = "logo"
  SplashSeconds* = 3.0
    ## How long the theme logo stays up while the client finishes loading.

type Splash* = object
  ## Wall-clock start of one loading splash.
  startedAt*: float64
  name*: string

when defined(emscripten):
  # Hidden tabs never fire requestAnimationFrame, so the timeout keeps
  # networked and bot games ticking in the background.
  {.emit: """
  EM_ASYNC_JS(void, polyworldWaitForDisplay, (), {
    await new Promise(function(resolve) {
      requestAnimationFrame(resolve);
      setTimeout(resolve, 100);
    });
  });
  """.}
  proc polyworldWaitForDisplay() {.importc, nodecl.}

proc waitForDisplay*() =
  ## Paces a browser game loop to the display's refresh. windy's pollEvents
  ## only yields a setTimeout(0), so without this the game renders frames
  ## the browser never shows and stalls when the GPU queue fills up.
  when defined(emscripten):
    polyworldWaitForDisplay()

type ViewingClock* = object
  last: float64
  hidden: bool

proc viewingDelta*(clock: var ViewingClock, window: Window): float32 =
  ## Measures visible wall time without counting time spent in hidden tabs.
  var
    now = epochTime()
    hidden = false
  when defined(emscripten):
    {.emit: """
    `now` = EM_ASM_DOUBLE({
      if (!Module.directorClock) {
        var c = Module.directorClock = {};
        c.hidden = document.hidden;
        c.last = performance.now();
        c.elapsed = 0;
        c.sample = function() {
          var now = performance.now();
          if (!c.hidden) c.elapsed += now - c.last;
          c.last = now;
          c.hidden = document.hidden;
        };
        document.addEventListener('visibilitychange', c.sample);
      }
      Module.directorClock.sample();
      return Module.directorClock.elapsed / 1000;
    });
    `hidden` = EM_ASM_INT({ return document.hidden ? 1 : 0; });
    """.}
  else:
    when compiles(window.minimized):
      hidden = window.minimized
    when compiles(window.visible):
      hidden = hidden or not window.visible
  if clock.last > 0 and not hidden and not clock.hidden:
    result = max(now - clock.last, 0).float32
  clock.last = now
  clock.hidden = hidden
  if captureActive() or defined(backendBench):
    result = 1.0'f / 60

proc damping*(rate, dt: float32): float32 =
  ## Returns a frame-rate-independent exponential easing fraction.
  1.0'f32 - exp(-rate * dt)

proc shortestTurn*(current, target: float32): float32 =
  ## Returns the shortest signed turn between two yaw angles.
  var delta = target - current
  while delta > PI.float32:
    delta -= (2 * PI).float32
  while delta < -PI.float32:
    delta += (2 * PI).float32
  delta

proc addThemeLogo*(builder: AtlasBuilder, path: string) =
  ## Packs one game's theme logo for the loading splash.
  if not builder.addImage(SplashName, readImage(path)):
    raise newException(
      ValueError,
      "the UI atlas is too small for the theme logo"
    )

proc addDefaultFonts*(builder: AtlasBuilder) =
  ## Adds the shared HUD type ramp used by every graphical client.
  builder.addFont(BoldFontPath, "H1", 32.0)
  builder.addFont(DefaultFontPath, "Default", 18.0)
  builder.addFont(BoldFontPath, "Bold", 18.0)
  builder.addFont(DefaultFontPath, "Hud", 15.0)
  builder.addFont(DefaultFontPath, "Small", 12.0)
  builder.addFont(MonoFontPath, "Mono", 18.0)

proc applyThemePatches*(sk: Silky) =
  ## Uses the measured corner slices of the main theme 9-patches.
  sk.theme.windowPatch = 7
  sk.theme.headerPatch = 4
  sk.theme.framePatch = 5
  sk.theme.buttonPatch = 5
  sk.theme.dropdownPatch = 5
  sk.theme.textboxPatch = 4
  sk.theme.tooltipPatch = 3
  sk.theme.scrollbarPatch = 5
  sk.theme.scrollbarTrackPatch = 3
  sk.theme.progressBarPatch = 3
  sk.theme.scrubberPatch = 3

proc addHudGlyphs(builder: AtlasBuilder) =
  ## Packs the shared transport and HUD glyphs every game can draw.
  for file in walkDir(IconDir):
    if not file.path.endsWith(".png"):
      continue
    let
      name = splitFile(file.path).name
      icon = readImage(file.path).resize(HudIconSize, HudIconSize)
    if not builder.addImage(name, icon):
      raise newException(
        ValueError,
        "the UI atlas is too small for HUD icons"
      )

proc newHudAtlas*(size = 1024): AtlasBuilder =
  ## Starts an atlas with the shared main theme and UI images.
  result = newAtlasBuilder(size, 4)
  result.addDir(MainThemeDir, MainThemeDir)
  result.addDir(UiDir, UiDir)
  result.addHudGlyphs()

proc gameWindowSize*(width, height: int32): IVec2 =
  ## Returns a requested window size, or the shared default.
  if width > 0 and height > 0:
    ivec2(width, height)
  else:
    DefaultWindowSize

proc initGameWindow*(
    title,
    atlasPath: string,
    size = DefaultWindowSize,
    vsync = true,
    msaa = msaaDisabled,
    visible = true
): (Window, Silky) =
  ## Creates the viewer and renderer, keeping screenshot captures hidden.
  let
    selectedSize = when defined(backendBench): ivec2(1280, 800) else: size
    selectedMsaa =
      when defined(backendBench):
        when BackendBenchSamples == 1:
          msaaDisabled
        elif BackendBenchSamples == 2:
          msaa2x
        elif BackendBenchSamples == 4:
          msaa4x
        elif BackendBenchSamples == 8:
          msaa8x
        else:
          {.error: "backendBenchSamples must be 1, 2, 4, or 8".}
      else:
        msaa
  let window = newWindow(
    title,
    selectedSize,
    visible = visible and not captureActive() and
      (not defined(backendBench) or defined(emscripten)),
    vsync = vsync and not captureActive() and not defined(backendBench),
    msaa = selectedMsaa
  )
  window.prepareDesktopFullscreen()
  initRenderer(window, max(1, ord(selectedMsaa)))
  let sk = newGameUi(window, atlasPath)
  sk.applyThemePatches()
  (window, sk)

proc drawSplash*(
    sk: Silky,
    window: Window,
    name = SplashName
) =
  ## Draws the theme logo centered on a black frame.
  clearFrame(color(0, 0, 0, 1))
  sk.beginUi(window, window.size)
  if name in sk.atlas.entries:
    let
      uv = sk.atlas.entries[name]
      src = vec2(uv.width.float32, uv.height.float32)
      view = window.size.vec2 / sk.uiScale
      area = view * 0.78
      scale = min(area.x / max(src.x, 1), area.y / max(src.y, 1))
      dest = src * scale
      pos = (view - dest) * 0.5
    sk.drawQuad(
      pos,
      dest,
      vec2(uv.x.float32, uv.y.float32),
      src,
      rgbx(255, 255, 255, 255)
    )
  sk.finishUi()
  window.presentRenderer()
  pollEvents()

proc startSplash*(
    sk: Silky,
    window: Window,
    name = SplashName
): Splash =
  ## Shows the splash and starts the hold clock.
  result.startedAt = epochTime()
  result.name = name
  drawSplash(sk, window, name)

proc holdSplash*(
    sk: Silky,
    window: Window,
    splash: Splash,
    seconds = SplashSeconds
) =
  ## Keeps the splash up until the hold time elapses.
  if captureActive() or defined(emscripten) or defined(backendBench):
    drawSplash(sk, window, splash.name)
  else:
    while epochTime() - splash.startedAt < seconds:
      if window.closeRequested:
        quit(0)
      drawSplash(sk, window, splash.name)
      sleep(10)

var
  presentDeadline = 0.0
  presentPaceHz = 0

proc presentFrame*(window: Window, paceHz = 60) =
  ## Swaps the back buffer, then waits so presents stay on one cadence.
  ## ProMotion vsync alone flips between 8.33 ms and 16.67 ms.
  window.presentRenderer()
  if paceHz <= 0 or captureActive() or defined(backendBench):
    presentDeadline = 0
    presentPaceHz = 0
    return
  if paceHz != presentPaceHz:
    presentDeadline = 0
    presentPaceHz = paceHz
  let
    step = 1.0 / paceHz.float64
    now = epochTime()
  if presentDeadline <= 0 or now > presentDeadline + step * 2:
    presentDeadline = now + step
    return
  let remain = presentDeadline - now
  if remain > 0.001:
    sleep(int(remain * 1000.0))
  presentDeadline += step

proc frameDelta*(
    lastFrameTime: var float64,
    captureStep = 1.0'f32 / 60.0'f32
): float32 =
  ## Returns clamped wall-clock dt, or a fixed step when capturing.
  let now = epochTime()
  result = clamp(now - lastFrameTime, 0.0, 0.1).float32
  lastFrameTime = now
  if defined(backendBench):
    result = 1.0'f / 60
  elif captureActive():
    result = captureStep

proc simulationActive*(transport: Player): bool =
  ## Returns whether presentation should advance on this frame.
  transport.playing or transport.targetTick >= 0

proc atLiveTickCap*(tick, maximumTicks: int32, live: bool): bool =
  ## Returns whether a live match has used its configured tick budget.
  live and tick >= maximumTicks

proc applyScreenshotCamera*(cameraDistance: var float32) =
  ## Overrides camera distance from CAM_DIST when capturing.
  if captureActive():
    if existsEnv("CAM_DIST"):
      cameraDistance = getEnv("CAM_DIST").parseFloat.float32

proc writeScreenshot*(window: Window, path: string) =
  ## Writes the current draw target and creates its parent directory if needed.
  if path.len == 0:
    raise newException(ScreenshotError, "Screenshot output path is empty")
  let
    size = window.size
    image = readFrameImage(size.x, size.y)
    directory = path.parentDir
  try:
    if directory.len > 0:
      createDir(directory)
    image.writeFile(path)
  except CatchableError as error:
    raise newException(ScreenshotError,
      "Could not save screenshot: " & error.msg)

proc captureFrame*(
  window: Window, frame: var int, waitFrames = DefaultScreenshotFrames,
  defaultPath = "screenshot.png"
): bool =
  ## Saves the selected rendered frame and lets the game perform normal cleanup.
  if not captureActive():
    return false
  if captureFinished():
    return true
  inc frame
  if not captureDue(frame, waitFrames):
    return false
  let path = capturePath(defaultPath)
  window.writeScreenshot(path)
  finishCapture()
  echo "Saved screenshot: ", path
  true

proc captureScreenshot*(
  window: Window, frame: var int, waitFrames: int, defaultPath: string
) =
  ## Preserves the standalone developer capture hook that exits after saving.
  if captureFrame(window, frame, waitFrames, defaultPath):
    quit(0)

proc reportReplayFrame*(tick, mismatches: int32) =
  ## Reports browser readiness and divergence after presenting a game frame.
  when defined(emscripten):
    {.emit: """
    EM_ASM({
      if (Module.polyworldFrame) Module.polyworldFrame($0, $1);
    }, `tick`, `mismatches`);
    """.}

proc reportDirectorFrame*(cam: ActionCam, transport: Player,
    distance: float32, mismatches: int32) =
  ## Exposes viewer diagnostics only in browser acceptance test builds.
  when defined(emscripten) and defined(directorProbe):
    let
      enabled = cam.enabled
      locked = cam.locked
      id = cam.director.subject.id
      floor = cam.director.subject.floor
      time = cam.director.time
      overview = cam.director.overview
      finalResults = cam.director.finalResults
      playing = transport.playing
      seeking = transport.targetTick >= 0
      tick = transport.tick
      speed = transport.speed
    {.emit: """
    EM_ASM({
      Module.directorProbe = (Object.freeze({
        enabled: !!$0, locked: !!$1, id: $2, floor: $3, time: $4,
        overview: !!$5, finalResults: !!$6, playing: !!$7,
        seeking: !!$8, tick: $9, speed: $10, distance: $11, mismatches: $12
      }));
    }, `enabled`, `locked`, `id`, `floor`, `time`, `overview`,
      `finalResults`, `playing`, `seeking`, `tick`, `speed`, `distance`,
      `mismatches`);
    """.}
