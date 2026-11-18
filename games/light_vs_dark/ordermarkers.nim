## Read-only destinations for the selected units' persistent order markers.
import
  std/sets,
  fixxy,
  polyworld/bodies,
  content, maps, sim, replays

type
  OrderMarker* = object
    position*: FixedVec2
    attack*: bool
  BuildMarker* = object
    owner*: int32
    kind*: BuildingKind
    origin*: Tile2

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

proc selectedBuildMarkers*(world: World, selected: openArray[int32],
    owner: int32): seq[BuildMarker] =
  ## Lists selected peons' future buildings without creating or placing them.
  if world == nil: return
  var seen: HashSet[tuple[owner: int32, kind: BuildingKind, x, y: int32]]
  for id in selected:
    let index = world.unitIndex(id)
    if index < 0 or index >= world.units.len: continue
    let unit = world.units[index]
    if unit.kind != PeonUnit or unit.hp <= 0 or unit.state == UnitDying or
        (owner >= 0 and unit.owner != owner):
      continue
    for order in unit.orderQueue:
      if order.kind != ActionBuild or
          order.first notin 0'i32 .. BuildableHigh.ord.int32 or
          order.offset != FixedVec2Zero:
        continue
      let
        kind = BuildingKind(order.first)
        size = BuildingTable[kind].footprint
        x = order.second
        y = order.third
      if x < 0 or y < 0 or x > world.map.side - size.width or
          y > world.map.side - size.depth:
        continue
      let key = (unit.owner, kind, x, y)
      if key notin seen:
        seen.incl key
        result.add BuildMarker(owner: unit.owner, kind: kind,
          origin: tile2(x, y))
