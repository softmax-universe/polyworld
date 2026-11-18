## Persistent markers follow explicit hero commands, including attack moves.
import
  fixxy,
  ../[maps, ordermarkers, replays, sim]

proc order(x, y: int32, attack = false,
    offset = FixedVec2Zero): HeroOrder =
  ## Builds one movement destination with an optional precise tile offset.
  HeroOrder(kind: if attack: ActionAttackMove else: ActionWalkTo,
    first: x, second: y, offset: offset)

proc marker(x, y: int32, attack = false,
    offset = FixedVec2Zero): OrderMarker =
  ## Builds the expected marker in absolute tile coordinates.
  OrderMarker(position: fixedVec2(fixed(x) + FixedHalf,
    fixed(y) + FixedHalf) + offset, attack: attack)

let
  half = (mapTiles() div 2).int32
  hero = Hero(id: 1, hp: 100, state: Marching, hasOrder: true,
    activeOrder: order(half, half),
    queuedOrders: @[order(half + 3, half), order(half + 3, half + 3)])
  initial = @[marker(half, half), marker(half + 3, half),
    marker(half + 3, half + 3)]
doAssert hero.heroOrderMarkers() == initial
doAssert hero.hasOrder and hero.queuedOrders.len == 2
doAssert hero.activeOrder == order(half, half)

# Advancing or replacing commands removes old destinations immediately.
hero.activeOrder = hero.queuedOrders[0]
hero.queuedOrders.delete(0)
doAssert hero.heroOrderMarkers() == initial[1 .. 2]
hero.activeOrder = order(half - 2, half)
hero.queuedOrders.setLen(0)
doAssert hero.heroOrderMarkers() == @[marker(half - 2, half)]
hero.hasOrder = false
doAssert hero.heroOrderMarkers().len == 0
echo "PASS explicit waypoints follow command completion, replacement and stop"

# Automatic chases and cast approach paths are not explicit move orders.
hero.hasMoveTarget = true
hero.moveTileX = half.int
hero.moveTileY = half.int
hero.attackObjectId = 10
hero.hasQueuedCast = true
doAssert hero.heroOrderMarkers().len == 0
hero.hasOrder = true
hero.activeOrder = HeroOrder(kind: ActionAttackTarget, first: 10)
doAssert hero.heroOrderMarkers().len == 0
hero.queuedOrders.add order(half + 2, half + 1)
doAssert hero.heroOrderMarkers() == @[marker(half + 2, half + 1)]
hero.activeOrder = order(half + 5, half + 4, true)
hero.attackMoving = true
doAssert hero.heroOrderMarkers() == @[
  marker(half + 5, half + 4, true), marker(half + 2, half + 1)]
echo "PASS attack moves retain their real goal during combat and ignore chases"

# All bounded queue entries render and preserve precise movement offsets.
hero.activeOrder = order(half, half)
hero.queuedOrders.setLen(0)
for i in 0 ..< MaxHeroOrders:
  hero.queuedOrders.add order(half + (i mod 4).int32,
    half + (i div 4).int32, offset = fixedVec2(-0.2'fx, 0.1'fx))
let markers = hero.heroOrderMarkers()
doAssert markers.len == MaxHeroOrders + 1
for i in 0 ..< MaxHeroOrders:
  doAssert markers[i + 1] == marker(half + (i mod 4).int32,
    half + (i div 4).int32, offset = fixedVec2(-0.2'fx, 0.1'fx))
hero.hp = 0
doAssert hero.heroOrderMarkers().len == 0
hero.hp = 100
hero.state = Dying
doAssert hero.heroOrderMarkers().len == 0
doAssert heroOrderMarkers(nil).len == 0
echo "PASS every queued marker survives, while dead and missing heroes hide paths"
