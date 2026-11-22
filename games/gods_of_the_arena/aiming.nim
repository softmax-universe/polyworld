## Nearby click targets for human controls after a direct mesh pick misses.

import sim

proc consider(point, position: WorldPoint, id: int32,
    best: var int64, selected: var int32) =
  ## Selects the nearest center within the inclusive radius, breaking ties by ID.
  let
    dx = int64(position.x) - point.x
    dz = int64(position.z) - point.z
    distance = dx * dx + dz * dz
  if distance < best or
    (distance == best and (selected == 0 or id < selected)):
      best = distance
      selected = id

proc nearbyTarget*(world: World, team: Team, point: WorldPoint,
    healing = false, denyingHeroId = 0'i32): int32 =
  ## Finds visible enemies, healing allies, or explicitly requested creep denies.
  var best = int64(2 * WorldScale) * (2 * WorldScale)
  for hero in world.heroes:
    if hero.id == 0 or hero.hp <= 0 or hero.state == Dying or
      (hero.team == team) != healing or not world.visible(team, hero.position):
        continue
    consider(point, hero.position, hero.id, best, result)
  if healing:
    return
  let
    denier = world.heroById(denyingHeroId)
    canDeny = denier.id != 0 and denier.team == team and
      denier.hp > 0 and denier.state != Dying
  for unit in world.footmen:
    let deniable = canDeny and world.canDeny(denier, unit.id)
    if (not world.hostile(unit, team, engageResting = true) and not deniable) or
      not world.visible(team, unit.position):
        continue
    consider(point, unit.position, unit.id, best, result)
  for building in world.buildings:
    if building.id == 0 or building.team == team or
      not world.buildingExposed(building) or
      not world.visible(team, building.position):
        continue
    consider(point, building.position, building.id, best, result)
  for god in world.forts:
    if god.id == 0 or god.hp <= 0 or god.team == team or
      not world.fortExposed(god.team) or not world.visible(team, god.center):
        continue
    consider(point, god.center, god.id, best, result)
