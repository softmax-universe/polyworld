import
  std/[os, tempfiles, unicode],
  opengl, pixie, silky, vmath, windy,
  polyworld/[assets, rtscameras, viewers],
  ../[common, hudassets, maps, resources, scenes, selections, sim, ui]

const RepositoryRoot =
  currentSourcePath().parentDir.parentDir.parentDir.parentDir

proc addFonts(builder: AtlasBuilder) =
  ## Uses the native game's HUD font sizes and character coverage.
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

proc advancePreview(world: var World, closeup: bool): int =
  ## Observes fresh autonomous villagers without staging their tasks or cargo.
  result = -1
  for tick in 0 ..< 600 * TickRate:
    world.step()
    if closeup:
      for i, person in world.villagers:
        if world.households[person.home].village == 0 and
          person.task == GatherTask and person.resource == FishResource and
          not person.moving and person.elapsed >= 2:
            return i
    elif tick >= 62 * TickRate:
      for i, person in world.villagers:
        if world.households[person.home].village != 0:
          continue
        if person.cargo.total() > 0 and length(person.position) < 14:
          return i
        if person.moving and length(person.position) < 14 and result < 0:
          result = i
      if result < 0:
        result = 0
      return
  doAssert false, "No autonomous fishing trip appeared in the preview."

proc preview() =
  ## Renders a disposable simulated village without loading the user's save.
  setCurrentDir(RepositoryRoot)
  let
    directory = createTempDir("monster-chores-ui-", "")
    atlasPath = directory / "hud.png"
    outputPath =
      if paramCount() > 0: absolutePath(paramStr(1))
      else: RepositoryRoot / "output" / "monster-village-life.png"
    closeup = paramCount() > 1 and paramStr(2) == "fishing"
  defer:
    removeDir(directory)
  var world = newWorld(generateMap())
  let selected = world.advancePreview(closeup)
  echo "Preview tick ", world.tick
  for person in world.villagers:
    if world.households[person.home].village == 0:
      echo person.name, ": ", person.activity, " at ", person.position,
        "; cargo ", person.cargo.inventoryText()
  let builder = newHudAtlas(4096)
  builder.addFonts()
  builder.addHudAssets()
  builder.write(atlasPath)
  let (window, sk) = initGameWindow("Monster village life preview", atlasPath,
    ivec2(1440, 900), vsync = false, visible = false)
  sk.builder = builder
  pollEvents()
  defer:
    window.close()
  let
    focus = if closeup: world.villagers[selected].position else: vec2(0, -2)
    distance = if closeup: 18'f else: 36'f
    cameraTarget = rtsFollowFrame(
      vec3(focus.x, world.map.groundHeight(focus), focus.y), distance, 0.23'f)
    scene = newMonsterScene(window, world.map, sk.atlas, sk.atlasTextureId())
    renderTime = world.tick.float32 / TickRate.float32
  defer:
    scene.close()
  var chat = initChatUi()
  chat.scale = chatScale(window.size.vec2)
  discard chat.select(world, world.selectionById(world.villagers[selected].id))
  for frame in 0 ..< 3:
    scene.drawScene(window, world, cameraTarget, distance, renderTime,
      chat.selection)
    sk.uiScale = chat.scale
    sk.beginUi(window, window.size)
    discard sk.drawUi(window, world, chat, @[], false, true, "",
      cameraTarget, distance, false)
    sk.endUi()
    if frame < 2:
      window.swapBuffers()
      pollEvents()
  let capture = newImage(window.size.x, window.size.y)
  glReadPixels(0, 0, window.size.x, window.size.y,
    GL_RGBA, GL_UNSIGNED_BYTE, capture.data[0].addr)
  capture.flipVertical()
  createDir(outputPath.parentDir)
  capture.writeFile(outputPath)
  echo "Saved ", outputPath

preview()
