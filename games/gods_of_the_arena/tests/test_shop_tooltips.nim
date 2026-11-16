include ../shops
let size = vec2(1280,800)
let hero = Hero(id: 1)
hero.inventory[0] = PortalScroll
hero.itemCounts[0] = 2
let cards = shopPanels(size).cards
let first = cards[0].origin + vec2(30)
updateShopTooltip(hero,size,first,0)
doAssert not shopTooltip.hover.visible
updateShopTooltip(hero,size,first,0.51)
doAssert shopTooltip.hover.visible
doAssert shopTooltip.current.card == itemDetails(HealthPotion)
let retained = shopTooltip.current
let panel = shopTooltip.panel
doAssert not panel.overlaps(shopPanels(size).catalog)
for card in cards: doAssert not panel.overlaps(card)
updateShopTooltip(hero,size,panel.origin+vec2(40),0.6)
doAssert shopTooltip.current == retained
doAssert shopTooltip.hover.visible
let other = cards[1].origin+vec2(30)
updateShopTooltip(hero,size,other,0.7)
doAssert shopTooltip.hover.visible
doAssert shopTooltip.current.card == itemDetails(VitalityElixir)
let inventory = shopInventoryPanels(size)[0]
updateShopTooltip(hero,size,inventory.origin+vec2(30),0.8)
doAssert shopTooltip.current.card == itemDetails(PortalScroll)
doAssert shopTooltip.hover.visible
resetShopUi()
for view in [vec2(1280,720),vec2(1280,800),vec2(1600,1000),vec2(3840,2160)]:
  for index, item in sortedShopItems():
    let at = shopPanels(view).cards[index].origin + vec2(30)
    shopTooltip.clearTooltip()
    updateShopTooltip(hero,view,at,1)
    updateShopTooltip(hero,view,at,1.6)
    doAssert shopTooltip.hover.visible
    doAssert shopTooltip.current.card == itemDetails(item)
    let p = shopTooltip.panel
    let gutter = shopPanels(view).tooltipGutter
    doAssert gutter.contains(p.origin)
    doAssert gutter.contains(p.origin+p.size-vec2(1))
    doAssert p.origin.x+p.size.x <= view.x-8
    doAssert p.origin.y+p.size.y <= view.y-8
resetShopUi()
doAssert not shopTooltip.hover.visible
echo "PASS exact HUD itemDetails, shared warmth, reserved gutter and retained popup"
