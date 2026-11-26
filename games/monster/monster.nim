import
  std/[os, strutils, times],
  polyworld/cli,
  common, maps, sim, brains, conversations, options

when not defined(headless):
  import
    std/unicode,
    pixie, silky, vmath, windy,
    polyworld/[assets, renderer, rtscameras, viewers],
    scenes, ui, hudassets, selections

  when not defined(emscripten):
    import voices, launches

const RepositoryRoot = currentSourcePath().parentDir.parentDir.parentDir

when not defined(headless):
  const
    CameraDistanceMin = 12'f
    CameraDistanceMax = 50'f
    CameraDistanceDefault = 34'f

when defined(headless):
  proc runGame(settings: Options) =
    ## Exercises a real conversation and its complete physical action plan.
    if settings.game.capture.captureRequested():
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
    var world = newWorld(generateMap(settings.game.seed.int))
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

  proc runGame(settings: Options) =
    ## Runs a responsive camera and chat around the fixed creature simulation.
    let
      capturing = captureActive()
      worldPath = settings.saveDir / "world.json"
      savePath = if capturing or defined(backendBench): "" else: worldPath
      atlasPath =
        when defined(emscripten): "/tmp/monster.atlas.png"
        else: RepositoryRoot / "tmp" / "monster.atlas.png"
      brain = newBrain(
        settings.saveDir / "conversation.json", settings.model,
        not settings.offline and (not capturing or settings.prompt.len > 0)
      )
    if capturing or defined(backendBench):
      brain.disableSaving()
    defer:
      brain.close()
    var world = newWorld(generateMap(settings.game.seed.int))
    world.restoreWorld(worldPath)
    createDir(atlasPath.parentDir)
    let builder = newHudAtlas(4096)
    builder.addFonts()
    builder.addHudAssets()
    builder.write(atlasPath)
    let (window, sk) = initGameWindow(
      "Monster / Polyworld", atlasPath,
      ivec2(settings.game.windowWidth, settings.game.windowHeight),
      vsync = settings.game.vsync,
      visible = not capturing
    )
    sk.builder = builder
    defer:
      window.onFrame = nil
      when not defined(backendBench):
        if not capturing:
          world.saveWorld(savePath)
      window.close()
    var captureTarget: ScreenshotTarget
    defer:
      captureTarget.releaseScreenshotTarget()
    let scene = newMonsterScene(
      window, world.map, sk.atlas, sk.atlasTexture()
    )
    defer:
      scene.close()
    when not defined(emscripten):
      let voice = newMonsterVoice(
        historyCount = brain.messages.len,
        enabled = not settings.offline and not settings.noVoice and
          not settings.game.soundMuted and not capturing and
          getEnv("COGAME_LLM").toLowerAscii() != "off"
      )
      defer:
        voice.close()
      voice.refreshKey()
      if settings.conversation:
        voice.setMode(ConversationMode)
    var
      chat = initChatUi()
      clock: ViewingClock
      accumulator = 0'f
      paused = settings.game.pauseOnStart
      cameraDistance = CameraDistanceDefault
      cameraTarget = rtsFollowFrame(
        vec3(world.creature.position.x, 0, world.creature.position.y),
        cameraDistance, 0.23'f
      )
      following = true
      frame = 0
      autoSent = false
      lastSave = epochTime()
    if settings.selection.len > 0:
      let selected = world.selectionById(settings.selection)
      if selected.kind == NoSelection:
        raise newException(MonsterError,
          "Unknown selection: " & settings.selection)
      discard chat.select(world, selected)
      following = selected.kind == MossSelection
    let started = epochTime()
    var benchmarkFinished = false
    window.installInput(chat.addr)
    window.onFrame = proc() =
      when defined(frameBench): beginBenchFrame(window)
      ## Consumes input before Windy clears the browser's per-frame events.
      when not defined(emscripten):
        voice.poll(window.focused)
      if window.size.x <= 0 or window.size.y <= 0:
        sleep(20)
        return
      beginBenchmarkFrame("monster", window.size)
      let dt =
        if capturing: 1'f / 60
        else: min(clock.viewingDelta(window), 0.1'f)
      if not chat.typing and window.buttonPressed[KeySpace]:
        paused = not paused
      if not paused:
        accumulator += dt * settings.game.speed.float32
      while accumulator >= 1'f / TickRate.float32:
        world.step()
        accumulator -= 1'f / TickRate.float32
      discard world.receive(brain)
      if settings.game.verbose:
        for text in world.events:
          echo text
      world.outcomes(brain, savePath)
      when not defined(emscripten):
        voice.observe(brain.messages)
        voice.submitPending(world, brain)
      discard world.sendPrompt(brain, settings.prompt, autoSent)
      chat.scale = chatScale(window.size.vec2)
      chat.updateMinimapCamera(window, world, cameraTarget, following)
      let blocked = chat.mouseOverUi(window)
      if not blocked:
        cameraDistance = clamp(
          cameraDistance - window.scrollDelta.y * 2,
          CameraDistanceMin, CameraDistanceMax
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
        discard chat.select(world, Selection())
        following = true
        cameraDistance = CameraDistanceDefault
        chat.focusRequested = false
      if following:
        let target = rtsFollowFrame(
          vec3(world.creature.position.x, 0, world.creature.position.y),
          cameraDistance, 0.23'f
        )
        cameraTarget = mix(cameraTarget, target, damping(8, dt))
      cameraTarget.x = clamp(cameraTarget.x, -MapHalf + 3, MapHalf - 3)
      cameraTarget.z = clamp(cameraTarget.z, -MapHalf + 3, MapHalf - 3)
      let renderTime = (world.tick.float32 +
        accumulator * TickRate.float32) / TickRate.float32
      if not blocked and window.buttonPressed[MouseLeft] and
        not window.buttonDown[MouseRight] and
        not window.buttonDown[MouseMiddle]:
          let picked = scene.pickSelection(window, world, cameraTarget,
            cameraDistance, renderTime)
          if chat.select(world, picked):
            following = chat.selection.kind == MossSelection
      discard captureTarget.beginScreenshotFrame(window)
      scene.drawScene(
        window, world, cameraTarget, cameraDistance,
        renderTime, chat.selection
      )
      sk.uiScale = chat.scale
      when not defined(emscripten):
        chat.voiceEnabled = voice.enabled
        chat.voiceHasKey = voice.hasKey
        chat.conversationMode = voice.mode == ConversationMode
        chat.voiceConnected = voice.client.state == Connected
        chat.voiceConnecting = voice.client.state == Connecting
        chat.voiceListening = voice.listening()
        chat.voiceSpeaking = voice.speaking()
        chat.voiceStatus = voice.status()
        chat.voiceError = voice.error
      sk.beginGameUi(window, window.size)
      let spoken = sk.drawUi(
        window, world, chat, brain.messages,
        brain.pending or brain.explanationPending,
        brain.available(), brain.failure, cameraTarget, cameraDistance,
        following
      )
      sk.finishUi()
      window.syncInput(chat)
      when not defined(emscripten):
        if chat.textModeRequested:
          voice.setMode(TextMode)
          chat.textModeRequested = false
        if chat.conversationModeRequested:
          voice.setMode(ConversationMode)
          chat.conversationModeRequested = false
      if spoken.len > 0:
        when not defined(emscripten):
          voice.interrupt()
        if not world.speak(brain, spoken):
          chat.restoreInput(spoken)
      when not defined(emscripten):
        voice.observe(brain.messages)
        voice.poll(window.focused)
      when not defined(backendBench):
        if not capturing and epochTime() - lastSave > 10:
          world.saveWorld(savePath)
          lastSave = epochTime()
      if endBenchmarkFrame(world.tick.int):
        benchmarkFinished = true
        when not defined(emscripten):
          window.closeRequested = true
        return
      if capturing:
        let ready = settings.prompt.len == 0 or
          (not brain.pending and not brain.explanationPending and
          not world.active and world.actions.len == 0)
        if ready:
          if settings.prompt.len > 0 and brain.failure.len > 0:
            raise newException(MonsterError, "Creature request failed: " & brain.failure)
          if window.captureFrame(frame):
            when not defined(emscripten):
              window.closeRequested = true
            return
        else:
          inc frame
      if capturing and epochTime() - started > 120:
        raise newException(MonsterError, "Timed out waiting for capture.")
      if not capturing:
        window.presentFrame()
        reportReplayFrame(world.tick, 0)
    while not window.closeRequested and not benchmarkFinished:
      pollEvents()
      waitForDisplay()

proc main() =
  ## Resolves repository assets and reports actionable startup failures.
  try:
    when not defined(headless) and not defined(emscripten):
      restoreMonsterDirectory()
    let settings = parseOptions()
    when not defined(headless):
      configureCapture(settings.game.capture, "output/monster.png")
      when not defined(emscripten):
        if not settings.offline and not settings.noVoice and
          not settings.game.soundMuted and
          not captureActive() and
          getEnv("COGAME_LLM").toLowerAscii() != "off":
            if launchMonster():
              return
    when not defined(emscripten):
      setCurrentDir(RepositoryRoot)
    if not settings.game.capture.captureRequested():
      createDir(settings.saveDir)
    runGame(settings)
    when not defined(headless) and not defined(emscripten):
      finishMonster()
  except MonsterError, ScreenshotError, IOError:
    stderr.writeLine("Monster: " & getCurrentExceptionMsg())
    quit(1)

main()
