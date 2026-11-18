## Selected movement queues use the production renderer in a hidden GL target.
import std/macros
import trafficfixture
include ../graphics

macro markerRoutine(name: static[string]): untyped =
  ## Extracts the actual selection-owned marker drawing without scene assets.
  for node in parseStmt(staticRead("../graphics.nim")):
    if node.kind == nnkProcDef and node[0].repr == "runGraphics*":
      for child in node[^1]:
        if child.kind == nnkProcDef and child[0].repr == name:
          return child
  error("Missing production marker routine: " & name)

proc main() =
  ## Checks persistent GPU pixels through queue and selection changes.
  window = newWindow("LvD queued order markers", ivec2(960, 640),
    visible = false)
  window.makeContextCurrent()
  loadExtensions()
  var target = initCaptureTarget(window.size)
  var
    clickMarks = initClickMarks(orderMarkSettings(false))
    attackClickMarks = initClickMarks(orderMarkSettings(true))
  defer:
    clickMarks.closeClickMarks()
    attackClickMarks.closeClickMarks()
    target.close()
    window.close()
    window = nil
    run = nil
  markerRoutine("playerMode")
  markerRoutine("screenPosition")
  markerRoutine("drawSelectedOrderMarkers")
  run = Game(world: trafficFixture(0, "open").world)
  options.playerSlot = 1
  viewMode = 0
  let
    half = run.world.map.side div 2
    unit = run.world.spawnUnit(0, PeonUnit, tile2(half - 7, half))
    enemy = run.world.spawnUnit(1, PeonUnit, tile2(half + 7, half))
    destinations = [tile2(half - 4, half - 3), tile2(half, half + 1),
      tile2(half + 4, half - 3)]
    vp = perspective(45'f, 1.5'f, 0.1'f, 1000'f) *
      lookAt(vec3(0, 18, 16), vec3(0), vec3(0, 1, 0))
  selectedIds = @[unit]
  for i, tile in destinations:
    doAssert run.world.applyMove(0, unit, tile.x.int32, tile.y.int32,
      append = i > 0)
  doAssert run.world.applyMove(1, enemy, half + 5, half + 4)
  let before = run.stateHash()

  proc point(tile: Tile2): Vec3 =
    ## Matches the renderer's tile center on the flat fixture terrain.
    vec3(tile.x.float32 + 0.5'f - mapHalf(), 0,
      tile.y.float32 + 0.5'f - mapHalf())

  proc frame(delta = 0.0'f): Image =
    ## Draws all real feedback into the offscreen color and depth buffers.
    clickMarks.advanceClickMarks(delta)
    attackClickMarks.advanceClickMarks(delta)
    glBindFramebuffer(GL_FRAMEBUFFER, target.framebuffer)
    glViewport(0, 0, window.size.x, window.size.y)
    glDepthMask(GL_TRUE)
    glClearColor(0, 0, 0, 1)
    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
    clickMarks.drawClickMarks(vp)
    attackClickMarks.drawClickMarks(vp)
    drawSelectedOrderMarkers(vp)
    result = newImage(window.size.x, window.size.y)
    glReadPixels(0, 0, window.size.x, window.size.y, GL_RGBA,
      GL_UNSIGNED_BYTE, result.data[0].addr)
    result.flipVertical()

  proc count(image: Image, attack = false): int =
    ## Counts only pixels with the expected order color on the black target.
    for pixel in image.data:
      if attack:
        if pixel.r > 30 and pixel.r.int > pixel.g.int * 14 div 10:
          inc result
      elif pixel.g > 30 and pixel.g.int > pixel.r.int * 14 div 10:
        inc result

  proc at(image: Image, tile: Tile2, attack = false): int =
    ## Checks each waypoint separately so a single surviving mark cannot pass.
    let center = screenPosition(point(tile), vp)
    for y in center.y.int - 18 .. center.y.int + 18:
      for x in center.x.int - 18 .. center.x.int + 18:
        let pixel = image[x, y]
        if attack:
          if pixel.r > 30 and pixel.r.int > pixel.g.int * 14 div 10:
            inc result
        elif pixel.g > 30 and pixel.g.int > pixel.r.int * 14 div 10:
          inc result

  let transient = tile2(half - 5, half + 5)
  clickMarks.emitClickMark(point(transient))
  let initial = frame(0.12'f)
  doAssert initial.at(transient) > 4
  for tile in destinations:
    doAssert initial.at(tile) > 4
  for loops in [3, 9]:
    let image = frame(ClickMarkDuration * loops.float32)
    doAssert image.at(transient) == 0
    for tile in destinations:
      doAssert image.at(tile) > 4, "Queued waypoint stopped looping"
  doAssert run.stateHash() == before
  echo "Active and queued destinations keep looping after transient feedback ends"

  selectedIds = @[]
  doAssert frame().count() == 0
  selectedIds = @[unit]
  let reselected = frame()
  for tile in destinations:
    doAssert reselected.at(tile) > 4
  selectedIds = @[enemy]
  doAssert frame().count() == 0
  selectedIds = @[unit]
  doAssert run.world.applyCancel(0, unit)
  doAssert frame().count() == 0
  echo "Reselection restores markers, while deselection, enemy selection and cancel hide them"

  doAssert run.world.applyMove(0, unit, destinations[0].x.int32,
    destinations[0].y.int32)
  doAssert run.world.applyAttackMove(0, unit, destinations[1].x.int32,
    destinations[1].y.int32, append = true)
  let mixed = frame(ClickMarkDuration * 4)
  doAssert mixed.at(destinations[0]) > 4
  doAssert mixed.at(destinations[1], attack = true) > 4
  doAssert mixed.at(destinations[2]) == 0
  doAssert run.world.applyCancel(0, unit)
  var many: seq[Tile2]
  for y in 0 .. 3:
    for x in 0 .. 3:
      let tile = tile2(half - 6 + x.int32 * 4, half - 6 + y.int32 * 4)
      many.add tile
      doAssert run.world.applyMove(0, unit, tile.x.int32, tile.y.int32,
        append = many.len > 1)
  let allMarkers = frame()
  for tile in many:
    doAssert allMarkers.at(tile) > 4, "A long queue lost a destination marker"
  doAssert glGetError() == GL_NO_ERROR
  echo "All sixteen destinations render, and attack moves retain their red color"

main()
