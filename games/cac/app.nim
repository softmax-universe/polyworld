## What every game mode shares: the window, the renderers, the heroes and
## the class choice. A mode is a client of the core that presents its match
## with these.
import std/[options, os]
import chroma, opengl, pixie, silky, vmath, windy
import core/sim, core/sessions, ui/cardfaces, scene/cardrenderer,
  vfx/vfxrenderer, scene/post, scene/table, scene/courtyard, scene/heroes,
  ui/hud, ui/heroselect, ui/frontendassets, scene/heroselectstage, paths,
  replayer, net/multiplayer
import polyworld/[assets, characters, chargen, connections,
  menus, viewers]

when not defined(emscripten):
  import polyworld/replaysaves, core/replays, replaylibraries, replaysettings
  export replaysettings

when PostPanelControls:
  import polyworld/common

const
  WindowTitle = "Cards and Casters"
  AppName* = "Polyworld CaC"
  CameraNear* = 0.1'f32
  CameraFar* = 100.0'f32
  ClassChoiceTarget* = HeroSelectCameraTarget

when PostLayerControls:
  const PostLayerKeys*: array[PostLayer, Button] =
    [Key1, Key2, Key3, Key4, Key5, Key6, Key7, Key8, Key9, Key0]


type
  App* = ref object
    options*: SessionOptions
    preferences*: Preferences
    preferenceError*: string
    connection*: Connection
    network*: NetworkMatch
    configuredSeats*: seq[Seat]
    configuredBotSources*: seq[string]
    configuredHumanSeat*: int = -1
    playerNames*: seq[string]
    returnToMenu*: bool
    battlefieldPlayers: int
    captureFramebuffer*: GLuint
    captureTexture, captureDepth: GLuint
    captureSize: IVec2
    humanSeat*: Option[Seat]
      ## The class and deck the human brought with `--human PATH.bas`;
      ## without one they choose a class and play its precon.
    appDir*: string  ## The project folder: players/, the atlas, screenshots.
    window*: Window
    sk*: Silky
    solid*: SolidRenderer
    cards*: CardRenderer
    vfx*: VfxRenderer
    post*: PostFx
    courtyard*: CourtyardRenderer
    selectionStage*: HeroSelectStage
    scene*: CharacterScene
    models*: array[HeroSeats, array[HeroClass, CharacterModel]]
    idleClips*: array[HeroSeats, array[HeroClass, int]]
    deathClips*: array[HeroSeats, array[HeroClass, int]]
    replay*: Replayer  ## Set when watching a recorded match.
    when not defined(emscripten):
      replayPreferences*: ReplayPreferences
      replaySaveError*: string
      unsavedReplays*: seq[ReplayData]
      recording*: ReplayRecorder
      replaySaving: ReplaySaveState

const DefaultBots* = ["archer.bas", "warrior.bas", "mage.bas",
    "archer_warrior.bas"]
  ## The reference bots in players/, one per precon, for seats no --bot
  ## fills.

proc defaultBotSources*(appDir: string): seq[string] =
  for name in DefaultBots:
    let path = appDir / "players" / name
    if fileExists(path):
      result.add readFile(path)

proc polyworldRoot*(): string =
  var candidates: seq[string]
  let configured = getEnv("POLYWORLD_REPO")
  if configured.len > 0:
    candidates.add configured
  let appDir = getAppDir()
  for base in [appDir, getCurrentDir()]:
    candidates.add base / ".." / ".."
  candidates.add getCurrentDir()
  for candidate in candidates:
    let root = absolutePath(candidate)
    if fileExists(root / "src" / "polyworld" / "common.nim") and
        dirExists(root / ".." / "polyworld_art"):
      return root

proc lightLikeCourtyard*(scene: CharacterScene, cameraSide: float32) =
  ## Gives the heroes the courtyard's lighting: a cool hemisphere ambient,
  ## the same warm key from the same direction, and a moonlit rim that
  ## keeps a dark silhouette readable against dark stone. Call after
  ## beginCharacters, which sets the shared defaults.
  let
    context = scene.context
    # Heroes have no mapped relief, so they take less fill and a stronger
    # key than the stone: shape has to come from the light alone.
    ambient = (CourtyardAmbientGround + CourtyardAmbientSky) * 0.30'f32
    key = CourtyardKeyColor * 1.15'f32
    keyDirection = courtyardKeyDirection(cameraSide)
  context.ambientLightColor =
    color(ambient.x, ambient.y, ambient.z, 1.0)
  # The PBR shader negates the light vectors.
  context.sunLightDirection = -keyDirection
  context.sunLightColor = color(key.x, key.y, key.z, 1.0)
  context.rimLightDirection =
    normalize(vec3(-keyDirection.x, 0.35, -keyDirection.z))
  context.rimLightColor = color(0.55, 0.62, 0.78, 0.30)
  # A daylight probe would wash out a night courtyard, and a hot specular
  # on a hero's head would feed the bloom.
  context.environmentMapStrength = 0.25
  context.exposure = 0.9

proc buildUiAtlas*(cardAssets: string): AtlasBuilder =
  ## The UI atlas: every card face part, the HUD's images and its fonts.
  ## Raises when they outgrow it. Call initCardAssets first.
  result = newHudAtlas(5632)
  result.addFrontendAssets()
  result.addFaceAssets()
  result.addCacHudAssets(cardAssets)
  when PostPanelControls:
    # Silky's widget images, for the screen-effects tuning window.
    const EditorTheme = DataRoot & "/themes/editor/"
    result.addDir(EditorTheme, EditorTheme)
  result.addFont(cardAssets / "fonts/Grenze-SemiBold.ttf", "H1", 60.0)
  result.addFont(DefaultFontPath, "Default", 34.5)
  result.addFont(DefaultFontPath, "Hud", 28.5)
  result.addFont(DefaultFontPath, "Small", 22.5)

proc initApp*(sessionOptions: SessionOptions): App =
  ## Opens the window and loads everything the modes draw with.
  when defined(emscripten):
    let appDir = "/"
    setCurrentDir("/")
  else:
    # The game folder contains the bundled player programs.
    const sourceDir = currentSourcePath().parentDir
    let
      appDir =
        if dirExists(getAppDir() / "players"): getAppDir()
        elif dirExists(sourceDir / "players"): sourceDir
        else: getAppDir()
      root = polyworldRoot()
    if root.len == 0:
      raise newException(IOError,
        "Could not find Polyworld. Set POLYWORLD_REPO to its repository root.")
    setCurrentDir(root)

  let
    cardAssets = artworkRoot() / "cards"
    atlasPath = appDir / "cac.atlas.png"
  initCardAssets(cardAssets)
  buildUiAtlas(cardAssets).write(atlasPath)

  var window: Window
  var sk: Silky
  (window, sk) = initGameWindow(
    WindowTitle,
    atlasPath,
    ivec2(3200, 2000),
    vsync = true
  )

  var
    solid = initSolidRenderer()
    cardSurfaces = initCardRenderer()
    vfx = initVfxRenderer(cardAssets.parentDir / "vfx" / "textures")
    post = initPostFx()
  var courtyard = initCourtyardRenderer(sessionOptions.playerCount)
  let selectionStage = initHeroSelectStage()
  let scene = newCharacterScene(window)
  # CaC lights heroes with the courtyard's own night rig, not the shared
  # toon ramp: see lightLikeCourtyard.
  scene.shading = PbrCharacters
  var
    models: array[HeroSeats, array[HeroClass, CharacterModel]]
    idleClips: array[HeroSeats, array[HeroClass, int]]
    deathClips: array[HeroSeats, array[HeroClass, int]]
  let
    heroManifest = readManifest(ChargenLibrary)
    heroPresets = readHeroPresets()
  for seat in 0 ..< HeroSeats:
    for heroClass in HeroClass:
      models[seat][heroClass] = heroManifest.loadHeroModel(
        heroPresets[seat][heroClass], heroClass)
      idleClips[seat][heroClass] =
        models[seat][heroClass].clipIndex(HeroIdleClips[heroClass])
      deathClips[seat][heroClass] =
        models[seat][heroClass].clipIndex(HeroDeathClip)
  result = App(options: sessionOptions, appDir: appDir, window: window, sk: sk,
    solid: solid, cards: cardSurfaces, vfx: vfx, post: post,
    courtyard: courtyard, selectionStage: selectionStage, scene: scene, models: models,
    idleClips: idleClips, deathClips: deathClips,
    battlefieldPlayers: sessionOptions.playerCount)
  try:
    result.preferences = readPreferences(AppName)
  except MenusError, IOError, OSError:
    result.preferenceError = getCurrentExceptionMsg()
    result.preferences = Preferences()
  when not defined(emscripten):
    result.replayPreferences = ReplayPreferences()
    try:
      result.replayPreferences = readReplayPreferences()
    except MenusError, IOError, OSError:
      result.replaySaveError = getCurrentExceptionMsg()
  result.preferences.applyPreferences(window,
    configureDisplay = not defined(takeScreenshot))

when not defined(emscripten):
  proc replaySavedPath*(app: App): string =
    ## Returns the last successfully saved prefix of the current match.
    app.replaySaving.savedPath

  proc useReplayRecording*(app: App, recorder: ReplayRecorder = nil) =
    ## Starts a fresh recording session without discarding failed prior saves.
    app.recording = if app.replay == nil: recorder else: nil
    app.replaySaveError = ""
    app.replaySaving.resetReplaySave()

  proc beginReplayRecording*(app: App, seats: openArray[Seat],
      seed: int64, messages: openArray[ReplayAction] = []): ReplayRecorder =
    ## Records the exact decks and public names used to start a local match.
    app.useReplayRecording()
    if app.replay != nil:
      return
    if seed < low(int32).int64 or seed > high(int32).int64:
      app.replaySaveError = "This seed is outside the replay format's range."
      return
    var config = GameConfig(seed: seed.int32, maxTicks: MaxReplayHashes.int32)
    for index in 0 ..< seats.len:
      config.players.add PlayerConfig(name:
        if index < app.playerNames.len: app.playerNames[index]
        else: "Player " & $(index + 1))
    result = initReplayRecorder(
      matchSetup(seats, seed.int32, MaxReplayHashes.uint32), config)
    for message in messages:
      result.record(message)
    app.recording = result

  proc saveCurrentReplay*(app: App): string =
    ## Saves a completed action prefix once, sharing manual and automatic saves.
    if app.replay != nil or app.recording == nil:
      raise newException(ReplayError, "There is no live match replay to save.")
    app.replaySaving.requestReplaySave()
    let data = app.recording.data
    result = app.replaySaving.saveReplaySnapshot(data,
      proc(data: ReplayData): string =
        ## Writes a validated CaC recording to its desktop library.
        saveLibraryReplay(data)
    )
    app.replaySaveError = ""

  proc updateReplaySaving*(app: App, completed: bool) =
    ## Saves a completed match before the player leaves its result screen.
    if app.replay == nil and app.recording != nil and
      app.replaySaving.beginAutomaticReplaySave(
        app.replayPreferences.saveReplay, completed):
        try:
          discard app.saveCurrentReplay()
        except CatchableError as error:
          app.replaySaveError = "Cannot save replay: " & error.msg

  proc finishReplayRecording*(app: App) =
    ## Preserves failed exit saves for retry after the renderer has cleaned up.
    if app.replay != nil or app.recording == nil or
      not app.replaySaving.shouldSaveReplayOnExit(
        app.replayPreferences.saveReplay):
        return
    try:
      discard app.saveCurrentReplay()
    except CatchableError as error:
      app.replaySaveError = "Cannot save replay: " & error.msg
      if app.window != nil:
        app.window.closeRequested = false
      try:
        app.recording.data.validate()
        app.unsavedReplays.add(app.recording.data)
      except ReplayError:
        discard

  proc retryPendingReplays*(app: App) =
    ## Removes retained recordings only after their library writes succeed.
    try:
      app.unsavedReplays.retryReplaySaves(
        proc(data: ReplayData): string =
          ## Writes a retained CaC recording to its desktop library.
          saveLibraryReplay(data)
      )
      app.replaySaveError = ""
    except CatchableError as error:
      app.replaySaveError = "Cannot save replay: " & error.msg

proc setBattlefield*(app: App, playerCount: int) =
  ## Uses Tower Arena for two players and the ring for larger matches.
  if app.battlefieldPlayers == playerCount:
    return
  var replacement = initCourtyardRenderer(playerCount)
  replacement.material = app.courtyard.material
  app.courtyard.dispose()
  app.courtyard = replacement
  app.battlefieldPlayers = playerCount

proc closeCapture*(app: App) =
  ## Releases the hidden capture target while the window context is alive.
  if app.captureFramebuffer == 0:
    return
  glBindFramebuffer(GL_FRAMEBUFFER, 0)
  glDeleteFramebuffers(1, app.captureFramebuffer.addr)
  glDeleteTextures(1, app.captureTexture.addr)
  glDeleteRenderbuffers(1, app.captureDepth.addr)
  app.captureFramebuffer = 0
  app.captureTexture = 0
  app.captureDepth = 0
  app.captureSize = ivec2(0)

proc beginCaptureFrame*(app: App) =
  ## Renders screenshots offscreen without depending on a visible Cocoa drawable.
  when defined(takeScreenshot):
    when not defined(emscripten):
      doAssert not app.window.visible, "Capture windows must stay hidden"
    let size = app.window.size
    if app.captureFramebuffer == 0 or app.captureSize != size:
      app.closeCapture()
      glGenFramebuffers(1, app.captureFramebuffer.addr)
      glBindFramebuffer(GL_FRAMEBUFFER, app.captureFramebuffer)
      glGenTextures(1, app.captureTexture.addr)
      glBindTexture(GL_TEXTURE_2D, app.captureTexture)
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.GLint, size.x, size.y,
        0, GL_RGBA, GL_UNSIGNED_BYTE, nil)
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST.GLint)
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST.GLint)
      glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
        GL_TEXTURE_2D, app.captureTexture, 0)
      glGenRenderbuffers(1, app.captureDepth.addr)
      glBindRenderbuffer(GL_RENDERBUFFER, app.captureDepth)
      glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8,
        size.x, size.y)
      glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT,
        GL_RENDERBUFFER, app.captureDepth)
      if glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE:
        app.closeCapture()
        raise newException(IOError, "Unable to allocate screenshot target")
      app.captureSize = size
    glBindFramebuffer(GL_FRAMEBUFFER, app.captureFramebuffer)
    glViewport(0, 0, size.x, size.y)

proc heroClip*(app: App, model: int, heroClass: HeroClass,
    dying, idleTime: float32): tuple[clip: int, time: float32] =
  ## Idle while alive; once dying, the death clip, held on its last
  ## frame.
  if dying < 0:
    (app.idleClips[model][heroClass], idleTime)
  else:
    let clip = app.deathClips[model][heroClass]
    (clip, min(dying,
      app.models[model][heroClass].clipDuration(clip) - 0.001'f32))

proc selectionCamera*(aspect: float32): Vec3 =
  HeroSelectCameraTarget + (HeroSelectCameraEye - HeroSelectCameraTarget) *
    max(1'f32, 1.35'f32 / max(0.1'f32, aspect))

proc drawSelectionHeroes*(app: App, hovered: Option[HeroClass],
    time: float32, cameraEye: Vec3) =
  for heroClass in HeroClass:
    let active = hovered == some(heroClass)
    drawCharacter(app.scene, app.models[0][heroClass],
      HeroSelectPositions[heroClass.ord], 0,
      app.idleClips[0][heroClass], time,
      tint = if active: color(1.18, 1.14, 1.05, 1) else: color(1.05, 1.05, 1.05, 1),
      sizeFactor = SelectionHeroScale * (if active: 1.025'f32 else: 1'f32))
    if active:
      app.vfx.addTargetRing(HeroSelectPositions[heroClass.ord] + vec3(0, 0.03, 0),
        cameraEye, 1.5, 0.8)

template bindApp*(app: App) {.dirty.} =
  ## Names a mode's loop uses for the shared app, so it reads like the rest
  ## of its code: `window`, `sk`, `solid`, `vfx`, `post`...
  bind heroSelectScale, drawHeroSelect, hoveredSelectionHero, selectionCamera
  let
    window = app.window
    sk = app.sk
    scene = app.scene
    sessionOptions = app.options
    appDir = app.appDir
  template solid: untyped = app.solid
  template cardSurfaces: untyped = app.cards
  template vfx: untyped = app.vfx
  template post: untyped = app.post
  template courtyard: untyped = app.courtyard
  template selectionStage: untyped = app.selectionStage
  template models: untyped = app.models
  const
    classChoiceTarget = ClassChoiceTarget
  proc classChoiceEye(aspect: float32): Vec3 = selectionCamera(aspect)
  proc heroClip(model: int, heroClass: HeroClass,
      dying, idleTime: float32): tuple[clip: int, time: float32] =
    app.heroClip(model, heroClass, dying, idleTime)
  proc classSelectionScale(): float32 = heroSelectScale(window)
  proc classSelectionHover(vp: Mat4): Option[HeroClass] =
    hoveredSelectionHero(window, sk.mousePos, vp)
  proc drawClassHeroes(hovered: Option[HeroClass], time: float32, eye: Vec3) =
    app.drawSelectionHeroes(hovered, time, eye)
  proc classSelection(vp: Mat4, human: bool, inputEnabled = true): Option[HeroClass] =
    drawHeroSelect(sk, window, vp, human, inputEnabled)
