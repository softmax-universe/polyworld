## Exercises live scenario switches through the real hidden game renderer.

import
  std/[os, strformat, times],
  opengl, pixie, silky, windy,
  polyworld/[actioncam, pathing, player],
  ../[controls, game, graphics],
  pathinggraphics, pathingscenarios

const
  Scenarios = [OpenField, OpposingStreams, CrossingStreams,
    BuildingDetour, NarrowChoke, OpenField]
  SceneKeys = [Key1, Key2, Key3, Key4, Key5]

type Phase = enum
  WarmCheckpoints, OpposingAdvance, OpposingRestore, OpposingRestart, ShowScene

var
  scenarioIndex = 0
  readyCount = 0
  frameCount = 0
  sceneFrames = 0
  phase = WarmCheckpoints
  initialHash: uint64
  atlasTexture: GLuint
  windowIdentity, silkyIdentity: pointer
  previousGame: Game
  switchStarted = 0.0
  started = epochTime()
  hooks: GraphicsHooks

proc checkTopology() =
  ## Checks that replacing blockers also installs the new rendered terrain.
  let scenario = Scenarios[scenarioIndex]
  doAssert run.world.units.len == PathingUnitCount
  doAssert layers.len == 1
  doAssert cast[pointer](layers[0]) ==
    cast[pointer](run.world.map.terrain[0])
  var trees, farms, halls = 0
  for i, tile in layers[0].tiles:
    if tile.kind == TreeTile:
      inc trees
      doAssert run.world.blocker[i] == TreeBlocker
      doAssert run.world.treeWood[i] == WoodPerTree
  for building in run.world.buildings:
    if building.kind == FarmBuilding: inc farms
    if building.kind == TownHallBuilding: inc halls
  doAssert trees == (if scenario == NarrowChoke: 156 else: 0)
  doAssert farms == (if scenario == BuildingDetour: 1 else: 0)
  doAssert halls == (if scenario == BuildingDetour: 3 else: 2)

proc captureScene() =
  ## Reads the renderer's offscreen target without showing a native window.
  doAssert not window.visible
  let
    directory = getCurrentDir() / "output/lvd-pathing-switch"
    path = directory / ($Scenarios[scenarioIndex] & ".png")
    capture = newImage(window.size.x, window.size.y)
  glReadPixels(0, 0, window.size.x, window.size.y, GL_RGBA,
    GL_UNSIGNED_BYTE, capture.data[0].addr)
  capture.flipVertical()
  createDir(directory)
  capture.writeFile(path)
  echo "Hidden switched scene: ", path

proc nextScenario() =
  ## Sends the actual manual test shortcut after leaving stale presentation intent.
  previousGame = run
  selectedIds = @[run.world.units[0].id]
  primaryId = selectedIds[0]
  followSelection = true
  pendingBuild = FarmBuilding.ord
  attackMoveArmed = true
  inc scenarioIndex
  switchStarted = epochTime()
  window.onButtonPress(SceneKeys[Scenarios[scenarioIndex].ord])

options.windowWidth = 1600
options.windowHeight = 1000
options.playerSlot = 0
options.viewMode = 0
options.maximumTicks = PathingDurationTicks
options.recordPath = ""
options.pauseOnStart = true
options.vsync = false
hooks = pathingHooks()
let
  originalReady = hooks.ready
  originalFrame = hooks.frame

hooks.ready = proc(camera: var ActionCam) =
  ## Checks resets after asset reuse, then exercises each fixture's playback.
  originalReady(camera)
  doAssert not window.visible
  doAssert run.world.tick == 0
  doAssert transport.tick == 0 and transport.recordedTicks == 0
  doAssert transport.targetTick == -1 and transport.restoreTick == -1
  doAssert selectedIds.len == 0 and primaryId == NoEntity
  doAssert not followSelection and not attackMoveArmed and pendingBuild == -1
  checkTopology()
  initialHash = run.stateHash()
  sceneFrames = 0
  if readyCount == 0:
    atlasTexture = sk.atlasTextureId()
    windowIdentity = cast[pointer](window)
    silkyIdentity = cast[pointer](sk)
    transport.setSpeed(2)
    transport.repeating = false
    transport.seekTo(610, play = false)
  else:
    doAssert run != previousGame
    doAssert sk.atlasTextureId() == atlasTexture
    doAssert cast[pointer](window) == windowIdentity
    doAssert cast[pointer](sk) == silkyIdentity
    doAssert not transport.playing and not transport.repeating
    doAssert transport.speedIndex == 2
    echo &"Switched to {ScenarioNames[Scenarios[scenarioIndex]]} in " &
      &"{(epochTime() - switchStarted) * 1000:.1f} ms"
    if scenarioIndex == 1:
      phase = OpposingAdvance
      transport.seekTo(350, play = false)
    else:
      phase = ShowScene
  inc readyCount

hooks.frame = proc(): bool =
  ## Checks replay isolation and drives all switches in one renderer session.
  if originalFrame(): return true
  inc frameCount
  inc sceneFrames
  doAssert frameCount < 3000 and epochTime() - started < 120,
    "Hidden pathing switch fixture did not finish"
  doAssert not window.visible
  doAssert run.hashCheck.mismatches == 0
  case phase
  of WarmCheckpoints:
    if run.world.tick == 610 and transport.targetTick < 0:
      nextScenario()
  of OpposingAdvance:
    if run.world.tick == 350 and transport.targetTick < 0:
      transport.seekTo(310, play = false)
      phase = OpposingRestore
  of OpposingRestore:
    if run.world.tick == 310 and transport.targetTick < 0:
      doAssert run.hashCheck.mismatches == 0,
        "Seek restored a checkpoint from the previous scenario"
      window.onButtonPress(KeyR)
      transport.playing = false
      phase = OpposingRestart
  of OpposingRestart:
    if run.world.tick == 0 and transport.targetTick < 0:
      doAssert run.stateHash() == initialHash,
        "Replay did not restore the new scenario's initial state"
      nextScenario()
  of ShowScene:
    doAssert run.world.tick == 0 and run.stateHash() == initialHash
    if sceneFrames >= 2:
      checkTopology()
      captureScene()
      if scenarioIndex == Scenarios.high:
        return true
      nextScenario()

runGraphics(hooks = hooks, hidden = true)
doAssert readyCount == Scenarios.len
doAssert not window.visible
window.close()
window = nil
run = nil
echo "Hidden pathing switches, asset reuse, and replay isolation passed"
