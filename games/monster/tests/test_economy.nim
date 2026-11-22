import
  std/[os, strutils, tempfiles],
  polyworld/daycycles,
  ../[common, maps, resources, sim]

const
  Days = 12
  WarmupDays = 2
  FoodKinds = {BerriesResource, GrainResource, FishResource}
  WorkingTasks = {GatherTask, WithdrawTask, DeliverTask, RefuelTask, RepairTask}
  LeisureTasks = {ChoreTask, WanderTask, ChatTask}

type
  Economy = object
    meals, residents, samples, urgent, work, leisure, cold: int
    minFood, maxFood, earlyFood, lateFood: int
    maxHunger: float32

proc advance(world: var World, seconds: int) =
  ## Advances physical village routines for a bounded number of seconds.
  for tick in 0 ..< seconds * TickRate:
    world.step()

proc suppliedWorld(): World =
  ## Supplies homes and halls so each test can expose one specific shortage.
  result = newWorld(generateMap())
  for house in result.households.mitems:
    house.stock = default(Inventory)
    house.stock[GrainResource] = HouseholdFoodReserve
    house.integrity = 100
    house.fuel = 100
  for village in result.villages.mitems:
    for kind in ResourceKind:
      village.stock[kind] = VillageWorkReserves[kind.ord]
  for person in result.villagers.mitems:
    person.hunger = 0
    person.sleepiness = 0
    person.retry = 10000

proc householdTrips(world: World, home: int): int =
  ## Counts residents replenishing this home's food rather than the hall.
  for person in world.villagers:
    if person.home == home and not person.supplyingHall and
      person.task in {GatherTask, WithdrawTask} and
      person.resource in FoodKinds:
        inc result

echo "Testing incoming household food prevents duplicate errands"
block:
  var world = suppliedWorld()
  let home = world.villagers[0].home
  world.households[home].stock[GrainResource] =
    HouseholdFoodReserve - VillagerCarryLimit
  world.villagers[0].retry = 0
  world.villagers[1].retry = 0
  world.step()
  doAssert world.householdTrips(home) == 1,
    "One household shortage must not send both residents for the same food."

block:
  var world = suppliedWorld()
  let home = world.villagers[0].home
  world.households[home].stock[GrainResource] =
    HouseholdFoodReserve - VillagerCarryLimit
  world.villagers[0].cargo[GrainResource] = VillagerCarryLimit
  world.villagers[1].retry = 0
  world.step()
  doAssert world.householdTrips(home) == 0,
    "Food already carried home must count toward the household reserve."

echo "Testing food shortages override a preferred material job"
block:
  var world = suppliedWorld()
  let
    worker = 2
    home = world.villagers[worker].home
    village = world.households[home].village
  world.villages[village].stock = default(Inventory)
  for house in world.households.mitems:
    if house.village == village:
      house.stock = default(Inventory)
  world.households[home].stock[GrainResource] = HouseholdFoodReserve
  world.villagers[worker].retry = 0
  world.step()
  doAssert world.villagers[worker].task == GatherTask
  doAssert world.villagers[worker].supplyingHall
  doAssert world.villagers[worker].resource in FoodKinds,
    "A village with less than one meal each must gather food before wood."

echo "Testing Reedbank uses nearby oak for its communal wood reserve"
block:
  var world = suppliedWorld()
  let
    worker = world.villagerIndex("reedbank_rosa")
    home = world.villagers[worker].home
    village = world.households[home].village
  world.villages[village].stock[SoftwoodResource] = 0
  world.villages[village].stock[HardwoodResource] = 0
  world.villagers[worker].position = world.villages[village].position
  world.villagers[worker].retry = 0
  world.step()
  doAssert world.villagers[worker].task == GatherTask
  doAssert world.villagers[worker].supplyingHall
  doAssert world.villagers[worker].resource == HardwoodResource
  doAssert world.villagers[worker].target == "south_oak",
    "A pine preference must not force a cross-map trip past nearby oak."

echo "Testing tired villagers finish fetching supper before going to bed"
for supper in [WithdrawTask, GatherTask]:
  var world = suppliedWorld()
  world.villagers.setLen(1)
  world.tick = HudDaySeconds * TickRate.int32 * 10 div 24
  let
    home = world.villagers[0].home
    village = world.households[home].village
  world.households[home].stock = default(Inventory)
  for hall in world.villages.mitems:
    hall.stock = default(Inventory)
  if supper == WithdrawTask:
    world.villages[village].stock[GrainResource] = VillagerCarryLimit
  world.villagers[0].hunger = MealRelief
  world.villagers[0].sleepiness = NightSleepThreshold + 10
  world.villagers[0].retry = 0
  var fetched, ate, slept: bool
  for tick in 0 ..< 45 * TickRate:
    world.step()
    let person = world.villagers[0]
    fetched = fetched or person.task == supper
    ate = ate or person.hunger < BedtimeHunger
    if person.sleeping:
      doAssert ate, "A hungry villager went to bed without fetching supper."
      slept = true
      break
  doAssert fetched and ate and slept,
    "Sleep priority must not restart the food errand before it can finish."

echo "Testing slower regrowth survives saves without renewing finite sources"
block:
  let directory = createTempDir("monster-economy-", "")
  defer:
    removeDir(directory)
  let path = directory / "world.json"
  for elapsed in [60'f, 75'f, 89'f]:
    var world = newWorld(generateMap())
    let
      oak = world.sourceIndex("oak")
      pine = world.sourceIndex("pine")
      berries = world.sourceIndex("berries")
      stone = world.sourceIndex("stone")
    world.sources[oak].amount = world.sources[oak].capacity - 1
    world.sources[oak].elapsed = elapsed
    world.sources[pine].amount = world.sources[pine].capacity - 1
    world.sources[pine].elapsed = 59
    world.sources[berries].amount = 0
    world.sources[berries].destroyed = true
    world.sources[stone].amount = 3
    world.saveWorld(path)
    var restored = newWorld(generateMap())
    restored.restoreWorld(path)
    doAssert restored.sources[oak].elapsed == elapsed
    doAssert restored.sources[pine].elapsed == 59
    doAssert restored.sources[berries].destroyed
    restored.villagers.setLen(0)
    restored.advance(31)
    doAssert restored.sources[oak].amount == restored.sources[oak].capacity
    doAssert restored.sources[pine].amount == restored.sources[pine].capacity
    doAssert restored.sources[berries].amount == 0,
      "Destroyed food sources must stay destroyed after loading."
    doAssert restored.sources[stone].amount == 3,
      "Slower renewable production must not make quarry stone renewable."

echo "Testing twelve-day village economies across different map seeds"
for seed in [42, 7, 123]:
  var
    world = newWorld(generateMap(seed))
    metrics = newSeq[Economy](world.villages.len)
    previousHunger = newSeq[float32](world.villagers.len)
  for i, person in world.villagers:
    inc metrics[world.households[person.home].village].residents
    previousHunger[i] = person.hunger
  for metric in metrics.mitems:
    metric.minFood = high(int)
  for tick in 0 ..< Days * HudDaySeconds.int * TickRate:
    world.step()
    let measuring = tick >= WarmupDays * HudDaySeconds.int * TickRate
    for i, person in world.villagers:
      let village = world.households[person.home].village
      if measuring and person.hunger < previousHunger[i]:
        inc metrics[village].meals
      previousHunger[i] = person.hunger
    if not measuring or tick mod TickRate != 0:
      continue
    for person in world.villagers:
      let village = world.households[person.home].village
      inc metrics[village].samples
      metrics[village].maxHunger = max(metrics[village].maxHunger,
        person.hunger)
      if person.hunger >= UrgentHunger:
        inc metrics[village].urgent
      if person.task in WorkingTasks:
        inc metrics[village].work
      if person.task in LeisureTasks:
        inc metrics[village].leisure
      doAssert person.cargo.total() in 0 .. VillagerCarryLimit
    for house in world.households:
      if house.fuel <= 0:
        inc metrics[house.village].cold
    for village in 0 ..< world.villages.len:
      let food = world.villageSupplies(village).foodTotal()
      metrics[village].minFood = min(metrics[village].minFood, food)
      metrics[village].maxFood = max(metrics[village].maxFood, food)
      let day = tick div (HudDaySeconds.int * TickRate)
      if day in 2 .. 4:
        metrics[village].earlyFood += food
      if day in 9 .. 11:
        metrics[village].lateFood += food
    for source in world.sources:
      doAssert source.amount in 0 .. source.capacity
    doAssert world.problems.len == 0
  for village, metric in metrics:
    let
      label = "Seed " & $seed & " " & world.villages[village].name
      mealsPerDay = metric.meals.float32 /
        ((Days - WarmupDays) * metric.residents).float32
      work = metric.work.float32 / metric.samples.float32
      leisure = metric.leisure.float32 / metric.samples.float32
    echo label, ": meals/person/day=", mealsPerDay.formatFloat(ffDecimal, 2),
      ", food=", metric.minFood, "..", metric.maxFood,
      ", max hunger=", metric.maxHunger.formatFloat(ffDecimal, 1),
      ", work=", (work * 100).formatFloat(ffDecimal, 1), "%",
      ", leisure=", (leisure * 100).formatFloat(ffDecimal, 1), "%"
    doAssert metric.maxHunger < 100, label & " ran out of meals."
    doAssert metric.urgent * 100 < metric.samples,
      label & " spends too much time urgently hungry."
    doAssert metric.cold == 0, label & " cannot keep its homes heated."
    doAssert metric.minFood >= metric.residents,
      label & " cannot maintain even one meal per resident."
    doAssert metric.maxFood <= metric.residents * 8,
      label & " stockpiles food instead of taking breaks."
    doAssert metric.lateFood * 4 >= metric.earlyFood * 3,
      label & " food reserves keep declining after the initial workdays."
    doAssert mealsPerDay >= 1.5'f and mealsPerDay <= 3'f,
      label & " does not sustain a reasonable daily meal rate."
    doAssert work > 0.05'f and leisure > 0.05'f,
      label & " needs both productive work and time for village life."

echo "Monster village economy passed"
