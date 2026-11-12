import
  std/[math, os],
  jsony, vmath,
  common, resources

const
  MoveSpeed = 3.2'f
  Neighbors = [
    (-1, 0), (1, 0), (0, -1), (0, 1),
    (-1, -1), (1, -1), (-1, 1), (1, 1)
  ]

type
  LegacyCreature = object
    position: Vec2
    facing: float32
    moving: bool
    food: int
    energy: float32
  LegacySave = object
    version, seed: int
    creature: LegacyCreature
    villageFood, berryFood, farmFood: int
  WorldSave = object
    version, seed: int
    creature: Creature
    stock: Inventory
    sources: seq[ResourceSource]
    households: seq[Household]
    villagers: seq[Villager]

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
  ## Starts a creature, resource sources, and households with physical needs.
  let home = map.landmark("home")
  if home < 0:
    raise newException(MonsterError, "Monster map has no home.")
  result = World(
    map: map,
    creature: Creature(position: map.landmarks[home].position, energy: 100),
    status: "Waiting for your voice"
  )
  const Capacities = [24, 12, 18, 36, 24, 48]
  for i, id in SourceIds:
    let index = map.landmark(id)
    if index >= 0:
      result.sources.add ResourceSource(
        id: id, name: map.landmarks[index].name,
        position: map.landmarks[index].position,
        resource: ResourceKind(i), amount: Capacities[i],
        capacity: Capacities[i]
      )
  for i, id in HouseholdIds:
    let index = map.landmark(id)
    if index >= 0:
      var house = Household(
        id: id, name: map.landmarks[index].name,
        position: map.landmarks[index].position,
        integrity: (if i == 2: 35'f else: 100'f),
        fuel: (if i == 1: 8'f else: 30'f)
      )
      house.stock[GrainResource] = 1
      result.households.add house
  const Names = ["Ada", "Ben", "Clara", "Dara", "Eli", "Finn"]
  for i, id in VillagerIds:
    let house = result.householdIndex(HouseholdIds[i div 2])
    if house >= 0:
      let doorway = result.households[house].position
      let offset = doorway + vec2(if i mod 2 == 0: -0.4'f else: 0.4'f, 0'f)
      result.villagers.add Villager(
        id: id, name: Names[i], home: house,
        position: (if map.walkable(offset): offset else: doorway),
        hunger: (if i mod 2 == 0: 65'f else: 25'f),
        activity: "At home"
      )
  if result.villagers.len > 0:
    result.stock[GrainResource] = 4

proc destination*(world: World, action: CreatureAction): Vec2 =
  ## Resolves named people and places before numeric map coordinates.
  if action.target.len > 0:
    let person = world.villagerIndex(action.target)
    if person >= 0:
      return world.villagers[person].position
    let index = world.map.landmark(
      if action.target == "hall": "village" else: action.target
    )
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
    if world.sourceIndex(action.target) < 0:
      raise newException(MonsterError, "That place has no gathering source.")
  of GiveAction:
    if action.target notin ["village", "hall"] and
      world.householdIndex(action.target) < 0 and
      world.villagerIndex(action.target) < 0:
        raise newException(MonsterError,
          "Deliver to the hall, a household, or a villager.")
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
        "Going to " & world.targetName(action.target)
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
    let index = world.sourceIndex(world.current.target)
    let kind = world.sources[index].resource
    let amount = min(CarryLimit - world.creature.cargo.total(),
      world.sources[index].amount)
    if amount <= 0:
      world.reportProblem(world.current,
        if world.creature.cargo.total() >= CarryLimit:
          "Carrying capacity is full."
        else:
          "There is no " & kind.resourceName() & " left at " &
            world.targetName(world.current.target) & "."
      )
      world.stop()
      return
    world.sources[index].amount -= amount
    world.creature.cargo[kind] += amount
    world.event("Gathered " & $amount & " " & kind.resourceName() &
      " from " & world.targetName(world.current.target) & ".")
  of GiveAction:
    if world.creature.cargo.total() == 0:
      world.reportProblem(world.current, "Carrying no supplies to give.")
      world.stop()
      return
    let
      target = world.current.target
      description = world.creature.cargo.inventoryText()
      house = world.householdIndex(target)
      person = world.villagerIndex(target)
    if person >= 0:
      if world.villagers[person].cargo.total() +
        world.creature.cargo.total() > 12:
          world.reportProblem(world.current,
            world.villagers[person].name & " is already carrying too much.")
          world.stop()
          return
      world.creature.cargo.transfer(world.villagers[person].cargo)
      world.villagers[person].task = IdleTask
      world.villagers[person].path.setLen(0)
      world.villagers[person].retry = 0
      world.villagers[person].moving = false
    elif house >= 0:
      if world.households[house].stock.total() +
        world.creature.cargo.total() > 4096:
          world.reportProblem(world.current, "That household's storage is full.")
          world.stop()
          return
      world.creature.cargo.transfer(world.households[house].stock)
    else:
      if world.stock.total() + world.creature.cargo.total() > 4096:
        world.reportProblem(world.current, "The village hall's storage is full.")
        world.stop()
        return
      world.creature.cargo.transfer(world.stock)
    world.event("Delivered " & description & " to " &
      world.targetName(target) & ".")
  of EatAction:
    if world.creature.cargo.eat():
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

proc walk(
  position: var Vec2,
  facing: var float32,
  path: seq[Vec2],
  waypoint: var int,
  distance: float32
): bool =
  ## Advances an actor along a collision-checked route without teleporting.
  var remainingDistance = distance
  while waypoint < path.len and remainingDistance > 0:
    let
      delta = path[waypoint] - position
      remaining = length(delta)
    if remaining > 0.001'f:
      facing = arctan2(delta.x, delta.y)
    if remaining <= remainingDistance:
      position = path[waypoint]
      remainingDistance -= remaining
      inc waypoint
    else:
      position += delta / remaining * remainingDistance
      remainingDistance = 0
  waypoint < path.len

proc arrivalPosition(
  world: World,
  index: int,
  target: string,
  position: Vec2
): Vec2 =
  ## Gives residents nearby standing places without stacking their bodies.
  result = position
  let person = world.villagers[index]
  if target != person.id:
    let offset =
      if target == world.households[person.home].id:
        vec2(if index mod 2 == 0: -0.65'f else: 0.65'f, 0.25'f)
      else:
        vec2(cos(index.float32 * PI.float32 / 3),
          sin(index.float32 * PI.float32 / 3)) * 0.8'f
    if world.map.walkable(position + offset):
      result = position + offset

proc planVillager(
  world: var World,
  index: int,
  task: VillagerTask,
  target: string,
  position: Vec2,
  activity: string,
  resource = BerriesResource
): bool =
  ## Starts a reachable autonomous errand or leaves the villager to retry.
  if not world.map.walkable(position):
    world.villagers[index].activity = "Cannot reach supplies; resting"
    return false
  let arrival = world.arrivalPosition(index, target, position)
  try:
    let path = world.map.route(world.villagers[index].position, arrival)
    world.villagers[index].task = task
    world.villagers[index].target = target
    world.villagers[index].resource = resource
    world.villagers[index].path = path
    world.villagers[index].waypoint = 0
    world.villagers[index].elapsed = 0
    world.villagers[index].activity = activity
    result = true
  except MonsterError:
    world.villagers[index].activity = "Cannot reach supplies; resting"

proc seekResource(
  world: var World,
  index: int,
  kinds: set[ResourceKind]
): bool =
  ## Tries the shared hall before choosing the nearest reachable source.
  let
    home = world.villagers[index].home
    houseName = world.households[home].name
    hall = world.map.landmark("village")
  if hall >= 0:
    for kind in kinds:
      if world.stock[kind] > 0 and world.planVillager(index, WithdrawTask,
        "village", world.map.landmarks[hall].position,
        "Fetching " & kind.resourceName() & " for " & houseName, kind):
          return true
  var candidates: seq[int]
  for i, source in world.sources:
    if source.resource in kinds and source.amount > 0:
      candidates.add i
  while candidates.len > 0:
    var nearest = 0
    for i in 1 ..< candidates.len:
      if lengthSq(world.sources[candidates[i]].position -
        world.villagers[index].position) <
        lengthSq(world.sources[candidates[nearest]].position -
        world.villagers[index].position):
          nearest = i
    let source = world.sources[candidates[nearest]]
    candidates.delete(nearest)
    if world.planVillager(index, GatherTask, source.id, source.position,
      "Gathering " & source.resource.resourceName() & " for " & houseName,
      source.resource):
        return true

proc chooseVillagerTask(world: var World, index: int) =
  ## Chooses a personal or household need without accepting player commands.
  let
    person = world.villagers[index]
    house = world.households[person.home]
  var planned = false
  if person.cargo.total() >= VillagerCarryLimit and
    person.cargo.foodTotal() == 0:
      planned = world.planVillager(index, DeliverTask, house.id,
        house.position, "Taking " & person.cargo.inventoryText() &
          " to " & house.name)
  if not planned and person.hunger >= 50:
    if person.cargo.foodTotal() > 0:
      planned = world.planVillager(index, EatTask, person.id,
        person.position, "Eating a meal")
    elif house.stock.foodTotal() > 0:
      planned = world.planVillager(index, EatTask, house.id,
        house.position, "Going home for a meal")
    else:
      planned = world.seekResource(index,
        {BerriesResource, GrainResource, FishResource})
  if not planned and person.cargo.total() > 0:
    planned = world.planVillager(index, DeliverTask, house.id,
      house.position, "Taking " & person.cargo.inventoryText() &
        " to " & house.name)
  if not planned and person.hunger < 50:
    if house.stock.foodTotal() < 4:
      planned = world.seekResource(index,
        {BerriesResource, GrainResource, FishResource})
    elif house.fuel < 35:
      if house.stock[SoftwoodResource] + house.stock[HardwoodResource] > 0:
        planned = world.planVillager(index, RefuelTask, house.id,
          house.position, "Tending the hearth")
      else:
        planned = world.seekResource(index,
          {SoftwoodResource, HardwoodResource})
    elif house.integrity < 100:
      if house.stock[StoneResource] >= 2 and
        house.stock[HardwoodResource] >= 1:
          planned = world.planVillager(index, RepairTask, house.id,
            house.position, "Repairing " & house.name)
      elif house.stock[StoneResource] < 2:
        planned = world.seekResource(index, {StoneResource})
      else:
        planned = world.seekResource(index, {HardwoodResource})
  if not planned and person.hunger < 50 and house.stock.foodTotal() >= 4 and
    house.fuel >= 35 and house.integrity >= 100:
      let resting = world.arrivalPosition(index, house.id, house.position)
      if length(person.position - resting) > 0.1'f:
        planned = world.planVillager(index, DeliverTask, house.id,
          house.position, "Going home to rest")
  if not planned:
    world.villagers[index].retry = 5
    world.villagers[index].moving = false
    world.villagers[index].activity =
      if person.hunger >= 50: "Looking for food"
      elif house.integrity < 100: "Waiting for repair supplies"
      elif house.fuel < 35: "Looking for firewood"
      else: "Resting; household supplied"

proc finishVillagerTask(world: var World, index: int) =
  ## Transfers or consumes real supplies only after reaching their location.
  let
    person = world.villagers[index]
    home = person.home
  case person.task
  of GatherTask:
    let source = world.sourceIndex(person.target)
    if source >= 0:
      let amount = min(max(0, VillagerCarryLimit - person.cargo.total()),
        world.sources[source].amount)
      world.sources[source].amount -= amount
      world.villagers[index].cargo[person.resource] += amount
  of WithdrawTask:
    let amount = min(max(0, VillagerCarryLimit - person.cargo.total()),
      world.stock[person.resource])
    world.stock[person.resource] -= amount
    world.villagers[index].cargo[person.resource] += amount
  of DeliverTask:
    if world.households[home].stock.total() + person.cargo.total() <= 4096:
      world.villagers[index].cargo.transfer(world.households[home].stock)
    else:
      world.villagers[index].retry = 5
      world.villagers[index].activity = "Home storage is full"

  of EatTask:
    let ate =
      if world.villagers[index].cargo.foodTotal() > 0:
        world.villagers[index].cargo.eat()
      else:
        world.households[home].stock.eat()
    if ate:
      world.villagers[index].hunger = max(0'f, person.hunger - 45)
  of RefuelTask:
    if world.households[home].fuel < 35:
      if world.households[home].stock[SoftwoodResource] > 0:
        dec world.households[home].stock[SoftwoodResource]
        world.households[home].fuel += 35
      elif world.households[home].stock[HardwoodResource] > 0:
        dec world.households[home].stock[HardwoodResource]
        world.households[home].fuel += 50
  of RepairTask:
    if world.households[home].integrity < 100 and
      world.households[home].stock[StoneResource] >= 2 and
      world.households[home].stock[HardwoodResource] >= 1:
        world.households[home].stock[StoneResource] -= 2
        dec world.households[home].stock[HardwoodResource]
        world.households[home].integrity = min(100'f,
          world.households[home].integrity + 35)
  of IdleTask:
    discard
  world.villagers[index].task = IdleTask
  world.villagers[index].moving = false
  world.villagers[index].path.setLen(0)
  world.villagers[index].elapsed = 0

proc stepVillage(world: var World) =
  ## Advances regrowth, household consumption, and independent NPC errands.
  const Dt = 1'f / TickRate.float32
  for source in world.sources.mitems:
    if source.resource == StoneResource or source.amount >= source.capacity:
      source.elapsed = 0
      continue
    source.elapsed += Dt
    let interval =
      case source.resource
      of BerriesResource: 12'f
      of GrainResource: 18'f
      of FishResource: 15'f
      of SoftwoodResource: 35'f
      of HardwoodResource: 50'f
      of StoneResource: 0'f
    if source.elapsed >= interval:
      source.elapsed -= interval
      inc source.amount
  for house in world.households.mitems:
    house.fuel = max(0'f, house.fuel - Dt * 0.08'f)
  for i in 0 ..< world.villagers.len:
    world.villagers[i].hunger = min(100'f,
      world.villagers[i].hunger + Dt * 0.12'f)
    if world.villagers[i].task == IdleTask:
      world.villagers[i].retry = max(0'f, world.villagers[i].retry - Dt)
      if world.villagers[i].retry <= 0:
        world.chooseVillagerTask(i)
    if world.villagers[i].task == IdleTask:
      continue
    world.villagers[i].moving = walk(
      world.villagers[i].position, world.villagers[i].facing,
      world.villagers[i].path, world.villagers[i].waypoint, Dt * 1.7'f
    )
    if world.villagers[i].moving:
      continue
    world.villagers[i].elapsed += Dt
    let duration = case world.villagers[i].task
      of GatherTask: 3'f
      of RepairTask: 8'f
      of RefuelTask: 3'f
      of EatTask: 2'f
      else: 1'f
    if world.villagers[i].elapsed >= duration:
      world.finishVillagerTask(i)

proc step*(world: var World) =
  ## Advances one fixed tick without waiting for language-model requests.
  const Dt = 1'f / TickRate.float32
  inc world.tick
  world.stepVillage()
  if not world.active and world.actions.len > 0:
    try:
      world.beginAction()
    except MonsterError:
      world.reportProblem(world.current, getCurrentExceptionMsg())
      world.stop()
  if not world.active:
    return
  let person = world.villagerIndex(world.current.target)
  if person >= 0 and world.current.kind in {MoveAction, GiveAction}:
    let target = world.villagers[person].position
    if length(target - world.creature.position) <= 1.25'f:
      world.path.setLen(0)
      world.waypoint = 0
    else:
      world.elapsed = 0
      if world.path.len == 0 or world.waypoint >= world.path.len or
        (world.tick mod 10 == 0 and length(target - world.path[^1]) > 0.5'f):
          try:
            world.path = world.map.route(world.creature.position, target)
            world.waypoint = 0
          except MonsterError:
            world.reportProblem(world.current, getCurrentExceptionMsg())
            world.stop()
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
    of GatherAction: "Gathering " &
      world.sources[world.sourceIndex(world.current.target)].resource.resourceName()
    of GiveAction: "Delivering to " & world.targetName(world.current.target)
    of RestAction: "Resting in the grass"
    of EatAction: "Having a snack"
    of DanceAction: "Dancing for you"
    of WaitAction: "Waiting here"
    else: "Listening"
  if world.elapsed >= duration:
    world.finishAction()

proc observation*(world: World): string =
  ## Describes resource ownership, living households, and reachable targets.
  type
    Place = object
      id, name: string
      x, z: float32
    Supply = object
      id, name, resource: string
      x, z: float32
      amount: int
    Home = object
      id, name, supplies: string
      x, z, condition, warmth: float32
    Person = object
      id, name, home, carrying, activity: string
      x, z, hunger: float32
    Observation = object
      x, z, energy: float32
      carrying, hallSupplies, status, note: string
      carryLimit: int
      places: seq[Place]
      sources: seq[Supply]
      households: seq[Home]
      villagers: seq[Person]
  var state = Observation(
    x: world.creature.position.x,
    z: world.creature.position.y,
    energy: world.creature.energy,
    carrying: world.creature.cargo.inventoryText(),
    carryLimit: CarryLimit,
    hallSupplies: world.stock.inventoryText(),
    status: world.status,
    note: "Gather fills remaining carrying space from a named source. " &
      "Farm grain belongs to the villagers; berries and fish are wild. " &
      "Pine and oak are fallen wood; stone is loose quarry stone. " &
      "Give transfers all carried supplies to hall/village, a hut, or a " &
      "named person. People take materials home and eat when hungry. " &
      "Huts consume food and firewood; pine gives 35 warmth, oak 50. " &
      "Each repair uses two stone and one oak wood for 35 condition. " &
      "Villagers act independently; you cannot order them around. " &
      "Berries, grain, fish and fallen wood replenish slowly; stone is finite. " &
      "North is negative z, east is positive x."
  )
  for place in world.map.landmarks:
    state.places.add Place(id: place.id, name: place.name,
      x: place.position.x, z: place.position.y)
  for source in world.sources:
    state.sources.add Supply(id: source.id, name: source.name,
      resource: source.resource.resourceName(), amount: source.amount,
      x: source.position.x, z: source.position.y)
  for house in world.households:
    state.households.add Home(id: house.id, name: house.name,
      supplies: house.stock.inventoryText(), condition: house.integrity,
      warmth: house.fuel, x: house.position.x, z: house.position.y)
  for person in world.villagers:
    state.villagers.add Person(id: person.id, name: person.name,
      home: world.households[person.home].id,
      carrying: person.cargo.inventoryText(), activity: person.activity,
      hunger: person.hunger, x: person.position.x, z: person.position.y)
  state.toJson()

proc saveWorld*(world: World, path: string) =
  ## Saves inventories and needs while excluding unfinished route state.
  try:
    createDir(path.parentDir)
    var saved = WorldSave(
      version: 2, seed: world.map.seed, creature: world.creature,
      stock: world.stock, sources: world.sources,
      households: world.households, villagers: world.villagers
    )
    for person in saved.villagers.mitems:
      person.path.setLen(0)
      person.task = IdleTask
      person.moving = false
      person.waypoint = 0
      person.elapsed = 0
      person.retry = 0
      person.target = ""
    writeFile(path & ".tmp", saved.toJson())
    moveFile(path & ".tmp", path)
  except IOError, OSError:
    raise newException(MonsterError, "Cannot save Monster: " &
      getCurrentExceptionMsg())

proc validInventory(stock: Inventory, limit = 4096): bool {.raises: [].} =
  ## Rejects negative counts and values too large for a bounded save.
  for amount in stock:
    if amount < 0 or amount > limit:
      return false
  stock.total() <= limit

proc validPosition(map: MonsterMap, position: Vec2): bool {.raises: [].} =
  ## Validates both finite coordinates and scenery clearance.
  map.walkable(position)

proc legacyPosition(map: MonsterMap, position: Vec2): Vec2 =
  ## Finds nearby ground when new scenery occupies an older saved position.
  if map.validPosition(position):
    return position
  if cell(position) < 0:
    raise newException(MonsterError, "Monster save has an invalid position.")
  let home = map.landmark("home")
  for radius in 1 .. 4:
    for dz in -radius .. radius:
      for dx in -radius .. radius:
        if abs(dx) != radius and abs(dz) != radius:
          continue
        let candidate = position + vec2(dx.float32, dz.float32)
        if map.walkable(candidate):
          try:
            discard map.route(map.landmarks[home].position, candidate)
            return candidate
          except MonsterError:
            discard
  raise newException(MonsterError, "Monster save has no nearby open ground.")

proc restoreWorld*(world: var World, path: string) =
  ## Atomically restores physical state and resumes independent NPC needs.
  if not fileExists(path):
    return
  try:
    if getFileSize(path) > 256 * 1024:
      raise newException(MonsterError, "Monster save is too large.")
    let
      body = readFile(path)
      saved = body.fromJson(WorldSave)
    if saved.seed != world.map.seed or saved.version notin [1, 2]:
      raise newException(MonsterError, "Monster save version or seed differs.")
    var restored = newWorld(world.map)
    if saved.version == 1:
      let old = body.fromJson(LegacySave)
      if old.creature.food notin 0 .. CarryLimit or
        not (old.creature.energy >= 0 and old.creature.energy <= 100) or
        classify(old.creature.facing) in {fcNan, fcInf, fcNegInf} or
        old.villageFood notin 0 .. 36 or old.berryFood notin 0 .. 24 or
        old.farmFood notin 0 .. 12:
          raise newException(MonsterError, "Monster save contains invalid state.")
      restored.creature.position = world.map.legacyPosition(
        old.creature.position)
      restored.creature.facing = old.creature.facing
      restored.creature.energy = old.creature.energy
      restored.creature.cargo[BerriesResource] = old.creature.food
      restored.stock = default(Inventory)
      restored.stock[BerriesResource] = old.villageFood
      let
        berries = restored.sourceIndex("berries")
        farm = restored.sourceIndex("farm")
      if berries >= 0:
        restored.sources[berries].amount = old.berryFood
      if farm >= 0:
        restored.sources[farm].amount = old.farmFood
    else:
      if not world.map.validPosition(saved.creature.position) or
        not saved.creature.cargo.validInventory(CarryLimit) or
        not (saved.creature.energy >= 0 and saved.creature.energy <= 100) or
        classify(saved.creature.facing) in {fcNan, fcInf, fcNegInf} or
        not saved.stock.validInventory() or
        saved.sources.len != restored.sources.len or
        saved.households.len != restored.households.len or
        saved.villagers.len != restored.villagers.len:
          raise newException(MonsterError, "Monster save contains invalid state.")
      restored.creature = saved.creature
      restored.stock = saved.stock
      for i, source in saved.sources:
        let expected = restored.sources[i]
        if source.id != expected.id or source.resource != expected.resource or
          source.position != expected.position or
          source.capacity != expected.capacity or
          source.amount notin 0 .. expected.capacity or
          not (source.elapsed >= 0 and source.elapsed <= 50):
            raise newException(MonsterError, "Monster resource save is invalid.")
        restored.sources[i].amount = source.amount
        restored.sources[i].elapsed = source.elapsed
      for i, house in saved.households:
        let expected = restored.households[i]
        if house.id != expected.id or house.position != expected.position or
          not house.stock.validInventory() or
          not (house.integrity >= 0 and house.integrity <= 100) or
          not (house.fuel >= 0 and house.fuel <= 100):
            raise newException(MonsterError, "Monster household save is invalid.")
        restored.households[i].stock = house.stock
        restored.households[i].integrity = house.integrity
        restored.households[i].fuel = house.fuel
      for i, person in saved.villagers:
        let expected = restored.villagers[i]
        if person.id != expected.id or person.home != expected.home or
          not world.map.validPosition(person.position) or
          not person.cargo.validInventory(12) or
          not (person.hunger >= 0 and person.hunger <= 100) or
          classify(person.facing) in {fcNan, fcInf, fcNegInf}:
            raise newException(MonsterError, "Monster villager save is invalid.")
        restored.villagers[i].position = person.position
        restored.villagers[i].facing = person.facing
        restored.villagers[i].cargo = person.cargo
        restored.villagers[i].hunger = person.hunger
    restored.creature.moving = false
    world = restored
  except IOError, OSError, ValueError:
    raise newException(MonsterError, "Cannot load Monster: " &
      getCurrentExceptionMsg())
