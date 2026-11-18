import
  std/strutils,
  vmath,
  ../[common, resources, sim]

proc fixture(): World =
  ## Builds open ground with homes, supplies, and residents for action checks.
  result = newWorld(MonsterMap(
    seed: 42,
    blocked: newSeq[bool](MapSize * MapSize),
    landmarks: @[
      Landmark(id: "home", position: vec2(-12.5'f, 0.5'f)),
      Landmark(id: "village", position: vec2(0.5'f, 8.5'f)),
      Landmark(id: "miller_hut", position: vec2(8.5'f, 0.5'f)),
      Landmark(id: "weaver_hut", position: vec2(8.5'f, 12.5'f)),
      Landmark(id: "berries", position: vec2(12.5'f, 0.5'f)),
      Landmark(id: "farm", position: vec2(-8.5'f, 6.5'f))
    ]
  ))
  for person in result.villagers.mitems:
    person.hunger = 0
    person.sleepiness = 0
    person.retry = 10000

proc advance(world: var World, seconds: float32) =
  ## Advances physical simulation without issuing any resident commands.
  for tick in 0 ..< int(seconds * TickRate.float32):
    world.step()

proc finish(world: var World) =
  ## Completes an explicit creature plan within its bounded action timeout.
  for tick in 0 ..< 120 * TickRate:
    world.step()
    if not world.active and world.actions.len == 0:
      return
  doAssert false, "The creature's plan did not settle."

proc strike(world: var World, target: string, count = 1) =
  ## Requests a known number of physical strikes and checks actual success.
  var actions: seq[CreatureAction]
  for i in 0 ..< count:
    actions.add CreatureAction(kind: AttackAction, target: target)
  let problems = world.problems.len
  world.instruct(actions)
  world.finish()
  doAssert world.problems.len == problems, $world.problems

proc give(world: var World, target: string, amount = 2) =
  ## Delivers real carried stone through the same action used by conversation.
  world.creature.cargo = default(Inventory)
  world.creature.cargo[StoneResource] = amount
  let problems = world.problems.len
  world.instruct(@[CreatureAction(kind: GiveAction, target: target)])
  world.finish()
  doAssert world.problems.len == problems, $world.problems
  doAssert world.creature.cargo.total() == 0

proc rejected(world: var World, kind: ActionKind, target: string): bool =
  ## Checks that a dead destination refuses an action before it can start.
  try:
    world.instruct(@[CreatureAction(kind: kind, target: target)])
  except MonsterError:
    return true

echo "Testing damaged and destroyed buildings"
block:
  var world = fixture()
  world.households[0].stock[StoneResource] = 8
  world.households[0].stock[HardwoodResource] = 4
  world.strike("miller_hut")
  doAssert world.households[0].integrity == 65
  world.strike("miller_hut", 2)
  doAssert world.households[0].integrity == 0
  doAssert world.households[0].stock.total() == 0
  doAssert world.households[0].fuel == 0
  doAssert world.events[^1].contains("Destroyed")
  doAssert world.rejected(GiveAction, "miller_hut")
  doAssert world.rejected(AttackAction, "miller_hut")
  world.creature.position = vec2(-40.5'f, -40.5'f)
  world.households[0].stock[StoneResource] = 8
  world.households[0].stock[HardwoodResource] = 4
  world.villagers[0].fear = 0
  world.villagers[0].fearLevel = 0
  world.villagers[0].trust = 100
  world.villagers[0].task = RepairTask
  world.villagers[0].target = "miller_hut"
  world.villagers[0].path.setLen(0)
  world.villagers[0].elapsed = 8
  world.advance(30)
  doAssert world.households[0].integrity == 0,
    "A queued repair must not rebuild a destroyed house."

block:
  var world = fixture()
  world.villages[0].stock[StoneResource] = 8
  world.strike("hall")
  doAssert world.villages[0].health == 65
  world.strike("village", 2)
  doAssert world.villages[0].health == 0
  doAssert world.villages[0].stock.total() == 0
  doAssert world.rejected(GiveAction, "hall")
  doAssert world.rejected(AttackAction, "village")
  world.advance(20)
  doAssert world.villages[0].health == 0
  doAssert world.villages[0].stock.total() == 0

echo "Testing destroyed resources remain unusable"
block:
  var world = fixture()
  world.strike("berries")
  doAssert world.sources[0].destroyed
  doAssert world.sources[0].amount == 0
  doAssert world.rejected(GatherAction, "berries")
  doAssert world.rejected(AttackAction, "berries")
  world.advance(60)
  doAssert world.sources[0].amount == 0,
    "Destroyed food sources must not replenish like an exhausted source."

echo "Testing displaced residents still sleep and eat"
block:
  var world = fixture()
  world.households[0].integrity = 0
  world.households[0].stock = default(Inventory)
  world.households[0].fuel = 0
  world.villagers[0].retry = 0
  world.villagers[0].sleepiness = 90
  world.villagers[0].trust = 100
  world.villagers[0].fearLevel = 0
  world.advance(15)
  doAssert world.villagers[0].sleeping
  doAssert world.villagers[0].target == "village",
    "Losing a home redirects sleep to the intact hall."
  world.villages[0].health = 0
  world.villages[0].stock = default(Inventory)
  world.villagers[0].sleepiness = 90
  world.advance(3)
  doAssert world.villagers[0].sleeping
  doAssert world.villagers[0].target == world.villagers[0].id,
    "A resident without a home or hall can still rest outdoors."
  world.villagers[0].hunger = 95
  world.villagers[0].sleepiness = 0
  world.advance(30)
  doAssert world.villagers[0].hunger < UrgentHunger,
    "A displaced resident can leave shelter and find a real meal."

echo "Testing wary residents become neutral through real gifts"
block:
  var world = fixture()
  world.creature.position = vec2(0.5'f, 0.5'f)
  world.villagers[0].position = vec2(1.5'f, 0.5'f)
  let distance = length(world.villagers[0].position - world.creature.position)
  world.advance(0.3'f)
  doAssert length(world.villagers[0].position - world.creature.position) > distance
  doAssert world.villagers[0].activity.contains("wary")
  doAssert world.villagers[0].health == 100
  doAssert world.events.len == 0

block:
  var world = fixture()
  for person in world.villagers:
    doAssert person.trust == 0
    doAssert person.fearLevel == InitialFear
    doAssert person.attitude() == "Wary"
  let start = vec2(-4.5'f, 0.5'f)
  world.villagers[0].position = start
  world.villagers[0].task = GatherTask
  world.villagers[0].target = "berries"
  world.villagers[0].resource = BerriesResource
  world.villagers[0].path = world.map.route(start, world.sources[0].position)
  world.villagers[0].retry = 0
  world.give("ada")
  doAssert world.villagers[0].position != start,
    "Moss can deliver a gift while catching up with a wary working resident."
  doAssert world.villagers[0].trust == 10
  doAssert world.villagers[0].fearLevel < InitialFear
  doAssert world.villagers[1].trust == 0,
    "A personal gift rewards its actual recipient."
  world.give("ada")
  doAssert world.villagers[0].trust == 20
  doAssert world.villagers[0].attitude() == "Neutral"
  let trust = world.villagers[0].trust
  world.instruct(@[CreatureAction(kind: GiveAction, target: "ada")])
  world.finish()
  doAssert world.problems.len == 1
  doAssert world.villagers[0].trust == trust,
    "An empty-handed delivery cannot create trust."

block:
  var world = fixture()
  world.give("miller_hut")
  doAssert world.villagers[0].trust == 4
  doAssert world.villagers[1].trust == 4
  doAssert world.villagers[2].trust == 0
  doAssert world.villagers[3].trust == 0
  world.give("hall", 6)
  doAssert world.villagers[0].trust == 16
  doAssert world.villagers[1].trust == 16
  doAssert world.villagers[2].trust == 12
  doAssert world.villagers[3].trust == 12,
    "Shared gifts benefit the residents who use that storage."

echo "Testing violence breaks trust and provokes flight"
block:
  var world = fixture()
  world.villagers[0].position = vec2(-1.5'f, 6.5'f)
  world.villagers[0].trust = 80
  world.villagers[0].fearLevel = 0
  world.strike("hall")
  doAssert world.villagers[0].health == 100
  doAssert world.villagers[0].trust == 35
  doAssert world.villagers[0].fearLevel >= PanicFear,
    "Witnesses fear attacks on their buildings as well as attacks on people."

block:
  var world = fixture()
  world.creature.position = vec2(0.5'f, 0.5'f)
  world.villagers[0].position = vec2(1.5'f, 0.5'f)
  world.villagers[1].position = vec2(4.5'f, 0.5'f)
  for person in world.villagers.mitems:
    person.trust = 80
    person.fearLevel = 0
  let position = world.villagers[0].position
  world.strike("ada")
  doAssert world.villagers[0].health == 65
  doAssert world.villagers[0].trust == 35
  doAssert world.villagers[0].fearLevel >= PanicFear
  doAssert world.villagers[0].attitude() == "Terrified"
  doAssert world.villagers[1].fearLevel >= PanicFear
  doAssert world.villagers[1].trust == 35
  doAssert world.villagers[2].trust == 80,
    "Distant residents do not witness an unseen strike."
  world.advance(1)
  doAssert world.villagers[0].position != position
  doAssert world.villagers[0].task == FleeTask
  world.strike("ada", 2)
  doAssert world.villagers[0].health == 0,
    "Repeated requested strikes can kill a target that flees."

echo "Monster destruction, survival, and relationships passed"
