import
  std/[os, parseopt, strutils, times],
  common, maps, sim, brains, conversations

when not defined(headless):
  import
    std/unicode,
    opengl, pixie, silky, vmath, windy,
    polyworld/[assets, rtscameras, viewers],
    scenes, ui

const RepositoryRoot = currentSourcePath().parentDir.parentDir.parentDir

type Options = object
  seed, width, height, frames: int
  offline: bool
  saveDir, screenshot, prompt, model: string

proc options(): Options =
  ## Reads a small native launcher interface and explicit capture options.
  var customSave = false
  result = Options(
    seed: 42, width: 1440, height: 900, frames: 3,
    model: DefaultMonsterModel,
    saveDir: getDataDir() / "polyworld" / "monster"
  )
  when defined(takeScreenshot):
    result.screenshot = absolutePath(
      getEnv("SCREENSHOT_PATH", "output/monster.png")
    )
  try:
    for kind, key, value in getopt():
      case kind
      of cmdLongOption, cmdShortOption:
        case key
        of "seed":
          result.seed = parseInt(value)
        of "width":
          result.width = parseInt(value)
        of "height":
          result.height = parseInt(value)
        of "frames":
          result.frames = parseInt(value)
        of "save-dir":
          result.saveDir = absolutePath(value)
          customSave = true
        of "screenshot":
          result.screenshot = absolutePath(value)
        of "prompt":
          result.prompt = value
        of "model":
          result.model = value
        of "offline":
          result.offline = true
        of "help", "h":
          echo "Monster / Polyworld"
          echo "Run from the repository: nim r games/monster/monster.nim"
          echo "Options: --model:ID --seed:N --save-dir:PATH --offline"
          echo "Hidden capture: --screenshot:PATH [--prompt:TEXT] [--frames:N]"
          echo "Or compile with -d:takeScreenshot (default: output/monster.png)."
          echo "Camera: right-drag to pan, wheel to zoom, F to find Moss."
          echo "Conversation: Enter to speak, Escape to release focus."
          quit(0)
        else:
          raise newException(MonsterError, "Unknown option: " & key)
      of cmdArgument:
        raise newException(MonsterError, "Unexpected argument: " & key)
      of cmdEnd:
        discard
  except ValueError:
    raise newException(MonsterError, "Invalid numeric Monster option.")
  if result.width < 640 or result.height < 480 or result.frames < 1:
    raise newException(MonsterError, "Use at least 640x480 and one frame.")
  if not customSave:
    result.saveDir = result.saveDir / $result.seed

when defined(headless):
  proc runGame(settings: Options) =
    ## Exercises a real conversation and its complete physical action plan.
    if settings.screenshot.len > 0:
      raise newException(MonsterError,
        "Use --screenshot or -d:takeScreenshot without -d:headless " &
          "to capture graphics.")
    if settings.prompt.len == 0:
      raise newException(MonsterError, "Headless Monster requires --prompt.")
    let
      savePath = settings.saveDir / "world.json"
      brain = newBrain(
        settings.saveDir / "conversation.json", settings.model,
        not settings.offline
      )
    defer:
      brain.close()
    var world = newWorld(generateMap(settings.seed))
    world.restoreWorld(savePath)
    let started = epochTime()
    var
      physicalTicks = 0
      autoSent = false
    while epochTime() - started < 120:
      if world.active or world.actions.len > 0:
        inc physicalTicks
        if physicalTicks > TickRate * 300:
          raise newException(MonsterError, "Creature action plan did not finish.")
      world.step()
      discard world.receive(brain)
      for text in world.events:
        echo text
      world.outcomes(brain, savePath)
      discard world.sendPrompt(brain, settings.prompt, autoSent)
      if not brain.pending and not brain.explanationPending and
        not world.active and world.actions.len == 0:
          break
      if brain.pending:
        sleep(10)
    if brain.failure.len > 0 or brain.pending or brain.explanationPending:
      raise newException(MonsterError,
        "Creature request failed: " & brain.failure)
    echo "Moss: ", brain.reply.speech
    if world.active or world.actions.len > 0:
      raise newException(MonsterError, "Creature action plan did not finish.")
    world.saveWorld(savePath)
    echo world.observation()
else:
  proc addFonts(builder: AtlasBuilder) =
    ## Includes conversational punctuation and Latin accents in the UI atlas.
    var glyphs = AsciiGlyphs
    for value in 160 .. 255:
      glyphs.add Rune(value).toUTF8()
    for rune in "‘’“”–—…•→←".runes:
      glyphs.add rune.toUTF8()
    builder.addFont(BoldFontPath, "H1", 32, glyphs)
    builder.addFont(DefaultFontPath, "Default", 18, glyphs)
    builder.addFont(BoldFontPath, "Bold", 18, glyphs)
    builder.addFont(DefaultFontPath, "Hud", 15, glyphs)
    builder.addFont(DefaultFontPath, "Small", 12, glyphs)
    builder.addFont(DefaultFontPath, "WorldName", 32, glyphs)

  proc capture(window: Window, path: string) =
    ## Saves the rendered game frame in a local PNG for visual inspection.
    let screenshot = newImage(window.size.x, window.size.y)
    glReadPixels(
      0, 0, window.size.x, window.size.y, GL_RGBA, GL_UNSIGNED_BYTE,
      screenshot.data[0].addr
    )
    screenshot.flipVertical()
    createDir(path.parentDir)
    screenshot.writeFile(path)

  proc runGame(settings: Options) =
    ## Runs a responsive camera and chat around the fixed creature simulation.
    let
      capturing = settings.screenshot.len > 0
      savePath = settings.saveDir / "world.json"
      atlasPath = RepositoryRoot / "tmp" / "monster.atlas.png"
      brain = newBrain(
        settings.saveDir / "conversation.json", settings.model,
        not settings.offline
      )
    defer:
      brain.close()
    var world = newWorld(generateMap(settings.seed))
    world.restoreWorld(savePath)
    createDir(atlasPath.parentDir)
    let builder = newHudAtlas(2048)
    builder.addFonts()
    builder.write(atlasPath)
    let (window, sk) = initGameWindow(
      "Monster / Polyworld", atlasPath,
      ivec2(settings.width.int32, settings.height.int32),
      vsync = not capturing,
      visible = not capturing
    )
    sk.builder = builder
    defer:
      world.saveWorld(savePath)
      window.close()
    let scene = newMonsterScene(
      window, world.map, sk.atlas, sk.atlasTextureId()
    )
    defer:
      scene.close()
    var
      chat = initChatUi()
      clock: ViewingClock
      accumulator = 0'f
      cameraDistance = 34'f
      cameraTarget = rtsFollowFrame(
        vec3(world.creature.position.x, 0, world.creature.position.y),
        cameraDistance, 0.23'f
      )
      following = true
      frame = 0
      autoSent = false
      lastSave = epochTime()
    let started = epochTime()
    window.installInput(chat.addr)
    while not window.closeRequested:
      pollEvents()
      if window.size.x <= 0 or window.size.y <= 0:
        sleep(20)
        continue
      let dt =
        if capturing: 1'f / 60
        else: min(clock.viewingDelta(window), 0.1'f)
      accumulator += dt
      while accumulator >= 1'f / TickRate.float32:
        world.step()
        accumulator -= 1'f / TickRate.float32
      discard world.receive(brain)
      world.outcomes(brain, savePath)
      discard world.sendPrompt(brain, settings.prompt, autoSent)
      chat.scale = clamp(window.size.y.float32 / 900'f, 0.75'f, 2'f)
      let blocked = chat.mouseOverUi(window)
      if not blocked:
        cameraDistance = clamp(
          cameraDistance - window.scrollDelta.y * 2, 12'f, 80'f
        )
        if window.buttonDown[MouseRight] or window.buttonDown[MouseMiddle]:
          let movement = window.mouseDelta.vec2 * cameraDistance * 0.0016'f
          cameraTarget.x -= movement.x
          cameraTarget.z -= movement.y * 1.4'f
          if length(movement) > 0:
            following = false
      if not chat.typing:
        let movement = window.rtsKeyPanDir() * cameraDistance * dt * 0.65'f
        cameraTarget.x += movement.x
        cameraTarget.z += movement.y
        if length(movement) > 0:
          following = false
        if window.buttonPressed[KeyF]:
          chat.focusRequested = true
      if chat.focusRequested:
        following = true
        chat.focusRequested = false
      if following:
        let target = rtsFollowFrame(
          vec3(world.creature.position.x, 0, world.creature.position.y),
          cameraDistance, 0.23'f
        )
        cameraTarget = mix(cameraTarget, target, damping(8, dt))
      cameraTarget.x = clamp(cameraTarget.x, -MapHalf + 3, MapHalf - 3)
      cameraTarget.z = clamp(cameraTarget.z, -MapHalf + 3, MapHalf - 3)
      scene.drawScene(
        window, world, cameraTarget, cameraDistance,
        (world.tick.float32 + accumulator * TickRate.float32) /
          TickRate.float32
      )
      sk.uiScale = chat.scale
      sk.beginUi(window, window.size)
      let spoken = sk.drawUi(
        window, world, chat, brain.messages,
        brain.pending or brain.explanationPending,
        brain.available(), brain.failure
      )
      sk.endUi()
      window.syncInput(chat)
      if spoken.len > 0:
        if not world.speak(brain, spoken):
          chat.restoreInput(spoken)
      if epochTime() - lastSave > 10:
        world.saveWorld(savePath)
        lastSave = epochTime()
      inc frame
      if capturing and frame >= settings.frames and
        not brain.pending and not brain.explanationPending and
        not world.active and world.actions.len == 0:
          window.capture(settings.screenshot)
          echo "Saved ", settings.screenshot
          break
      if capturing and epochTime() - started > 120:
        raise newException(MonsterError, "Timed out waiting for capture.")
      window.swapBuffers()
      waitForDisplay()

proc main() =
  ## Resolves repository assets and reports actionable startup failures.
  try:
    let settings = options()
    setCurrentDir(RepositoryRoot)
    createDir(settings.saveDir)
    runGame(settings)
  except MonsterError:
    stderr.writeLine("Monster: " & getCurrentExceptionMsg())
    quit(1)

main()
