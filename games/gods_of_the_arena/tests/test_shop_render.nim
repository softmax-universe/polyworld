## Native production shop pointer routes and framebuffer, without game art.
import std/[importutils, os]
import opengl, windy/internal
import ../replays
import polyworld/viewers
include ../shops
privateAccess(Window)
let window = newWindow("Shop input", ivec2(1600,1000), visible=false)
window.makeContextCurrent()
loadExtensions()
let builder = newHudAtlas(2048)
builder.addDefaultFonts()
let sk = newSilky(window, builder.atlasImage, builder.atlas)
sk.applyThemePatches()
sk.uiScale = 1
var fb, tex: GLuint
glGenFramebuffers(1, fb.addr)
glGenTextures(1, tex.addr)
glBindTexture(GL_TEXTURE_2D, tex)
glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8.GLint,1600,1000,0,GL_RGBA,GL_UNSIGNED_BYTE,nil)
glBindFramebuffer(GL_FRAMEBUFFER,fb)
glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,tex,0)
let hero = Hero(id: 1, state: Dying, gold: 10000)
hero.inventory[2] = HealthPotion
hero.itemCounts[2] = 3
run = Game(world: World(phase: Playing, heroes: @[hero]))
run.networked = true
proc takePlayerCommands(): seq[ReplayAction] =
  run.flushPlayerCommands()
  for submission in run.submissions:
    result.add submission.action
  run.submissions.setLen(0)
options.playerSlot = 1
shopOpen = true
proc frame(point: Vec2, pressed: set[Button] = {}, released: set[Button] = {}, down: set[Button] = {}) =
  window.state.perFrame = PerFrame(buttonPressed: pressed, buttonReleased: released)
  window.state.buttonDown = down
  sk.beginUi(window, window.size)
  sk.mousePos = point
  glClear(GL_COLOR_BUFFER_BIT)
  sk.drawShop(window, run.world, hero, vec2(1600,1000), true)
  sk.endUi()
proc center(panel: GameUiPanel): Vec2 = panel.origin + panel.size/2
let panels = shopInventoryPanels(vec2(1600,1000))
frame(panels[2].center)
clearPlayerCommands()
frame(panels[2].center, {MouseRight}, {}, {MouseRight})
frame(panels[2].center, {}, {MouseRight})
doAssert sellSlot == 2
var image = newImage(1600,1000)
glReadPixels(0,0,1600,1000,GL_RGBA,GL_UNSIGNED_BYTE,image.data[0].addr)
image.flipVertical()
image.writeFile(getEnv("GOTA_SHOP_FIXTURE",getTempDir()/"gota-shop.png"))
let sale = sellPanel.center
frame(sale,{MouseLeft},{},{MouseLeft})
frame(sale,{}, {MouseLeft})
let sold = takePlayerCommands()
doAssert sold.len == 1 and sold[0].kind == ActionSellItem and sold[0].slot == 2
frame(panels[2].center,{MouseLeft},{},{MouseLeft})
frame(panels[0].center,{}, {},{MouseLeft})
frame(panels[0].center,{}, {MouseLeft})
let moved = takePlayerCommands()
doAssert moved.len == 1 and moved[0].kind == ActionSwapItems and moved[0].slot == 2
let card = shopPanels(vec2(1600,1000)).cards[0].center
frame(card,{MouseLeft},{},{MouseLeft})
doAssert takePlayerCommands().len == 0
frame(card,{}, {MouseLeft})
let bought = takePlayerCommands()
doAssert bought.len == 1 and bought[0].kind == ActionBuyItem
doAssert bought[0].first == sortedShopItems(sortMode)[0].ord.int32
closeShop()
doAssert sellSlot == -1 and not shopOpen
window.close()
echo "PASS production shop: native Sell popup, single Sell/Swap, sorted release-only buy"
