## Persistent destinations read from a hero's authoritative command queue.
import
  fixxy,
  maps, replays, sim

type OrderMarker* = object
  position*: FixedVec2
  attack*: bool

proc heroOrderMarkers*(hero: Hero): seq[OrderMarker] =
  ## Lists remaining explicit movement goals without changing simulation state.
  if hero == nil or hero.hp <= 0 or hero.state == Dying:
    return
  template addMarker(orderValue: HeroOrder) =
    block:
      let order = orderValue
      if order.kind in {ActionWalkTo, ActionAttackMove} and
        order.first >= 0 and order.second >= 0 and
        order.first < mapTiles().int32 and order.second < mapTiles().int32:
          result.add OrderMarker(
            position: fixedVec2(fixed(order.first) + FixedHalf,
              fixed(order.second) + FixedHalf) + order.offset,
            attack: order.kind == ActionAttackMove
          )
  if hero.hasOrder:
    addMarker(hero.activeOrder)
  for order in hero.queuedOrders:
    addMarker(order)
