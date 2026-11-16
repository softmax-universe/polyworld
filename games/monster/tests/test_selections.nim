import
  vmath,
  ../[common, maps, selections, sim]

echo "Testing selection identities and safe fallbacks"
block:
  var world = newWorld(generateMap())
  doAssert world.resolveSelection(Selection()).kind == MossSelection
  doAssert world.selectionById("moss").kind == MossSelection
  doAssert world.selectionById(" MOSS ").kind == MossSelection
  doAssert world.selectionById("hall") == world.selectionById("village")
  doAssert world.selectionById("missing").kind == NoSelection
  doAssert world.resolveSelection(Selection(kind: NoSelection)).kind ==
    MossSelection
  for person in world.villagers:
    let selected = world.selectionById(person.id)
    doAssert selected.kind == VillagerSelection
    doAssert selected.id == person.id
    doAssert world.resolveSelection(selected) == selected
  for source in world.sources:
    let selected = world.selectionById(source.id)
    doAssert selected.kind == SourceSelection
    doAssert selected.id == source.id
    doAssert world.resolveSelection(selected) == selected
  for house in world.households:
    let selected = world.selectionById(house.id)
    doAssert selected.kind == HouseholdSelection
    doAssert selected.id == house.id
    doAssert world.resolveSelection(selected) == selected
  for village in world.villages:
    let selected = world.selectionById(village.id)
    doAssert selected.kind == VillageSelection
    doAssert selected.id == village.id
    doAssert world.resolveSelection(selected) == selected
  for kind in [VillagerSelection, SourceSelection, HouseholdSelection,
      VillageSelection]:
    doAssert world.resolveSelection(Selection(kind: kind,
      id: "missing")).kind == MossSelection
  doAssert world.resolveSelection(Selection(kind: VillagerSelection,
    id: "miller_hut")).kind == MossSelection,
    "A stale or mismatched identity must not display another entity's stats."
  let ada = world.selectionById("ada")
  swap(world.villagers[0], world.villagers[1])
  doAssert world.resolveSelection(ada) == ada,
    "Selection follows stable IDs rather than positions in the NPC list."
  for person in world.villagers.mitems:
    if person.id == "ada":
      person.health = 0
      person.cargo[StoneResource] = 2
  doAssert world.resolveSelection(ada) == ada,
    "Dead residents remain inspectable along with their carried supplies."
  world.villagers.setLen(0)
  doAssert world.resolveSelection(ada).kind == MossSelection
  doAssert world.actions.len == 0,
    "Inspection must never create creature orders."

echo "Testing visible scenery selects its own settlement or supplies"
block:
  let world = newWorld(generateMap())
  for scenery in world.map.props:
    let selected = world.scenerySelection(scenery)
    case scenery.prop
    of "town_hall":
      doAssert selected.kind == VillageSelection
    of "hut":
      doAssert selected.kind == HouseholdSelection
    of "farm", "berries":
      doAssert selected.kind == SourceSelection
    else:
      doAssert selected.kind == NoSelection
    if selected.kind != NoSelection:
      doAssert world.resolveSelection(selected) == selected
  doAssert world.scenerySelection(Scenery(prop: "town_hall",
    position: vec2(-3, -5))).id == "village"
  doAssert world.scenerySelection(Scenery(prop: "hut",
    position: vec2(9, -10))).id == "miller_hut"
  doAssert world.scenerySelection(Scenery(prop: "farm",
    position: vec2(10, -8))).id == "farm"
  doAssert world.scenerySelection(Scenery(prop: "town_hall",
    position: vec2(37, 17))).id == "reedbank"
  doAssert world.scenerySelection(Scenery(prop: "farm",
    position: vec2(52, 13))).id == "reedbank_farm"
  for prop in ["town_hall", "hut", "farm", "berries", "tree"]:
    doAssert world.scenerySelection(Scenery(prop: prop,
      position: vec2(60, -60))).kind == NoSelection

echo "Monster selections passed"

block wreckage:
  var world = newWorld(generateMap())
  let
    house = world.selectionById("miller_hut")
    hall = world.selectionById("village")
    source = world.selectionById("pine")
  doAssert not world.selectionDestroyed(house)
  doAssert not world.selectionDestroyed(hall)
  doAssert not world.selectionDestroyed(source)
  world.households[0].integrity = 0
  world.villages[0].health = 0
  world.sources[3].amount = 0
  doAssert not world.selectionDestroyed(source),
    "An empty source is not necessarily a destroyed source."
  world.sources[3].destroyed = true
  for selected in [house, hall, source]:
    doAssert world.selectionDestroyed(selected)
    doAssert world.resolveSelection(selected) == selected,
      "Wreckage keeps its identity for inspection after destruction."
