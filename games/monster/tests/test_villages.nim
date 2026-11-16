import
  std/[json, os, tempfiles],
  jsony, vmath,
  ../[common, maps, resources, sim]

proc run(world: var World, seconds: int) =
  ## Advances independent villages while checking their physical boundaries.
  for tick in 0 ..< seconds * TickRate:
    world.step()
    for person in world.villagers:
      doAssert world.map.walkable(person.position), person.name
      doAssert person.cargo.total() in 0 .. 12
      doAssert person.hunger >= 0 and person.hunger <= 100
    for village in world.villages:
      for amount in village.stock:
        doAssert amount >= 0
    for source in world.sources:
      doAssert source.amount in 0 .. source.capacity

proc finish(world: var World) =
  ## Completes a creature trip without waiting for autonomous villagers.
  for tick in 0 ..< 180 * TickRate:
    world.step()
    doAssert world.map.walkable(world.creature.position)
    if not world.active and world.actions.len == 0:
      doAssert world.problems.len == 0, $world.problems
      return
  doAssert false, "Creature did not finish the regional delivery."

proc units(world: World, kind: ResourceKind): int =
  ## Counts one resource across every source, carrier, home, and hall.
  result = world.creature.cargo[kind]
  for village in world.villages:
    result += village.stock[kind]
  for home in world.households:
    result += home.stock[kind]
  for person in world.villagers:
    result += person.cargo[kind]
  for source in world.sources:
    if source.resource == kind:
      result += source.amount

proc clearSupplies(world: var World) =
  ## Removes available supplies and regrowth for controlled shortage checks.
  for village in world.villages.mitems:
    village.stock = default(Inventory)
  for house in world.households.mitems:
    house.stock = default(Inventory)
  for source in world.sources.mitems:
    source.amount = 0
    source.capacity = 0

proc meetHomeNeeds(world: var World) =
  ## Leaves communal reserve gathering as the only immediate village job.
  for house in world.households.mitems:
    house.stock[GrainResource] = 8
    house.fuel = 100
    house.integrity = 100
  for person in world.villagers.mitems:
    person.hunger = 0
    person.cargo = default(Inventory)

echo "Testing separate villages and regional creature deliveries"
block:
  let world = newWorld(generateMap())
  doAssert MapSize == 128
  doAssert world.villages.len == 3
  doAssert world.households.len == 9
  doAssert world.villagers.len == 18
  doAssert world.villageIndex("hall") == world.villageIndex("village")
  for i, id in VillageIds:
    doAssert world.villages[i].id == id
    var residents = 0
    for person in world.villagers:
      if world.households[person.home].village == i:
        inc residents
    doAssert residents == 6

for target in ["bracken", "reedbank", "bracken_hut2", "reedbank_hut3"]:
  var world = newWorld(generateMap())
  world.villagers.setLen(0)
  let before = world.units(StoneResource)
  world.creature.cargo[StoneResource] = CarryLimit
  var stocks: seq[Inventory]
  for village in world.villages:
    stocks.add village.stock
  let house = world.householdIndex(target)
  let originalHome =
    if house >= 0: world.households[house].stock
    else: default(Inventory)
  world.instruct(@[CreatureAction(kind: GiveAction, target: target)])
  world.finish()
  doAssert world.creature.cargo.total() == 0
  doAssert world.units(StoneResource) == before + CarryLimit
  for i, village in world.villages:
    doAssert village.stock[StoneResource] == stocks[i][StoneResource] +
      (if i == world.villageIndex(target): CarryLimit else: 0)
  if house >= 0:
    doAssert world.households[house].stock[StoneResource] ==
      originalHome[StoneResource] + CarryLimit

block:
  var world = newWorld(generateMap())
  let target = world.villagerIndex("reedbank_ora")
  let home = world.villagers[target].home
  world.villagers = @[world.villagers[target]]
  world.villagers[0].retry = 1000
  world.creature.cargo[StoneResource] = CarryLimit
  world.instruct(@[CreatureAction(kind: GiveAction, target: "reedbank_ora")])
  world.finish()
  doAssert world.villagers[0].cargo[StoneResource] == CarryLimit
  doAssert world.creature.cargo.total() == 0
  doAssert length(world.creature.position -
    world.villagers[0].position) <= 1.6'f
  doAssert world.households[home].village == world.villageIndex("reedbank")

echo "Testing village ownership and competition for shared resources"
block:
  var world = newWorld(generateMap())
  world.villagers = @[world.villagers[0]]
  world.clearSupplies()
  let rival = world.villageIndex("bracken")
  world.villages[rival].stock[GrainResource] = 9
  let farm = world.sourceIndex("bracken_farm")
  world.sources[farm].amount = 7
  world.sources[farm].capacity = 7
  world.villagers[0].hunger = 90
  world.villagers[0].position = world.sources[farm].position
  world.run(20)
  doAssert world.villagers[0].cargo.total() == 0,
    "A hungry resident must not withdraw another village's hall or farm."
  doAssert world.villages[rival].stock[GrainResource] == 9
  doAssert world.sources[farm].amount == 7
  doAssert world.villagers[0].hunger > 90
  world.villages[0].stock[GrainResource] = 4
  world.run(100)
  doAssert world.villagers[0].hunger < 90,
    "The same resident should fetch food from their own hall."
  doAssert world.villages[rival].stock[GrainResource] == 9
  doAssert world.sources[farm].amount == 7

block:
  var world = newWorld(generateMap())
  let competitor = world.villagerIndex("bracken_iris")
  world.villagers = @[world.villagers[0], world.villagers[competitor]]
  world.clearSupplies()
  world.meetHomeNeeds()
  for village in world.villages.mitems:
    village.stock[GrainResource] = 20
    village.stock[SoftwoodResource] = 20
  let source = world.sourceIndex("stone")
  world.sources[source].amount = 3
  world.sources[source].capacity = 3
  for person in world.villagers.mitems:
    person.position = world.sources[source].position
  let before = world.units(StoneResource)
  world.run(8)
  doAssert world.sources[source].amount == 0
  doAssert world.units(StoneResource) == before,
    "Two villages must divide the actual stone, never duplicate it."
  doAssert world.villagers[0].cargo[StoneResource] > 0
  doAssert world.villagers[1].cargo[StoneResource] > 0
  doAssert world.villages[0].harvested > 0
  doAssert world.villages[world.villageIndex("bracken")].harvested > 0
  world.run(100)
  doAssert world.villages[0].stock[StoneResource] > 0
  doAssert world.villages[world.villageIndex("bracken")].stock[StoneResource] > 0
  doAssert world.units(StoneResource) == before
  doAssert world.events.len == 0,
    "Routine rival work must not fill the creature's conversation."

echo "Testing regional saves and version two migration"
block:
  let directory = createTempDir("monster-regions-", "")
  defer:
    removeDir(directory)
  let path = directory / "world.json"
  var world = newWorld(generateMap())
  world.run(10)
  world.villages[1].stock[StoneResource] = 13
  world.villages[2].stock[HardwoodResource] = 7
  world.villages[1].harvested = 41
  world.villages[2].gifts = 12
  let before = world.toJson()
  world.saveWorld(path)
  doAssert world.toJson() == before
  doAssert parseJson(readFile(path))["version"].getInt() == 8
  var restored = newWorld(generateMap())
  restored.restoreWorld(path)
  doAssert restored.villages == world.villages
  for i, house in world.households:
    doAssert restored.households[i].stock == house.stock
    doAssert restored.households[i].village == house.village
  for i, person in world.villagers:
    doAssert restored.villagers[i].position == person.position
    doAssert restored.villagers[i].cargo == person.cargo

block:
  let directory = createTempDir("monster-v2-regions-", "")
  defer:
    removeDir(directory)
  let path = directory / "world.json"
  var old = newWorld(generateMap())
  old.creature.cargo[FishResource] = 3
  old.creature.energy = 68
  old.villages[0].stock[HardwoodResource] = 7
  old.households[1].stock[StoneResource] = 9
  old.households[2].integrity = 80
  old.households[0].fuel = 63
  old.villagers[0].cargo[GrainResource] = 1
  old.villagers[0].hunger = 23
  old.sources[old.sourceIndex("berries")].amount = 8
  let legacy = %*{
    "version": 2,
    "seed": old.map.seed,
    "creature": parseJson(old.creature.toJson()),
    "stock": parseJson(old.villages[0].stock.toJson()),
    "sources": parseJson(old.sources[0 .. 5].toJson()),
    "households": parseJson(old.households[0 .. 2].toJson()),
    "villagers": parseJson(old.villagers[0 .. 5].toJson())
  }
  for source in legacy["sources"]:
    source.delete("owner")
    if source["id"].getStr() == "fish":
      source["position"] = parseJson(vec2(15, -6).toJson())
  for house in legacy["households"]:
    house.delete("village")
  for person in legacy["villagers"]:
    person.delete("supplyingHall")
  writeFile(path, $legacy)
  var world = newWorld(generateMap())
  world.restoreWorld(path)
  doAssert world.creature.cargo == old.creature.cargo
  doAssert world.creature.energy == 68
  doAssert world.villages[0].stock == old.villages[0].stock
  doAssert world.sources[world.sourceIndex("berries")].amount == 8
  for i in 0 ..< 3:
    doAssert world.households[i].stock == old.households[i].stock
    doAssert world.households[i].integrity == old.households[i].integrity
    doAssert world.households[i].fuel == old.households[i].fuel
  for i in 0 ..< 6:
    doAssert world.villagers[i].cargo == old.villagers[i].cargo
    doAssert world.villagers[i].hunger == old.villagers[i].hunger
  doAssert world.villages.len == 3
  doAssert world.households.len == 9
  doAssert world.villagers.len == 18
  world.saveWorld(path)
  doAssert parseJson(readFile(path))["version"].getInt() == 8
  world.run(30)
  doAssert world.problems.len == 0

echo "Testing widened river save migration"
block:
  let directory = createTempDir("monster-river-migration-", "")
  defer:
    removeDir(directory)
  let path = directory / "world.json"
  var world = newWorld(generateMap())
  world.creature.cargo[FishResource] = 3
  world.creature.energy = 68
  world.villages[1].stock[StoneResource] = 13
  world.villages[0].alarm = 12
  world.households[1].stock[HardwoodResource] = 9
  world.households[2].integrity = 80
  world.villagers[0].cargo[FishResource] = 2
  world.villagers[0].hunger = 23
  world.villagers[0].health = 65
  world.villagers[0].fear = 9
  world.sources[world.sourceIndex("fish")].amount = 7
  world.sources[world.sourceIndex("south_fish")].amount = 11
  world.saveWorld(path)
  let old = parseJson(readFile(path))
  old["version"] = %4
  old["creature"]["position"] = parseJson(vec2(15, -6).toJson())
  old["villagers"][0]["position"] = parseJson(vec2(22, 30).toJson())
  old["villagers"][1]["position"] = parseJson(vec2(9, -8).toJson())
  for source in old["sources"]:
    if source["id"].getStr() == "fish":
      source["position"] = parseJson(vec2(15, -6).toJson())
    elif source["id"].getStr() == "south_fish":
      source["position"] = parseJson(vec2(22, 30).toJson())
  writeFile(path, $old)
  var restored = newWorld(generateMap())
  restored.restoreWorld(path)
  doAssert restored.map.walkable(restored.creature.position)
  doAssert restored.creature.position != vec2(15, -6)
  doAssert length(restored.creature.position - vec2(15, -6)) <= 5
  doAssert restored.creature.cargo == world.creature.cargo
  doAssert restored.creature.energy == world.creature.energy
  doAssert restored.villages == world.villages
  doAssert restored.households == world.households
  doAssert restored.sources == world.sources,
    "Moving fishing banks must preserve their remaining resource amounts."
  for i, original in [vec2(22, 30), vec2(9, -8)]:
    doAssert restored.map.walkable(restored.villagers[i].position)
    doAssert restored.villagers[i].position != original
    doAssert length(restored.villagers[i].position - original) <= 5
  doAssert restored.villagers[0].cargo == world.villagers[0].cargo
  doAssert restored.villagers[0].hunger == world.villagers[0].hunger
  doAssert restored.villagers[0].health == 65
  doAssert restored.villagers[0].fear == 9
  restored.saveWorld(path)
  doAssert parseJson(readFile(path))["version"].getInt() == 8
  var reloaded = newWorld(generateMap())
  reloaded.restoreWorld(path)
  doAssert reloaded.creature.position == restored.creature.position
  doAssert reloaded.sources == restored.sources

  let before = restored.toJson()
  for position in [vec2(100, 0), vec2(Inf.float32, 0), vec2(NaN.float32, 0)]:
      let broken = parseJson($old)
      broken["creature"]["position"] = %[position.x, position.y]
      writeFile(path, $broken)
      var rejected = false
      try:
        restored.restoreWorld(path)
      except MonsterError:
        rejected = true
      doAssert rejected, "Invalid old coordinates must not relocate: " & $position
      doAssert restored.toJson() == before
  for corruption in ["source", "combat", "version"]:
    let broken = parseJson($old)
    case corruption
    of "source":
      broken["sources"][world.sourceIndex("fish")]["position"] =
        parseJson(vec2(0, 0).toJson())
    of "combat":
      broken["villagers"][0].delete("health")
    else:
      broken["version"] = %5
    writeFile(path, $broken)
    var rejected = false
    try:
      restored.restoreWorld(path)
    except MonsterError:
      rejected = true
    doAssert rejected,
      "River migration must preserve strict save validation: " & corruption
    doAssert restored.toJson() == before

echo "Monster rival villages passed"
