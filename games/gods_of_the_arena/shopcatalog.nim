## Shop presentation only: functional groups and stable actual-price order.
import std/algorithm
import content

type
  ShopGroup* = enum
    ShopHealing, ShopMana, ShopMelee, ShopRanged, ShopEquipment, ShopUtility
  ShopSortMode* = enum
    ShopSortName, ShopSortPrice, ShopSortType, ShopSortGrouped

const ShopGroupNames*: array[ShopGroup, string] =
  ["HEALING", "MANA", "MELEE", "RANGED", "OTHER EQUIPMENT", "UTILITY"]

proc shopGroup*(item: Item): ShopGroup =
  let spec = item.itemSpec
  if spec.heal > 0: ShopHealing
  elif spec.restore > 0: ShopMana
  elif item in [BattleAxe, SunsteelLongsword]: ShopMelee
  elif item in [RuneCrossbow, RangerBow]: ShopRanged
  elif spec.kind == Equipment: ShopEquipment
  else: ShopUtility

proc sortedShopItems*(mode: ShopSortMode = ShopSortGrouped): seq[Item] =
  result = @ShopItems
  result.sort(proc(a, b: Item): int =
    case mode
    of ShopSortName: result = cmp(a.itemSpec.name, b.itemSpec.name)
    of ShopSortPrice: result = cmp(a.itemSpec.cost, b.itemSpec.cost)
    of ShopSortType: result = cmp(a.itemSpec.kind, b.itemSpec.kind)
    of ShopSortGrouped:
      result = cmp(a.shopGroup, b.shopGroup)
      if result == 0: result = cmp(a.itemSpec.cost, b.itemSpec.cost)
    if result == 0: result = cmp(a.itemSpec.name, b.itemSpec.name)
    if result == 0: result = cmp(a.ord, b.ord))
