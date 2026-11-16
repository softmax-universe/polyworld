import
  std/[json, math, os, tempfiles],
  jsony, vmath,
  polyworld/daycycles,
  ../[common, maps, resources, sim]

proc tickAt(hour: float32): int32 =
  ## Places a fixture at an hour of the same accelerated village clock.
  int32(round(((hour - 8 + 24) mod 24) *
    HudDaySeconds.float32 * TickRate.float32 / 24))

proc advance(world: var World, seconds: int) =
  ## Advances needs while checking bounded meters and physical positions.
  for tick in 0 ..< seconds * TickRate:
    world.step()
    for person in world.villagers:
      doAssert world.map.walkable(person.position), person.name
      doAssert person.hunger >= 0 and person.hunger <= 100
      doAssert person.sleepiness >= 0 and person.sleepiness <= 100
      doAssert person.cargo.total() in 0 .. 12
      if person.sleeping:
        doAssert not person.moving
        doAssert length(person.position -
          world.households[person.home].position) < 1.5'f,
          "Sleep must happen at the villager's own home."

proc fixture(hour = 12'f): World =
  ## Isolates one supplied resident from competing household errands.
  result = newWorld(generateMap())
  result.tick = tickAt(hour)
  result.villagers.setLen(1)
  result.villagers[0].hunger = 10
  result.villagers[0].sleepiness = 10
  for house in result.households.mitems:
    house.stock[GrainResource] = 8
    house.fuel = 100
    house.integrity = 100
  for village in result.villages.mitems:
    village.stock[GrainResource] = 12
    village.stock[SoftwoodResource] = 8
    village.stock[StoneResource] = 6

proc awaitSleep(world: var World, index = 0) =
  ## Waits for physical arrival at home without allowing an endless commute.
  for tick in 0 ..< 40 * TickRate:
    world.step()
    if world.villagers[index].sleeping:
      return
  doAssert false, "The tired villager did not reach home to sleep."

proc stoneUnits(world: World): int =
  ## Counts finite stone to detect dropped cargo during interrupted errands.
  result = world.creature.cargo[StoneResource]
  for village in world.villages:
    result += village.stock[StoneResource]
  for house in world.households:
    result += house.stock[StoneResource]
  for person in world.villagers:
    result += person.cargo[StoneResource]
  for source in world.sources:
    if source.resource == StoneResource:
      result += source.amount

echo "Testing filling hunger and sleepiness meters"
block:
  var day = fixture(12)
  var night = fixture(20)
  day.villagers[0].retry = 1000
  night.villagers[0].retry = 1000
  day.advance(10)
  night.advance(10)
  doAssert day.villagers[0].hunger > 10
  doAssert night.villagers[0].hunger > 10
  doAssert day.villagers[0].sleepiness > 10
  doAssert night.villagers[0].sleepiness > day.villagers[0].sleepiness,
    "Staying awake at night should build sleepiness faster."
  doAssert not day.villagers[0].sleeping
  doAssert not night.villagers[0].sleeping

block:
  var world = fixture()
  let home = world.villagers[0].home
  world.villagers[0].hunger = 65
  world.villagers[0].position = world.households[home].position
  let food = world.households[home].stock.foodTotal()
  world.advance(6)
  doAssert world.villagers[0].hunger < 30
  doAssert world.households[home].stock.foodTotal() == food - 1,
    "Relieving hunger must consume one real meal."

echo "Testing nighttime preference and a physical trip home"
block:
  var day = fixture(12)
  var night = fixture(20)
  for world in [day.addr, night.addr]:
    world[].villagers[0].sleepiness = 50
    world[].villagers[0].position = vec2(0, 0)
  day.step()
  night.step()
  doAssert day.villagers[0].task != SleepTask
  doAssert night.villagers[0].task == SleepTask
  doAssert night.villagers[0].moving
  doAssert not night.villagers[0].sleeping
  var previous = night.villagers[0].sleepiness
  for tick in 0 ..< 40 * TickRate:
    night.step()
    if night.villagers[0].sleepiness < previous:
      doAssert night.villagers[0].sleeping,
        "Walking home must not count as restorative sleep."
      doAssert length(night.villagers[0].position -
        night.households[night.villagers[0].home].position) < 1.5'f
      break
    previous = night.villagers[0].sleepiness
  doAssert night.villagers[0].sleeping
  let before = night.villagers[0].sleepiness
  night.advance(10)
  doAssert night.villagers[0].sleepiness < before
  doAssert night.villagers[0].sleeping

block:
  var world = fixture(12)
  world.villagers[0].sleepiness = 95
  world.awaitSleep()
  let before = world.villagers[0].sleepiness
  world.advance(10)
  doAssert world.villagers[0].sleepiness < before,
    "Exhausted villagers should be able to rest during daylight."

block:
  var world = fixture(20)
  world.villagers[0].sleepiness = 50
  world.awaitSleep()
  world.villagers[0].sleepiness = 0
  world.advance(10)
  doAssert world.villagers[0].sleeping,
    "A rested villager should stay in bed through the night."
  world.tick = tickAt(6)
  world.step()
  doAssert not world.villagers[0].sleeping,
    "A rested villager should wake at dawn."

echo "Testing meals and danger interrupt sleep"
block:
  var world = fixture(20)
  world.villagers[0].sleepiness = 50
  world.awaitSleep()
  world.villagers[0].hunger = 90
  world.villagers[0].cargo[GrainResource] = 1
  world.step()
  doAssert not world.villagers[0].sleeping
  world.advance(6)
  doAssert world.villagers[0].hunger < 60
  doAssert world.villagers[0].cargo[GrainResource] == 0

block:
  var world = fixture(20)
  world.villagers[0].sleepiness = 50
  world.awaitSleep()
  world.creature.position = world.villagers[0].position
  world.villagers[0].fear = FrightDuration
  let before = world.villagers[0].sleepiness
  world.step()
  doAssert not world.villagers[0].sleeping
  doAssert world.villagers[0].task == FleeTask
  doAssert world.villagers[0].sleepiness >= before

block:
  var world = fixture(20)
  world.villagers[0].hunger = 95
  world.villagers[0].sleepiness = 95
  world.villagers[0].cargo[StoneResource] = 2
  world.villagers[0].position = vec2(0, 0)
  let stone = world.stoneUnits()
  world.advance(30)
  doAssert world.villagers[0].hunger < 80,
    "Full non-food cargo must not trap a hungry villager in a fetch loop."
  doAssert world.stoneUnits() == stone

block:
  var world = fixture(20)
  for house in world.households.mitems:
    house.stock = default(Inventory)
  for village in world.villages.mitems:
    village.stock = default(Inventory)
  let berries = world.sourceIndex("berries")
  world.villagers[0].position = world.sources[berries].position
  world.villagers[0].hunger = 95
  world.villagers[0].sleepiness = 95
  world.villagers[0].cargo[StoneResource] = 2
  let food = world.sources[berries].amount
  world.advance(6)
  doAssert world.villagers[0].hunger < 80,
    "A full carrier must be able to find and eat wild food."
  doAssert world.sources[berries].amount == food - 1
  doAssert world.villagers[0].cargo[StoneResource] == 2

block:
  var world = fixture(20)
  world.villagers[0].health = 0
  world.villagers[0].hunger = 45
  world.villagers[0].sleepiness = 55
  world.advance(10)
  doAssert world.villagers[0].hunger == 45
  doAssert world.villagers[0].sleepiness == 55
  doAssert not world.villagers[0].sleeping

echo "Testing autonomous routines over two full days"
block:
  var world = newWorld(generateMap())
  for house in world.households.mitems:
    house.integrity = 100
  var
    slept = newSeq[bool](world.villagers.len)
    ate = newSeq[bool](world.villagers.len)
    previousHunger = newSeq[float32](world.villagers.len)
  for i, person in world.villagers:
    previousHunger[i] = person.hunger
  let stone = world.stoneUnits()
  for second in 0 ..< HudDaySeconds.int * 2:
    world.advance(1)
    for i, person in world.villagers:
      slept[i] = slept[i] or person.sleeping
      ate[i] = ate[i] or person.hunger < previousHunger[i] - 1
      previousHunger[i] = person.hunger
    for source in world.sources:
      doAssert source.amount in 0 .. source.capacity
  for i, person in world.villagers:
    doAssert slept[i], person.name & " never slept over two full days."
    doAssert ate[i], person.name & " never ate over two full days."
  doAssert world.stoneUnits() == stone,
    "Sleeping and interrupted errands must not discard carried supplies."

echo "Testing persistent needs and day/night phase"
block:
  let directory = createTempDir("monster-needs-", "")
  defer:
    removeDir(directory)
  let path = directory / "world.json"
  var world = newWorld(generateMap())
  world.tick = tickAt(20)
  world.villagers[0].hunger = 10
  world.villagers[0].sleepiness = 61
  world.awaitSleep()
  let before = world.toJson()
  world.saveWorld(path)
  doAssert world.toJson() == before
  let document = parseJson(readFile(path))
  doAssert document["version"].getInt() == 8
  var restored = newWorld(generateMap())
  restored.restoreWorld(path)
  doAssert restored.tick == world.tick
  doAssert clockHour(restored.tick, TickRate) ==
    clockHour(world.tick, TickRate)
  for i, person in world.villagers:
    doAssert restored.villagers[i].hunger == person.hunger
    doAssert restored.villagers[i].sleepiness == person.sleepiness
    doAssert restored.villagers[i].sleeping == person.sleeping
    doAssert restored.villagers[i].cargo == person.cargo
  let sleepiness = restored.villagers[0].sleepiness
  restored.step()
  doAssert restored.villagers[0].sleeping
  doAssert restored.villagers[0].sleepiness < sleepiness

  let old = parseJson($document)
  old["version"] = %5
  old.delete("tick")
  for person in old["villagers"]:
    person.delete("sleepiness")
    person.delete("sleeping")
  writeFile(path, $old)
  restored.restoreWorld(path)
  doAssert restored.tick == 0
  doAssert not isNight(clockHour(restored.tick, TickRate))
  for i, person in restored.villagers:
    doAssert person.sleepiness >= 0 and person.sleepiness < 25
    doAssert not person.sleeping
    doAssert person.hunger == world.villagers[i].hunger
    doAssert person.cargo == world.villagers[i].cargo

  let previous = restored.toJson()
  for field in ["tick", "sleepiness", "sleeping"]:
    for invalid in ["missing", "null", "range", "type"]:
      let broken = parseJson($document)
      let owner =
        if field == "tick": broken
        else: broken["villagers"][0]
      case invalid
      of "missing": owner.delete(field)
      of "null": owner[field] = newJNull()
      of "range": owner[field] = %(-1)
      else: owner[field] = %"invalid"
      writeFile(path, $broken)
      var rejected = false
      try:
        restored.restoreWorld(path)
      except MonsterError:
        rejected = true
      doAssert rejected, "Invalid persisted need: " & field & " " & invalid
      doAssert restored.toJson() == previous,
        "Invalid needs must not partially replace the live world."
  for amount in [101'f, Inf.float32, NaN.float32]:
    let broken = parseJson($document)
    broken["villagers"][0]["sleepiness"] = %amount
    writeFile(path, $broken)
    var rejected = false
    try:
      restored.restoreWorld(path)
    except MonsterError:
      rejected = true
    doAssert rejected
    doAssert restored.toJson() == previous

echo "Monster villager needs passed"
