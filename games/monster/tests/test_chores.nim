import
  std/[math, os, tempfiles],
  vmath,
  ../[common, maps, resources, sim]

proc fixture(): World =
  ## Keeps useful work close enough to observe complete trips before night.
  result = newWorld(MonsterMap(
    seed: 42,
    blocked: newSeq[bool](MapSize * MapSize),
    landmarks: @[
      Landmark(id: "home", position: vec2(-40.5'f, -40.5'f)),
      Landmark(id: "village", position: vec2(0.5'f, 0.5'f)),
      Landmark(id: "miller_hut", position: vec2(0.5'f, 5.5'f)),
      Landmark(id: "weaver_hut", position: vec2(5.5'f, 5.5'f)),
      Landmark(id: "mason_hut", position: vec2(-5.5'f, 5.5'f)),
      Landmark(id: "berries", position: vec2(-8.5'f, 0.5'f)),
      Landmark(id: "farm", position: vec2(-3.5'f, -4.5'f)),
      Landmark(id: "fish", position: vec2(3.5'f, -1.5'f)),
      Landmark(id: "pine", position: vec2(4.5'f, 2.5'f)),
      Landmark(id: "oak", position: vec2(-4.5'f, 2.5'f)),
      Landmark(id: "stone", position: vec2(0.5'f, -4.5'f))
    ]
  ))
  for house in result.households.mitems:
    house.stock[GrainResource] = 8
    house.fuel = 100
    house.integrity = 100
  for kind in ResourceKind:
    result.villages[0].stock[kind] = VillageWorkReserves[kind.ord]
  for person in result.villagers.mitems:
    person.hunger = 0
    person.sleepiness = 0

proc advance(world: var World) =
  ## Steps real movement while checking inventory and navigation bounds.
  world.step()
  for person in world.villagers:
    doAssert world.map.walkable(person.position), person.name
    doAssert person.cargo.total() in 0 .. VillagerCarryLimit
  for source in world.sources:
    doAssert source.amount in 0 .. source.capacity
  doAssert world.problems.len == 0

proc units(world: World): Inventory =
  ## Counts all existing supplies to catch invented output from leisure.
  result = world.creature.cargo
  for source in world.sources:
    result[source.resource] += source.amount
  for village in world.villages:
    for kind in ResourceKind:
      result[kind] += village.stock[kind]
  for house in world.households:
    for kind in ResourceKind:
      result[kind] += house.stock[kind]
  for person in world.villagers:
    for kind in ResourceKind:
      result[kind] += person.cargo[kind]

proc awaitGathering(world: var World, kind: ResourceKind) =
  ## Waits until a lone worker has physically begun the requested job.
  for tick in 0 ..< 30 * TickRate:
    world.advance()
    let person = world.villagers[0]
    if person.task == GatherTask and person.resource == kind and
      not person.moving and person.elapsed > 0.5'f:
        return
  doAssert false, "The resident never began gathering " & kind.resourceName()

echo "Testing slow harvest, fishing, woodcutting, mining, and deliveries"
for kind in ResourceKind:
  var world = fixture()
  world.villagers.setLen(1)
  let
    source = world.sourceIndex(SourceIds[kind.ord])
    available = world.sources[source].amount
    reserved = world.villages[0].stock[kind] - VillagerCarryLimit
  world.villages[0].stock[kind] = reserved
  world.villagers[0].position = world.sources[source].position
  var
    worked = false
    pickedUp = false
    elapsed = 0
  for tick in 0 ..< 20 * TickRate:
    world.advance()
    inc elapsed
    let person = world.villagers[0]
    worked = worked or (person.task == GatherTask and
      person.resource == kind and not person.moving)
    doAssert world.villages[0].stock[kind] == reserved,
      "Gathered supplies must travel with a carrier before reaching storage."
    if person.cargo[kind] > 0:
      pickedUp = true
      doAssert person.cargo[kind] == VillagerCarryLimit
      doAssert world.sources[source].amount == available - VillagerCarryLimit
      doAssert elapsed >= 4 * TickRate,
        "Resource work should take time instead of creating cargo on arrival."
      break
    doAssert world.sources[source].amount == available,
      "A resident must finish the work before taking the resource."
  doAssert worked and pickedUp, kind.resourceName()
  var carried, delivered: bool
  for tick in 0 ..< 20 * TickRate:
    world.advance()
    let person = world.villagers[0]
    carried = carried or (person.moving and person.cargo[kind] > 0)
    if person.cargo[kind] == 0:
      doAssert world.villages[0].stock[kind] == reserved + VillagerCarryLimit
      doAssert length(person.position - world.villages[0].position) < 1.1'f,
        "Supplies must be deposited at the actual hall."
      delivered = true
      break
  doAssert carried and delivered, kind.resourceName()

echo "Testing varied work and shared source claims"
block:
  var world = fixture()
  for kind in ResourceKind:
    world.villages[0].stock[kind] = 0
  for person in world.villagers.mitems:
    person.position = world.villages[0].position
  world.advance()
  var assigned: set[ResourceKind]
  for person in world.villagers:
    if person.task == GatherTask:
      assigned.incl person.resource
  doAssert assigned * {BerriesResource, GrainResource, FishResource} != {} and
    assigned * {SoftwoodResource, HardwoodResource} != {} and
    StoneResource in assigned,
    "A village should spread its workers across food, wood, and stone jobs."

block:
  var world = fixture()
  let stone = world.sourceIndex("stone")
  world.sources[stone].amount = 3
  world.sources[stone].capacity = 3
  world.villages[0].stock[StoneResource] = 0
  for person in world.villagers.mitems:
    person.position = world.sources[stone].position
  let before = world.units()
  world.advance()
  var gatherers = 0
  for person in world.villagers:
    if person.task == GatherTask and person.target == "stone":
      inc gatherers
  doAssert gatherers in 1 .. 2,
    "A three-unit deposit should not attract six two-unit carriers."
  for tick in 0 ..< 25 * TickRate:
    world.advance()
  doAssert world.sources[stone].amount == 0
  doAssert world.villages[0].stock[StoneResource] == 3
  doAssert world.units() == before,
    "Competing workers must split finite deposits without duplicating them."

block:
  var world = fixture()
  world.villages[0].stock[StoneResource] -= VillagerCarryLimit
  world.advance()
  var gatherers = 0
  for person in world.villagers:
    if person.task == GatherTask and person.resource == StoneResource:
      inc gatherers
  doAssert gatherers == 1,
    "One two-unit shortage should reserve only one gathering trip."

echo "Testing depleted, destroyed, and unreachable worksite fallback"
for unavailable in 0 .. 2:
  var world = fixture()
  world.villagers.setLen(1)
  world.villages[0].stock[GrainResource] = 0
  world.villages[0].stock[FishResource] = 0
  let farm = world.sourceIndex("farm")
  case unavailable
  of 0:
    world.sources[farm].amount = 0
    world.sources[farm].capacity = 0
  of 1:
    world.sources[farm].destroyed = true
  else:
    let
      point = world.sources[farm].position + vec2(MapHalf)
      x = floor(point.x).int
      z = floor(point.y).int
    for dz in -1 .. 1:
      for dx in -1 .. 1:
        if dx != 0 or dz != 0:
          world.map.blocked[(z + dz) * MapSize + x + dx] = true
  world.advance()
  doAssert world.villagers[0].task == GatherTask
  doAssert world.villagers[0].resource == FishResource,
    "An unavailable preferred site must not prevent another useful job."

block:
  var world = fixture()
  world.villagers.setLen(1)
  let stone = world.sourceIndex("stone")
  world.households[0].integrity = 40
  world.sources[stone].amount = 0
  world.sources[stone].capacity = 0
  world.villages[0].stock[StoneResource] = 0
  world.villages[0].stock[FishResource] = 0
  world.advance()
  doAssert world.villagers[0].task == GatherTask
  doAssert world.villagers[0].resource in
    {BerriesResource, GrainResource, FishResource},
    "A home waiting on exhausted stone must not trap its resident in idleness."

echo "Testing maintenance, strolling, and real neighbor conversations"
block:
  var world = fixture()
  world.tick = 36 * TickRate
  for i, person in world.villagers.mpairs:
    if i notin [0, 3]:
      person.health = 0
  world.villagers[0].position = vec2(0.5'f, 0.5'f)
  world.villagers[3].position = vec2(4.5'f, 0.5'f)
  var met = false
  for tick in 0 ..< 10 * TickRate:
    world.advance()
    let
      first = world.villagers[0]
      second = world.villagers[3]
    if first.task == ChatTask and second.task == ChatTask and
      not first.moving and not second.moving:
        doAssert first.target == second.id and second.target == first.id
        doAssert length(first.position - second.position) >= 1,
          "Neighbors should face each other without overlapping their bodies."
        met = true
        break
  doAssert met, "Available nearby neighbors should meet for their conversation."

block:
  var world = fixture()
  let before = world.units()
  var
    observed: set[VillagerTask]
    walked = newSeq[bool](world.villagers.len)
    chatted = false
  for tick in 0 ..< 60 * TickRate:
    world.advance()
    for i, person in world.villagers:
      observed.incl person.task
      walked[i] = walked[i] or person.moving
      if person.task == ChatTask:
        let neighbor = world.villagerIndex(person.target)
        doAssert neighbor >= 0 and neighbor != i,
          "Conversation must name another real resident."
        let other = world.villagers[neighbor]
        doAssert world.households[person.home].village ==
          world.households[other.home].village
        if not person.moving:
          doAssert length(person.position - other.position) < 3,
            "Villagers must stand near one another to chat."
          chatted = true
    doAssert world.units() == before,
      "Maintenance, strolling, and conversation must not invent supplies."
  doAssert {ChoreTask, WanderTask, ChatTask} <= observed,
    "A supplied village should still maintain homes, stroll, and socialize."
  doAssert chatted
  for moved in walked:
    doAssert moved, "Every rested resident should take part in village life."
  doAssert world.events.len == 0,
    "Ordinary village life should not flood Moss's conversation."

echo "Testing needs and fear interrupt work without losing supplies"
for interruption in 0 .. 2:
  var world = fixture()
  world.villagers.setLen(1)
  world.villages[0].stock[StoneResource] = 0
  world.awaitGathering(StoneResource)
  let before = world.units()
  case interruption
  of 0:
    world.villagers[0].hunger = 90
  of 1:
    world.villagers[0].sleepiness = 95
  else:
    world.villagers[0].fear = FrightDuration
  world.advance()
  let expected = case interruption
    of 0: EatTask
    of 1: SleepTask
    else: FleeTask
  doAssert world.villagers[0].task == expected,
    "A current chore must yield to urgent needs and danger."
  doAssert world.units() == before,
    "Interrupting unfinished work must neither grant nor discard supplies."

block:
  var world = fixture()
  world.villagers.setLen(1)
  world.villagers[0].cargo[StoneResource] = VillagerCarryLimit
  world.villagers[0].supplyingHall = true
  world.villagers[0].position = world.sources[world.sourceIndex("stone")].position
  world.advance()
  doAssert world.villagers[0].task == DeliverTask
  let before = world.units()
  world.villagers[0].fear = FrightDuration
  world.advance()
  doAssert world.villagers[0].task == FleeTask
  doAssert world.villagers[0].cargo[StoneResource] == VillagerCarryLimit
  doAssert world.units() == before

echo "Testing saved carriers and social routines resume physical work"
block:
  var world = fixture()
  world.villages[0].stock[StoneResource] = 0
  for i, person in world.villagers.mpairs:
    if i > 0:
      person.retry = 10000
  var pickedUp = false
  for tick in 0 ..< 30 * TickRate:
    world.advance()
    if world.villagers[0].cargo[StoneResource] > 0:
      pickedUp = true
      break
  doAssert pickedUp
  let
    directory = createTempDir("monster-chores-", "")
    saved = directory / "carrier.json"
    before = world.units()
  defer:
    removeDir(directory)
  world.saveWorld(saved)
  var restored = fixture()
  restored.restoreWorld(saved)
  doAssert restored.units() == before
  doAssert restored.villagers[0].cargo == world.villagers[0].cargo
  doAssert restored.villagers[0].task == IdleTask
  restored.advance()
  doAssert restored.villagers[0].task == DeliverTask
  var delivered = false
  for tick in 0 ..< 20 * TickRate:
    restored.advance()
    if restored.villagers[0].cargo.total() == 0:
      delivered = true
      break
  doAssert delivered
  doAssert restored.villages[0].stock[StoneResource] >= VillagerCarryLimit
  doAssert restored.units()[StoneResource] == before[StoneResource]

block:
  var world = fixture()
  world.tick = 36 * TickRate
  for i, person in world.villagers.mpairs:
    if i notin [0, 3]:
      person.health = 0
  world.advance()
  doAssert world.villagers[0].task == ChatTask
  doAssert world.villagers[3].task == ChatTask
  let
    directory = createTempDir("monster-social-", "")
    saved = directory / "neighbors.json"
    before = world.units()
  defer:
    removeDir(directory)
  world.saveWorld(saved)
  var restored = fixture()
  restored.restoreWorld(saved)
  doAssert world.villagers[0].task == ChatTask,
    "Saving must not interrupt the running world's conversation."
  doAssert restored.villagers[0].task == IdleTask
  doAssert restored.villagers[0].path.len == 0
  var resumed = false
  for tick in 0 ..< 30 * TickRate:
    restored.advance()
    resumed = resumed or restored.villagers[0].task in
      {ChoreTask, WanderTask, ChatTask}
  doAssert resumed
  doAssert restored.units() == before

echo "Testing a fresh village works and socializes over two days"
block:
  var world = newWorld(generateMap())
  var
    jobs: set[ResourceKind]
    leisure: set[VillagerTask]
    firstChat = -1
  for tick in 0 ..< 600 * TickRate:
    world.advance()
    for person in world.villagers:
      if person.moving:
        continue
      if person.task == GatherTask and person.elapsed > 0:
        jobs.incl person.resource
      if person.task in {ChoreTask, WanderTask, ChatTask} and
        person.elapsed > 0:
          leisure.incl person.task
          if person.task == ChatTask and firstChat < 0:
            firstChat = tick div TickRate
  echo "Fresh village first conversation after ", firstChat, " seconds"
  doAssert jobs == {BerriesResource .. StoneResource},
    "A fresh village should do each kind of resource work without setup."
  doAssert leisure == {ChoreTask, WanderTask, ChatTask},
    "Fresh residents should make time for chores, walks, and conversation."

echo "Monster villager chores passed"
