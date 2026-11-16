## Native GL rendering of the production held-Tab countdown row.
import std/[os, unittest]
import chroma, pixie, silky, vmath, windy, opengl
import polyworld/[chrome, gameuis, stats, viewers]
import ../[game, sim, presets, symbols, content]
include ../ui

let window = newWindow("LvD match clock", ivec2(1000,700), visible=false)
window.makeContextCurrent()
loadExtensions()
pollEvents()
let builder = newHudAtlas(2048)
builder.addDefaultFonts()
let badges = loadUnitSymbols()
doAssert builder.addImage(unitSymbolKey(PeonUnit), badges[PeonUnit])
let sk = newSilky(window, builder.atlasImage, builder.atlas)
sk.applyThemePatches()
var config = defaultConfig()
config.maxTicks = TickRate * 200
initializeLocalMatch(config, ["", ""])
run.world.tick = TickRate * 20
var framebuffer, texture: GLuint
glGenFramebuffers(1, framebuffer.addr)
glGenTextures(1, texture.addr)
glBindTexture(GL_TEXTURE_2D, texture)
glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0)

suite "native production Tab countdown rendering":
  test "countdown glyphs remain inside a reserved readable row at all viewport sizes":
    for size in [ivec2(640,480), ivec2(1000,700), ivec2(1920,1080)]:
      window.size = size
      pollEvents()
      sk.uiScale = gameUiScale(window)
      glBindTexture(GL_TEXTURE_2D, texture)
      glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
      glDisable(GL_SCISSOR_TEST)
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.GLint, size.x, size.y, 0,
        GL_RGBA, GL_UNSIGNED_BYTE, nil)
      doAssert glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE
      glViewport(0, 0, size.x, size.y)
      glClearColor(28.0/255,38.0/255,34.0/255,1)
      glClear(GL_COLOR_BUFFER_BIT)
      # Hidden windows are not OS-focused: use the same production stats toggle.
      statsState.toggled = true
      drawStatsOverlay(sk, window, [])
      let image = newImage(size.x,size.y)
      glReadPixels(0,0,size.x,size.y,GL_RGBA,GL_UNSIGNED_BYTE,image.data[0].addr)
      image.flipVertical()
      let scale = statsScale(sk.uiScale)
      let slots = statsLayout(statsViewport(currentLayout(window),sk.uiScale),
        currentStats(),currentStatsOptions())
      check currentStatsOptions().statusText == "Time remaining: 03:00"
      check sk.getTextSize("Default", currentStatsOptions().statusText).x <= slots.status.size.x
      var ink = 0
      for y in 0 ..< size.y:
        for x in 0 ..< size.x:
          let point = vec2(x.float32,y.float32) / scale
          let pixel = image[x,y]
          if slots.status.contains(point) and pixel.r > 170 and pixel.g > 130 and pixel.b < 150:
            inc ink
          if not GameUiPanel(origin: slots.panel.origin - vec2(3),
              size: slots.panel.size + vec2(6)).contains(point):
            doAssert pixel == rgbx(28,38,34,255), "Unexpected ink outside stats card"
      check ink > 40
      let output = getEnv("LVD_CLOCK_FIXTURE_DIR")
      if output.len > 0: image.writeFile(output / ("lvd-clock-" & $size.x & ".png"))
      echo "Countdown FBO ", size, ": gold glyph pixels=", ink

suite "spectator server notice rendering":
  test "a seatless spectator sees the authenticated notice feed":
    options.playerSlot = 0
    resetHumanCommunication()
    let client = RoomClient()
    client.accept(RoomMessage(kind: BeginMatch, match: 1).encode)
    client.accept(RoomMessage(kind: ServerNotice, match: 1, noticeId: 1,
      tick: 1, noticeCode: ThreeMinutesRemain).encode)
    client.appliedTick(1)
    observeServerCommunication(NetworkMatch(client: client))
    glDisable(GL_SCISSOR_TEST)
    glClearColor(0,0,0,1)
    glClear(GL_COLOR_BUFFER_BIT)
    sk.beginUi(window, window.size)
    drawHumanCommunication(sk,window)
    sk.endUi()
    let image = newImage(window.size.x,window.size.y)
    glReadPixels(0,0,window.size.x,window.size.y,GL_RGBA,GL_UNSIGNED_BYTE,image.data[0].addr)
    var ink = 0
    for pixel in image.data:
      if pixel.r > 170 and pixel.g > 130: inc ink
    check ink > 40
    echo "Spectator notice glyph pixels=", ink

glDeleteTextures(1, texture.addr)
glDeleteFramebuffers(1, framebuffer.addr)
window.close()
