## Render production hero path markers through repeated pulses and cancellation.
import std/[macros, os]
include ../graphics

macro markerRoutine(name: static[string]): untyped =
  ## Extracts the real marker selection and drawing without loading game assets.
  for node in parseStmt(staticRead("../graphics.nim")):
    if node.kind == nnkProcDef and node[0].repr == "runGraphics*":
      for child in node[^1]:
        if child.kind == nnkProcDef and child[0].repr == name:
          return child
  error("Missing production marker routine: " & name)

macro markerSettings(): untyped =
  ## Reuses the exact production green and red ground effect settings.
  result = newStmtList()
  var collecting = false
  for node in parseStmt(staticRead("../graphics.nim")):
    if node.kind == nnkProcDef and node[0].repr == "runGraphics*":
      for child in node[^1]:
        if child.kind == nnkVarSection:
          if child[0][0].eqIdent("moveMarkSettings"):
            collecting = true
          elif child[0][0].eqIdent("particles"):
            return
        if collecting:
          result.add child
  error("Missing production marker settings")

proc main() =
  ## Checks actual GPU pixels and captures the same production pulse rendering.
  let window = newWindow("GotA queued hero path", ivec2(1200, 720),
    visible = false)
  window.makeContextCurrent()
  loadExtensions()
  markerSettings()
  var
    clickMarks = initClickMarks(moveMarkSettings)
    attackMarks = initClickMarks(attackMarkSettings)
    framebuffer, texture: GLuint
    primaryId = 2'i32
    viewMode = 1
    visible = true
  let
    half = (mapTiles() div 2).int32
    destinations = [(half - 4, half - 2), (half, half + 2),
      (half + 4, half - 2)]
    hero = Hero(id: 1, hp: 100, team: RedTeam, hasOrder: true)
    enemy = Hero(id: 2, hp: 100, team: BlueTeam, hasOrder: true,
      activeOrder: HeroOrder(kind: ActionWalkTo,
        first: half + 5, second: half + 5))
    vp = perspective(45'f, 1200'f / 720'f, 0.1'f, 100'f) *
      lookAt(vec3(0, 12, 11), vec3(0), vec3(0, 1, 0))
  run = Game(world: World(phase: Playing, heroes: @[hero, enemy]))
  options.playerSlot = 1
  viewMode = 1

  proc surfaceHeight(x, z: float32): float32 =
    ## Keeps the fixture flat without replacing production marker positioning.
    0

  proc visibleInView(team: Team, position: WorldPoint): bool =
    ## Models view visibility independently of the fixture's empty fog grid.
    visible

  proc refill() =
    ## Restores three movement destinations after lifecycle assertions.
    hero.hp = 100
    hero.state = Marching
    hero.hasOrder = true
    hero.queuedOrders.setLen(0)
    for i, point in destinations:
      let order = HeroOrder(kind: ActionWalkTo,
        first: point[0], second: point[1])
      if i == 0:
        hero.activeOrder = order
      else:
        hero.queuedOrders.add order

  markerRoutine("playerMode")
  markerRoutine("playerHeroId")
  markerRoutine("drawHeroOrderMarkers")
  refill()
  glGenFramebuffers(1, framebuffer.addr)
  glGenTextures(1, texture.addr)
  glBindTexture(GL_TEXTURE_2D, texture)
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.GLint,
    window.size.x.GLsizei, window.size.y.GLsizei, 0, GL_RGBA,
    GL_UNSIGNED_BYTE, nil)
  glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
    GL_TEXTURE_2D, texture, 0)
  doAssert glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE
  defer:
    clickMarks.closeClickMarks()
    attackMarks.closeClickMarks()
    glBindFramebuffer(GL_FRAMEBUFFER, 0)
    glDeleteTextures(1, texture.addr)
    glDeleteFramebuffers(1, framebuffer.addr)
    window.close()
    run = nil

  proc capture(): Image =
    ## Reads the actual color target into a correctly oriented image.
    result = newImage(window.size.x, window.size.y)
    glReadPixels(0, 0, window.size.x.GLsizei, window.size.y.GLsizei,
      GL_RGBA, GL_UNSIGNED_BYTE, result.data[0].addr)
    result.flipVertical()

  proc frame(delta = 0'f): Image =
    ## Draws transient clicks and persistent production destination effects.
    clickMarks.advanceClickMarks(delta)
    attackMarks.advanceClickMarks(delta)
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
    glViewport(0, 0, window.size.x, window.size.y)
    glClearColor(0, 0, 0, 1)
    glClear(GL_COLOR_BUFFER_BIT)
    clickMarks.drawClickMarks(vp)
    attackMarks.drawClickMarks(vp)
    drawHeroOrderMarkers(vp)
    capture()

  proc screen(point: Vec3): Vec2 =
    ## Projects a fixture world point into screenshot pixel coordinates.
    let clip = vp * vec4(point.x, point.y, point.z, 1)
    vec2((clip.x / clip.w + 1) * window.size.x.float32 / 2,
      (1 - clip.y / clip.w) * window.size.y.float32 / 2)

  proc point(tile: (int32, int32)): Vec3 =
    ## Converts an absolute tile to the center used by the production renderer.
    vec3(tile[0].float32 - half.float32 + 0.5'f, 0,
      tile[1].float32 - half.float32 + 0.5'f)

  proc at(image: Image, tile: (int32, int32), attack = false): int =
    ## Counts colored pixels at each goal separately, including later waypoints.
    let center = screen(point(tile))
    for y in center.y.int - 24 .. center.y.int + 24:
      for x in center.x.int - 24 .. center.x.int + 24:
        let pixel = image[x, y]
        if attack:
          if pixel.r > 30 and pixel.r.int > pixel.g.int * 14 div 10:
            inc result
        elif pixel.g > 30 and pixel.g.int > pixel.r.int * 14 div 10:
          inc result

  let transient = (half - 5, half + 4)
  clickMarks.emitClickMark(point(transient))
  let initial = frame(0.12'f)
  doAssert initial.at(transient) > 4
  for tile in destinations:
    doAssert initial.at(tile) > 4
  doAssert initial.at((half + 5, half + 5)) == 0,
    "Inspecting an enemy must keep the player's own path visible"
  for loops in [3, 9]:
    let image = frame(ClickMarkDuration * loops.float32)
    doAssert image.at(transient) == 0
    for tile in destinations:
      doAssert image.at(tile) > 4, "Queued destination stopped pulsing"
  let
    beforePulse = frame()
    pulse = frame(0.1'f)
  doAssert beforePulse.data != pulse.data,
    "The ground effects must keep animating"
  echo "PASS all queued destinations keep pulsing beyond transient click lifetime"

  hero.activeOrder = hero.queuedOrders[0]
  hero.queuedOrders.delete(0)
  let advanced = frame()
  doAssert advanced.at(destinations[0]) == 0
  doAssert advanced.at(destinations[1]) > 4
  doAssert advanced.at(destinations[2]) > 4
  hero.hasOrder = false
  hero.queuedOrders.setLen(0)
  for tile in destinations:
    doAssert frame().at(tile) == 0
  refill()
  hero.hp = 0
  for tile in destinations:
    doAssert frame().at(tile) == 0
  refill()
  visible = false
  for tile in destinations:
    doAssert frame().at(tile) == 0
  visible = true
  options.playerSlot = 0
  doAssert frame().at((half + 5, half + 5)) == 0
  options.playerSlot = 1
  hero.queuedOrders[1].kind = ActionAttackMove
  doAssert frame().at(destinations[2], attack = true) > 4
  doAssert glGetError() == GL_NO_ERROR
  echo "PASS completed, stopped, dead and hidden paths disappear; attack goals stay red"

  refill()
  # Capture at 0.08 seconds into the next pulse, before its brightness fades.
  discard frame(ClickMarkDuration - 0.14'f)
  let builder = newHudAtlas(2048)
  builder.addDefaultFonts()
  let sk = newSilky(window, builder.atlasImage, builder.atlas)
  sk.uiScale = 1.5'f
  glClearColor(0.035'f, 0.055'f, 0.07'f, 1)
  glClear(GL_COLOR_BUFFER_BIT)
  var grid = initShapeRenderer()
  for i in -7 .. 7:
    grid.addLine(vec3(i.float32, -0.02'f, -6),
      vec3(i.float32, -0.02'f, 6), rgbx(35, 49, 55, 255), 0.008'f)
  for i in -6 .. 6:
    grid.addLine(vec3(-7, -0.02'f, i.float32),
      vec3(7, -0.02'f, i.float32), rgbx(35, 49, 55, 255), 0.008'f)
  grid.draw(vp)
  drawHeroOrderMarkers(vp)
  sk.beginUi(window, window.size)
  sk.drawLabel("Queued hero path", vec2(32, 24), vec2(736, 40),
    rgbx(234, 242, 228, 255), "H1")
  sk.drawLabel("Hold Shift and right-click to add destinations.",
    vec2(32, 68), vec2(736, 28), rgbx(161, 185, 190, 255), "Default")
  for i, tile in destinations:
    let center = screen(point(tile)) / sk.uiScale
    sk.drawLabel($(i + 1), center + vec2(-30, -46), vec2(60, 24),
      rgbx(162, 255, 169, 255), "Default", CenterAlign)
    sk.drawLabel(if i == 0: "Current destination" else: "Queued",
      center + vec2(-80, 20), vec2(160, 24),
      rgbx(188, 212, 198, 255), "Default", CenterAlign)
  sk.drawLabel("Green markers keep pulsing until each destination is reached.",
    vec2(32, 416), vec2(736, 28), rgbx(161, 185, 190, 255),
    "Default", CenterAlign)
  sk.endUi()
  let output = getCurrentDir() / "output"
  createDir(output)
  capture().writeFile(output / "gota-queued-path.png")
  grid.closeShapeRenderer()

main()
