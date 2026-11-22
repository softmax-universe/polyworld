## Production passive inspection: native FBO, 4K layout and real HUD hit tests.
import std/[os, importutils]
import windy/internal
import opengl
import polyworld/viewers
include ../ui
privateAccess(Window)

let window = newWindow("GotA inspection 4K", ivec2(3840, 2160), visible = false)
window.makeContextCurrent()
loadExtensions()
pollEvents()
let builder = newHudAtlas(2048)
builder.addDefaultFonts()
let sk = newSilky(window, builder.atlasImage, builder.atlas)
sk.applyThemePatches()
sk.uiScale = gameUiScale(window)
run = Game(networked: true, world: World(phase: Playing, heroes: @[
  Hero(id: 104, team: RedTeam, slot: 3, class: VanguardKnight, hp: 900, maxHp: 1000),
  Hero(id: 109, team: RedTeam, slot: 4, class: VanguardKnight,
    hp: 321, maxHp: 700, mana: 42, maxMana: 90)]))
run.replayData.config.players.setLen(2)
run.replayData.config.players[1].name = "mason :)"
options.playerSlot = 1
let hud = currentChrome(window)
let panel = inspectionPanel(window)
doAssert not panel.overlaps(hud.score) and not panel.overlaps(hud.heroes)
doAssert not panel.overlaps(deathHudPanel(hud))
for plate in [hud.details, hud.inventory, hud.minimap]:
  doAssert plate.origin.y + plate.size.y == hud.layout.size.y - hud.layout.margin,
    "Normal multiplayer HUD must be bottom anchored at actual 4K"
doAssert not transportAvailable()
options.playerSlot = 0 # bot-only controller is still networked, not a watcher.
doAssert not transportAvailable()
networkSpectator = true
doAssert transportAvailable()
doAssert currentLayout(window).transportHeight == TransportHeight
networkSpectator = false
options.playerSlot = 1
let point = panel.origin + vec2(20)
doAssert mouseOverInspection(window, point, 109, 0)
doAssert mouseOverUi(window, point, 109)
doAssert not mouseOverInspection(window, point, 104, 0)
let ownDetails = hud.details.origin + vec2(20)
doAssert mouseOverUi(window, ownDetails, 0), "Permanent own HUD blocks ground orders even without inspection"

var framebuffer, texture: GLuint
glGenFramebuffers(1, framebuffer.addr)
glGenTextures(1, texture.addr)
glBindTexture(GL_TEXTURE_2D, texture)
glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.GLint, 3840, 2160,
  0, GL_RGBA, GL_UNSIGNED_BYTE, nil)
glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0)
doAssert glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE
proc render(id: int32): Image =
  sk.beginUi(window, window.size)
  glClearColor(0, 0, 0, 0)
  glClear(GL_COLOR_BUFFER_BIT)
  sk.mousePos = point
  sk.drawInspection(window, id, 0)
  doAssert not sk.mouseConsumed, "Inspection is passive, not a control"
  sk.endUi()
  result = newImage(3840, 2160)
  glReadPixels(0, 0, 3840, 2160, GL_RGBA, GL_UNSIGNED_BYTE, result.data[0].addr)
  result.flipVertical()
proc ink(image: Image): int =
  for pixel in image.data:
    if pixel.r > 180 and pixel.a > 0: inc result
let shown = render(109)
doAssert shown.ink > 250, "Actual name, identity and meters must draw readable pixels"
# Exercise production click gate, not a synthetic rectangle-only assertion.
sk.mousePos = hud.details.detailsPanels().abilities[0].origin + vec2(20)
window.state.perFrame = PerFrame(buttonPressed: {KeyA})
doAssert not window.hudClicked(sk, hud.details.detailsPanels().abilities[0]),
  "Human keyboard aliases must never cast an own HUD ability"
window.state.perFrame = PerFrame(buttonPressed: {MouseLeft})
doAssert window.hudClicked(sk, hud.details.detailsPanels().abilities[0])
doAssert render(104).ink == 0
run.world.heroes[1].team = BlueTeam
doAssert not mouseOverInspection(window, point, 109, 0)
doAssert render(109).ink == 0, "Hidden enemy inspection must vanish"
shown.writeFile(getEnv("GOTA_INSPECTION_FIXTURE", "/Users/me/.hermes/cache/scratch/gota-inspection-4k.png"))
echo "PASS native 4K inspection FBO ink=", shown.ink,
  "; passive, own HUD hit bounds, no death overlap, hidden enemy retired, human/bot footer anchored, watcher transport retained"
glDeleteTextures(1, texture.addr)
glDeleteFramebuffers(1, framebuffer.addr)
window.close()
