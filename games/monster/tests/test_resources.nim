import
  std/[json, os, tempfiles],
  jsony, vmath,
  ../[common, maps, resources, sim]

proc run(world: var World, seconds: int) =
  ## Advances the village while checking that everyone stays on the navmesh.
  for tick in 0 ..< seconds * TickRate:
    world.step()
    doAssert world.map.walkable(world.creature.position)
    for villager in world.villagers:
      doAssert world.map.walkable(villager.position), villager.name
      doAssert villager.hunger >= 0 and villager.hunger <= 100
      for amount in villager.cargo:
        doAssert amount >= 0

proc finish(world: var World) =
  ## Finishes one bounded creature plan without depending on NPC idleness.
  for tick in 0 ..< 120 * TickRate:
    world.step()
    doAssert world.map.walkable(world.creature.position)
    if not world.active and world.actions.len == 0:
      doAssert world.problems.len == 0, $world.problems
      return
  doAssert false, "Creature resource plan did not finish."

proc quietWorld(): World =
  ## Isolates creature transfers from autonomous consumption.
  result = newWorld(generateMap())
  result.villagers.setLen(0)

proc allUnits(world: World, kind: ResourceKind): int =
  ## Counts each physical location that can own a resource unit.
  result = world.stock[kind] + world.creature.cargo[kind]
  for source in world.sources:
    if source.resource == kind:
      result += source.amount
  for house in world.households:
    result += house.stock[kind]
  for villager in world.villagers:
    result += villager.cargo[kind]

echo "Testing resource varieties and physical deliveries"
block:
  var stock: Inventory
  stock[BerriesResource] = 2
  stock[GrainResource] = 1
  stock[FishResource] = 3
  stock[SoftwoodResource] = 4
  stock[HardwoodResource] = 5
  stock[StoneResource] = 6
  doAssert stock.total() == 21
  doAssert stock.foodTotal() == 6
  doAssert stock.eat()
  doAssert stock[BerriesResource] == 1
  doAssert stock[StoneResource] == 6
  var recipient: Inventory
  stock.transfer(recipient)
  doAssert stock.total() == 0
  doAssert recipient.total() == 20

for sourceId in SourceIds:
  var world = quietWorld()
  let
    source = world.sourceIndex(sourceId)
    kind = world.sources[source].resource
  doAssert source >= 0
  world.instruct(@[CreatureAction(kind: GatherAction, target: sourceId)])
  world.finish()
  doAssert world.creature.cargo[kind] == CarryLimit
  doAssert world.creature.cargo.total() == CarryLimit
  let before = world.stock[kind]
  world.instruct(@[CreatureAction(kind: GiveAction, target: "hall")])
  world.finish()
  doAssert world.stock[kind] == before + CarryLimit
  doAssert world.creature.cargo.total() == 0

block:
  var world = quietWorld()
  let
    destination = world.householdIndex("mason_hut")
    before = world.allUnits(StoneResource)
    stored = world.households[destination].stock[StoneResource]
  world.instruct(@[
    CreatureAction(kind: GatherAction, target: "stone"),
    CreatureAction(kind: GiveAction, target: "mason_hut")
  ])
  world.finish()
  doAssert world.households[destination].stock[StoneResource] ==
    stored + CarryLimit
  doAssert world.allUnits(StoneResource) == before
  doAssert world.creature.cargo.total() == 0

block:
  var world = quietWorld()
  world.creature.cargo[GrainResource] = 2
  world.instruct(@[CreatureAction(kind: GatherAction, target: "stone")])
  world.finish()
  doAssert world.creature.cargo[GrainResource] == 2
  doAssert world.creature.cargo[StoneResource] == 4
  doAssert world.creature.cargo.total() == CarryLimit
  world.instruct(@[CreatureAction(kind: EatAction)])
  world.finish()
  doAssert world.creature.cargo[GrainResource] == 1
  doAssert world.creature.cargo[StoneResource] == 4

block:
  var world = newWorld(generateMap())
  world.villagers.setLen(1)
  world.creature.cargo[StoneResource] = CarryLimit
  let
    start = world.villagers[0].position
    home = world.villagers[0].home
    stoneBefore = world.households[home].stock[StoneResource]
    totalBefore = world.allUnits(StoneResource)
  world.villagers[0].hunger = 80
  world.instruct(@[CreatureAction(kind: GiveAction, target: "ada")])
  var delivered = false
  for tick in 0 ..< 120 * TickRate:
    world.step()
    if world.creature.cargo.total() == 0:
      doAssert length(world.creature.position -
        world.villagers[0].position) <= 1.6'f,
        "A gift must reach the person's current position."
      delivered = true
      break
  doAssert delivered
  doAssert world.villagers[0].position != start,
    "The delivery test must exercise a moving recipient."
  doAssert world.allUnits(StoneResource) == totalBefore
  world.run(90)
  doAssert world.households[home].stock[StoneResource] >=
    stoneBefore + CarryLimit

block:
  var world = newWorld(generateMap())
  world.villagers.setLen(1)
  world.villagers[0].cargo[StoneResource] = 12
  world.villagers[0].retry = 1000
  world.creature.cargo[StoneResource] = CarryLimit
  world.instruct(@[CreatureAction(kind: GiveAction, target: "ada")])
  for tick in 0 ..< 120 * TickRate:
    world.step()
    if not world.active and world.actions.len == 0:
      break
  doAssert world.problems.len == 1
  doAssert world.creature.cargo[StoneResource] == CarryLimit
  doAssert world.villagers[0].cargo[StoneResource] == 12

block:
  var world = newWorld(generateMap())
  world.villagers.setLen(1)
  world.stock = default(Inventory)
  let home = world.villagers[0].home
  world.households[home].stock = default(Inventory)
  world.villagers[0].position =
    world.sources[world.sourceIndex("pine")].position
  world.villagers[0].hunger = 90
  world.villagers[0].cargo[StoneResource] = CarryLimit
  world.run(120)
  doAssert world.villagers[0].hunger < 90,
    "A hungry villager must put down building supplies to collect food."
  doAssert world.households[home].stock[StoneResource] == CarryLimit

echo "Testing autonomous villager needs and home maintenance"
block:
  var world = newWorld(generateMap())
  doAssert world.villagers.len == 6
  doAssert world.households.len == 3
  let
    hungry = world.villagers[0].hunger
    condition = world.households[2].integrity
  var walked: array[6, bool]
  for second in 0 ..< 600:
    var positions: array[6, Vec2]
    for i in 0 ..< world.villagers.len:
      positions[i] = world.villagers[i].position
    world.run(1)
    for i in 0 ..< world.villagers.len:
      if positions[i] != world.villagers[i].position:
        walked[i] = true
  for moving in walked:
    doAssert moving, "Every resident should take part in the village."
  doAssert world.villagers[0].hunger < hungry
  doAssert world.households[2].integrity > condition
  for house in world.households:
    doAssert house.fuel > 0
    doAssert house.stock.foodTotal() > 0
  doAssert world.problems.len == 0,
    "NPC shortages must not become failures of the player's creature."

block:
  var world = newWorld(generateMap())
  for house in world.households.mitems:
    house.stock[GrainResource] = 4
    house.fuel = 100
    house.integrity = 100
  for person in world.villagers.mitems:
    person.position = world.households[person.home].position
    person.hunger = 0
  world.run(5)
  for home in 0 ..< world.households.len:
    doAssert length(world.villagers[home * 2].position -
      world.villagers[home * 2 + 1].position) > 1,
      "Resting residents should walk to separate places by their home."

block:
  var world = newWorld(generateMap())
  for source in world.sources.mitems:
    source.amount = 0
    source.capacity = 0
  world.stock = default(Inventory)
  for house in world.households.mitems:
    house.stock = default(Inventory)
  for villager in world.villagers.mitems:
    villager.hunger = 90
    villager.cargo = default(Inventory)
  world.run(90)
  doAssert world.allUnits(BerriesResource) == 0
  doAssert world.allUnits(GrainResource) == 0
  doAssert world.allUnits(FishResource) == 0
  doAssert world.problems.len == 0
  for villager in world.villagers:
    doAssert villager.cargo.total() == 0
    doAssert not villager.moving

block:
  var world = newWorld(generateMap())
  world.stock = default(Inventory)
  for house in world.households.mitems:
    house.stock = default(Inventory)
  for source in world.sources:
    let cell = int(source.position.y + MapHalf) * MapSize +
      int(source.position.x + MapHalf)
    world.map.blocked[cell] = true
  var positions: seq[Vec2]
  for villager in world.villagers.mitems:
    villager.hunger = 90
    positions.add villager.position
  world.run(30)
  for i, villager in world.villagers:
    doAssert villager.position == positions[i]
    doAssert villager.cargo.total() == 0
    doAssert not villager.moving
  doAssert world.problems.len == 0

block:
  var world = quietWorld()
  let
    berries = world.sourceIndex("berries")
    stone = world.sourceIndex("stone")
  world.sources[berries].amount = 0
  world.sources[stone].amount = 0
  world.run(300)
  doAssert world.sources[berries].amount > 0
  doAssert world.sources[berries].amount <= world.sources[berries].capacity
  doAssert world.sources[stone].amount == 0

echo "Testing resource saves and old food migration"
block:
  let directory = createTempDir("monster-resources-", "")
  defer:
    removeDir(directory)
  let path = directory / "world.json"
  var world = newWorld(generateMap())
  world.run(20)
  world.creature.cargo[FishResource] = 2
  world.stock[HardwoodResource] = 7
  world.households[1].stock[StoneResource] = 9
  world.villagers[0].cargo[SoftwoodResource] = 1
  let villagersBefore = world.villagers.toJson()
  world.saveWorld(path)
  doAssert world.villagers.toJson() == villagersBefore,
    "Saving must not cancel or change live villager errands."
  var restored = newWorld(generateMap())
  restored.restoreWorld(path)
  doAssert restored.creature.cargo == world.creature.cargo
  doAssert restored.stock == world.stock
  for i in 0 ..< world.sources.len:
    doAssert restored.sources[i].amount == world.sources[i].amount
  for i in 0 ..< world.households.len:
    doAssert restored.households[i].stock == world.households[i].stock
    doAssert restored.households[i].integrity == world.households[i].integrity
    doAssert restored.households[i].fuel == world.households[i].fuel
  for i in 0 ..< world.villagers.len:
    doAssert restored.villagers[i].position == world.villagers[i].position
    doAssert restored.villagers[i].cargo == world.villagers[i].cargo
    doAssert restored.villagers[i].hunger == world.villagers[i].hunger
  restored.run(90)
  doAssert restored.problems.len == 0
  var invalid = parseJson(readFile(path))
  invalid["stock"].elems[0] = %(-1)
  writeFile(path, $invalid)
  let stockBefore = restored.stock
  var rejected = false
  try:
    restored.restoreWorld(path)
  except MonsterError:
    rejected = true
  doAssert rejected
  doAssert restored.stock == stockBefore

block:
  type
    LegacyCreature = object
      position: Vec2
      facing: float32
      moving: bool
      food: int
      energy: float32
    LegacyWorld = object
      version, seed: int
      creature: LegacyCreature
      villageFood, berryFood, farmFood: int
  let directory = createTempDir("monster-legacy-", "")
  defer:
    removeDir(directory)
  let path = directory / "world.json"
  var world = newWorld(generateMap())
  var legacy = LegacyWorld(
    version: 1,
    seed: world.map.seed,
    creature: LegacyCreature(
      position: world.creature.position, food: 4, energy: 73
    ),
    villageFood: 7,
    berryFood: 11,
    farmFood: 8
  )
  writeFile(path, legacy.toJson())
  world.restoreWorld(path)
  doAssert world.creature.cargo.foodTotal() == 4
  doAssert world.creature.energy == 73
  doAssert world.stock.foodTotal() == 7
  doAssert world.sources[world.sourceIndex("berries")].amount == 11
  doAssert world.sources[world.sourceIndex("farm")].amount == 8
  doAssert world.villagers.len == 6
  doAssert world.households.len == 3
  world.saveWorld(path)
  doAssert parseJson(readFile(path))["version"].getInt() == 2
  let oldPosition = vec2(-3, -5)
  doAssert not world.map.walkable(oldPosition)
  legacy.creature.position = oldPosition
  writeFile(path, legacy.toJson())
  world.restoreWorld(path)
  doAssert world.map.walkable(world.creature.position)
  doAssert abs(world.creature.position.x - oldPosition.x) <= 4
  doAssert abs(world.creature.position.y - oldPosition.y) <= 4
  doAssert world.creature.cargo.foodTotal() == 4
  for invalid in [vec2(100, 0), vec2(Inf.float32, 0),
    vec2(NaN.float32, 0)]:
      let before = world.creature.position
      legacy.creature.position = invalid
      writeFile(path, legacy.toJson())
      var rejected = false
      try:
        world.restoreWorld(path)
      except MonsterError:
        rejected = true
      doAssert rejected, "Invalid old coordinates must not teleport home."
      doAssert world.creature.position == before
  legacy.creature.position = oldPosition
  writeFile(path, legacy.toJson())
  for dz in -5 .. 5:
    for dx in -5 .. 5:
      let point = oldPosition + vec2(dx.float32, dz.float32)
      let cell = int(point.y + MapHalf) * MapSize + int(point.x + MapHalf)
      world.map.blocked[cell] = true
  var rejected = false
  try:
    world.restoreWorld(path)
  except MonsterError:
    rejected = true
  doAssert rejected, "An old creature must not relocate outside nearby ground."

echo "Monster resources and villagers passed"
