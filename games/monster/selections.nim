import
  std/strutils,
  vmath,
  common, resources

type
  SelectionKind* = enum
    MossSelection, VillagerSelection, SourceSelection, HouseholdSelection,
    VillageSelection, NoSelection
  Selection* = object
    kind*: SelectionKind
    id*: string

proc selectionById*(world: World, id: string): Selection =
  ## Resolves a stable inspection target without creating a creature order.
  let key = id.strip().toLowerAscii()
  if key in ["moss", "creature"]:
    return Selection(kind: MossSelection, id: "moss")
  let person = world.villagerIndex(key)
  if person >= 0:
    return Selection(kind: VillagerSelection, id: world.villagers[person].id)
  let source = world.sourceIndex(key)
  if source >= 0:
    return Selection(kind: SourceSelection, id: world.sources[source].id)
  let house = world.householdIndex(key)
  if house >= 0:
    return Selection(kind: HouseholdSelection, id: world.households[house].id)
  let village = world.villageIndex(key)
  if village >= 0:
    return Selection(kind: VillageSelection, id: world.villages[village].id)
  Selection(kind: NoSelection)

proc resolveSelection*(world: World, selection: Selection): Selection =
  ## Keeps valid inspected entities and safely falls back to Moss otherwise.
  if selection.kind != MossSelection:
    let resolved = world.selectionById(selection.id)
    if resolved.kind == selection.kind and resolved.kind != NoSelection:
      return resolved
  Selection(kind: MossSelection, id: "moss")

proc selectionDestroyed*(world: World, selection: Selection): bool =
  ## Identifies inspectable ruins and exhausted wreckage by their stable owner.
  case selection.kind
  of HouseholdSelection:
    let index = world.householdIndex(selection.id)
    index >= 0 and world.households[index].integrity <= 0
  of VillageSelection:
    let index = world.villageIndex(selection.id)
    index >= 0 and world.villages[index].health <= 0
  of SourceSelection:
    let index = world.sourceIndex(selection.id)
    index >= 0 and world.sources[index].destroyed
  else:
    false

proc scenerySelection*(world: World, scenery: Scenery): Selection =
  ## Maps a visible hall, home, field, or berry bush to its inspectable owner.
  result = Selection(kind: NoSelection)
  case scenery.prop
  of "town_hall":
    var nearest = 16'f
    for village in world.villages:
      let distance = lengthSq(scenery.position -
        village.position - vec2(-3, -5))
      if distance <= nearest:
        nearest = distance
        result = Selection(kind: VillageSelection, id: village.id)
  of "hut":
    var nearest = 16'f
    for house in world.households:
      let distance = lengthSq(scenery.position - house.position)
      if distance <= nearest:
        nearest = distance
        result = Selection(kind: HouseholdSelection, id: house.id)
  of "farm", "berries":
    let kind =
      if scenery.prop == "farm": GrainResource
      else: BerriesResource
    var nearest = 25'f
    for source in world.sources:
      if source.resource != kind:
        continue
      let distance = lengthSq(scenery.position - source.position)
      if distance <= nearest:
        nearest = distance
        result = Selection(kind: SourceSelection, id: source.id)
  else:
    discard
