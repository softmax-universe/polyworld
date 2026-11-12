## Native offscreen pixels from the production mana renderer (no game art).
import std/os
import chroma, pixie, silky, vmath, windy, opengl
import polyworld/[chrome, gameuis, viewers]
import ../[content, maps, sim, hudpresentation, layouts]

let window = newWindow("Cleric mana regression", ivec2(760, 245), visible = false)
window.makeContextCurrent()
loadExtensions()
pollEvents()
let builder = newHudAtlas(2048)
builder.addDefaultFonts()
let sk = newSilky(window, builder.atlasImage, builder.atlas)
sk.applyThemePatches()
sk.uiScale = 1
var framebuffer, texture: GLuint
glGenFramebuffers(1, framebuffer.addr)
glGenTextures(1, texture.addr)
glBindTexture(GL_TEXTURE_2D, texture)
glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.GLint, window.size.x, window.size.y,
  0, GL_RGBA, GL_UNSIGNED_BYTE, nil)
glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0)
doAssert glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE
let w = newWorld(generateMap(DefaultSeed), TickRate * 10)
let id = w.spawnUnit(0, ClericUnit, tile2(w.map.side div 2, w.map.side div 2))
let cleric = w.units[w.unitIndex(id)]
let patientId = w.spawnUnit(0, SoldierUnit, tile2(cleric.tile.x.int32 + 1, cleric.tile.y.int32))
w.units[w.unitIndex(patientId)].hp -= 10
sk.beginUi(window, window.size)
sk.drawRect(vec2(0), window.size.vec2, rgbx(20, 24, 32, 255))
for i in 0 .. 1:
  if i == 1:
    cleric.mana = ClericHealManaCost
    w.tickWorld(nil)
    doAssert cleric.mana == 0
    doAssert w.units[w.unitIndex(patientId)].hp == unitOf(0, SoldierUnit).hp - 2
  let panel = GameUiPanel(origin: vec2(8 + i.float32 * 378, 8), size: PanelSelection)
  sk.drawPanel(panel)
  let selection = panel.selectionPanels(true)
  sk.drawClericMana(selection.cargo, cleric)
  sk.drawLabel(if i == 0: "Full reserve" else: "Heal: 5 to 0", selection.name.origin,
    selection.name.size, rgbx(230, 230, 230, 255), "Small")
  for slot in selection.units:
    doAssert slot.origin.y >= selection.cargo.origin.y + selection.cargo.size.y
    doAssert slot.origin.y + slot.size.y <= panel.origin.y + panel.size.y
sk.endUi()
let image = newImage(window.size.x, window.size.y)
glReadPixels(0, 0, window.size.x, window.size.y, GL_RGBA, GL_UNSIGNED_BYTE, image.data[0].addr)
image.flipVertical()
var blue: array[2, int]
for i in 0 .. 1:
  let panel = GameUiPanel(origin: vec2(8 + i.float32 * 378, 8), size: PanelSelection)
  let mana = panel.selectionPanels(true).cargo
  for y in mana.origin.y.int + 23 ..< mana.origin.y.int + 46:
    for x in mana.origin.x.int ..< (mana.origin.x + mana.size.x).int:
      let pixel = image[x, y]
      if pixel.b.int > pixel.r.int + 40 and pixel.b > 100: inc blue[i]
doAssert blue[0] > 500 and blue[1] < blue[0] div 4, $blue
let output = getEnv("LVD_HEAL_FIXTURE", getEnv("TMPDIR") / "cleric-mana.png")
image.writeFile(output)
echo "Native mana pixels before/after actual heal: ", blue, " image=", output
glDeleteTextures(1, texture.addr)
glDeleteFramebuffers(1, framebuffer.addr)
window.close()
