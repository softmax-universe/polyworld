## Exercise the production AO checkbox and its saved preference.
import
  std/[importutils, monotimes, os],
  opengl, pixie, silky, vmath, windy/internal,
  polyworld/[gameuis, menus, viewers],
  ../settings

privateAccess(Window)

proc verifySettings(size: IVec2): Image =
  ## Render and click the real settings panel in an isolated hidden window.
  let
    app = "GotA graphics settings render " & $getCurrentProcessId() &
      "-" & $getMonoTime().ticks
    directory = getConfigHome(app)
    window = newWindow("GotA graphics settings", size, visible = false)
  defer:
    window.close()
    if dirExists(directory):
      removeDir(directory)
  window.makeContextCurrent()
  loadExtensions()
  let builder = newHudAtlas(2048)
  builder.addDefaultFonts()
  let sk = newSilky(window, builder.atlasImage, builder.atlas)
  sk.applyThemePatches()
  sk.uiScale = window.size.x.float32 / 1100
  let
    width = window.size.x.int
    height = window.size.y.int
    origin = vec2(190, 70)
    checkbox = GameUiPanel(
      origin: origin + vec2(360, 160), size: vec2(360, 40)
    )
  var preferences = Preferences(mainVolume: 0)
  preferences.bindings = GotaControlProfile.defaults
  var framebuffer, texture: GLuint
  glGenFramebuffers(1, framebuffer.addr)
  glGenTextures(1, texture.addr)
  glBindTexture(GL_TEXTURE_2D, texture)
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.GLint, width.GLsizei, height.GLsizei,
    0, GL_RGBA, GL_UNSIGNED_BYTE, nil)
  glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
    GL_TEXTURE_2D, texture, 0)
  doAssert glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE
  defer:
    glBindFramebuffer(GL_FRAMEBUFFER, 0)
    glDeleteTextures(1, texture.addr)
    glDeleteFramebuffers(1, framebuffer.addr)

  proc render(supported = true, click = false): Image =
    ## Route input through the panel and read its rendered framebuffer.
    window.state.perFrame =
      if click:
        PerFrame(buttonPressed: {MouseLeft}, buttonReleased: {MouseLeft})
      else:
        PerFrame()
    window.state.buttonDown = {}
    glClearColor(0.035, 0.045, 0.065, 1)
    glClear(GL_COLOR_BUFFER_BIT)
    sk.beginUi(window, window.size)
    sk.mousePos = if click: checkbox.origin + vec2(12, 16) else: vec2(-100)
    discard sk.settingsPanel(
      window, preferences, app, origin,
      controls = GotaControlProfile, supportsAmbientOcclusion = supported
    )
    sk.endUi()
    result = newImage(width, height)
    glReadPixels(0, 0, width.GLsizei, height.GLsizei,
      GL_RGBA, GL_UNSIGNED_BYTE, result.data[0].addr)
    result.flipVertical()

  let without = render(false)
  result = render()
  var changed = 0
  for y in 0 ..< height:
    for x in 0 ..< width:
      let index = y * width + x
      if without.data[index] != result.data[index]:
        inc changed
        let point = vec2(x.float32 + 0.5'f, y.float32 + 0.5'f) / sk.uiScale
        doAssert checkbox.contains(point),
          "AO must fit its own row beside interpolation: " & $point
  doAssert changed > 0, "The AO option must be visibly drawn"
  discard render(click = true)
  doAssert not preferences.ambientOcclusion
  doAssert not readPreferences(app).ambientOcclusion
  doAssert preferences.interpolation
  discard render()
  discard render(click = true)
  doAssert preferences.ambientOcclusion
  doAssert readPreferences(app).ambientOcclusion
  doAssert preferences.interpolation

let screenshot = verifySettings(ivec2(1100, 700))
discard verifySettings(ivec2(700, 500))
let output = getEnv("GOTA_SETTINGS_FIXTURES", getCurrentDir() / "output")
createDir(output)
screenshot.writeFile(output / "gota-ao-settings.png")
echo "PASS AO settings checkbox fits its row and saves both on and off"
