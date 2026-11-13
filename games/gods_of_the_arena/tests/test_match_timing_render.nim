## Invoke the actual production TAB route with a native hidden window/FBO.
import std/importutils
import windy/[internal, platforms/macos/macdefs]
import opengl
import polyworld/viewers
include ../ui
privateAccess(Window)

let window = newWindow("GotA TAB timing", ivec2(1600, 1000), visible = false)
window.makeContextCurrent()
loadExtensions()
pollEvents()
let builder = newHudAtlas(2048)
builder.addDefaultFonts()
let sk = newSilky(window, builder.atlasImage, builder.atlas)
sk.applyThemePatches()
sk.uiScale = 1
run = Game(world: World(phase: Playing), history: MetricHistory())
run.replayData.config.maxTicks = 367 * TickRate
var framebuffer, texture: GLuint
glGenFramebuffers(1, framebuffer.addr)
glGenTextures(1, texture.addr)
glBindTexture(GL_TEXTURE_2D, texture)
glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.GLint, 1600, 1000,
  0, GL_RGBA, GL_UNSIGNED_BYTE, nil)
glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0)
doAssert glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE
proc render(): Image =
  glClearColor(0, 0, 0, 0)
  glClear(GL_COLOR_BUFFER_BIT)
  sk.drawStatsOverlay(window)
  result = newImage(1600, 1000)
  glReadPixels(0, 0, 1600, 1000, GL_RGBA, GL_UNSIGNED_BYTE, result.data[0].addr)
proc ink(image: Image): int =
  for pixel in image.data:
    if pixel.a > 0: inc result
doAssert render().ink == 0, "No TAB means no scoreboard"
NSApp.activateIgnoringOtherApps(true)
window.inner.makeKeyAndOrderFront(ID(0))
pollEvents()
doAssert window.focused, "Native fixture must own focused TAB input"
window.state.buttonDown.incl(KeyTab)
let shown = render()
doAssert shown.ink > 1000, "Held TAB must execute the production render route"
run.world.tick = TickRate
let next = render()
doAssert shown.data != next.data, "Changing authoritative remaining time must change actual TAB pixels"
doAssert next.data == render().data, "Paused tick cannot drift"
run.world.gameOver = true
let ended = render()
doAssert ended.data != next.data
run.world.tick = 900 * TickRate
doAssert ended.data == render().data, "Game-over timer stays zero beyond cutoff"
glDeleteTextures(1, texture.addr)
glDeleteFramebuffers(1, framebuffer.addr)
window.close()
echo "PASS native production TAB FBO: configured countdown changes pixels, pause stable, game-over clamped"
