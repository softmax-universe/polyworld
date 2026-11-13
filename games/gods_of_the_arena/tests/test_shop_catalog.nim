## Functional catalogue is price ordered within each visible group.
import ../[shops, content]
var previousGroup = -1
var previousCost = -1'i32
let catalog = sortedShopItems(ShopSortGrouped)
doAssert catalog.len == ShopItems.len
for item in catalog:
  let group = item.shopGroup.ord
  doAssert group >= previousGroup
  if group != previousGroup: previousCost = -1
  doAssert item.itemSpec.cost >= previousCost
  previousGroup = group
  previousCost = item.itemSpec.cost
doAssert HealthPotion.shopGroup == ShopHealing
doAssert ManaPotion.shopGroup == ShopMana
doAssert SunsteelLongsword.shopGroup == ShopMelee
doAssert RangerBow.shopGroup == ShopRanged
doAssert SteelHelmet.shopGroup == ShopEquipment
doAssert PortalScroll.shopGroup == ShopUtility
doAssert catalog[0] == HealthPotion
echo "PASS functional groups / ascending actual prices"
