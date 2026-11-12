## Integration contract for production shop, exercised further by the FBO fixture.
import ../shops
import ../[content, sim]
import vmath
let panels = shopInventoryPanels(vec2(1280, 800))
doAssert panels[0].origin.x < panels[1].origin.x
doAssert panels[0].size == vec2(72)
for mode in ShopSortMode:
  let catalog = sortedShopItems(mode)
  doAssert catalog.len == ShopItems.len
  for i in 1..<catalog.len:
    case mode
    of ShopSortName: doAssert catalog[i-1].itemSpec.name <= catalog[i].itemSpec.name
    of ShopSortPrice: doAssert catalog[i-1].itemSpec.cost <= catalog[i].itemSpec.cost
    of ShopSortType: doAssert catalog[i-1].itemSpec.kind <= catalog[i].itemSpec.kind
resetShopUi()
closeShop()
doAssert not consumeShopEscape()
echo "PASS shop geometry, catalog sorting and lifecycle API"
