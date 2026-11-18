## Queued buildings use the production ghost renderer in a hidden GL target.
import std/[macros, os]
import trafficfixture
include ../graphics

macro ghostRoutine(name: static[string]): untyped =
  ## Extracts production ghost drawing while avoiding the full game scene.
  for node in parseStmt(staticRead("../graphics.nim")):
    if node.kind == nnkProcDef and node[0].repr == "runGraphics*":
      for child in node[^1]:
        if child.kind == nnkProcDef and child[0].repr == name:
          return child
  error("Missing production ghost routine: " & name)

proc main() =
  ## Checks real model pixels through changes in the selected build queues.
  window = newWindow("LvD queued building ghosts", ivec2(960, 640),
    visible = false)
  window.makeContextCurrent()
  loadExtensions()
  doAssert not window.visible
  var target = initCaptureTarget(window.size)
  initTerrain(treeStyle = NoTrees, rockStyle = NoRocks,
    terrainStyle = GeneratedTerrain, settings = TerrainAssets(size: 64))
  sunShadowsEnabled = false
  let buildingArt = BuildingArt(pack: loadPropPack([
    BuildingModelRoot / "farm.glb", BuildingModelRoot / "barracks.glb"],
    unitHeight = false, mergeNodes = true))
  defer:
    buildingArt.pack.closePropPack()
    target.close()
    window.close()
    window = nil
    run = nil
  ghostRoutine("playerMode")
  ghostRoutine("drawBuildingGhost")
  ghostRoutine("drawQueuedBuildGhosts")
  run = Game(world: trafficFixture(0, "open").world)
  options.playerSlot = 1
  viewMode = 0
  let
    half = run.world.map.side div 2
    first = run.world.spawnUnit(0, PeonUnit, tile2(half - 9, half + 7))
    second = run.world.spawnUnit(0, PeonUnit, tile2(half + 9, half + 7))
    enemy = run.world.spawnUnit(1, PeonUnit, tile2(half, half + 7))
    farm = tile2(half - 6, half - 1)
    barracks = tile2(half + 4, half - 1)
    vp = perspective(45'f, 1.5'f, 0.1'f, 1000'f) *
      lookAt(vec3(0, 18, 16), vec3(0), vec3(0, 1, 0))
  pendingBuild = -1
  doAssert run.world.applyBuild(0, first, FarmBuilding.ord.int32,
    farm.x.int32, farm.y.int32, append = true)
  doAssert run.world.applyBuild(0, second, BarracksBuilding.ord.int32,
    barracks.x.int32, barracks.y.int32, append = true)
  doAssert run.world.applyBuild(1, enemy, FarmBuilding.ord.int32,
    half - 1, half - 1, append = true)

  proc frame(): Image =
    ## Captures actual ghost pixels and checks that drawing never writes orders.
    let before = run.stateHash()
    glBindFramebuffer(GL_FRAMEBUFFER, target.framebuffer)
    glViewport(0, 0, window.size.x, window.size.y)
    glDepthMask(GL_TRUE)
    glClearColor(0, 0, 0, 1)
    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
    drawQueuedBuildGhosts(vp)
    result = newImage(window.size.x, window.size.y)
    glReadPixels(0, 0, window.size.x, window.size.y, GL_RGBA,
      GL_UNSIGNED_BYTE, result.data[0].addr)
    result.flipVertical()
    doAssert run.stateHash() == before

  proc greenPixels(image: Image, right: bool): int =
    ## Counts the green building on one side of the offscreen target.
    let
      firstX = if right: image.width div 2 else: 0
      lastX = if right: image.width else: image.width div 2
    for y in 0 ..< image.height:
      for x in firstX ..< lastX:
        let pixel = image[x, y]
        if pixel.g > 30 and pixel.g.int > pixel.r.int * 14 div 10 and
            pixel.g.int > pixel.b.int * 12 div 10:
          inc result

  selectedIds = @[first, second]
  let both = frame()
  doAssert both.greenPixels(false) > 300
  doAssert both.greenPixels(true) > 300
  selectedIds = @[]
  let deselected = frame()
  doAssert deselected.greenPixels(false) == 0
  doAssert deselected.greenPixels(true) == 0
  selectedIds = @[first]
  let firstOnly = frame()
  doAssert firstOnly.greenPixels(false) > 300
  doAssert firstOnly.greenPixels(true) == 0
  selectedIds = @[second]
  let secondOnly = frame()
  doAssert secondOnly.greenPixels(false) == 0
  doAssert secondOnly.greenPixels(true) > 300
  selectedIds = @[first]
  doAssert frame().data == firstOnly.data
  selectedIds = @[first, second]
  doAssert frame().data == both.data
  echo "Farm and barracks ghosts hide, switch and restore with peon selection"

  selectedIds = @[enemy]
  let enemySelection = frame()
  doAssert enemySelection.greenPixels(false) == 0
  doAssert enemySelection.greenPixels(true) == 0
  selectedIds = @[first]
  doAssert run.world.applyCancel(0, first)
  let cancelled = frame()
  doAssert cancelled.greenPixels(false) == 0
  doAssert cancelled.greenPixels(true) == 0
  doAssert glGetError() == GL_NO_ERROR
  echo "Enemy queues stay hidden and cancellation removes the selected ghost"

main()
