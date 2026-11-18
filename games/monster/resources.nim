import
  std/strutils,
  common

proc resourceName*(kind: ResourceKind): string {.raises: [].} =
  ## Names a physical resource in player-facing language.
  case kind
  of BerriesResource: "berries"
  of GrainResource: "grain"
  of FishResource: "fish"
  of SoftwoodResource: "pine wood"
  of HardwoodResource: "oak wood"
  of StoneResource: "stone"

proc total*(stock: Inventory): int {.raises: [].} =
  ## Counts all carried or stored units.
  for amount in stock:
    result += amount

proc foodTotal*(stock: Inventory): int {.raises: [].} =
  ## Counts edible supplies without including building materials.
  for kind in BerriesResource .. FishResource:
    result += stock[kind]

proc inventoryText*(stock: Inventory): string =
  ## Describes each occupied inventory slot with its actual resource type.
  var items: seq[string]
  for kind in ResourceKind:
    if stock[kind] > 0:
      items.add $stock[kind] & " " & kind.resourceName()
  if items.len == 0: "empty" else: items.join(", ")

proc sourceIndex*(world: World, id: string): int {.raises: [].} =
  ## Finds a resource source by its stable action identifier.
  for i, source in world.sources:
    if source.id == id:
      return i
  -1

proc householdIndex*(world: World, id: string): int {.raises: [].} =
  ## Finds a household by its stable delivery identifier.
  for i, house in world.households:
    if house.id == id:
      return i
  -1

proc villagerIndex*(world: World, id: string): int {.raises: [].} =
  ## Finds a person by their stable delivery identifier.
  for i, villager in world.villagers:
    if villager.id == id:
      return i
  -1

proc villageIndex*(world: World, id: string): int {.raises: [].} =
  ## Finds an independent hall, including the original village alias.
  let target = if id == "hall": "village" else: id
  for i, village in world.villages:
    if village.id == target:
      return i
  -1

proc targetDestroyed*(world: World, id: string): bool {.raises: [].} =
  ## Reports permanent loss without treating an unknown landmark as a target.
  let person = world.villagerIndex(id)
  if person >= 0:
    return world.villagers[person].health <= 0
  let house = world.householdIndex(id)
  if house >= 0:
    return world.households[house].integrity <= 0
  let village = world.villageIndex(id)
  if village >= 0:
    return world.villages[village].health <= 0
  let source = world.sourceIndex(id)
  source >= 0 and world.sources[source].destroyed

proc villageSupplies*(world: World, index: int): Inventory {.raises: [].} =
  ## Counts supplies owned by a village across its hall, homes, and carriers.
  if index < 0 or index >= world.villages.len:
    return
  result = world.villages[index].stock
  for house in world.households:
    if house.village == index:
      for kind in ResourceKind:
        result[kind] += house.stock[kind]
  for person in world.villagers:
    if world.households[person.home].village == index and person.health > 0:
      for kind in ResourceKind:
        result[kind] += person.cargo[kind]

proc villageWellbeing*(world: World, index: int): int {.raises: [].} =
  ## Averages actual hunger, warmth, and home condition into a readable score.
  var score = 0'f
  var measures = 0
  for house in world.households:
    if house.village == index:
      score += min(100'f, house.fuel / 35 * 100) + house.integrity
      measures += 2
  for person in world.villagers:
    if world.households[person.home].village == index:
      if person.health > 0:
        score += min(100 - person.hunger, person.health)
      inc measures
  if measures > 0:
    result = int(score / measures.float32)

proc targetName*(world: World, id: string): string =
  ## Resolves action identifiers into readable names.
  let village = world.villageIndex(id)
  if village >= 0:
    return world.villages[village].name & " hall"
  let person = world.villagerIndex(id)
  if person >= 0:
    return world.villagers[person].name
  let house = world.householdIndex(id)
  if house >= 0:
    return world.households[house].name
  let source = world.sourceIndex(id)
  if source >= 0:
    return world.sources[source].name
  for place in world.map.landmarks:
    if place.id == id:
      return place.name
  id

proc transfer*(source, destination: var Inventory) {.raises: [].} =
  ## Moves every unit without changing its resource type.
  for kind in ResourceKind:
    destination[kind] += source[kind]
    source[kind] = 0

proc eat*(stock: var Inventory): bool {.raises: [].} =
  ## Consumes one available food unit in a stable order.
  for kind in BerriesResource .. FishResource:
    if stock[kind] > 0:
      dec stock[kind]
      return true
