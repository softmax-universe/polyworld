import
  std/[os, strutils, tempfiles],
  vmath,
  ../[common, sim]

proc fixture(): World =
  ## Creates a small traversable world for deterministic action checks.
  var map = MonsterMap(
    seed: 42,
    blocked: newSeq[bool](MapSize * MapSize),
    landmarks: @[
      Landmark(id: "home", position: vec2(-6.5'f, 0.5'f)),
      Landmark(id: "berries", position: vec2(6.5'f, 0.5'f)),
      Landmark(id: "farm", position: vec2(0.5'f, -6.5'f)),
      Landmark(id: "village", position: vec2(0.5'f, 6.5'f))
    ]
  )
  for z in 28 .. 35:
    map.blocked[z * MapSize + 32] = true
  newWorld(map)

proc finish(world: var World) =
  ## Executes bounded work and checks every movement position for collisions.
  for i in 0 ..< TickRate * 120:
    world.step()
    doAssert world.map.walkable(world.creature.position)
    if not world.active and world.actions.len == 0:
      return
  doAssert false, "Creature plan did not finish."

echo "Testing conversation-driven creature actions"
block:
  var world = fixture()
  world.instruct(@[CreatureAction(kind: MoveAction, target: "berries")])
  world.finish()
  doAssert length(world.creature.position - vec2(6.5'f, 0.5'f)) < 0.01'f
  doAssert world.events[^1] == "Arrived at berries."

block:
  var world = fixture()
  world.instruct(@[
    CreatureAction(kind: GatherAction, target: "berries"),
    CreatureAction(kind: GiveAction, target: "village")
  ])
  world.finish()
  doAssert world.berryFood == 18
  doAssert world.farmFood == 12
  doAssert world.villageFood == 6
  doAssert world.creature.food == 0

block:
  var world = fixture()
  world.instruct(@[CreatureAction(kind: GatherAction, target: "farm")])
  world.finish()
  doAssert world.farmFood == 6
  doAssert world.events[^1] == "Took 6 food from the villagers' farm."
  world.instruct(@[CreatureAction(kind: EatAction)])
  world.finish()
  doAssert world.creature.food == 5

block:
  var world = fixture()
  world.instruct(@[CreatureAction(kind: MoveAction, target: "berries")])
  world.step()
  let position = world.creature.position
  world.stop()
  for i in 0 ..< 30:
    world.step()
  doAssert world.creature.position == position
  doAssert not world.active

block:
  var world = fixture()
  world.instruct(@[
    CreatureAction(kind: StopAction),
    CreatureAction(kind: MoveAction, target: "berries")
  ])
  world.finish()
  doAssert length(world.creature.position - vec2(6.5'f, 0.5'f)) < 0.01'f

block:
  var world = fixture()
  let original = CreatureAction(kind: MoveAction, target: "berries")
  world.instruct(@[original])
  for action in [
    CreatureAction(kind: MoveAction, x: NaN.float32),
    CreatureAction(kind: MoveAction, x: 100),
    CreatureAction(kind: MoveAction, x: 0.5'f, z: 0.5'f),
    CreatureAction(kind: MoveAction, target: "missing"),
    CreatureAction(kind: GatherAction, target: "home")
  ]:
    var rejected = false
    try:
      world.instruct(@[original, action])
    except MonsterError:
      rejected = true
      let reason = getCurrentExceptionMsg()
      doAssert reason.contains(
        if action.target.len > 0: action.target else: "x="
      ), "Validation feedback must identify the action that failed."
    doAssert rejected
    doAssert world.actions == @[original]

block:
  let directory = createTempDir("monster-sim-", "")
  defer:
    removeDir(directory)
  let path = directory / "world.json"
  var world = fixture()
  world.instruct(@[CreatureAction(kind: GatherAction, target: "berries")])
  world.finish()
  world.saveWorld(path)
  var restored = fixture()
  restored.restoreWorld(path)
  doAssert restored.creature.position == world.creature.position
  doAssert restored.creature.food == 6
  doAssert restored.berryFood == 18
  doAssert not restored.active
  writeFile(path, "{broken")
  var rejected = false
  try:
    restored.restoreWorld(path)
  except MonsterError:
    rejected = true
  doAssert rejected

echo "Testing failed actions become private creature feedback"
block:
  var world = fixture()
  for z in 0 ..< MapSize:
    world.map.blocked[z * MapSize + 32] = true
  let start = world.creature.position
  doAssert world.map.walkable(vec2(6.5'f, 0.5'f))
  world.instruct(@[
    CreatureAction(kind: MoveAction, target: "berries"),
    CreatureAction(kind: DanceAction)
  ])
  world.finish()
  doAssert world.creature.position == start
  doAssert world.actions.len == 0 and not world.active
  doAssert world.events.len == 0
  doAssert world.problems.len == 1
  doAssert world.problems[0].contains("move to berries failed")
  doAssert world.problems[0].contains("cannot find a path")

for (action, food, berries, reason) in [
  (CreatureAction(kind: GatherAction, target: "berries"), 0, 0,
    "no food left at berries"),
  (CreatureAction(kind: GatherAction, target: "berries"), 6, 24,
    "capacity is full"),
  (CreatureAction(kind: GiveAction, target: "village"), 0, 24,
    "no food to give"),
  (CreatureAction(kind: EatAction), 0, 24, "no food to eat")
]:
  var world = fixture()
  world.creature.food = food
  world.berryFood = berries
  world.instruct(@[action, CreatureAction(kind: DanceAction)])
  world.finish()
  doAssert world.actions.len == 0 and not world.active
  doAssert world.events.len == 0
  doAssert world.problems.len == 1
  doAssert world.problems[0].contains(reason)
  doAssert world.creature.food == food
  doAssert world.berryFood == berries
  doAssert world.villageFood == 0

echo "Monster simulation passed"
