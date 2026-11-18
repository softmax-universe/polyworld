import
  std/[json, os, strutils, tempfiles],
  jsony, vmath,
  ../[common, maps, sim]

proc fixture(): World =
  ## Builds open ground with two residents and quiet needs for combat checks.
  let map = MonsterMap(
    seed: 42,
    blocked: newSeq[bool](MapSize * MapSize),
    landmarks: @[
      Landmark(id: "home", position: vec2(-8.5'f, 0.5'f)),
      Landmark(id: "village", position: vec2(0.5'f, 8.5'f)),
      Landmark(id: "miller_hut", position: vec2(8.5'f, 0.5'f)),
      Landmark(id: "berries", position: vec2(12.5'f, 0.5'f))
    ]
  )
  result = newWorld(map)
  result.creature.position = vec2(0.5'f, 0.5'f)
  for i, person in result.villagers.mpairs:
    person.position = vec2(1.5'f + i.float32 * 3, 0.5'f)
    person.hunger = 0
    person.retry = 1000
    person.trust = 20

proc advance(world: var World, seconds: float32) =
  ## Advances a bounded interval while checking physical navigation positions.
  for tick in 0 ..< int(seconds * TickRate.float32):
    world.step()
    doAssert world.map.walkable(world.creature.position)
    for person in world.villagers:
      doAssert world.map.walkable(person.position), person.name

proc finish(world: var World) =
  ## Completes one requested attack without requiring NPCs to stop fleeing.
  for tick in 0 ..< 120 * TickRate:
    world.step()
    doAssert world.map.walkable(world.creature.position)
    if not world.active and world.actions.len == 0:
      return
  doAssert false, "The requested attack never settled."

proc stoneUnits(world: World): int =
  ## Counts preserved stone supplies even when a carrier is injured or dead.
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

proc attack(world: var World, target = "ada") =
  ## Runs one explicitly requested strike against a named villager.
  world.instruct(@[CreatureAction(kind: AttackAction, target: target)])
  world.finish()

echo "Testing one requested strike and interruption"
block:
  let world = newWorld(generateMap())
  for person in world.villagers:
    doAssert person.health == 100
    doAssert person.fear == 0
  for village in world.villages:
    doAssert village.alarm == 0

block:
  var world = fixture()
  world.attack()
  doAssert world.problems.len == 0, $world.problems
  doAssert world.villagers[0].health == 100 - AttackDamage
  doAssert world.villagers[1].health == 100
  doAssert world.villagers[0].hitTime > 0
  doAssert world.villagers[0].fear > 0
  doAssert world.villagers[1].fear > 0,
    "A nearby witness should react to the strike."
  doAssert world.villages[0].alarm > 0
  doAssert world.events.len == 1
  doAssert world.events[0].contains("Ada")
  world.advance(20)
  doAssert world.villagers[0].health == 100 - AttackDamage,
    "One attack order must not turn into repeated automatic attacks."

block:
  var world = fixture()
  world.instruct(@[CreatureAction(kind: AttackAction, target: "ada")])
  var windingUp = false
  for tick in 0 ..< TickRate * 3:
    world.step()
    if world.active and not world.creature.moving and world.elapsed > 0:
      windingUp = true
      break
  doAssert windingUp
  doAssert world.villagers[0].health == 100
  world.stop()
  world.advance(2)
  doAssert world.villagers[0].health == 100,
    "Stop during the windup must prevent the impact."
  doAssert world.events.len == 0
  doAssert world.villages[0].alarm == 0

block:
  var world = fixture()
  let original = CreatureAction(kind: MoveAction, target: "home")
  world.instruct(@[original])
  for target in ["", "home", "missing"]:
    var rejected = false
    try:
      world.instruct(@[CreatureAction(kind: AttackAction, target: target)])
    except MonsterError:
      rejected = true
    doAssert rejected
    doAssert world.actions == @[original],
      "A rejected attack must leave the existing plan intact."

echo "Testing moving targets, walls, and fear"
block:
  var world = fixture()
  let start = vec2(6.5'f, 0.5'f)
  world.villagers[0].position = start
  world.villagers[0].task = GatherTask
  world.villagers[0].target = "berries"
  world.villagers[0].resource = BerriesResource
  world.villagers[0].path = world.map.route(start, vec2(12.5'f, 0.5'f))
  world.villagers[0].waypoint = 0
  world.villagers[0].retry = 0
  world.instruct(@[CreatureAction(kind: AttackAction, target: "ada")])
  var hit = false
  for tick in 0 ..< TickRate * 30:
    world.step()
    if world.villagers[0].health < 100:
      doAssert world.villagers[0].position != start,
        "The test must chase a moving target."
      doAssert length(world.creature.position -
        world.villagers[0].position) <= AttackRange + 0.05'f,
        "An impact must occur at the target's current position."
      hit = true
      break
  doAssert hit
  doAssert world.villagers[0].health == 100 - AttackDamage

block:
  var world = fixture()
  world.creature.position = vec2(-0.1'f, 0.5'f)
  world.villagers[0].position = vec2(1.1'f, 0.5'f)
  for z in 0 ..< MapSize:
    world.map.blocked[z * MapSize + MapSize div 2] = true
  doAssert length(world.creature.position -
    world.villagers[0].position) < AttackRange
  world.attack()
  doAssert world.villagers[0].health == 100,
    "Melee range alone must not permit an attack through a blocked cell."
  doAssert world.problems.len == 1
  doAssert world.events.len == 0

block:
  var world = fixture()
  world.villagers[0].cargo[StoneResource] = 2
  world.villagers[1].cargo[StoneResource] = 1
  let
    units = world.stoneUnits()
    victimStart = world.villagers[0].position
    witnessStart = world.villagers[1].position
  world.attack()
  world.advance(1)
  doAssert world.villagers[0].position != victimStart
  doAssert world.villagers[1].position != witnessStart
  doAssert world.villagers[0].fear > 0
  doAssert world.villagers[1].fear > 0
  doAssert world.stoneUnits() == units,
    "Fleeing must neither lose nor create the supplies people carry."
  doAssert world.villagers[0].cargo[StoneResource] == 2
  doAssert world.villagers[1].cargo[StoneResource] == 1

block:
  var world = fixture()
  world.creature.position = vec2(-0.1'f, 0.5'f)
  world.villagers[0].position = vec2(1.1'f, 0.5'f)
  world.instruct(@[CreatureAction(kind: AttackAction, target: "ada")])
  world.step()
  doAssert world.active and world.elapsed > 0
  for z in 0 ..< MapSize:
    world.map.blocked[z * MapSize + MapSize div 2] = true
  world.finish()
  doAssert world.villagers[0].health == 100,
    "The strike must recheck the line of sight at impact time."
  doAssert world.problems.len == 1

echo "Testing death, stable identities, and persistent consequences"
block:
  var world = fixture()
  world.instruct(@[
    CreatureAction(kind: AttackAction, target: "ada"),
    CreatureAction(kind: AttackAction, target: "ada"),
    CreatureAction(kind: AttackAction, target: "ada"),
    CreatureAction(kind: AttackAction, target: "ada"),
    CreatureAction(kind: DanceAction)
  ])
  world.finish()
  doAssert world.villagers[0].health == 0
  doAssert world.problems.len == 1,
    "A target dying during a plan must produce one grounded failure."
  doAssert world.actions.len == 0 and not world.active
  for outcome in world.events:
    doAssert not outcome.contains("dance"),
      "A failed attack must cancel the remaining dependent plan."

block:
  var world = fixture()
  world.villagers[0].cargo[StoneResource] = 2
  let units = world.stoneUnits()
  for strike in 1 .. 3:
    world.attack()
    doAssert world.problems.len == 0, $world.problems
    doAssert world.villagers[0].health == max(0'f,
      100'f - AttackDamage * strike.float32)
  let
    position = world.villagers[0].position
    hunger = world.villagers[0].hunger
    cargo = world.villagers[0].cargo
  doAssert world.villagers[0].id == "ada"
  doAssert world.villagers.len == 2
  world.advance(30)
  doAssert world.villagers[0].health == 0
  doAssert world.villagers[0].position == position
  doAssert world.villagers[0].hunger == hunger
  doAssert world.villagers[0].cargo == cargo
  doAssert not world.villagers[0].moving
  doAssert world.stoneUnits() == units
  for kind in [AttackAction, GiveAction]:
    var rejected = false
    try:
      world.instruct(@[CreatureAction(kind: kind, target: "ada")])
    except MonsterError:
      rejected = true
    doAssert rejected, "Dead villagers cannot be attacked or accept supplies."
  doAssert world.villagers[0].health == 0

block:
  let directory = createTempDir("monster-attacks-", "")
  defer:
    removeDir(directory)
  let path = directory / "world.json"
  var world = fixture()
  world.villagers[0].health = 0
  world.villagers[0].cargo[StoneResource] = 2
  world.villagers[1].health = 65
  world.villagers[1].fear = 9
  world.villages[0].alarm = 10
  let before = world.toJson()
  world.saveWorld(path)
  doAssert world.toJson() == before,
    "Saving combat state must not mutate the running world."
  let document = parseJson(readFile(path))
  doAssert document["version"].getInt() == 8
  var restored = fixture()
  restored.restoreWorld(path)
  doAssert restored.villagers[0].health == 0
  doAssert restored.villagers[0].cargo[StoneResource] == 2
  doAssert restored.villagers[1].health == 65
  doAssert restored.villagers[1].fear == 9
  doAssert restored.villages[0].alarm == 10
  restored.advance(1)
  doAssert restored.villagers[0].health == 0
  doAssert restored.villagers[1].health == 65
  doAssert restored.villagers[1].fear < 9

  for invalid in [-1'f, 101'f, NaN.float32]:
    var broken = parseJson(readFile(path))
    broken["villagers"][0]["health"] = %invalid
    writeFile(path, $broken)
    let previous = restored.toJson()
    var rejected = false
    try:
      restored.restoreWorld(path)
    except MonsterError:
      rejected = true
    doAssert rejected
    doAssert restored.toJson() == previous,
      "Invalid health must not partially replace the live world."
    writeFile(path, $document)

  for field in ["health", "fear", "hitTime", "alarm"]:
    for missing in [true, false]:
      let broken = parseJson($document)
      let owner =
        if field == "alarm": broken["villages"][0]
        else: broken["villagers"][0]
      if missing:
        owner.delete(field)
      else:
        owner[field] = newJNull()
      writeFile(path, $broken)
      let previous = restored.toJson()
      var rejected = false
      try:
        restored.restoreWorld(path)
      except MonsterError:
        rejected = true
      doAssert rejected,
        "Combat saves require numeric combat state: " & field
      doAssert restored.toJson() == previous,
        "Incomplete combat state must not partially replace the live world."

  var old = parseJson($document)
  old["version"] = %3
  for person in old["villagers"]:
    person.delete("health")
    person.delete("fear")
    person.delete("hitTime")
  for village in old["villages"]:
    village.delete("alarm")
  writeFile(path, $old)
  restored.restoreWorld(path)
  for person in restored.villagers:
    doAssert person.health == 100,
      "Older saves without health must load living residents."
    doAssert person.fear == 0
  doAssert restored.villages[0].alarm == 0
  doAssert restored.villagers[0].cargo[StoneResource] == 2

echo "Monster attacks passed"
