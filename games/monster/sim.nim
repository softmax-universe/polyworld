import
  std/[json, math, os],
  jsony, vmath,
  polyworld/daycycles,
  common, resources

when defined(emscripten):
  import windy

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
  ResourceSave = object
    version, seed: int
    creature: Creature
    stock: Inventory
    sources: seq[ResourceSource]
    households: seq[Household]
    villagers: seq[Villager]
  WorldSave = object
    version, seed: int
    tick: int32
    creature: Creature
    villages: seq[Village]
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

proc clearReach(map: MonsterMap, start, target: Vec2): bool =
  ## Checks direct contact without reaching through walls or blocked corners.
  let steps = max(1, int(ceil(length(target - start) * 12)))
  var previous = cell(start)
  if previous < 0 or not map.walkable(start):
    return false
  for i in 1 .. steps:
    let point = mix(start, target, i.float32 / steps.float32)
    let current = cell(point)
    if current < 0 or not map.walkable(point):
      return false
    let
      x = current mod MapSize
      z = current div MapSize
      px = previous mod MapSize
      pz = previous div MapSize
    if x != px and z != pz and
      (map.blocked[pz * MapSize + x] or map.blocked[z * MapSize + px]):
        return false
    previous = current
  true

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
      of AttackAction: "attack"
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
    creature: Creature(position: map.landmarks[home].position,
      energy: 100, health: 100),
    status: "Waiting for your voice"
  )
  const
    Capacities = [24, 12, 18, 36, 24, 48, 12, 12, 24, 18, 36, 24, 36]
    Kinds = [BerriesResource, GrainResource, FishResource, SoftwoodResource,
      HardwoodResource, StoneResource, GrainResource, GrainResource,
      BerriesResource, FishResource, SoftwoodResource, HardwoodResource,
      StoneResource]
    VillageNames = ["Willow", "Bracken", "Reedbank"]
  for i, id in VillageIds:
    let index = map.landmark(id)
    if index >= 0 or i == 0:
      result.villages.add Village(
        id: id, name: VillageNames[i],
        position: map.landmarks[if index >= 0: index else: home].position,
        health: 100
      )
  for i, id in SourceIds:
    let index = map.landmark(id)
    if index >= 0:
      result.sources.add ResourceSource(
        id: id, name: map.landmarks[index].name,
        position: map.landmarks[index].position,
        resource: Kinds[i], amount: Capacities[i],
        owner: (if id == "farm": 0
          elif id == "bracken_farm": result.villageIndex("bracken")
          elif id == "reedbank_farm": result.villageIndex("reedbank")
          else: -1),
        capacity: Capacities[i]
      )
  for i, id in HouseholdIds:
    let index = map.landmark(id)
    let village = result.villageIndex(VillageIds[i div 3])
    if index >= 0 and village >= 0:
      var house = Household(
        id: id, name: map.landmarks[index].name,
        position: map.landmarks[index].position,
        village: village,
        integrity: (if i mod 3 == 2: 35'f else: 100'f),
        fuel: (if i mod 3 == 1: 8'f else: 30'f)
      )
      house.stock[GrainResource] = 1
      result.households.add house
  const Names = ["Ada", "Ben", "Clara", "Dara", "Eli", "Finn",
    "Iris", "Jory", "Kira", "Leo", "Mina", "Ned", "Ora", "Pax",
    "Rosa", "Seth", "Tess", "Uri"]
  for i, id in VillagerIds:
    let house = result.householdIndex(HouseholdIds[i div 2])
    if house >= 0:
      let doorway = result.households[house].position
      let offset = doorway + vec2(if i mod 2 == 0: -0.4'f else: 0.4'f, 0'f)
      result.villagers.add Villager(
        id: id, name: Names[i], home: house,
        position: (if map.walkable(offset): offset else: doorway),
        hunger: (if i mod 2 == 0: 65'f else: 25'f), health: 100,
        sleepiness: InitialSleepiness,
        activity: "At home"
      )
  for house in result.households:
    result.villages[house.village].stock[GrainResource] = 4

proc destination*(world: World, action: CreatureAction): Vec2 =
  ## Resolves named people and places before numeric map coordinates.
  if action.target.len > 0:
    let person = world.villagerIndex(action.target)
    if person >= 0:
      return world.villagers[person].position
    let hall = world.villageIndex(action.target)
    if action.kind == AttackAction and hall >= 0:
      let approach = world.villages[hall].position + vec2(-3, -2)
      if world.map.walkable(approach):
        return approach
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
  of AttackAction:
    if world.villagerIndex(action.target) < 0 and
      world.householdIndex(action.target) < 0 and
      world.villageIndex(action.target) < 0 and
      world.sourceIndex(action.target) < 0:
        raise newException(MonsterError,
          "Attack a named villager, building, or resource source.")
    if world.targetDestroyed(action.target):
      raise newException(MonsterError, world.targetName(action.target) &
        " is already " & (if world.villagerIndex(action.target) >= 0:
          "dead." else: "destroyed."))
    if action.duration != 0:
      raise newException(MonsterError, "An attack is one strike; use zero duration.")
  of GatherAction:
    if world.sourceIndex(action.target) < 0:
      raise newException(MonsterError, "That place has no gathering source.")
    if world.targetDestroyed(action.target):
      raise newException(MonsterError, "That resource source was destroyed.")
  of GiveAction:
    if world.villageIndex(action.target) < 0 and
      world.householdIndex(action.target) < 0 and
      world.villagerIndex(action.target) < 0:
        raise newException(MonsterError,
          "Deliver to the hall, a household, or a villager.")
    if world.targetDestroyed(action.target):
      raise newException(MonsterError, world.targetName(action.target) &
        " can no longer receive supplies.")
  else:
    discard
  if action.kind in {MoveAction, GatherAction, GiveAction, RestAction,
    AttackAction}:
    if not world.map.walkable(world.destination(action)):
      raise newException(MonsterError, "That destination is not walkable.")

proc stop*(world: var World) =
  ## Immediately stops the current action and clears queued work.
  world.actions.setLen(0)
  world.path.setLen(0)
  world.active = false
  world.creature.moving = false
  world.elapsed = 0
  world.actionTime = 0
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
  world.actionTime = 0
  world.waypoint = 0
  world.path.setLen(0)
  let action = world.current
  case action.kind
  of MoveAction, GatherAction, GiveAction, RestAction, AttackAction:
    world.validateAction(action)
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

proc frighten(world: var World, position: Vec2, victim = -1, village = -1) =
  ## Interrupts nearby witnesses while preserving the supplies they carry.
  for i in 0 ..< world.villagers.len:
    if world.villagers[i].health <= 0:
      continue
    if i != victim and (length(world.villagers[i].position - position) > 8 or
      not world.map.clearReach(position, world.villagers[i].position)):
        continue
    world.villagers[i].fear = FrightDuration
    world.villagers[i].fearLevel = min(100'f,
      world.villagers[i].fearLevel + (if i == victim: 75'f else: 65'f))
    world.villagers[i].trust = max(0'f, world.villagers[i].trust - 45)
    world.villagers[i].sleeping = false
    world.villagers[i].task = IdleTask
    world.villagers[i].path.setLen(0)
    world.villagers[i].waypoint = 0
    world.villagers[i].elapsed = 0
    world.villagers[i].retry = 0
    world.villagers[i].moving = false
    world.villagers[i].activity = "Frightened by Moss"
    let village = world.households[world.villagers[i].home].village
    world.villages[village].alarm = 30
  if village >= 0:
    world.villages[village].alarm = 30

proc thank(world: var World, target: string, amount: int) =
  ## Rewards real deliveries among the people who receive their benefit.
  let
    person = world.villagerIndex(target)
    house = world.householdIndex(target)
    village = world.villageIndex(target)
  for i in 0 ..< world.villagers.len:
    if world.villagers[i].health <= 0:
      continue
    if i != person and world.villagers[i].home != house and
      (village < 0 or world.households[world.villagers[i].home].village != village):
        continue
    let gain = amount.float32 * (if i == person: 5'f else: 2'f)
    world.villagers[i].trust = min(100'f, world.villagers[i].trust + gain)
    world.villagers[i].fearLevel = max(0'f,
      world.villagers[i].fearLevel - gain * 1.5'f)
    if world.villagers[i].fearLevel < PanicFear:
      world.villagers[i].fear = 0

proc finishAction(world: var World) =
  ## Applies a completed action and reports only events that really happened.
  case world.current.kind
  of AttackAction:
    let
      target = world.current.target
      position = world.destination(world.current)
      person = world.villagerIndex(target)
      house = world.householdIndex(target)
      hall = world.villageIndex(target)
      source = world.sourceIndex(target)
      name = world.targetName(target)
    if world.targetDestroyed(target):
      world.reportProblem(world.current, name & " is already gone.")
      world.stop()
      return
    if length(position - world.creature.position) > AttackRange or
      not world.map.clearReach(world.creature.position, position):
        world.reportProblem(world.current, "The target moved out of reach.")
        world.stop()
        return
    var village = hall
    if person >= 0:
      let damage = min(AttackDamage, world.villagers[person].health)
      village = world.households[world.villagers[person].home].village
      world.villagers[person].health -= damage
      world.villagers[person].hitTime = HitDuration
      world.frighten(position, person, village)
      if world.villagers[person].health == 0:
        world.villagers[person].fear = 0
        world.villagers[person].sleeping = false
        world.villagers[person].task = IdleTask
        world.villagers[person].path.setLen(0)
        world.villagers[person].waypoint = 0
        world.villagers[person].moving = false
        world.villagers[person].supplyingHall = false
        world.villagers[person].activity = "Dead"
      world.event("Struck " & name & " for " & $int(damage) & " damage. " &
        name & (if world.villagers[person].health == 0: " died."
        else: " has " & $int(world.villagers[person].health) &
          " health remaining."))
    else:
      var remaining = 0'f
      if house >= 0:
        village = world.households[house].village
        world.households[house].integrity = max(0'f,
          world.households[house].integrity - AttackDamage)
        remaining = world.households[house].integrity
        if remaining == 0:
          world.households[house].stock = default(Inventory)
          world.households[house].fuel = 0
      elif hall >= 0:
        world.villages[hall].health = max(0'f,
          world.villages[hall].health - AttackDamage)
        remaining = world.villages[hall].health
        if remaining == 0:
          world.villages[hall].stock = default(Inventory)
      elif source >= 0:
        village = world.sources[source].owner
        world.sources[source].amount = 0
        world.sources[source].elapsed = 0
        world.sources[source].destroyed = true
      world.frighten(position, village = village)
      world.event(if remaining == 0: "Destroyed " & name & "."
        else: "Struck " & name & ". It has " & $int(remaining) &
          " health remaining.")
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
      amount = world.creature.cargo.total()
      house = world.householdIndex(target)
      person = world.villagerIndex(target)
      hall = world.villageIndex(target)
    var recipientVillage = hall
    if person >= 0:
      if world.villagers[person].cargo.total() +
        world.creature.cargo.total() > 12:
          world.reportProblem(world.current,
            world.villagers[person].name & " is already carrying too much.")
          world.stop()
          return
      world.creature.cargo.transfer(world.villagers[person].cargo)
      world.villagers[person].task =
        if world.villagers[person].sleeping: SleepTask else: IdleTask
      world.villagers[person].path.setLen(0)
      world.villagers[person].retry = 0
      world.villagers[person].moving = false
      world.villagers[person].supplyingHall = false
      recipientVillage = world.households[world.villagers[person].home].village
    elif house >= 0:
      if world.households[house].stock.total() +
        world.creature.cargo.total() > 4096:
          world.reportProblem(world.current, "That household's storage is full.")
          world.stop()
          return
      world.creature.cargo.transfer(world.households[house].stock)
      recipientVillage = world.households[house].village
    else:
      if world.villages[hall].stock.total() +
        world.creature.cargo.total() > 4096:
        world.reportProblem(world.current, "The village hall's storage is full.")
        world.stop()
        return
      world.creature.cargo.transfer(world.villages[hall].stock)
    world.villages[recipientVillage].gifts += amount
    world.thank(target, amount)
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
  let arrival = if task == ChatTask: position
    else: world.arrivalPosition(index, target, position)
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
  kinds: set[ResourceKind],
  forHall = false,
  meal = false,
  preferred: set[ResourceKind] = {}
): bool =
  ## Tries the shared hall before choosing the nearest reachable source.
  let
    home = world.villagers[index].home
    village = world.households[home].village
    hall = world.villages[village]
    destination =
      if forHall: hall.name & " hall"
      else: world.households[home].name
  if not forHall and hall.health > 0:
    for kind in kinds:
      if hall.stock[kind] > 0 and world.planVillager(index,
        (if meal: EatTask else: WithdrawTask),
        hall.id, hall.position,
        (if meal: "Going to the hall for a meal"
          else: "Fetching " & kind.resourceName() & " for " & destination),
        kind):
          world.villagers[index].supplyingHall = false
          return true
  var candidates: seq[int]
  for i, source in world.sources:
    if not source.destroyed and source.resource in kinds and source.amount > 0 and
      source.owner in [-1, village]:
      var claimed = 0
      for other, worker in world.villagers:
        if other != index and worker.health > 0 and worker.target == source.id:
          if worker.task == GatherTask:
            claimed += max(0, VillagerCarryLimit - worker.cargo.total())
          elif worker.task == EatTask:
            inc claimed
      if source.amount > claimed:
        candidates.add i
  let origin = world.villagers[index].position
  proc travelCost(source: ResourceSource): float32 =
    ## Favors varied jobs only when their travel distances are comparable.
    max(0'f, length(source.position - origin) -
      (if source.resource in preferred: 5'f else: 0'f))
  while candidates.len > 0:
    var nearest = 0
    for i in 1 ..< candidates.len:
      if travelCost(world.sources[candidates[i]]) <
        travelCost(world.sources[candidates[nearest]]):
          nearest = i
    let source = world.sources[candidates[nearest]]
    candidates.delete(nearest)
    if world.planVillager(index, (if meal: EatTask else: GatherTask),
      source.id, source.position,
      (if meal: "Finding a meal at " & source.name
        else: "Gathering " & source.resource.resourceName() & " for " &
          destination),
      source.resource):
        world.villagers[index].supplyingHall = forHall
        return true

proc seekMeal(world: var World, index: int): bool =
  ## Finds real food even when tools or gifts have filled the carrying space.
  let
    person = world.villagers[index]
    house = world.households[person.home]
  if person.cargo.foodTotal() > 0:
    return world.planVillager(index, EatTask, person.id,
      person.position, "Eating a meal")
  if house.integrity > 0 and house.stock.foodTotal() > 0:
    return world.planVillager(index, EatTask, house.id,
      house.position, "Going home for a meal")
  world.seekResource(index, {BerriesResource, GrainResource, FishResource},
    meal = person.cargo.total() >= VillagerCarryLimit)

proc wantsSleep(person: Villager, night: bool): bool {.raises: [].} =
  ## Prefers a night's rest well before daytime exhaustion sets in.
  person.sleepiness >=
    (if night: NightSleepThreshold else: DaySleepThreshold)

proc clearVillagerTask(person: var Villager) {.raises: [].} =
  ## Interrupts an errand or sleep without changing carried supplies.
  person.task = IdleTask
  person.sleeping = false
  person.moving = false
  person.path.setLen(0)
  person.waypoint = 0
  person.elapsed = 0
  person.retry = 0

proc workOffset(person: Villager): int {.raises: [].} =
  ## Gives each resident a stable preference without changing saved games.
  for i, id in VillagerIds:
    if person.id == id:
      return i
  person.home * 2

proc householdReserves(world: World, home: int): Inventory =
  ## Counts household supplies and trips already bringing supplies home.
  result = world.households[home].stock
  for worker in world.villagers:
    if worker.health <= 0 or worker.home != home or worker.supplyingHall:
      continue
    for kind in ResourceKind:
      result[kind] += worker.cargo[kind]
    if worker.task in {GatherTask, WithdrawTask}:
      result[worker.resource] +=
        max(0, VillagerCarryLimit - worker.cargo.total())

proc chooseVillageWork(world: var World, index: int): bool =
  ## Shares varied gathering jobs while accounting for supplies on the way.
  let
    person = world.villagers[index]
    village = world.households[person.home].village
    hall = world.villages[village]
  if hall.health <= 0 or person.cargo.total() > 0:
    return false
  var reserves = hall.stock
  for worker in world.villagers:
    if worker.health <= 0 or not worker.supplyingHall or
      world.households[worker.home].village != village:
        continue
    for kind in ResourceKind:
      reserves[kind] += worker.cargo[kind]
    if worker.task == GatherTask:
      reserves[worker.resource] +=
        max(0, VillagerCarryLimit - worker.cargo.total())
  const Jobs = [GrainResource, FishResource, SoftwoodResource,
    HardwoodResource, StoneResource, BerriesResource]
  const
    FoodKinds = {BerriesResource, GrainResource, FishResource}
    WoodKinds = {SoftwoodResource, HardwoodResource}
    FoodReserve = VillageWorkReserves[0] + VillageWorkReserves[1] +
      VillageWorkReserves[2]
    WoodReserve = VillageWorkReserves[3] + VillageWorkReserves[4]
  var residents = 0
  for worker in world.villagers:
    if worker.health > 0 and world.households[worker.home].village == village:
      inc residents
  if world.villageSupplies(village).foodTotal() < residents and
    reserves.foodTotal() < residents and
    world.seekResource(index, FoodKinds, forHall = true):
      return true
  for offset in 0 ..< Jobs.len:
    let kind = Jobs[(person.workOffset() + offset) mod Jobs.len]
    let kinds = case kind
      of BerriesResource .. FishResource: FoodKinds
      of SoftwoodResource, HardwoodResource: WoodKinds
      of StoneResource: {StoneResource}
    let needed = case kind
      of BerriesResource .. FishResource: reserves.foodTotal() < FoodReserve
      of SoftwoodResource, HardwoodResource:
        reserves[SoftwoodResource] + reserves[HardwoodResource] < WoodReserve
      of StoneResource: reserves[kind] < VillageWorkReserves[kind.ord]
    if needed and world.seekResource(index, kinds, forHall = true,
      preferred = {kind}):
        return true

proc chatWithNeighbor(world: var World, index: int): bool =
  ## Arranges a short conversation only between free, nearby neighbors.
  let
    person = world.villagers[index]
    village = world.households[person.home].village
    night = isNight(clockHour(world.tick, TickRate.int32))
  for other, neighbor in world.villagers:
    if other == index or neighbor.health <= 0 or neighbor.fear > 0 or
      neighbor.sleeping or neighbor.wantsSleep(night) or
      neighbor.hunger >= MealHunger or neighbor.cargo.total() > 0 or
      neighbor.task notin {IdleTask, WanderTask} or
      world.households[neighbor.home].village != village or
      length(neighbor.position - person.position) > 10:
        continue
    let
      middle = (person.position + neighbor.position) / 2
      first = middle + vec2(-0.7'f, 0)
      second = middle + vec2(0.7'f, 0)
    if not world.map.walkable(first) or not world.map.walkable(second):
      continue
    if world.planVillager(index, ChatTask, neighbor.id, first,
      "Meeting " & neighbor.name):
      if world.planVillager(other, ChatTask, person.id, second,
        "Meeting " & person.name):
          return true
      world.villagers[index].clearVillagerTask()

proc chooseVillageLeisure(world: var World, index: int): bool =
  ## Alternates small chores, neighborly chats, and walks near the village.
  let
    person = world.villagers[index]
    house = world.households[person.home]
    hall = world.villages[house.village]
    phase = world.tick.int div (18 * TickRate) + person.workOffset()
  if phase mod 3 == 2 and world.chatWithNeighbor(index):
    return true
  if phase mod 3 == 0 and house.integrity > 0:
    if phase mod 2 == 0:
      let farmId = if house.village == 0: "farm" else: hall.id & "_farm"
      let farm = world.sourceIndex(farmId)
      if farm >= 0 and not world.sources[farm].destroyed and
        world.planVillager(index, ChoreTask, farmId,
          world.sources[farm].position, "Tending the crops"):
            return true
    if world.planVillager(index, ChoreTask, house.id,
      house.position, "Sweeping outside " & house.name):
        return true
  for attempt in 0 ..< 8:
    let
      angle = (phase + attempt).float32 * PI.float32 / 4
      destination = hall.position +
        vec2(cos(angle), sin(angle)) * (4 + phase mod 4).float32
    if world.planVillager(index, WanderTask, person.id, destination,
      "Strolling around " & hall.name):
        return true
  false

proc chooseVillagerTask(world: var World, index: int) =
  ## Meets urgent needs before work, maintenance, and village social life.
  let
    person = world.villagers[index]
    house = world.households[person.home]
    reserves = world.householdReserves(person.home)
    hall = world.villages[house.village]
    deliverHall = (person.supplyingHall and hall.health > 0) or
      house.integrity <= 0
    canDeliver = if deliverHall: hall.health > 0 else: house.integrity > 0
    deliveryId = if deliverHall: hall.id else: house.id
    deliveryPosition = if deliverHall: hall.position else: house.position
    deliveryName = if deliverHall: hall.name & " hall" else: house.name
    night = isNight(clockHour(world.tick, TickRate.int32))
  var planned = false
  if person.cargo.total() == 0:
    world.villagers[index].supplyingHall = false
  if person.hunger >= UrgentHunger or
    (night and person.wantsSleep(night) and person.hunger >= BedtimeHunger):
      planned = world.seekMeal(index)
  if not planned and person.hunger < UrgentHunger and person.wantsSleep(night):
    if house.integrity > 0:
      planned = world.planVillager(index, SleepTask, house.id,
        house.position, "Going home to sleep")
    elif hall.health > 0:
      planned = world.planVillager(index, SleepTask, hall.id,
        hall.position, "Seeking shelter at the hall")
    else:
      planned = world.planVillager(index, SleepTask, person.id,
        person.position, "Sleeping outside; home destroyed")
  if not planned and person.cargo.total() >= VillagerCarryLimit and
    person.cargo.foodTotal() == 0 and canDeliver:
      planned = world.planVillager(index, DeliverTask, deliveryId,
        deliveryPosition, "Taking " & person.cargo.inventoryText() &
          " to " & deliveryName)
  if not planned and person.hunger >= MealHunger:
    planned = world.seekMeal(index)
  if not planned and person.cargo.total() > 0 and canDeliver:
    planned = world.planVillager(index, DeliverTask, deliveryId,
      deliveryPosition, "Taking " & person.cargo.inventoryText() &
        " to " & deliveryName)
  if not planned and person.hunger < MealHunger:
    if house.integrity <= 0:
      if hall.health > 0 and person.cargo.total() < VillagerCarryLimit and
        hall.stock.foodTotal() < 12:
          planned = world.seekResource(index,
            {BerriesResource, GrainResource, FishResource}, forHall = true)
    elif reserves.foodTotal() < HouseholdFoodReserve:
      planned = world.seekResource(index,
        {BerriesResource, GrainResource, FishResource})
    if not planned and house.integrity > 0 and house.fuel < 35:
      if house.stock[SoftwoodResource] + house.stock[HardwoodResource] > 0:
        planned = world.planVillager(index, RefuelTask, house.id,
          house.position, "Tending the hearth")
      else:
        planned = world.seekResource(index,
          {SoftwoodResource, HardwoodResource})
    if not planned and house.integrity > 0 and house.integrity < 100:
      if house.stock[StoneResource] >= 2 and
        house.stock[HardwoodResource] >= 1:
          planned = world.planVillager(index, RepairTask, house.id,
            house.position, "Repairing " & house.name)
      elif house.stock[StoneResource] < 2:
        planned = world.seekResource(index, {StoneResource})
      else:
        planned = world.seekResource(index, {HardwoodResource})
    if not planned and house.stock.foodTotal() >= HouseholdFoodReserve and
      house.fuel >= 35 and
      house.integrity >= 100 and world.tick >= 30 * TickRate and
      (world.tick.int div (20 * TickRate) + person.workOffset()) mod 4 == 0:
        planned = world.chooseVillageLeisure(index)
    if not planned:
      planned = world.chooseVillageWork(index)
    if not planned and person.cargo.total() == 0:
      planned = world.chooseVillageLeisure(index)
  if not planned:
    world.villagers[index].retry = 5
    world.villagers[index].moving = false
    world.villagers[index].activity =
      if person.hunger >= MealHunger: "Looking for food"
      elif person.wantsSleep(night): "Looking for a way home to sleep"
      elif house.integrity <= 0: "Homeless; seeking shelter"
      elif house.integrity < 100: "Waiting for repair supplies"
      elif house.fuel < 35: "Looking for firewood"
      else: "Resting; household supplied"

proc flee(world: var World, index: int) =
  ## Chooses reachable shelter away from the creature without dropping cargo.
  let
    person = world.villagers[index]
    house = world.households[person.home]
    danger = world.creature.position
  var candidates: seq[Vec2]
  if house.integrity > 0 and
    length(house.position - danger) > length(person.position - danger) + 2:
    candidates.add house.position
  var away = person.position - danger
  if lengthSq(away) < 0.01'f:
    away = vec2(1, 0)
  else:
    away = normalize(away)
  for angle in [0'f, 0.7'f, -0.7'f, 1.3'f, -1.3'f]:
    let direction = vec2(away.x * cos(angle) - away.y * sin(angle),
      away.x * sin(angle) + away.y * cos(angle))
    for distance in [8'f, 5'f, 3'f]:
      candidates.add person.position + direction * distance
  for target in candidates:
    if world.planVillager(index, FleeTask, person.id, target,
      "Fleeing from Moss"):
        return
  world.villagers[index].task = FleeTask
  world.villagers[index].path.setLen(0)
  world.villagers[index].moving = false
  world.villagers[index].retry = 2
  world.villagers[index].activity = "Frightened; nowhere to run"

proc finishVillagerTask(world: var World, index: int) =
  ## Transfers or consumes real supplies only after reaching their location.
  let
    person = world.villagers[index]
    home = person.home
    village = world.households[home].village
  case person.task
  of GatherTask:
    let source = world.sourceIndex(person.target)
    if source >= 0 and not world.sources[source].destroyed:
      let amount = min(max(0, VillagerCarryLimit - person.cargo.total()),
        world.sources[source].amount)
      world.sources[source].amount -= amount
      world.villagers[index].cargo[person.resource] += amount
      world.villages[village].harvested += amount
  of WithdrawTask:
    if world.villages[village].health > 0:
      let amount = min(max(0, VillagerCarryLimit - person.cargo.total()),
        world.villages[village].stock[person.resource])
      world.villages[village].stock[person.resource] -= amount
      world.villagers[index].cargo[person.resource] += amount
  of DeliverTask:
    if person.target == world.villages[village].id:
      if world.villages[village].health > 0 and
        world.villages[village].stock.total() + person.cargo.total() <= 4096:
        world.villagers[index].cargo.transfer(world.villages[village].stock)
        world.villagers[index].supplyingHall = false
      else:
        world.villagers[index].retry = 5
        world.villagers[index].activity = "Hall storage is full"
    elif world.households[home].integrity > 0 and
      world.households[home].stock.total() + person.cargo.total() <= 4096:
      world.villagers[index].cargo.transfer(world.households[home].stock)
      world.villagers[index].supplyingHall = false
    else:
      world.villagers[index].retry = 5
      world.villagers[index].activity = "Home storage is full"

  of EatTask:
    var ate = false
    if person.target == person.id:
      ate = world.villagers[index].cargo.eat()
    elif person.target == world.households[home].id and
      world.households[home].integrity > 0:
      ate = world.households[home].stock.eat()
    elif person.target == world.villages[village].id and
      world.villages[village].health > 0:
      ate = world.villages[village].stock.eat()
    else:
      let source = world.sourceIndex(person.target)
      if source >= 0 and not world.sources[source].destroyed and
        world.sources[source].amount > 0 and
        world.sources[source].resource in
          {BerriesResource, GrainResource, FishResource}:
            dec world.sources[source].amount
            inc world.villages[village].harvested
            ate = true
    if ate:
      world.villagers[index].hunger = max(0'f, person.hunger - MealRelief)
  of RefuelTask:
    if world.households[home].integrity > 0 and world.households[home].fuel < 35:
      if world.households[home].stock[SoftwoodResource] > 0:
        dec world.households[home].stock[SoftwoodResource]
        world.households[home].fuel += 35
      elif world.households[home].stock[HardwoodResource] > 0:
        dec world.households[home].stock[HardwoodResource]
        world.households[home].fuel += 50
  of RepairTask:
    if world.households[home].integrity > 0 and
      world.households[home].integrity < 100 and
      world.households[home].stock[StoneResource] >= 2 and
      world.households[home].stock[HardwoodResource] >= 1:
        world.households[home].stock[StoneResource] -= 2
        dec world.households[home].stock[HardwoodResource]
        world.households[home].integrity = min(100'f,
          world.households[home].integrity + 35)
  of ChoreTask, WanderTask, ChatTask:
    world.villagers[index].retry = 2 + (person.workOffset() mod 4).float32
    world.villagers[index].activity = "Taking a short break"
  of IdleTask, FleeTask, SleepTask:
    discard
  world.villagers[index].task = IdleTask
  world.villagers[index].moving = false
  world.villagers[index].path.setLen(0)
  world.villagers[index].elapsed = 0

proc stepVillage(world: var World) =
  ## Advances regrowth, household consumption, and independent NPC errands.
  const Dt = 1'f / TickRate.float32
  let night = isNight(clockHour(world.tick, TickRate.int32))
  for source in world.sources.mitems:
    if source.destroyed or source.resource == StoneResource or
      source.amount >= source.capacity:
      source.elapsed = 0
      continue
    source.elapsed += Dt
    let interval = RegrowthSeconds[source.resource.ord]
    if source.elapsed >= interval:
      source.elapsed -= interval
      inc source.amount
  for house in world.households.mitems:
    house.fuel = max(0'f, house.fuel - Dt * 0.08'f)
  for village in world.villages.mitems:
    village.alarm = max(0'f, village.alarm - Dt)
  for i in 0 ..< world.villagers.len:
    world.villagers[i].hitTime = max(0'f, world.villagers[i].hitTime - Dt)
    if world.villagers[i].health <= 0:
      world.villagers[i].moving = false
      world.villagers[i].sleeping = false
      world.villagers[i].task = IdleTask
      world.villagers[i].activity = "Dead"
      continue
    world.villagers[i].hunger = min(100'f,
      world.villagers[i].hunger + Dt * VillagerHungerRate)
    if not world.villagers[i].sleeping:
      world.villagers[i].sleepiness = min(100'f,
        world.villagers[i].sleepiness + Dt * (if night: 0.5'f else: 0.24'f))
    let
      distance = length(world.villagers[i].position - world.creature.position)
      baseline = max(0'f, InitialFear - world.villagers[i].trust * 0.7'f)
      receivingGift = world.active and world.current.kind == GiveAction and
        world.current.target == world.villagers[i].id
    if world.villagers[i].fearLevel > baseline:
      world.villagers[i].fearLevel = max(baseline,
        world.villagers[i].fearLevel - Dt * 0.08'f)
    if world.villagers[i].fearLevel >= PanicFear and distance < 8 and
      world.map.clearReach(world.creature.position, world.villagers[i].position):
        world.villagers[i].fear = max(world.villagers[i].fear, 2'f)
    if world.villagers[i].task != IdleTask and
      world.targetDestroyed(world.villagers[i].target):
        world.villagers[i].clearVillagerTask()
    if world.villagers[i].sleeping and
      world.households[world.villagers[i].home].integrity <= 0:
        let hall = world.villages[
          world.households[world.villagers[i].home].village]
        if hall.health > 0 and
          length(world.villagers[i].position - hall.position) > 1.1'f:
            world.villagers[i].clearVillagerTask()
    if world.villagers[i].fear > 0:
      world.villagers[i].sleeping = false
      world.villagers[i].fear = max(0'f, world.villagers[i].fear - Dt)
      world.villagers[i].retry = max(0'f, world.villagers[i].retry - Dt)
      if world.villagers[i].task != FleeTask or
        (world.villagers[i].waypoint >= world.villagers[i].path.len and
        world.villagers[i].retry <= 0 and
        length(world.villagers[i].position - world.creature.position) < 5):
          world.flee(i)
      world.villagers[i].moving = walk(
        world.villagers[i].position, world.villagers[i].facing,
        world.villagers[i].path, world.villagers[i].waypoint, Dt * 2.6'f
      )
      if not world.villagers[i].moving:
        world.villagers[i].activity = "Hiding from Moss"
      continue
    if not receivingGift and world.villagers[i].trust < 20 and
      world.villagers[i].fearLevel >= 20 and distance < 2 and
      world.map.clearReach(world.creature.position, world.villagers[i].position):
        world.villagers[i].sleeping = false
        if world.villagers[i].task != FleeTask:
          world.flee(i)
        world.villagers[i].moving = walk(world.villagers[i].position,
          world.villagers[i].facing, world.villagers[i].path,
          world.villagers[i].waypoint, Dt * 1.7'f)
        world.villagers[i].activity = "Keeping a wary distance from Moss"
        continue
    if world.villagers[i].sleeping:
      if world.villagers[i].hunger >= UrgentHunger or
        (not night and world.villagers[i].sleepiness <= 10):
          world.villagers[i].clearVillagerTask()
      else:
        world.villagers[i].sleepiness = max(0'f,
          world.villagers[i].sleepiness - Dt * 0.8'f)
        world.villagers[i].activity =
          if world.households[world.villagers[i].home].integrity > 0:
            "Sleeping at home"
          elif world.villages[
            world.households[world.villagers[i].home].village].health > 0:
              "Sleeping at the hall"
          else: "Sleeping outside"
        continue
    if world.villagers[i].task == FleeTask:
      world.villagers[i].clearVillagerTask()
    let
      person = world.villagers[i]
      findingMeal = person.task == EatTask or
        (person.task in {GatherTask, WithdrawTask} and
        person.resource in {BerriesResource, GrainResource, FishResource} and
        not person.supplyingHall)
      freeingSpace = person.task == DeliverTask and
        person.cargo.total() >= VillagerCarryLimit
      hungry = person.hunger >= UrgentHunger and
        not findingMeal and not freeingSpace
      tired = person.hunger < UrgentHunger and person.wantsSleep(night) and
        person.task notin {SleepTask, EatTask} and
        not (findingMeal and person.hunger >= BedtimeHunger)
    if person.task != IdleTask and (hungry or tired):
      world.villagers[i].clearVillagerTask()
    if world.villagers[i].task == IdleTask:
      world.villagers[i].retry = max(0'f, world.villagers[i].retry - Dt)
      if world.villagers[i].retry <= 0:
        world.chooseVillagerTask(i)
    if world.villagers[i].task == IdleTask:
      continue
    world.villagers[i].moving = walk(
      world.villagers[i].position, world.villagers[i].facing,
      world.villagers[i].path, world.villagers[i].waypoint,
      Dt * (if world.villagers[i].task in {ChoreTask, WanderTask, ChatTask}:
        1.1'f else: 1.7'f)
    )
    if world.villagers[i].moving:
      continue
    if world.villagers[i].task == SleepTask:
      world.villagers[i].sleeping = true
      world.villagers[i].activity = "Sleeping"
      continue
    if world.villagers[i].task == ChatTask:
      let partner = world.villagerIndex(world.villagers[i].target)
      if partner < 0 or world.villagers[partner].task != ChatTask or
        world.villagers[partner].target != world.villagers[i].id:
          world.villagers[i].clearVillagerTask()
          continue
      let direction = world.villagers[partner].position -
        world.villagers[i].position
      world.villagers[i].facing = arctan2(direction.x, direction.y)
      if world.villagers[partner].waypoint < world.villagers[partner].path.len:
        world.villagers[i].activity =
          "Waiting for " & world.villagers[partner].name
        continue
      world.villagers[i].activity =
        "Chatting with " & world.villagers[partner].name
    if world.villagers[i].task == GatherTask:
      let source = world.sourceIndex(world.villagers[i].target)
      if source < 0 or world.sources[source].amount <= 0:
        world.villagers[i].clearVillagerTask()
        continue
      let kind = world.villagers[i].resource
      let work = case kind
        of BerriesResource: "Picking berries"
        of GrainResource: "Harvesting grain"
        of FishResource: "Fishing"
        of SoftwoodResource: "Chopping pine wood"
        of HardwoodResource: "Chopping oak wood"
        of StoneResource: "Mining stone"
      world.villagers[i].activity = work & " at " & world.sources[source].name
      let direction = world.sources[source].position - world.villagers[i].position
      world.villagers[i].facing = if kind == FishResource:
          (if world.sources[source].id == "south_fish": -PI.float32 / 2
            else: PI.float32 / 2)
        else: arctan2(direction.x, direction.y)
    world.villagers[i].elapsed += Dt
    let duration = case world.villagers[i].task
      of GatherTask:
        GatherSeconds[world.villagers[i].resource.ord]
      of RepairTask: 8'f
      of RefuelTask: 3'f
      of EatTask: 2'f
      of ChoreTask: 10'f
      of WanderTask: 4'f
      of ChatTask: 12'f
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
  world.actionTime += Dt
  let person = world.villagerIndex(world.current.target)
  if world.current.kind in {AttackAction, GatherAction, GiveAction} and
    world.targetDestroyed(world.current.target):
      world.reportProblem(world.current,
        world.targetName(world.current.target) & " is already gone.")
      world.stop()
      return
  if world.current.kind == AttackAction and world.actionTime > AttackTimeout:
    world.reportProblem(world.current,
      "I could not get close enough to " & world.targetName(world.current.target) & ".")
    world.stop()
    return
  if person >= 0 and world.current.kind in {GiveAction, AttackAction} and
    world.villagers[person].health <= 0:
      world.reportProblem(world.current,
        world.villagers[person].name & " is already dead.")
      world.stop()
      return
  if person >= 0 and world.current.kind in {MoveAction, GiveAction, AttackAction}:
    let target = world.villagers[person].position
    let reach = if world.current.kind == AttackAction: AttackRange else: 1.25'f
    if length(target - world.creature.position) <= reach and
      (world.current.kind notin {AttackAction, GiveAction} or
      world.map.clearReach(world.creature.position, target)):
      if world.current.kind in {AttackAction, GiveAction} and
        world.villagers[person].moving:
        world.path = @[target]
      else:
        world.path.setLen(0)
      world.waypoint = 0
      let delta = target - world.creature.position
      if lengthSq(delta) > 0.001'f:
        world.creature.facing = arctan2(delta.x, delta.y)
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
    if world.current.kind notin {AttackAction, GiveAction} or
      (world.current.kind == GiveAction and person < 0) or
      length(world.destination(world.current) - world.creature.position) >
        (if world.current.kind == AttackAction: AttackRange else: 1.25'f) or
        not world.map.clearReach(world.creature.position,
        world.destination(world.current)):
          return
  world.creature.moving = world.waypoint < world.path.len
  if world.current.kind == AttackAction:
    let target = world.destination(world.current)
    if length(target - world.creature.position) > AttackRange or
      not world.map.clearReach(world.creature.position, target):
        world.elapsed = 0
        return
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
      of AttackAction:
        AttackWindup
  world.status = case world.current.kind
    of GatherAction: "Gathering " &
      world.sources[world.sourceIndex(world.current.target)].resource.resourceName()
    of GiveAction: "Delivering to " & world.targetName(world.current.target)
    of RestAction: "Resting in the grass"
    of EatAction: "Having a snack"
    of DanceAction: "Dancing for you"
    of WaitAction: "Waiting here"
    of AttackAction: "Attacking " & world.targetName(world.current.target)
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
      id, name, resource, owner: string
      x, z: float32
      amount: int
      destroyed: bool
    Home = object
      id, name, supplies, village: string
      x, z, condition, warmth: float32
      destroyed: bool
    Person = object
      id, name, home, village, carrying, activity, attitude: string
      x, z, hunger, sleepiness, health, fear, trust, fearLevel: float32
      alive, sleeping: bool
    Settlement = object
      id, name, hallSupplies, totalSupplies: string
      x, z, alarm, health: float32
      wellbeing, harvested, gifts, living, casualties: int
      destroyed: bool
    Observation = object
      x, z, energy, health, mapHalf, hour: float32
      carrying, status, note: string
      carryLimit, day: int
      night: bool
      villages: seq[Settlement]
      places: seq[Place]
      sources: seq[Supply]
      households: seq[Home]
      villagers: seq[Person]
  var state = Observation(
    x: world.creature.position.x,
    z: world.creature.position.y,
    energy: world.creature.energy,
    health: world.creature.health,
    carrying: world.creature.cargo.inventoryText(),
    carryLimit: CarryLimit,
    mapHalf: MapHalf,
    hour: clockHour(world.tick, TickRate.int32),
    day: hudClock(world.tick, TickRate.int32).day,
    night: isNight(clockHour(world.tick, TickRate.int32)),
    status: world.status,
    note: "Gather fills remaining carrying space from a named source. " &
      "Farm grain belongs to the villagers; berries and fish are wild. " &
      "Pine and oak are fallen wood; stone is loose quarry stone. " &
      "Give transfers all carried supplies to hall/village, a hut, or a " &
      "named person. People take materials home and eat when hungry. " &
      "Hunger and sleepiness fill toward 100 when needs go unmet. " &
      "Villagers go home to sleep much sooner at night, from 18:00 to 06:00. " &
      "Homeless residents seek shelter at an intact hall or sleep outside. " &
      "Sleepiness falls while sleeping; urgent hunger or " &
      "danger wakes them. One full day lasts five real minutes. " &
      "Residents eat about two meals per day and eat before bed when " &
      "hungry. Huts consume firewood; pine gives 35 warmth, oak 50. " &
      "Each repair uses two stone and one oak wood for 35 condition. " &
      "Villagers act independently; you cannot order them around. " &
      "Attack strikes one named living villager, hut, or village hall once " &
      "for 35 damage after walking within reach. Huts use condition as " &
      "health. Zero health is permanent death or destruction. Attack a " &
      "resource source once to destroy its stock and stop its regrowth. " &
      "Destroyed buildings lose stored supplies and cannot receive gifts, " &
      "shelter residents, or be rebuilt yet. Injured villagers and nearby " &
      "witnesses flee; their fear rises quickly and trust falls. " &
      "Villagers start wary of Moss. Real gifts to them, their household, " &
      "or village hall raise trust and reduce fear. Fear fades slowly; " &
      "trust does not recover without help. High-fear villagers flee when " &
      "Moss approaches. Neutral trust begins at 20, friendly at 45, " &
      "and allied at 75. " &
      "Dead villagers cannot work or receive gifts; their cargo stays " &
      "with their body. There is no healing or revival yet. Stop cancels " &
      "the current plan before any unfinished strike lands. " &
      "Our village means Willow. Bracken and Reedbank are independent " &
      "neighbors competing for the same wild supplies and finite stone. " &
      "People use only their own village hall and farms, but everyone " &
      "can gather shared resources. Residents share harvesting, fishing, " &
      "woodcutting, and mining jobs, carrying two supplies at a time. " &
      "Hall reserves target 14 food, 10 wood, and 6 stone; homes keep " &
      "about four food. Nearby foods and fuel woods can substitute for " &
      "each other. Shortages take priority over optional stockpiling. " &
      "Gathering takes 6 to 12 seconds plus travel per two-unit load. " &
      "When supplied, people tend crops, sweep, " &
      "stroll around their village, and chat with neighbors. " &
      "Wellbeing averages actual " &
      "hunger, home condition, and warmth, not military strength. " &
      "Berries, grain, fish and fallen wood replenish slowly; stone is finite. " &
      "North is negative z, east is positive x."
  )
  for i, village in world.villages:
    var living, casualties: int
    for person in world.villagers:
      if world.households[person.home].village == i:
        if person.health > 0: inc living
        else: inc casualties
    state.villages.add Settlement(id: village.id, name: village.name,
      hallSupplies: village.stock.inventoryText(),
      totalSupplies: world.villageSupplies(i).inventoryText(),
      x: village.position.x, z: village.position.y,
      wellbeing: world.villageWellbeing(i), harvested: village.harvested,
      gifts: village.gifts, alarm: village.alarm, health: village.health,
      living: living, casualties: casualties, destroyed: village.health <= 0)
  for place in world.map.landmarks:
    state.places.add Place(id: place.id, name: place.name,
      x: place.position.x, z: place.position.y)
  for source in world.sources:
    state.sources.add Supply(id: source.id, name: source.name,
      resource: source.resource.resourceName(), amount: source.amount,
      destroyed: source.destroyed,
      owner: (if source.owner < 0: "shared"
        else: world.villages[source.owner].id),
      x: source.position.x, z: source.position.y)
  for house in world.households:
    state.households.add Home(id: house.id, name: house.name,
      supplies: house.stock.inventoryText(), condition: house.integrity,
      destroyed: house.integrity <= 0,
      village: world.villages[house.village].id,
      warmth: house.fuel, x: house.position.x, z: house.position.y)
  for person in world.villagers:
    state.villagers.add Person(id: person.id, name: person.name,
      home: world.households[person.home].id,
      village: world.villages[world.households[person.home].village].id,
      carrying: person.cargo.inventoryText(), activity: person.activity,
      hunger: person.hunger, sleepiness: person.sleepiness,
      sleeping: person.sleeping, health: person.health, fear: person.fear,
      trust: person.trust, fearLevel: person.fearLevel,
      attitude: person.attitude(),
      alive: person.health > 0, x: person.position.x, z: person.position.y)
  state.toJson()

proc saveWorld*(world: World, path: string) =
  ## Saves inventories and needs while excluding unfinished route state.
  try:
    when not defined(emscripten):
      createDir(path.parentDir)
    var saved = WorldSave(
      version: 8, seed: world.map.seed, tick: world.tick,
      creature: world.creature,
      villages: world.villages, sources: world.sources,
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
    when defined(emscripten):
      setConfig("Polyworld Monster", path, saved.toJson())
    else:
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

proc validateCombatFields(body: string) =
  ## Rejects missing combat state instead of turning absent health into death.
  let document = parseJson(body)
  if document.kind != JObject or not document.hasKey("villagers") or
    not document.hasKey("villages") or
    document["villagers"].kind != JArray or
    document["villages"].kind != JArray:
      raise newException(MonsterError, "Monster combat save is incomplete.")
  for person in document["villagers"]:
    if person.kind != JObject:
      raise newException(MonsterError, "Monster combat save is incomplete.")
    for field in ["health", "fear", "hitTime"]:
      if not person.hasKey(field) or person[field].kind notin {JInt, JFloat}:
        raise newException(MonsterError, "Monster combat save is incomplete.")
  for village in document["villages"]:
    if village.kind != JObject or not village.hasKey("alarm") or
      village["alarm"].kind notin {JInt, JFloat}:
        raise newException(MonsterError, "Monster combat save is incomplete.")

proc validateNeedsFields(body: string) =
  ## Requires an explicit clock and needs instead of accepting missing zeros.
  let document = parseJson(body)
  if not document.hasKey("tick") or document["tick"].kind != JInt or
    document["tick"].getBiggestInt() < 0 or
    document["tick"].getBiggestInt() > high(int32).int64:
      raise newException(MonsterError, "Monster clock save is invalid.")
  for person in document["villagers"]:
    if not person.hasKey("sleepiness") or
      person["sleepiness"].kind notin {JInt, JFloat} or
      not person.hasKey("sleeping") or person["sleeping"].kind != JBool:
        raise newException(MonsterError, "Monster needs save is incomplete.")

proc validateHealthFields(body: string) =
  ## Requires explicit health for Moss and each village hall in newer saves.
  let document = parseJson(body)
  if not document.hasKey("creature") or
    document["creature"].kind != JObject or
    not document["creature"].hasKey("health") or
    document["creature"]["health"].kind notin {JInt, JFloat}:
      raise newException(MonsterError, "Monster health save is incomplete.")
  for village in document["villages"]:
    if not village.hasKey("health") or
      village["health"].kind notin {JInt, JFloat}:
        raise newException(MonsterError, "Monster health save is incomplete.")

proc validateRelationshipFields(body: string) =
  ## Requires explicit destruction and relationship state in newer saves.
  let document = parseJson(body)
  if not document.hasKey("sources") or document["sources"].kind != JArray:
    raise newException(MonsterError, "Monster destruction save is incomplete.")
  for source in document["sources"]:
    if source.kind != JObject or not source.hasKey("destroyed") or
      source["destroyed"].kind != JBool:
        raise newException(MonsterError,
          "Monster destruction save is incomplete.")
  for person in document["villagers"]:
    for field in ["trust", "fearLevel"]:
      if not person.hasKey(field) or
        person[field].kind notin {JInt, JFloat}:
          raise newException(MonsterError,
            "Monster relationship save is incomplete.")

proc restoreWorld*(world: var World, path: string) =
  ## Atomically restores physical state and resumes independent NPC needs.
  try:
    var body: string
    when defined(emscripten):
      body = getConfig("Polyworld Monster", path)
      if body.len == 0:
        return
      if body.len > 256 * 1024:
        raise newException(MonsterError, "Monster save is too large.")
    else:
      if not fileExists(path):
        return
      if getFileSize(path) > 256 * 1024:
        raise newException(MonsterError, "Monster save is too large.")
      body = readFile(path)
    let
      saved = body.fromJson(WorldSave)
    if saved.seed != world.map.seed or saved.version notin 1 .. 8:
      raise newException(MonsterError, "Monster save version or seed differs.")
    if saved.version >= 4:
      validateCombatFields(body)
    if saved.version >= 6:
      validateNeedsFields(body)
    if saved.version >= 7:
      validateHealthFields(body)
    if saved.version >= 8:
      validateRelationshipFields(body)
    var restored = newWorld(world.map)
    if saved.version >= 6:
      restored.tick = saved.tick
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
      restored.villages[0].stock = default(Inventory)
      restored.villages[0].stock[BerriesResource] = old.villageFood
      let
        berries = restored.sourceIndex("berries")
        farm = restored.sourceIndex("farm")
      if berries >= 0:
        restored.sources[berries].amount = old.berryFood
      if farm >= 0:
        restored.sources[farm].amount = old.farmFood
    else:
      let migrating = saved.version == 2
      var state = saved
      if migrating:
        let old = body.fromJson(ResourceSave)
        state.villages = restored.villages
        state.villages[0].stock = old.stock
        state.creature.position = world.map.legacyPosition(old.creature.position)
        for person in state.villagers.mitems:
          person.position = world.map.legacyPosition(person.position)
          person.supplyingHall = false
      elif saved.version < 5:
        state.creature.position = world.map.legacyPosition(
          state.creature.position)
        for person in state.villagers.mitems:
          person.position = world.map.legacyPosition(person.position)
      if saved.version < 5:
        for source in state.sources.mitems:
          let index = restored.sourceIndex(source.id)
          if index >= 0 and
            ((source.id == "fish" and source.position == vec2(15, -6)) or
            (source.id == "south_fish" and source.position == vec2(22, 30))):
              source.position = restored.sources[index].position
      if saved.version < 4:
        for village in state.villages.mitems:
          village.alarm = 0
        for person in state.villagers.mitems:
          person.health = 100
          person.fear = 0
          person.hitTime = 0
      if saved.version < 6:
        for person in state.villagers.mitems:
          person.sleepiness = InitialSleepiness
          person.sleeping = false
      if saved.version < 7:
        state.creature.health = 100
        for village in state.villages.mitems:
          village.health = 100
      if saved.version < 8:
        for source in state.sources.mitems:
          source.destroyed = false
        for village in state.villages.mitems:
          if village.health <= 0:
            village.stock = default(Inventory)
        for house in state.households.mitems:
          if house.integrity <= 0:
            house.stock = default(Inventory)
            house.fuel = 0
        for person in state.villagers.mitems:
          person.trust = 0
          person.fearLevel = if person.fear > 0: 80'f else: InitialFear
      if not world.map.validPosition(state.creature.position) or
        not state.creature.cargo.validInventory(CarryLimit) or
        not (state.creature.energy >= 0 and state.creature.energy <= 100) or
        not (state.creature.health >= 0 and state.creature.health <= 100) or
        classify(state.creature.facing) in {fcNan, fcInf, fcNegInf} or
        state.villages.len != restored.villages.len or
        state.sources.len !=
          (if migrating: min(6, restored.sources.len) else: restored.sources.len) or
        state.households.len !=
          (if migrating: min(3, restored.households.len) else: restored.households.len) or
        state.villagers.len !=
          (if migrating: min(6, restored.villagers.len) else: restored.villagers.len):
          raise newException(MonsterError, "Monster save contains invalid state.")
      restored.creature = state.creature
      for i, village in state.villages:
        let expected = restored.villages[i]
        if village.id != expected.id or village.position != expected.position or
          not village.stock.validInventory() or
          village.harvested notin 0 .. 1000000000 or
          village.gifts notin 0 .. 1000000000 or
          not (village.health >= 0 and village.health <= 100) or
          not (village.alarm >= 0 and village.alarm <= 30):
            raise newException(MonsterError, "Monster village save is invalid.")
        restored.villages[i].stock = village.stock
        restored.villages[i].harvested = village.harvested
        restored.villages[i].gifts = village.gifts
        restored.villages[i].alarm = village.alarm
        restored.villages[i].health = village.health
      for i, source in state.sources:
        let expected = restored.sources[i]
        if source.id != expected.id or source.resource != expected.resource or
          source.position != expected.position or
          source.capacity != expected.capacity or
          (not migrating and source.owner != expected.owner) or
          source.amount notin 0 .. expected.capacity or
          (source.destroyed and source.amount != 0) or
          not (source.elapsed >= 0 and
            source.elapsed <= max(50'f, RegrowthSeconds[source.resource.ord])):
            raise newException(MonsterError, "Monster resource save is invalid.")
        restored.sources[i].amount = source.amount
        restored.sources[i].elapsed = source.elapsed
        restored.sources[i].destroyed = source.destroyed
      for i, house in state.households:
        let expected = restored.households[i]
        if house.id != expected.id or house.position != expected.position or
          (not migrating and house.village != expected.village) or
          not house.stock.validInventory() or
          not (house.integrity >= 0 and house.integrity <= 100) or
          not (house.fuel >= 0 and house.fuel <= 100):
            raise newException(MonsterError, "Monster household save is invalid.")
        restored.households[i].stock = house.stock
        restored.households[i].integrity = house.integrity
        restored.households[i].fuel = house.fuel
      for i, person in state.villagers:
        let expected = restored.villagers[i]
        if person.id != expected.id or person.home != expected.home or
          not world.map.validPosition(person.position) or
          not person.cargo.validInventory(12) or
          not (person.hunger >= 0 and person.hunger <= 100) or
          not (person.sleepiness >= 0 and person.sleepiness <= 100) or
          not (person.health >= 0 and person.health <= 100) or
          not (person.fear >= 0 and person.fear <= FrightDuration) or
          not (person.trust >= 0 and person.trust <= 100) or
          not (person.fearLevel >= 0 and person.fearLevel <= 100) or
          not (person.hitTime >= 0 and person.hitTime <= HitDuration) or
          classify(person.facing) in {fcNan, fcInf, fcNegInf}:
            raise newException(MonsterError, "Monster villager save is invalid.")
        let
          house = restored.households[person.home]
          hall = restored.villages[house.village]
          restingPlace = if house.integrity > 0: house.position
            elif hall.health > 0: hall.position else: person.position
        if person.sleeping and (person.health <= 0 or person.fear > 0 or
          length(person.position - restingPlace) > 1.1'f):
            raise newException(MonsterError, "Monster sleeping save is invalid.")
        restored.villagers[i].position = person.position
        restored.villagers[i].facing = person.facing
        restored.villagers[i].cargo = person.cargo
        restored.villagers[i].hunger = person.hunger
        restored.villagers[i].sleepiness = person.sleepiness
        restored.villagers[i].sleeping = person.sleeping
        restored.villagers[i].supplyingHall = person.supplyingHall
        restored.villagers[i].health = person.health
        restored.villagers[i].fear = person.fear
        restored.villagers[i].trust = person.trust
        restored.villagers[i].fearLevel = person.fearLevel
        restored.villagers[i].hitTime = person.hitTime
        if person.sleeping:
          restored.villagers[i].task = SleepTask
          restored.villagers[i].target = if house.integrity > 0: house.id
            elif hall.health > 0: hall.id else: person.id
          restored.villagers[i].activity = if house.integrity > 0:
            "Sleeping at home"
          elif hall.health > 0: "Sleeping at the hall"
          else: "Sleeping outdoors"
        if person.health <= 0:
          restored.villagers[i].activity = "Dead"
          restored.villagers[i].fear = 0
          restored.villagers[i].supplyingHall = false
    restored.creature.moving = false
    world = restored
  except IOError, OSError, ValueError:
    raise newException(MonsterError, "Cannot load Monster: " &
      getCurrentExceptionMsg())
