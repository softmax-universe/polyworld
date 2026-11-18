## Read-only destinations for the selected units' persistent order markers.
import
  std/sets,
  fixxy,
  polyworld/bodies,
  maps, sim, replays

type OrderMarker* = object
  position*: FixedVec2
  attack*: bool

proc selectedOrderMarkers*(world: World, selected: openArray[int32],
    owner: int32): seq[OrderMarker] =
  ## Lists active and queued movement destinations without changing orders.
  if world == nil: return
  var seen: HashSet[tuple[x, y: int32, attack: bool]]
  template addMarker(targetX, targetY: int32, offsetValue: FixedVec2,
      isAttack: bool) =
    block:
      let
        x = targetX
        y = targetY
        offset = offsetValue
      if world.map.inGrid(x, y) and offset.validTileOffset:
        let
          marker = OrderMarker(position: fixedVec2(
            fixed(x) + FixedHalf, fixed(y) + FixedHalf) + offset,
            attack: isAttack)
          key = (int32(marker.position.x), int32(marker.position.y),
            marker.attack)
        if key notin seen:
          seen.incl key
          result.add marker
  for id in selected:
    let index = world.unitIndex(id)
    if index < 0 or index >= world.units.len: continue
    let unit = world.units[index]
    if unit.hp <= 0 or unit.state in {UnitDying, UnitInMine} or
        (owner >= 0 and unit.owner != owner):
      continue
    if unit.attackMove:
      addMarker(unit.attackMoveGoal.x.int32, unit.attackMoveGoal.y.int32,
        unit.attackMoveOffset, true)
    elif unit.state == UnitMoving and unit.hasGoal and not unit.autoAttacking:
      addMarker(unit.goal.x.int32, unit.goal.y.int32, unit.goalOffset, false)
    for order in unit.orderQueue:
      if order.kind in {ActionMove, ActionAttackMove}:
        addMarker(order.first, order.second, order.offset,
          order.kind == ActionAttackMove)
