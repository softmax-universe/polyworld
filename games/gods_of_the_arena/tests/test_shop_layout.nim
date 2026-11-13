import ../[layouts, shopcatalog]
import vmath
import polyworld/gameuis
for size in [vec2(1280,800),vec2(1600,1000),vec2(3840,2160)]:
  let p = shopPanels(size)
  for i in 0..<p.cards.len:
    for j in i+1..<p.cards.len:
      doAssert not p.cards[i].overlaps(p.cards[j])
  doAssert p.panel.size.x <= 1200
  doAssert p.panel.size.y <= 744
  doAssert p.panel.origin.x >= 8 and p.panel.origin.y >= 8
  doAssert p.panel.origin + p.panel.size == size - p.panel.origin
  doAssert p.tooltipGutter.size.x >= 380
  for card in p.cards:
    doAssert card.size.x >= 72 and card.size.y >= 88
    doAssert not card.overlaps(p.tooltipGutter)
    doAssert p.panel.contains(card.origin)
    doAssert p.panel.contains(card.origin + card.size - vec2(1))
  let items = sortedShopItems()
  for i in 1..<items.len:
    if items[i].shopGroup == items[i-1].shopGroup:
      let a = p.cards[i-1].origin
      let b = p.cards[i].origin
      doAssert b.y > a.y or (b.y == a.y and b.x > a.x)
echo "PASS centered compact grid, row-major grouped prices, 1280/1600/4K gutter fit"
