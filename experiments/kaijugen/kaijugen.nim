import
  std/[math, os, strutils, tables, times],
  bumpy, chroma, gltf, pixie, silky, vmath,
  polyworld/[kaijus, shadows, toon]

const
  ExperimentDir = currentSourcePath().parentDir
  TempDir = ExperimentDir / "../../tmp/kaijugen"
  ThemeDir = ExperimentDir / "../../../polyworld_art/themes/main"
  AtlasPath = TempDir / "viewer.atlas.png"
  RecipePath = TempDir / "custom.json"
  ExportPath = TempDir / "kaiju.glb"
  RowWidth = 300
  PanelWidth = 344
  ColorNames = ["Skin", "Belly", "Spikes", "Iris", "Claws"]

type
  PanelTab = enum
    Shape, Colors, Shading
  Options = object
    frames: int
    screenshot, exportPath, loadPath: string
    noPanel: bool
    yaw, pitch: float32
  KaijuApp = object
    sk: Silky
    toon: ToonContext
    settings, built: KaijuSettings
    materials: KaijuMaterials
    root, ground: Node
    tab: PanelTab
    colorName, status: string
    showPanel, turntable, wireframe, orbiting, panning: bool
    yaw, pitch, distance, threshold, softness, contrast, rim: float32
    rampThreshold, rampSoftness: float32
    target: Vec3
    frames: int

proc optionsFromArgs(): Options =
  ## Parses reproducible captures, camera views, and exports without a window.
  result.yaw = 0.68
  result.pitch = 0.20
  try:
    for argument in commandLineParams():
      if argument == "--smoke":
        result.frames = 4
      elif argument == "--no-panel":
        result.noPanel = true
      elif argument.startsWith("--frames="):
        result.frames = argument[9 .. ^1].parseInt
      elif argument.startsWith("--yaw="):
        result.yaw = argument[6 .. ^1].parseFloat.float32
      elif argument.startsWith("--pitch="):
        result.pitch = argument[8 .. ^1].parseFloat.float32
      elif argument.startsWith("--screenshot="):
        result.screenshot = argument[13 .. ^1]
      elif argument.startsWith("--export="):
        result.exportPath = argument[9 .. ^1]
      elif argument.startsWith("--load="):
        result.loadPath = argument[7 .. ^1]
      else:
        raise newException(KaijugenError, "Unknown argument: " & argument)
  except ValueError:
    raise newException(KaijugenError, "Expected a numeric launch option.")
  if result.frames < 0 or not (
    result.yaw >= -2 * PI and result.yaw <= 2 * PI and
    result.pitch >= -0.2 and result.pitch <= 1.45):
      raise newException(KaijugenError, "Camera or frame count out of range.")
  if result.screenshot.len > 0 and result.frames == 0:
    result.frames = 4

proc groundNode(): Node =
  ## Creates the blue studio floor that receives the kaiju's cast shadow.
  let
    white = newImage(1, 1)
    surface = Material(
      name: "Studio floor", baseColor: white,
      baseColorSampler: defaultTextureSampler(),
      baseColorFactor: color(0.49, 0.73, 0.89), roughnessFactor: 1
    )
  white.fill(color(1, 1, 1, 1))
  Node(
    name: "Ground", visible: true, scale: vec3(1),
    rot: quat(0, 0, 0, 1), mesh: Mesh(primitives: @[
      Primitive(
        mode: TrianglesMode, material: surface,
        points: @[
          vec3(-100, -0.02, -100), vec3(-100, -0.02, 100),
          vec3(100, -0.02, 100), vec3(100, -0.02, -100)
        ],
        normals: @[vec3(0, 1, 0), vec3(0, 1, 0),
          vec3(0, 1, 0), vec3(0, 1, 0)],
        indices32: @[0'u32, 1, 2, 0, 2, 3]
      )
    ])
  )

proc geometryKey(settings: KaijuSettings): KaijuSettings =
  ## Excludes palette edits from geometry rebuilds.
  result = settings
  result.colors = default(array[KaijuColor, Vec3])

proc rebuild(app: var KaijuApp) =
  ## Releases old GPU resources before rebuilding the modular character.
  if app.root != nil:
    app.root.clearFromGpu()
  app.root = generateKaiju(app.settings, app.materials)
  app.built = app.settings

proc frameKaiju(app: var KaijuApp) =
  ## Centers the creature with enough space for the crown and curled tail.
  let
    bounds = app.root.getAABounds()
    extent = bounds.max - bounds.min
  app.target = (bounds.min + bounds.max) * 0.5'f
  app.distance = max(extent.y, max(extent.x, extent.z)) * 1.9'f

proc mouseOverUi(app: KaijuApp, window: Window): bool =
  ## Keeps orbit and pan gestures away from the editor panel.
  if not app.showPanel:
    return false
  for state in subWindowStates.values:
    if state.visible and window.mousePos.vec2.overlaps(
      rect(state.pos, state.size)):
        return true
  window.mousePos.x < PanelWidth + 20

proc handleInput(app: var KaijuApp, window: Window, dt: float32) =
  ## Handles the same drag, pan, and zoom interactions as Chargen.
  if window.buttonPressed[KeyEscape]:
    window.closeRequested = true
  if window.buttonPressed[KeyTab]:
    app.showPanel = not app.showPanel
  if window.buttonPressed[KeyW]:
    app.wireframe = not app.wireframe
  if window.buttonPressed[KeySpace]:
    app.turntable = not app.turntable
  if window.buttonPressed[KeyF]:
    app.frameKaiju()
  if window.buttonPressed[Key1]:
    app.tab = Shape
  if window.buttonPressed[Key2]:
    app.tab = Colors
  if window.buttonPressed[Key3]:
    app.tab = Shading
  if window.buttonPressed[KeyC]:
    if app.softness > 0.2:
      app.threshold = 0.48
      app.softness = 0.07
      app.contrast = 0.42
    else:
      app.threshold = 0.55
      app.softness = 1.0
      app.contrast = 0.45
  let overUi = app.mouseOverUi(window)
  if window.buttonPressed[MouseLeft] and not overUi:
    app.orbiting = true
  if (window.buttonPressed[MouseRight] or
    window.buttonPressed[MouseMiddle]) and not overUi:
      app.panning = true
  if not window.buttonDown[MouseLeft]:
    app.orbiting = false
  if not window.buttonDown[MouseRight] and
    not window.buttonDown[MouseMiddle]:
      app.panning = false
  let delta = window.mouseDelta.vec2
  if app.orbiting:
    app.yaw -= delta.x * 0.008'f
    app.pitch = clamp(app.pitch + delta.y * 0.008'f, -0.15'f, 1.4'f)
  if app.panning:
    let right = vec3(cos(app.yaw), 0, -sin(app.yaw))
    app.target -= right * delta.x * app.distance * 0.0012'f
    app.target.y += delta.y * app.distance * 0.0012'f
  if not overUi and window.scrollDelta.y != 0:
    app.distance = clamp(
      app.distance * pow(0.92'f, window.scrollDelta.y), 3.5'f, 16.0'f
    )
  if app.turntable and not app.orbiting:
    app.yaw += dt * 0.35'f

template slider(id, caption: string, value: var float32,
    low, high: float32) =
  ## Draws a caption and a scrubber with a visible numeric value.
  text(caption & "  " & value.formatFloat(ffDecimal, 2))
  scrubber(id, value, low, high, "")

proc shapeControls(app: var KaijuApp, window: Window) =
  ## Adjusts the proportions of the first head, plate, and eye presets.
  let sk = app.sk
  text "Head: Classic"
  slider("head", "Head size", app.settings.headSize, 0.75'f, 1.25'f)
  text "Spikes: Dorsal plates"
  slider("plates", "Plate size", app.settings.spikeSize, 0.4'f, 1.5'f)
  text "Eyes: Fierce"
  slider("eyes", "Eye size", app.settings.eyeSize, 0.75'f, 1.25'f)
  slider("tail", "Tail length", app.settings.tailLength, 0.75'f, 1.25'f)
  slider("facets", "Faceting", app.settings.facets, 0.0'f, 1.0'f)

proc colorControls(app: var KaijuApp, window: Window) =
  ## Edits independent color slots without altering the eye ink or glints.
  let sk = app.sk
  text "Palette: Garden kaiju"
  dropDown(app.colorName, ColorNames)
  var slot = KaijuColor.Skin
  for i, name in ColorNames:
    if name == app.colorName:
      slot = KaijuColor(i)
  slider("red", "Red", app.settings.colors[slot].x, 0.0'f, 1.0'f)
  slider("green", "Green", app.settings.colors[slot].y, 0.0'f, 1.0'f)
  slider("blue", "Blue", app.settings.colors[slot].z, 0.0'f, 1.0'f)
  button "Reset palette":
    app.settings.colors = classicKaiju().colors

proc shadingControls(app: var KaijuApp, window: Window) =
  ## Tunes the existing toon ramp, colored shadows, rim, and studio light.
  let sk = app.sk
  group "shading presets":
    box RowWidth - 16, 34
    layout LeftToRight
    button "Soft toon":
      app.threshold = 0.55
      app.softness = 1.0
      app.contrast = 0.45
    button "Cel":
      app.threshold = 0.48
      app.softness = 0.07
      app.contrast = 0.42
  slider("threshold", "Band threshold", app.threshold, 0.1'f, 0.9'f)
  slider("softness", "Band softness", app.softness, 0.01'f, 1.0'f)
  slider("contrast", "Shadow depth", app.contrast, 0.0'f, 0.8'f)
  slider("rim", "Rim light", app.rim, 0.0'f, 0.5'f)
  slider("azimuth", "Light direction", sunAzimuth, 0.0'f, 360.0'f)
  slider("elevation", "Light height", sunElevation, 15.0'f, 85.0'f)
  checkBox("Cast shadows", sunShadowsEnabled)

proc drawUi(app: var KaijuApp, window: Window) =
  ## Draws the compact generator panel and file actions.
  let sk = app.sk
  glDisable(GL_DEPTH_TEST)
  glDisable(GL_CULL_FACE)
  sk.beginUi(window, window.size)
  ui:
    subWindow("Kaijugen", app.showPanel, vec2(12, 12),
      vec2(PanelWidth, window.size.y.float32 - 24)):
        text "Garden kaiju"
        text "Classic head / dorsal plates / fierce eyes"
        group "tabs":
          box RowWidth, 34
          layout LeftToRight
          radioButton("Shape", app.tab, Shape)
          radioButton("Colors", app.tab, Colors)
          radioButton("Shading", app.tab, Shading)
        frame "controls":
          size(RowWidth, max(280.0'f, window.size.y.float32 - 450))
          case app.tab
          of Shape:
            app.shapeControls(window)
          of Colors:
            app.colorControls(window)
          of Shading:
            app.shadingControls(window)
        group "views":
          box RowWidth, 34
          layout LeftToRight
          button "Front":
            app.yaw = 0
            app.pitch = 0.05
          button "Side":
            app.yaw = PI.float32 / 2
            app.pitch = 0.05
          button "Back":
            app.yaw = PI.float32
            app.pitch = 0.05
          button "3/4":
            app.yaw = 0.68
            app.pitch = 0.20
        group "inspection":
          box RowWidth, 34
          layout LeftToRight
          checkBox("Turntable", app.turntable)
          checkBox("Wireframe", app.wireframe)
          button "Fit":
            app.frameKaiju()
        group "files":
          box RowWidth, 34
          layout LeftToRight
          button "Save":
            try:
              app.settings.saveKaiju(RecipePath)
              app.status = "Saved tmp/kaijugen/custom.json"
            except KaijugenError as error:
              app.status = error.msg
          button "Load":
            try:
              app.settings = loadKaiju(RecipePath)
              app.status = "Loaded custom recipe"
            except KaijugenError as error:
              app.status = error.msg
          button "Export GLB":
            try:
              app.settings.exportKaiju(ExportPath)
              app.status = "Exported tmp/kaijugen/kaiju.glb"
            except KaijugenError as error:
              app.status = error.msg
        button "Reset kaiju":
          app.settings = classicKaiju()
          app.frameKaiju()
        text "Drag orbit / right drag pan / scroll zoom"
        text "1/2/3 tabs / C cel / Space turntable"
        if app.status.len > 0:
          text app.status
  sk.endUi()

proc drawScene(app: var KaijuApp, window: Window) =
  ## Renders the first kaiju with a tunable toon ramp and real sun shadows.
  if app.threshold != app.rampThreshold or app.softness != app.rampSoftness:
    app.toon.setRamp(rampImage(
      app.threshold - app.softness * 0.5'f,
      app.threshold + app.softness * 0.5'f
    ))
    app.rampThreshold = app.threshold
    app.rampSoftness = app.softness
  let
    left = if app.showPanel: PanelWidth.int32 + 24 else: 0'i32
    width = max(1'i32, window.size.x - left)
    height = max(1'i32, window.size.y)
    eye = app.target + vec3(
      sin(app.yaw) * cos(app.pitch), sin(app.pitch),
      cos(app.yaw) * cos(app.pitch)
    ) * app.distance
    halfHeight = app.distance * 0.31'f
    aspect = width.float32 / height.float32
  app.toon.view = lookAt(eye, app.target, vec3(0, 1, 0))
  app.toon.proj = ortho(
    -halfHeight * aspect, halfHeight * aspect,
    -halfHeight, halfHeight, -1000.0'f, 1000.0'f
  )
  app.toon.cameraPosition = eye
  app.toon.highlightColor = color(1.35, 1.22, 1.10)
  app.toon.shadowColor = color(
    1 - app.contrast, 1 - app.contrast, 1 - app.contrast
  )
  app.toon.rimColor = color(0.85, 0.95, 1, app.rim)
  updateSunMatrix()
  app.toon.lightDirection = -sunDirection
  sunDepthPasses(window.size):
    app.toon.drawSunDepth(app.root)
  glViewport(left, 0, width, height)
  glClearColor(0.49, 0.73, 0.89, 1)
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
  glEnable(GL_MULTISAMPLE)
  app.toon.draw(app.ground)
  app.toon.draw(app.root)
  if app.wireframe:
    glPolygonMode(GL_FRONT_AND_BACK, GL_LINE)
    glEnable(GL_POLYGON_OFFSET_LINE)
    glPolygonOffset(-1, -1)
    app.toon.tint = color(0.08, 0.10, 0.14)
    app.toon.draw(app.root)
    app.toon.tint = color(1, 1, 1)
    glDisable(GL_POLYGON_OFFSET_LINE)
    glPolygonMode(GL_FRONT_AND_BACK, GL_FILL)
  glViewport(0, 0, window.size.x, window.size.y)

proc screenshot(window: Window, path: string) =
  ## Writes a reproducible frame for checking the model and editor layout.
  try:
    createDir(path.parentDir)
    let image = newImage(window.size.x, window.size.y)
    glReadPixels(
      0, 0, window.size.x, window.size.y, GL_RGBA,
      GL_UNSIGNED_BYTE, image.data[0].addr
    )
    image.flipVertical()
    image.writeFile(path)
  except IOError, OSError, PixieError:
    raise newException(KaijugenError, "Cannot save screenshot: " &
      getCurrentExceptionMsg())

proc main() =
  ## Opens Kaijugen or exports a recipe without requiring a display.
  let options = optionsFromArgs()
  var settings = classicKaiju()
  if options.loadPath.len > 0:
    settings = loadKaiju(options.loadPath)
  if options.exportPath.len > 0:
    settings.exportKaiju(options.exportPath)
    echo "Exported ", options.exportPath
    return
  createDir(TempDir)
  let builder = newAtlasBuilder(1024, 4)
  builder.addDir(ThemeDir & "/", ThemeDir & "/")
  builder.addFont(ThemeDir / "IBMPlexSans-Regular.ttf", "Default", 16)
  builder.addFont(ThemeDir / "IBMPlexSans-Regular.ttf", "H1", 26)
  builder.write(AtlasPath)
  let window = newWindow(
    "Kaijugen", ivec2(1440, 960), visible = options.frames == 0,
    vsync = true, msaa = msaa4x
  )
  makeContextCurrent(window)
  loadExtensions()
  initSunShadows(8, 18)
  sunAzimuth = 320
  sunElevation = 45
  sunShadowStrength = 0.32
  sunShadowSoftness = 6
  var app = KaijuApp(
    sk: newSilky(window, AtlasPath), toon: newToonContext(),
    settings: settings, materials: kaijuMaterials(settings),
    ground: groundNode(), colorName: "Skin", showPanel: not options.noPanel,
    yaw: options.yaw, pitch: options.pitch, threshold: 0.55,
    softness: 1.0, contrast: 0.45, rim: 0.06
  )
  app.rebuild()
  app.frameKaiju()
  var lastTime = epochTime()
  while not window.closeRequested:
    pollEvents()
    let now = epochTime()
    app.handleInput(window, min(0.05'f, (now - lastTime).float32))
    lastTime = now
    if app.settings.geometryKey() != app.built.geometryKey():
      app.rebuild()
    app.materials.tint(app.settings)
    app.drawScene(window)
    app.drawUi(window)
    inc app.frames
    if options.frames > 0 and app.frames >= options.frames:
      if options.screenshot.len > 0:
        window.screenshot(options.screenshot)
      window.closeRequested = true
    window.swapBuffers()
  app.root.clearFromGpu()
  app.ground.clearFromGpu()
  window.close()

main()
