import
  std/[os, tempfiles, unicode],
  opengl, pixie, silky, vmath, windy,
  polyworld/[assets, rtscameras, viewers],
  ../[common, hudassets, maps, scenes, sim, ui]

const RepositoryRoot =
  currentSourcePath().parentDir.parentDir.parentDir.parentDir

proc addFonts(builder: AtlasBuilder) =
  ## Builds the same font names and glyph coverage as the native game.
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

proc preview() =
  ## Captures the live HUD without networking, microphones, or saved progress.
  setCurrentDir(RepositoryRoot)
  let
    directory = createTempDir("monster-voice-ui-", "")
    atlasPath = directory / "hud.png"
    outputPath =
      if paramCount() > 0: absolutePath(paramStr(1))
      else: RepositoryRoot / "output" / "monster-voice.png"
  defer:
    removeDir(directory)
  let builder = newHudAtlas(4096)
  builder.addFonts()
  builder.addHudAssets()
  builder.write(atlasPath)
  let (window, sk) = initGameWindow("Monster voice preview", atlasPath,
    ivec2(1440, 900), vsync = false, visible = false)
  sk.builder = builder
  pollEvents()
  defer:
    window.close()
  let
    world = newWorld(generateMap())
    cameraTarget = rtsFollowFrame(
      vec3(world.creature.position.x, 0, world.creature.position.y),
      34'f, 0.23'f)
    scene = newMonsterScene(window, world.map, sk.atlas, sk.atlasTextureId())
    messages = @[
      Message(role: PlayerMessage,
        text: "Moss, gather wild berries and bring them to Willow."),
      Message(role: CreatureMessage,
        text: "Wild berries. I remember. I'll leave the farm alone.")
    ]
  defer:
    scene.close()
  var chat = initChatUi()
  chat.scale = chatScale(window.size.vec2)
  chat.voiceEnabled = true
  chat.voiceConnected = true
  chat.voiceStatus = "Ready to talk"
  for frame in 0 ..< 3:
    scene.drawScene(window, world, cameraTarget, 34'f, 0, chat.selection)
    sk.uiScale = chat.scale
    sk.beginUi(window, window.size)
    discard sk.drawUi(window, world, chat, messages, false, true, "",
      cameraTarget, 34'f, true)
    sk.endUi()
    if frame < 2:
      window.swapBuffers()
      pollEvents()
  let image = newImage(window.size.x, window.size.y)
  glReadPixels(0, 0, window.size.x, window.size.y,
    GL_RGBA, GL_UNSIGNED_BYTE, image.data[0].addr)
  image.flipVertical()
  createDir(outputPath.parentDir)
  image.writeFile(outputPath)
  echo "Saved ", outputPath

preview()
