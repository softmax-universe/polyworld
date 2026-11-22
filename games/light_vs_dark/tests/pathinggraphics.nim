## Shared renderer hooks for manual pathing and scenario-switch tests.

import
  std/[os, strformat, times],
  chroma, opengl, pixie, silky, vmath, windy,
  polyworld/[actioncam, chrome, player, rtscameras],
  ../[game, graphics, replays],
  pathingscenarios

const
  SceneKeys = [Key1, Key2, Key3, Key4, Key5]
  SceneLabels = "1 Open field   2 Opposing   3 Crossing   4 Choke   5 Buildings"

proc prepareMatch(scene: PathingScene) =
  ## Gives the fixture normal metrics and a tape for pause, seek, and replay.
  let map = scene.world.map
  run = newGame(map, PathingDurationTicks)
  run.world = scene.world
  var setup = Setup(
    mapSeed: map.seed,
    tickRate: TickRate.uint16,
    gridTiles: map.side.uint16,
    decisionTicks: DecisionTicks.uint16,
    maximumTicks: PathingDurationTicks.uint32,
    mapHash: map.hash,
    contentHash: contentHash()
  )
  for i, origin in map.hallOrigin:
    setup.players.add ReplayPlayerSetup(
      id: i.int32, startX: origin.x.int32, startY: origin.y.int32
    )
  run.recorder = initReplayRecorder(setup)
  run.recorder.data.config.players[0].name = "Manual pathing test"
  run.recorder.data.config.players[1].name = "Reserve"
  run.replayPlayer = ReplayPlayer(data: run.recorder.data)

proc frameScene(scene: PathingScene, scenario: PathingScenario) =
  ## Frames the interaction closely, with the normal game camera and zoom.
  let
    bounds = scene.bounds
    half = scene.world.map.side.float32 / 2
    center = vec3(
      bounds.x.float32 + bounds.width.float32 / 2 - half,
      0,
      bounds.y.float32 + bounds.height.float32 / 2 - half
    )
  cameraDistance = if scenario == CrossingStreams: 42 else: 34
  cameraTarget = rtsFollowFrame(center, cameraDistance, 0.12)
  followSelection = false

proc captureFrame(path: string) =
  ## Saves the actual rendered game framebuffer, including its HUD.
  let directory = path.parentDir
  if directory.len > 0:
    createDir(directory)
  let capture = newImage(window.size.x, window.size.y)
  glReadPixels(
    0, 0, window.size.x.GLsizei, window.size.y.GLsizei,
    GL_RGBA, GL_UNSIGNED_BYTE, capture.data[0].addr
  )
  capture.flipVertical()
  capture.writeFile(path)
  echo "Captured ", path

proc drawPathingOverlay(scenario: PathingScenario) =
  ## Labels the five fixtures while retaining the ordinary game HUD.
  let
    size = window.size.vec2 / sk.uiScale
    unit = 1 / sk.uiScale
    width = min(700 * unit, size.x - 24 * unit)
    at = vec2((size.x - width) / 2, max(88'f32, 44 * unit))
    titleFont = if sk.uiScale < 1: "H1" else: "Bold"
    detailFont = if sk.uiScale < 1: "WorldName" else: "Default"
  sk.drawRect(at, vec2(width, 84 * unit), rgbx(18, 25, 35, 245))
  sk.drawLabel(
    &"Manual pathing test / {ScenarioNames[scenario]} / {PathingUnitCount} units",
    at + vec2(12, 3) * unit, vec2(width - 24 * unit, 25 * unit),
    font = titleFont
  )
  sk.drawLabel(SceneLabels, at + vec2(12, 29) * unit,
    vec2(width - 24 * unit, 23 * unit), font = detailFont)
  sk.drawLabel("Space Pause   R Replay   S Speed   P Paths   F Frame   Scroll Zoom",
    at + vec2(12, 53) * unit, vec2(width - 24 * unit, 24 * unit),
    color = rgbx(174, 193, 213, 255), font = detailFont)

proc pathingHooks*(first = OpenField, capture = "",
    ticks = 240'i32): GraphicsHooks =
  ## Keeps test commands and scene replacements inside one renderer session.
  var
    scenario = first
    scene = createScene(scenario)
    requested = scenario
    switchScene = false
    screenshot = ""
    captureFrames = 0
  prepareMatch(scene)
  result = GraphicsHooks(
    ready: proc(camera: var ActionCam) =
      ## Starts close to the scenario instead of an offscreen town hall.
      camera.takeManual()
      frameScene(scene, scenario)
      window.title = "Light vs Dark - Manual pathing test"
      if capture.len > 0:
        doAssert not window.visible, "Screenshot window must stay hidden"
        transport.repeating = false
        transport.playing = false
        transport.seekTo(ticks, play = false)
    ,
    reload: proc(): bool =
      ## Replaces only simulation state; the renderer keeps its loaded assets.
      if not switchScene:
        return false
      scenario = requested
      scene = createScene(scenario)
      prepareMatch(scene)
      switchScene = false
      captureFrames = 0
      true
    ,
    key: proc(button: Button, camera: var ActionCam): bool =
      ## Reserves test shortcuts and leaves camera and selection intact.
      for i, key in SceneKeys:
        if button == key:
          requested = PathingScenario(i)
          switchScene = true
          return true
      case button
      of KeyR:
        transport.skipToStart()
        camera.takeManual()
        frameScene(scene, scenario)
      of KeyS:
        transport.setSpeed((transport.speedIndex + 1) mod PlayerSpeeds.len)
      of KeyP:
        showPaths = not showPaths
      of KeyF:
        camera.takeManual()
        frameScene(scene, scenario)
      of KeyF12:
        screenshot = "output/lvd-manual-pathing/" & $scenario & "-" &
          $epochTime().int64 & ".png"
      else:
        return false
      true
    ,
    overlay: proc() =
      ## Adds scenario context without replacing the normal game controls.
      drawPathingOverlay(scenario)
    ,
    frame: proc(): bool =
      ## Captures completed game frames without interrupting the renderer.
      if capture.len > 0 and run.world.tick == ticks and
          transport.targetTick < 0:
        doAssert not window.visible, "Screenshot window must stay hidden"
        inc captureFrames
        if captureFrames == 3:
          captureFrame(capture)
          window.closeRequested = true
      if screenshot.len > 0:
        captureFrame(screenshot)
        screenshot = ""
      false
  )
