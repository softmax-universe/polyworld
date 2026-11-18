import
  std/[os, strutils],
  polyworld/daycycles,
  ../[common, maps, resources, sim]

type
  EconomySample = object
    meals: int
    gathered: Inventory
    gathering, travelling: array[ResourceKind, int]
    tasks: array[VillagerTask, int]
    samples, urgent, starving, emptyHearths: int
    hungerPeak, fuelLow, healthLow: float32

proc percent(amount, count: int): string =
  ## Formats a share of resident simulation time.
  formatFloat(100 * amount.float / max(1, count).float, ffDecimal, 1)

proc measure(seed, days: int, emptyFood: bool) =
  ## Runs an untouched village economy without rendering or external services.
  var
    world = newWorld(generateMap(seed))
    totals = newSeq[EconomySample](world.villages.len)
    sourceHarvest, regrown: Inventory
    previousHunger = newSeq[float32](world.villagers.len)
    previousCargo = newSeq[Inventory](world.villagers.len)
    previousTask = newSeq[VillagerTask](world.villagers.len)
    previousResource = newSeq[ResourceKind](world.villagers.len)
    previousSource = newSeq[int](world.villagers.len)
    previousAmounts = newSeq[int](world.sources.len)
    previousElapsed = newSeq[float32](world.sources.len)
  if emptyFood:
    for kind in BerriesResource .. FishResource:
      world.creature.cargo[kind] = 0
      for village in world.villages.mitems:
        village.stock[kind] = 0
      for house in world.households.mitems:
        house.stock[kind] = 0
      for person in world.villagers.mitems:
        person.cargo[kind] = 0
    for source in world.sources.mitems:
      if source.resource in {BerriesResource, GrainResource, FishResource}:
        source.amount = 0
  for sample in totals.mitems:
    sample.fuelLow = 100
    sample.healthLow = 100
  echo "seed=", seed, " emptyFood=", emptyFood,
    " day | village: meals foodStock hungerPeak fuelLow"
  for day in 1 .. days:
    var daily = newSeq[EconomySample](world.villages.len)
    for sample in daily.mitems:
      sample.fuelLow = 100
      sample.healthLow = 100
    for tick in 0 ..< HudDaySeconds.int * TickRate:
      for i, person in world.villagers:
        previousHunger[i] = person.hunger
        previousCargo[i] = person.cargo
        previousTask[i] = person.task
        previousResource[i] = person.resource
        previousSource[i] = world.sourceIndex(person.target)
      for i, source in world.sources:
        previousAmounts[i] = source.amount
        previousElapsed[i] = source.elapsed
      world.step()
      for i, source in world.sources:
        let regrew = source.resource != StoneResource and
          previousAmounts[i] < source.capacity and
          source.elapsed < previousElapsed[i]
        sourceHarvest[source.resource] +=
          previousAmounts[i] + ord(regrew) - source.amount
        regrown[source.resource] += ord(regrew)
      for i, person in world.villagers:
        let
          village = world.households[person.home].village
          meal = previousHunger[i] - person.hunger > 1
        for sample in [daily[village].addr, totals[village].addr]:
          inc sample[].samples
          inc sample[].tasks[person.task]
          if person.task == GatherTask:
            inc sample[].gathering[person.resource]
            if person.moving:
              inc sample[].travelling[person.resource]
          sample[].hungerPeak = max(sample[].hungerPeak, person.hunger)
          sample[].healthLow = min(sample[].healthLow, person.health)
          if person.hunger >= UrgentHunger:
            inc sample[].urgent
          if person.hunger >= 100:
            inc sample[].starving
          if meal:
            inc sample[].meals
          if previousTask[i] == GatherTask:
            let kind = previousResource[i]
            sample[].gathered[kind] +=
              max(0, person.cargo[kind] - previousCargo[i][kind])
          elif meal and previousTask[i] == EatTask and previousSource[i] >= 0:
            inc sample[].gathered[world.sources[previousSource[i]].resource]
      for house in world.households:
        for sample in [daily[house.village].addr, totals[house.village].addr]:
          sample[].fuelLow = min(sample[].fuelLow, house.fuel)
          if house.fuel <= 0:
            inc sample[].emptyHearths
    var line = $day
    for i, village in world.villages:
      let sample = daily[i]
      line.add " | " & village.name & ": " & $sample.meals & " " &
        $world.villageSupplies(i).foodTotal() & " " &
        formatFloat(sample.hungerPeak, ffDecimal, 1) & " " &
        formatFloat(sample.fuelLow, ffDecimal, 1)
    var sourceFood = 0
    for source in world.sources:
      if source.resource in {BerriesResource, GrainResource, FishResource}:
        sourceFood += source.amount
    echo line, " | sourceFood=", sourceFood
  var totalHarvest: Inventory
  for i, village in world.villages:
    let
      sample = totals[i]
      awake = sample.samples - sample.tasks[SleepTask]
      work = sample.tasks[GatherTask] + sample.tasks[WithdrawTask] +
        sample.tasks[DeliverTask] + sample.tasks[RefuelTask] +
        sample.tasks[RepairTask]
      leisure = sample.tasks[ChoreTask] + sample.tasks[WanderTask] +
        sample.tasks[ChatTask]
    for kind in ResourceKind:
      totalHarvest[kind] += sample.gathered[kind]
    echo "FINAL seed=", seed, " village=", village.name,
      " meals=", sample.meals,
      " food=", world.villageSupplies(i).foodTotal(),
      " gathered=", sample.gathered.inventoryText(),
      " urgent%=", percent(sample.urgent, sample.samples),
      " saturatedHunger%=", percent(sample.starving, sample.samples),
      " peakHunger=", formatFloat(sample.hungerPeak, ffDecimal, 1),
      " minHealth=", formatFloat(sample.healthLow, ffDecimal, 1),
      " coldHearthTicks=", sample.emptyHearths,
      " sleep%=", percent(sample.tasks[SleepTask], sample.samples),
      " awakeWork%=", percent(work, awake),
      " awakeLeisure%=", percent(leisure, awake),
      " awakeIdle%=", percent(sample.tasks[IdleTask], awake),
      " chat%=", percent(sample.tasks[ChatTask], awake)
    var workLine = "GATHER awake% (travel%) " & village.name & ":"
    for kind in ResourceKind:
      workLine.add " " & kind.resourceName() & "=" &
        percent(sample.gathering[kind], awake) & "(" &
        percent(sample.travelling[kind], awake) & ")"
    echo workLine
  doAssert totalHarvest == sourceHarvest,
    "Gathering observations must match physical source withdrawals."
  var remaining: Inventory
  for source in world.sources:
    remaining[source.resource] += source.amount
  echo "SOURCES seed=", seed, " remaining=", remaining.inventoryText(),
    " regrown=", regrown.inventoryText()

let
  days = if paramCount() > 0: parseInt(paramStr(1)) else: 12
  seeds = if paramCount() > 1: paramStr(2) else: "42,7,123"
  emptyFood = paramCount() > 2 and paramStr(3) == "empty-food"
doAssert days > 0
for seed in seeds.split(','):
  measure(parseInt(seed), days, emptyFood)
