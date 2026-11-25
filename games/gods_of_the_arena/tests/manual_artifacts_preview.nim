import
  std/[os, strutils],
  opengl,
  polyworld/[viewers, common]
include ../shops

let
  width = parseInt(getEnv("GOTA_ARTIFACTS_WIDTH", "1600"))
  height = parseInt(getEnv("GOTA_ARTIFACTS_HEIGHT", "1000"))
  viewport = vec2(width.float32, height.float32)
  window = newWindow("Magical artifacts",
    ivec2(width.int32, height.int32), visible = false)
window.makeContextCurrent()
loadExtensions()
let builder = newHudAtlas(4096)
for item in ShopItems:
  let icon = readImage(DataRoot / "items" /
    (item.itemSpec.icon & ".png")).resize(128, 128)
  doAssert builder.addImage(itemIconKey(item), icon)
builder.addDefaultFonts()
let sk = newSilky(window, builder.atlasImage, builder.atlas)
sk.applyThemePatches()
sk.uiScale = 1

var framebuffer, texture: GLuint
glGenFramebuffers(1, framebuffer.addr)
glGenTextures(1, texture.addr)
glBindTexture(GL_TEXTURE_2D, texture)
glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.GLint, width.GLsizei,
  height.GLsizei, 0, GL_RGBA, GL_UNSIGNED_BYTE, nil)
glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
  GL_TEXTURE_2D, texture, 0)

let hero = Hero(id: 1, state: Dying, gold: 10000)
for slot, item in ArtifactItems:
  hero.inventory[slot] = item
  hero.itemCounts[slot] = 1
run = Game(world: World(phase: Playing, heroes: @[hero]))
options.playerSlot = 1
shopOpen = true
proc drawFrame(point: Vec2) =
  ## Draws the production shop into the preview framebuffer.
  sk.beginUi(window, window.size)
  sk.mousePos = point
  glClear(GL_COLOR_BUFFER_BIT)
  sk.drawShop(window, run.world, hero, viewport, true)
  sk.endUi()

let
  panel = shopInventoryPanels(viewport)[2]
  point = panel.origin + panel.size / 2
drawFrame(point)
let
  now = getMonoTime().ticks.float64 / 1_000_000_000.0
shopTooltip.clearTooltip()
updateShopTooltip(hero, viewport, point, now - 0.6)
updateShopTooltip(hero, viewport, point, now)
drawFrame(point)
doAssert shopTooltip.hover.visible
doAssert shopTooltip.current.card == itemDetails(Worldbreaker)
var preview = newImage(width, height)
glReadPixels(0, 0, width.GLsizei, height.GLsizei,
  GL_RGBA, GL_UNSIGNED_BYTE, preview.data[0].addr)
preview.flipVertical()
preview.writeFile(getEnv("GOTA_ARTIFACTS_PREVIEW",
  getCurrentDir() / "output/gota-artifacts.png"))
window.close()
