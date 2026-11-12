import
  std/[math, os, strutils],
  jsony, vmath,
  common

const
  MoveSpeed = 3.2'f
  CarryLimit = 6
  Neighbors = [
    (-1, 0), (1, 0), (0, -1), (0, 1),
    (-1, -1), (1, -1), (-1, 1), (1, 1)
  ]

type
  WorldSave = object
    version, seed: int
    creature: Creature
    villageFood, berryFood, farmFood: int

proc landmark*(map: MonsterMap, id: string): int {.raises: [].} =
  ## Finds a named place without guessing a different destination.
  for i, place in map.landmarks:
    if place.id == id:
      return i
  -1

proc cell(position: Vec2): int {.raises: [].} =
  ## Converts a finite world position into a flat navigation cell.
  if not (position.x >= -MapHalf and position.x < MapHalf and
    position.y >= -MapHalf and position.y < MapHalf):
      return -1
  (floor(position.y + MapHalf).int * MapSize) +
    floor(position.x + MapHalf).int

proc walkable*(map: MonsterMap, position: Vec2): bool {.raises: [].} =
  ## Checks the same occupied cells used by the scenery generator.
  let index = cell(position)
  index >= 0 and index < map.blocked.len and not map.blocked[index]

proc center(index: int): Vec2 {.raises: [].} =
  ## Returns the world-space center of one navigation cell.
  vec2(
    (index mod MapSize).float32 - MapHalf + 0.5'f,
    (index div MapSize).float32 - MapHalf + 0.5'f
  )

proc route*(map: MonsterMap, start, target: Vec2): seq[Vec2] =
  ## Finds a bounded grid route while preventing diagonal corner cutting.
  if not map.walkable(start) or not map.walkable(target):
    raise newException(MonsterError, "That destination is blocked.")
  let
    source = cell(start)
    destination = cell(target)
  if source == destination:
    return @[target]
  var
    parents = newSeq[int](MapSize * MapSize)
    queue = newSeqOfCap[int](MapSize * MapSize)
    cursor = 0
  for parent in parents.mitems:
    parent = -1
  parents[source] = source
  queue.add source
  while cursor < queue.len and parents[destination] < 0:
    let
      index = queue[cursor]
      x = index mod MapSize
      z = index div MapSize
    inc cursor
    for (dx, dz) in Neighbors:
      let
        nx = x + dx
        nz = z + dz
      if nx < 0 or nx >= MapSize or nz < 0 or nz >= MapSize:
        continue
      let next = nz * MapSize + nx
      if parents[next] >= 0 or map.blocked[next]:
        continue
      if dx != 0 and dz != 0 and
        (map.blocked[z * MapSize + nx] or
        map.blocked[nz * MapSize + x]):
          continue
      parents[next] = index
      queue.add next
  if parents[destination] < 0:
    raise newException(MonsterError, "I cannot find a path there.")
  var
    reverse: seq[int]
    index = destination
  while index != source:
    reverse.add index
    index = parents[index]
  for i in countdown(reverse.high, 0):
    result.add center(reverse[i])
  result.add target

proc event(world: var World, text: string) =
  ## Records a bounded stream of actual physical outcomes.
  if world.events.len == 32:
    world.events.delete(0)
  world.events.add text

proc actionDescription(action: CreatureAction): string =
  ## Identifies the attempted action and its explicit destination.
  let
    kind = case action.kind
      of MoveAction: "move"
      of GatherAction: "gather"
      of GiveAction: "give"
      of EatAction: "eat"
      of RestAction: "rest"
      of DanceAction: "dance"
      of StopAction: "stop"
      of WaitAction: "wait"
    target =
      if action.target.len > 0:
        (if action.kind == MoveAction: " to " else: " at ") & action.target
      elif action.kind == MoveAction:
        " to x=" & $action.x & ", z=" & $action.z
      else:
        ""
  kind & target

proc reportProblem*(
  world: var World,
  action: CreatureAction,
  reason: string
) =
  ## Records an action failure for the creature to interpret privately.
  if world.problems.len >= 32:
    world.problems.delete(0)
  world.problems.add "Action " & action.actionDescription() &
    " failed: " & reason

proc newWorld*(map: MonsterMap): World =
  ## Starts one curious creature beside its home and a hungry village.
  let home = map.landmark("home")
  if home < 0:
    raise newException(MonsterError, "Monster map has no home.")
  result = World(
    map: map,
    creature: Creature(position: map.landmarks[home].position, energy: 100),
    berryFood: 24,
    farmFood: 12,
    status: "Waiting for your voice"
  )

proc destination*(world: World, action: CreatureAction): Vec2 =
  ## Resolves explicit landmarks before accepting numeric map coordinates.
  if action.target.len > 0:
    let index = world.map.landmark(action.target)
    if index < 0:
      raise newException(MonsterError, "Unknown place: " & action.target)
    return world.map.landmarks[index].position
  if action.kind == MoveAction:
    return vec2(action.x, action.z)
  world.creature.position

proc validateAction(world: World, action: CreatureAction) =
  ## Rejects impossible plans before replacing the creature's current work.
  if not (action.duration >= 0 and action.duration <= 30):
    raise newException(MonsterError, "Action duration must be 0 to 30 seconds.")
  case action.kind
  of GatherAction:
    if action.target notin ["berries", "farm"]:
      raise newException(MonsterError, "Gather food at berries or farm.")
  of GiveAction:
    if action.target != "village":
      raise newException(MonsterError, "Give food at the village.")
  else:
    discard
  if action.kind in {MoveAction, GatherAction, GiveAction, RestAction}:
    if not world.map.walkable(world.destination(action)):
      raise newException(MonsterError, "That destination is not walkable.")

proc stop*(world: var World) =
  ## Immediately stops the current action and clears queued work.
  world.actions.setLen(0)
  world.path.setLen(0)
  world.active = false
  world.creature.moving = false
  world.status = "Listening"

proc instruct*(world: var World, actions: seq[CreatureAction]) =
  ## Atomically replaces a plan after every proposed action is validated.
  if actions.len > MaxActions:
    raise newException(MonsterError, "Too many actions in one plan.")
  for action in actions:
    try:
      world.validateAction(action)
    except MonsterError:
      raise newException(MonsterError,
        action.actionDescription() & ": " & getCurrentExceptionMsg())
  if actions.len == 0:
    return
  world.stop()
  world.actions = actions

proc beginAction(world: var World) =
  ## Starts the next physical action and computes its reachable route.
  world.current = world.actions[0]
  world.actions.delete(0)
  world.active = true
  world.elapsed = 0
  world.waypoint = 0
  world.path.setLen(0)
  let action = world.current
  case action.kind
  of MoveAction, GatherAction, GiveAction, RestAction:
    let target = world.destination(action)
    if length(target - world.creature.position) > 0.05'f:
      world.path = world.map.route(world.creature.position, target)
    world.status =
      if action.target.len > 0:
        "Going to " & action.target
      else:
        "Exploring the meadow"
  of EatAction:
    world.status = "Having a snack"
  of DanceAction:
    world.status = "Dancing for you"
  of WaitAction:
    world.status = "Waiting here"
  of StopAction:
    world.active = false
    world.creature.moving = false
    world.status = "Listening"
    world.event("Stopped the previous action.")

proc finishAction(world: var World) =
  ## Applies a completed action and reports only events that really happened.
  case world.current.kind
  of MoveAction:
    let target = world.current.target
    world.event(
      if target.len > 0:
        "Arrived at " & target & "."
      else:
        "Arrived at the requested position."
    )
  of GatherAction:
    let source = world.current.target
    var remaining =
      if source == "farm":
        world.farmFood
      else:
        world.berryFood
    let amount = min(CarryLimit - world.creature.food, remaining)
    if amount == 0:
      world.reportProblem(
        world.current,
        if world.creature.food >= CarryLimit:
          "Carrying capacity is full (6/6 food)."
        else:
          "There is no food left at " & source & "."
      )
      world.stop()
      return
    remaining -= amount
    world.creature.food += amount
    if source == "farm":
      world.farmFood = remaining
    else:
      world.berryFood = remaining
    if source == "farm":
      world.event("Took " & $amount & " food from the villagers' farm.")
    else:
      world.event("Gathered " & $amount & " wild berries.")
  of GiveAction:
    let amount = world.creature.food
    if amount == 0:
      world.reportProblem(world.current, "Carrying no food to give.")
      world.stop()
      return
    world.villageFood += amount
    world.creature.food = 0
    world.event(
      "Gave the villagers " & $amount & " food. They are grateful."
    )
  of EatAction:
    if world.creature.food > 0:
      dec world.creature.food
      world.creature.energy = min(100'f, world.creature.energy + 15)
      world.event("Ate one carried food and recovered energy.")
    else:
      world.reportProblem(world.current, "Carrying no food to eat.")
      world.stop()
      return
  of RestAction:
    world.creature.energy = min(100'f, world.creature.energy + 30)
    world.event("Rested and recovered energy.")
  of DanceAction:
    world.event("Finished a happy dance.")
  of WaitAction:
    world.event("Finished waiting.")
  of StopAction:
    discard
  world.active = false
  world.creature.moving = false
  world.status = "Listening"

proc step*(world: var World) =
  ## Advances one fixed tick without waiting for language-model requests.
  const Dt = 1'f / TickRate.float32
  inc world.tick
  if not world.active and world.actions.len > 0:
    try:
      world.beginAction()
    except MonsterError:
      world.reportProblem(world.current, getCurrentExceptionMsg())
      world.stop()
  if not world.active:
    return
  var distance = MoveSpeed * Dt
  world.creature.moving = world.waypoint < world.path.len
  while world.waypoint < world.path.len and distance > 0:
    let
      delta = world.path[world.waypoint] - world.creature.position
      remaining = length(delta)
    if remaining > 0.001'f:
      world.creature.facing = arctan2(delta.x, delta.y)
    if remaining <= distance:
      world.creature.position = world.path[world.waypoint]
      distance -= remaining
      inc world.waypoint
    else:
      world.creature.position += delta / remaining * distance
      distance = 0
  if world.waypoint < world.path.len:
    world.creature.energy = max(0'f, world.creature.energy - Dt * 0.08'f)
    return
  world.creature.moving = false
  world.elapsed += Dt
  let duration =
    if world.current.duration > 0:
      world.current.duration
    else:
      case world.current.kind
      of MoveAction, StopAction:
        0'f
      of GatherAction, GiveAction, EatAction:
        1.5'f
      of RestAction:
        6'f
      of DanceAction, WaitAction:
        3'f
  world.status = case world.current.kind
    of GatherAction: "Gathering food"
    of GiveAction: "Sharing with the village"
    of RestAction: "Resting in the grass"
    of EatAction: "Having a snack"
    of DanceAction: "Dancing for you"
    of WaitAction: "Waiting here"
    else: "Listening"
  if world.elapsed >= duration:
    world.finishAction()

proc observation*(world: World): string =
  ## Describes grounded places and resources for the creature's next decision.
  type
    Place = object
      id, name: string
      x, z: float32
    Observation = object
      x, z, energy: float32
      carryingFood, carryLimit, villageFood, wildBerries, farmFood: int
      status, note: string
      places: seq[Place]
  var state = Observation(
    x: world.creature.position.x,
    z: world.creature.position.y,
    energy: world.creature.energy,
    carryingFood: world.creature.food,
    carryLimit: CarryLimit,
    villageFood: world.villageFood,
    wildBerries: world.berryFood,
    farmFood: world.farmFood,
    status: world.status,
    note: "The village needs food. Farm food belongs to the villagers. " &
      "Berries are wild. Gather carries up to six food. Give delivers all " &
      "carried food to village. North is negative z, east is positive x."
  )
  for place in world.map.landmarks:
    state.places.add Place(
      id: place.id, name: place.name,
      x: place.position.x, z: place.position.y
    )
  state.toJson()

proc saveWorld*(world: World, path: string) =
  ## Saves physical progress independently of conversation and API secrets.
  try:
    createDir(path.parentDir)
    let saved = WorldSave(
      version: 1, seed: world.map.seed, creature: world.creature,
      villageFood: world.villageFood, berryFood: world.berryFood,
      farmFood: world.farmFood
    )
    writeFile(path & ".tmp", saved.toJson())
    moveFile(path & ".tmp", path)
  except IOError, OSError:
    raise newException(MonsterError, "Cannot save Monster: " &
      getCurrentExceptionMsg())

proc restoreWorld*(world: var World, path: string) =
  ## Restores valid physical state while leaving old unfinished orders stopped.
  if not fileExists(path):
    return
  try:
    if getFileSize(path) > 64 * 1024:
      raise newException(MonsterError, "Monster save is too large.")
    let saved = readFile(path).fromJson(WorldSave)
    if saved.version != 1 or saved.seed != world.map.seed or
      not world.map.walkable(saved.creature.position) or
      saved.creature.food notin 0 .. CarryLimit or
      not (saved.creature.energy >= 0 and saved.creature.energy <= 100) or
      saved.villageFood notin 0 .. 36 or saved.berryFood notin 0 .. 24 or
      saved.farmFood notin 0 .. 12:
        raise newException(MonsterError, "Monster save contains invalid state.")
    world.creature = saved.creature
    world.creature.moving = false
    world.villageFood = saved.villageFood
    world.berryFood = saved.berryFood
    world.farmFood = saved.farmFood
  except IOError, OSError, ValueError:
    raise newException(MonsterError, "Cannot load Monster: " &
      getCurrentExceptionMsg())
