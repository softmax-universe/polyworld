## Actual Silky preparation plate: tick rounding, layout and native pixels.
import std/os
import opengl
import polyworld/viewers
include ../ui

let window = newWindow("GotA preparation HUD", ivec2(1600, 1000), visible = false)
window.makeContextCurrent()
loadExtensions()
pollEvents()
let builder = newHudAtlas(2048)
builder.addDefaultFonts()
let sk = newSilky(window, builder.atlasImage, builder.atlas)
sk.applyThemePatches()
sk.uiScale = 1
run = Game(world: World(phase: Playing, drafting: true, heroes: @[
  Hero(id: 1, team: RedTeam), Hero(id: 2, team: BlueTeam)]))
options.playerSlot = 1
doAssert preparationHudText(run.world) == "PREPARATION 0:30"
run.world.preparationTicks = 1
doAssert preparationHudText(run.world) == "PREPARATION 0:30"
run.world.preparationTicks = TickRate
doAssert preparationHudText(run.world) == "PREPARATION 0:29"
run.world.preparationTicks = PreparationTicks - 1
doAssert preparationHudText(run.world) == "PREPARATION 0:01"
let hud = placeChrome(initGameUiLayout(vec2(1600, 1000)))
let panel = preparationHudPanel(hud)
doAssert not panel.overlaps(hud.heroes)
doAssert not panel.overlaps(deathHudPanel(hud))
doAssert not panel.overlaps(inspectionPanel(window))
for size in [vec2(1280, 800), vec2(1600, 1000), vec2(3840, 2160)]:
  for count in [1, 5]:
    run.world.heroes.setLen(0)
    for team in Team:
      for slot in 0 ..< count:
        run.world.heroes.add Hero(team: team)
    let chrome = placeChrome(initGameUiLayout(size / gameUiScale(size)))
    let preparation = preparationHudPanel(chrome)
    doAssert not preparation.overlaps(chrome.heroes)
    doAssert not preparation.overlaps(deathHudPanel(chrome))
    doAssert preparation.origin.x >= 0
    doAssert preparation.origin.x + preparation.size.x <= chrome.layout.size.x
    doAssert preparation.origin.y + preparation.size.y < chrome.details.origin.y
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
  sk.beginUi(window, window.size)
  glClearColor(0, 0, 0, 0)
  glClear(GL_COLOR_BUFFER_BIT)
  sk.drawPreparationHud(hud)
  doAssert not sk.mouseConsumed
  sk.endUi()
  result = newImage(1600, 1000)
  glReadPixels(0, 0, 1600, 1000, GL_RGBA, GL_UNSIGNED_BYTE, result.data[0].addr)
  result.flipVertical()
proc ink(image: Image): int =
  for pixel in image.data:
    if pixel.r > 180 and pixel.a > 0: inc result
run.world.preparationTicks = 0
let shown = render()
doAssert shown.ink > 100
doAssert render().data == shown.data
run.world.preparationTicks = TickRate
doAssert render().data != shown.data
run.world.preparationTicks = PreparationTicks
doAssert render().ink == 0
doAssert preparationHudText(run.world) == ""
run.world.phase = Drafting
doAssert render().ink == 0
shown.writeFile(getEnv("GOTA_PREPARATION_FIXTURE", getTempDir() / "gota-preparation-hud.png"))
glDeleteTextures(1, texture.addr)
glDeleteFramebuffers(1, framebuffer.addr)
window.close()
echo "PASS native preparation HUD: ceil ticks, themed pixels, pause stable, no overlaps, opening hidden"
