## Native production shop routes and framebuffer with actual packaged item art.
import std/[importutils, os, strutils]
import opengl, windy/internal
import ../replays
import polyworld/[viewers, common]
include ../shops
privateAccess(Window)
let width = parseInt(getEnv("GOTA_SHOP_WIDTH", "1600"))
let height = parseInt(getEnv("GOTA_SHOP_HEIGHT", "1000"))
let viewport = vec2(width.float32,height.float32)
let window = newWindow("Shop input", ivec2(width.int32,height.int32), visible=false)
window.makeContextCurrent()
loadExtensions()
let builder = newHudAtlas(4096)
for item in ShopItems:
  let icon = readImage(DataRoot / "items" / (item.itemSpec.icon & ".png")).resize(128,128)
  doAssert builder.addImage(itemIconKey(item), icon)
builder.addDefaultFonts()
let sk = newSilky(window, builder.atlasImage, builder.atlas)
sk.applyThemePatches()
sk.uiScale = 1
var fb, tex: GLuint
glGenFramebuffers(1, fb.addr)
glGenTextures(1, tex.addr)
glBindTexture(GL_TEXTURE_2D, tex)
glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8.GLint,width.GLsizei,height.GLsizei,0,GL_RGBA,GL_UNSIGNED_BYTE,nil)
glBindFramebuffer(GL_FRAMEBUFFER,fb)
glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,tex,0)
let hero = Hero(id: 1, state: Dying, gold: 10000)
hero.inventory[0] = ManaPotion
hero.itemCounts[0] = 2
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
  sk.drawShop(window, run.world, hero, viewport, true)
  sk.endUi()
proc center(panel: GameUiPanel): Vec2 = panel.origin + panel.size/2
let panels = shopInventoryPanels(viewport)
frame(panels[2].center)
clearPlayerCommands()
# Warm the production session with its explicit clock, then draw real art.
shopTooltip.clearTooltip()
let now = getMonoTime().ticks.float64 / 1_000_000_000.0
updateShopTooltip(hero,viewport,panels[2].center,now-0.6)
updateShopTooltip(hero,viewport,panels[2].center,now)
frame(panels[2].center)
doAssert shopTooltip.hover.visible
doAssert shopTooltip.current.card == itemDetails(HealthPotion)
let retainedPanel = shopTooltip.panel
frame(retainedPanel.center)
doAssert shopTooltip.hover.visible
frame(retainedPanel.center,{MouseLeft},{},{MouseLeft})
frame(retainedPanel.center,{}, {MouseLeft})
doAssert takePlayerCommands().len == 0
frame(panels[2].center)
var tooltipImage = newImage(width,height)
glReadPixels(0,0,width.GLsizei,height.GLsizei,GL_RGBA,GL_UNSIGNED_BYTE,tooltipImage.data[0].addr)
tooltipImage.flipVertical()
# Item interiors contain real coloured artwork, not just theme-slot chrome.
for card in shopPanels(viewport).cards:
  var coloured = 0
  for y in int(card.origin.y)+8..<int(card.origin.y)+64:
    for x in int(card.origin.x)+12..<int(card.origin.x)+68:
      let pixel = tooltipImage.data[y*width+x]
      let hi = max(pixel.r,max(pixel.g,pixel.b)).int
      let lo = min(pixel.r,min(pixel.g,pixel.b)).int
      if hi > 70 and hi-lo > 20: inc coloured
  doAssert coloured > 60, "missing item art in catalogue framebuffer"
tooltipImage.writeFile(getEnv("GOTA_SHOP_TOOLTIP_FIXTURE", getTempDir()/"gota-shop-tooltip.png"))
frame(panels[2].center, {MouseRight}, {}, {MouseRight})
frame(panels[2].center, {}, {MouseRight})
doAssert sellSlot == 2
doAssert not shopTooltip.hover.visible
var image = newImage(width,height)
glReadPixels(0,0,width.GLsizei,height.GLsizei,GL_RGBA,GL_UNSIGNED_BYTE,image.data[0].addr)
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
# Cancel a drag by Escape; its eventual release must not move or buy.
frame(panels[2].center,{MouseLeft},{},{MouseLeft})
frame(panels[1].center,{}, {},{MouseLeft})
doAssert consumeShopEscape()
frame(panels[1].center,{}, {MouseLeft})
doAssert takePlayerCommands().len == 0
# Buying targets the shown sorted item and never fires on press/held/release twice.
let card = shopPanels(viewport).cards[0].center
frame(card,{MouseLeft},{},{MouseLeft})
doAssert takePlayerCommands().len == 0
frame(card,{}, {MouseLeft})
let bought = takePlayerCommands()
doAssert bought.len == 1 and bought[0].kind == ActionBuyItem
doAssert bought[0].first == sortedShopItems(sortMode)[0].ord.int32
frame(card,{}, {MouseLeft})
doAssert takePlayerCommands().len == 0
# Warm details must not steal any catalogue buy hit, including wrapped rows.
shopTooltip.clearTooltip()
let buyNow = getMonoTime().ticks.float64 / 1_000_000_000.0
updateShopTooltip(hero,viewport,card,buyNow-0.6)
updateShopTooltip(hero,viewport,card,buyNow)
for index, item in sortedShopItems():
  waitingItem = NoItem
  let point = shopPanels(viewport).cards[index].center
  frame(point,{MouseLeft},{},{MouseLeft})
  doAssert shopTooltip.hover.visible
  doAssert shopTooltip.current.card == itemDetails(item)
  doAssert takePlayerCommands().len == 0
  frame(point,{}, {MouseLeft})
  let commands = takePlayerCommands()
  if run.world.purchaseReason(hero.id,item.ord.int32).len == 0:
    doAssert commands.len == 1 and commands[0].kind == ActionBuyItem
    doAssert commands[0].first == item.ord.int32
  else:
    doAssert commands.len == 0
closeShop()
doAssert sellSlot == -1 and not shopOpen
window.close()
echo "PASS production shop: native Sell popup, single Sell/Swap, sorted release-only buy"
