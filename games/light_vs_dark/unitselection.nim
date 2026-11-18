## Read-only unit selection, independent of camera position and simulation writes.
import content, sim

proc nextIdlePeon*(world: World, owner, after: int32): int32 =
  ## Cycles owned idle workers by identifier without changing their orders.
  if world == nil or owner < 0 or owner >= world.players.len: return NoEntity
  var first = NoEntity
  for unit in world.units:
    if unit.owner != owner or unit.kind != PeonUnit or unit.hp <= 0 or
        unit.state != UnitIdle or unit.hasGoal or unit.orderQueue.len > 0:
      continue
    if first == NoEntity or unit.id < first: first = unit.id
    if unit.id > after and (result == NoEntity or unit.id < result):
      result = unit.id
  if result == NoEntity: result = first

proc matchingUnitIds*(world: World, clicked, owner: int32): seq[int32] =
  ## A negative owner is the existing omniscient spectator selection scope.
  ## Keep the clicked unit first so group selection preserves its primary.
  if world == nil:
    return
  let index = world.unitIndex(clicked)
  if index < 0:
    return
  let target = world.units[index]
  if target.hp <= 0 or target.state in {UnitDying, UnitInMine} or
      (owner >= 0 and target.owner != owner):
    return
  result.add clicked
  for unit in world.units:
    if unit.id != clicked and unit.kind == target.kind and unit.hp > 0 and
        unit.state notin {UnitDying, UnitInMine} and
        (owner < 0 or unit.owner == owner):
      result.add unit.id
