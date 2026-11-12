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

proc targetName*(world: World, id: string): string =
  ## Resolves action identifiers into readable names.
  if id in ["village", "hall"]:
    return "Willow village hall"
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
