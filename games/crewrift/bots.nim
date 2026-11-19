## Bounded BASIC policies with visible observations and queued game inputs.

import
  bassy,
  polyworld/[policyhosts, pathing, rngs],
  sim, maps, replays

const
  DefaultBotName* = "base.bas"
  DefaultBotSource* = staticRead("players/base.bas")
  BotDataNames = [
    "selfSlot", "worldTick", "phase", "myX", "myY", "myAlive", "myRole",
    "myKillCooldown", "playerTotal", "taskTotal", "assignmentTotal",
    "bodyTotal", "chatTotal", "meetingCaller", "meetingKind", "voteTimer",
    "voteDuration", "voteFinalize", "chatCooldown", "myLastChatTick",
    "myVote", "myCursor", "killRange", "reportRange", "tickRate",
    "routeStuck", "routeLength"
  ]

type
  Bot* = object
    runtime*: Runtime
    path*: seq[MapPoint]
    waypoint*, stuck*: int
    previous*, goal*: MapPoint
    hasGoal*: bool
    rng*: Rng
    failed*: bool
    lastError*: string
    decisions*: int
    lastWork*, lastInstructions*: int64
    chat*: string
    choice*: int
    output: InputState
    searched: bool
    dataIds: array[BotDataNames.len, int32]
  Navigator* = object
    layer*: QuadLayer
    parents: seq[int32]
    queue: seq[int32]

var
  activeBot: ptr Bot
  activeWorld: ptr SimServer
  activeNav: ptr Navigator
  activeSlot: int
  previousInput: InputState
  visibleBodies: seq[int]

template world(): untyped = activeWorld[]
template own(): untyped = activeWorld[].players[activeSlot]

proc botLimits*(): Limits =
  ## Bounds each policy's source, persistent memory, and per-tick work.
  result = defaultLimits()
  result.maxSourceBytes = 128 * 1024
  result.maxCodeInstructions = 50_000
  result.maxArrays = 32
  result.maxArrayElements = 4096
  result.maxGlobals = 512
  result.maxHostData = 64
  result.maxHostFunctions = 96
  result.maxRoutines = 64
  result.maxParameters = 8
  result.maxRegisters = 256
  result.maxCallDepth = 16
  result.maxSyntaxDepth = 32
  result.maxStrings = 512
  result.maxStringLength = 4096
  result.maxStringBytes = 128 * 1024
  result.maxMemoryBytes = 2 * 1024 * 1024
  result.maxInstructions = 50_000
  result.maxWorkUnits = 100_000
  result.maxPrintBytes = 4096
  result.maxPrintEvents = 64

proc findPath*(
  nav: var Navigator,
  sim: SimServer,
  start, goal: MapPoint
): seq[MapPoint] =
  ## Finds Polyworld tile routes, retaining pixel paths for older recordings.
  if not sim.isWalkable(start.x, start.y) or
    not sim.isWalkable(goal.x, goal.y):
      return
  if sim.gameMap.path == "map1":
    if nav.layer == nil:
      nav.layer = sim.buildShipMap().layer
    installImmutableLayers(@[nav.layer])
    let tiles = findTilePath(
      0, start.x div PixelsPerTile, start.y div PixelsPerTile,
      0, goal.x div PixelsPerTile, goal.y div PixelsPerTile
    )
    if tiles.len == 0:
      return
    for tile in tiles:
      result.add MapPoint(
        x: tile.x.int * PixelsPerTile + PixelsPerTile div 2,
        y: tile.z.int * PixelsPerTile + PixelsPerTile div 2
      )
    result.add goal
    return
  nav.parents.setLen(MapWidth * MapHeight)
  nav.queue.setLen(MapWidth * MapHeight)
  for parent in nav.parents.mitems:
    parent = -1
  let
    first = mapIndex(start.x, start.y)
    last = mapIndex(goal.x, goal.y)
  var
    head = 0
    tail = 1
  nav.queue[0] = first.int32
  nav.parents[first] = first.int32
  while head < tail and nav.parents[last] < 0:
    let current = nav.queue[head].int
    inc head
    let
      x = current mod MapWidth
      y = current div MapWidth
    for offset in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
      let
        nx = x + offset[0]
        ny = y + offset[1]
      if not sim.isWalkable(nx, ny):
        continue
      let next = mapIndex(nx, ny)
      if nav.parents[next] < 0:
        nav.parents[next] = current.int32
        nav.queue[tail] = next.int32
        inc tail
  if nav.parents[last] < 0:
    return
  var
    current = last
    reversed: seq[MapPoint]
  while current != first:
    reversed.add MapPoint(x: current mod MapWidth, y: current div MapWidth)
    current = nav.parents[current].int
  for i in countdown(reversed.high, 0):
    result.add reversed[i]

proc roomName(sim: SimServer, x, y: int): string =
  ## Names a public map room or its connecting corridor.
  for room in sim.rooms:
    if x >= room.x and x < room.x + room.w and
      y >= room.y and y < room.y + room.h:
        return room.name
  "the corridor"

proc validPlayer(index: int32): bool =
  ## Rejects a policy's out-of-range roster index.
  index >= 0 and index.int < world().players.len

proc visiblePlayer(index: int32): bool =
  ## Keeps hidden players out of all position and life-state queries.
  if not validPlayer(index):
    return false
  let player = world().players[index]
  world().phase != Playing or index.int == activeSlot or
    (player.alive and world().visibleFrom(activeSlot, player.x, player.y))

proc validTask(index: int32): bool =
  ## Rejects a policy's out-of-range public station index.
  index >= 0 and index.int < world().tasks.len

proc bodyIndex(index: int32): int =
  ## Maps only a visible-body index to the authoritative body list.
  if index >= 0 and index.int < visibleBodies.len:
    visibleBodies[index]
  else:
    -1

proc validChat(index: int32): bool =
  ## Restricts transcript queries to the public meeting feed.
  world().phase == Voting and index >= 0 and
    index.int < world().chatMessages.len

proc navigate(x, y: int32): int32 =
  ## Follows a requested public map point without choosing a destination.
  if world().phase != Playing or x < 0 or x >= MapWidth or
    y < 0 or y >= MapHeight or not world().isWalkable(x.int, y.int):
      return 0
  let point = MapPoint(x: x.int, y: y.int)
  if not activeBot[].hasGoal or activeBot[].goal != point or
    activeBot[].path.len == 0 or activeBot[].stuck > TargetFps * 2:
      if activeBot[].searched:
        return 0
      activeBot[].searched = true
      activeBot[].goal = point
      activeBot[].hasGoal = true
      activeBot[].waypoint = 0
      activeBot[].stuck = 0
      if not own().alive:
        activeBot[].path = @[point]
      else:
        activeBot[].path = activeNav[].findPath(
          world(), MapPoint(x: own().x, y: own().y), point
        )
  if activeBot[].path.len == 0:
    return 0
  while activeBot[].waypoint < activeBot[].path.high and
    distSq(own().x, own().y, activeBot[].path[activeBot[].waypoint].x,
      activeBot[].path[activeBot[].waypoint].y) <= 9:
      inc activeBot[].waypoint
  let target = activeBot[].path[activeBot[].waypoint]
  activeBot[].output.left = target.x < own().x - 1
  activeBot[].output.right = target.x > own().x + 1
  activeBot[].output.up = target.y < own().y - 1
  activeBot[].output.down = target.y > own().y + 1
  1

proc buildBotHost*(slot = -1): Host =
  ## Exposes private observations and queued commands for one running policy.
  result = initPolicyHost(slot)
  for name in BotDataNames:
    discard result.addData(name)
  template number(name: string, arity, cost: int, body: untyped) =
    let callback: HostProc = proc(args {.inject.}: openArray[int32]): int32 =
      ## Evaluates one bounded numeric observation or queued input.
      body
    discard result.addFunction(name, arity, callback, cost)
  template text(name: string, arity, cost: int, body: untyped) =
    let callback: NumericHostProc = proc(
      values: openArray[Value]
    ): Value =
      ## Copies a permitted observation into this runtime's string storage.
      var args {.inject.}: array[1, int32]
      if values.len > 0:
        args[0] = values[0].asInt
      let value: string = body
      activeBot[].runtime.putString(value)
    discard result.addFunction(name, arity, callback, cost)

  number("playerVisible", 1, 100):
    int32(visiblePlayer(args[0]))
  number("playerAlive", 1, 100):
    if visiblePlayer(args[0]): int32(world().players[args[0]].alive)
    else: -1
  number("playerRole", 1, 4):
    if not validPlayer(args[0]): -1
    elif args[0].int == activeSlot: own().role.ord.int32
    elif own().role == Imposter and
      world().players[args[0]].role == Imposter: Imposter.ord.int32
    else: -1
  number("playerX", 1, 100):
    if visiblePlayer(args[0]): world().players[args[0]].x.int32
    else: -1
  number("playerY", 1, 100):
    if visiblePlayer(args[0]): world().players[args[0]].y.int32
    else: -1
  text("playerName$", 1, 8):
    if validPlayer(args[0]): playerColorText(world().players[args[0]].color)
    else: ""
  number("assignedTask", 1, 4):
    if args[0] >= 0 and args[0].int < own().assignedTasks.len:
      own().assignedTasks[args[0]].int32
    else: -1
  number("taskX", 1, 100):
    if validTask(args[0]): world().taskPoint(args[0].int).x.int32
    else: -1
  number("taskY", 1, 100):
    if validTask(args[0]): world().taskPoint(args[0].int).y.int32
    else: -1
  number("taskDone", 1, 20):
    if validTask(args[0]) and args[0].int in own().assignedTasks:
      int32(world().tasks[args[0]].completed[activeSlot])
    else: -1
  number("atTask", 1, 4):
    if not validTask(args[0]):
      return 0
    let station = world().tasks[args[0]]
    int32(own().x >= station.x and own().x < station.x + station.w and
      own().y >= station.y and own().y < station.y + station.h)
  number("bodyId", 1, 4):
    let index = bodyIndex(args[0])
    if index >= 0: world().bodies[index].slotId.int32 else: -1
  number("bodyX", 1, 4):
    let index = bodyIndex(args[0])
    if index >= 0: world().bodies[index].x.int32 else: -1
  number("bodyY", 1, 4):
    let index = bodyIndex(args[0])
    if index >= 0: world().bodies[index].y.int32 else: -1
  number("bodyAge", 1, 4):
    let index = bodyIndex(args[0])
    if index >= 0: int32(world().tickCount - world().bodies[index].killTick)
    else: -1
  text("bodyRoom$", 1, 30):
    let index = bodyIndex(args[0])
    if index >= 0:
      let body = world().bodies[index]
      world().roomName(body.x, body.y)
    else: ""
  number("chatSender", 1, 20):
    if validChat(args[0]):
      let identity = world().chatMessages[args[0]].slotId
      for index, player in world().players:
        if player.joinOrder == identity:
          return index.int32
    -1
  text("chatText$", 1, VoteChatMaxChars):
    if validChat(args[0]): world().chatMessages[args[0]].text else: ""
  text("ownRoom$", 0, 30):
    world().roomName(own().x, own().y)
  text("meetingBodyName$", 0, 8):
    if world().phase == Voting and
      world().voteState.callKind == VoteCalledBody:
        playerColorText(world().voteState.bodyColor)
    else: ""
  text("meetingBodyRoom$", 0, 50):
    var name = ""
    if world().phase == Voting and
      world().voteState.callKind == VoteCalledBody:
        for body in world().bodies:
          if body.slotId == world().voteState.bodySlotId:
            name = world().roomName(body.x, body.y)
    name
  number("randomInt", 1, 4):
    activeBot[].rng.below(args[0])

  number("setInput", 1, 4):
    if args[0] < 0 or args[0] > 127:
      return 0
    activeBot[].output = readInput(args[0].uint8)
    1
  number("pressUse", 0, 4):
    activeBot[].output.attack = not previousInput.attack
    int32(activeBot[].output.attack)
  number("holdUse", 0, 4):
    activeBot[].output.attack = true
    1
  number("moveTo", 2, 10_000):
    navigate(args[0], args[1])
  number("voteFor", 1, 8):
    if world().phase != Voting or not own().alive or args[0] < 0 or
      args[0].int > world().players.len or
      world().voteState.votes[activeSlot] != -1:
        return 0
    if args[0].int < world().players.len and
      not world().players[args[0]].alive:
        return 0
    activeBot[].output.attack = not previousInput.attack
    if activeBot[].output.attack:
      activeBot[].choice = args[0].int
      return 1
    0
  let sendChat: NumericHostProc = proc(args: openArray[Value]): Value =
    ## Queues one legal meeting message without modifying the world.
    if args[0].asInt != -2 or world().phase != Voting or not own().alive or
      activeBot[].chat.len > 0 or
      world().tickCount - own().lastChatTick <
        world().config.messageCooldownTicks:
          return 0
    activeBot[].runtime.withString(args[1], message):
      if message.len == 0 or message.len > VoteChatMaxChars:
        return 0
      var copy = newString(message.len)
      for index, character in message:
        copy[index] = character
      activeBot[].chat = cleanChatMessage(copy)
    int32(activeBot[].chat.len > 0)
  discard result.addFunction("sendChat", 2, sendChat, VoteChatMaxChars)

proc initBots*(sources: openArray[string], seed: int): seq[Bot] =
  ## Compiles each distinct source once and isolates every slot's VM and RNG.
  let
    limits = botLimits()
    schema = buildBotHost()
  var
    compiledSources: seq[string]
    programs: seq[Program]
  result.setLen(sources.len)
  for slot, source in sources:
    result[slot].choice = -1
    if source.len == 0:
      continue
    try:
      var program: Program
      for index, previous in compiledSources:
        if source == previous:
          program = programs[index]
          break
      if program == nil:
        program = compile(source, schema, limits)
        compiledSources.add source
        programs.add program
      result[slot].runtime = initRuntime(program, buildBotHost(slot), limits)
      result[slot].rng = initRng(
        0, cast[uint64](seed.int64) xor ((slot.uint64 + 1) * 1_000_003)
      )
      for index, name in BotDataNames:
        result[slot].dataIds[index] = program.hostDataIndex(name)
    except BasicError as error:
      raise newException(BasicError, "Bot " & $(slot + 1) & ": " & error.msg)

proc decideBot*(
  bot: var Bot,
  nav: var Navigator,
  sim: var SimServer,
  slot: int,
  previous: InputState
): InputState =
  ## Runs one bounded decision and returns only validated queued inputs.
  bot.output = InputState()
  bot.searched = false
  bot.chat.setLen(0)
  bot.choice = -1
  if bot.runtime == nil or bot.failed:
    return
  activeBot = bot.addr
  activeWorld = sim.addr
  activeNav = nav.addr
  activeSlot = slot
  previousInput = previous
  defer:
    activeBot = nil
    activeWorld = nil
    activeNav = nil
    visibleBodies.setLen(0)
  visibleBodies.setLen(0)
  let player = sim.players[slot]
  if sim.phase == Playing:
    if bot.previous == MapPoint(x: player.x, y: player.y):
      inc bot.stuck
    else:
      bot.stuck = 0
    bot.previous = MapPoint(x: player.x, y: player.y)
    for index, body in sim.bodies:
      if sim.visibleFrom(slot, body.x, body.y):
        visibleBodies.add index
  let
    voting = sim.phase == Voting
    values = [
      slot, sim.tickCount, sim.phase.ord, player.x, player.y, player.alive.int,
      player.role.ord, player.killCooldown, sim.players.len, sim.tasks.len,
      player.assignedTasks.len, visibleBodies.len,
      (if voting: sim.chatMessages.len else: 0),
      (if voting: sim.meetingCallCallerIndex() else: -1),
      (if voting: sim.voteState.callKind.ord else: 0),
      sim.voteState.voteTimer, sim.config.voteTimerTicks,
      sim.voteState.finalizeTimer, sim.config.messageCooldownTicks,
      player.lastChatTick,
      (if voting: sim.voteState.votes[slot] else: -1),
      (if voting: sim.voteState.cursor[slot] else: -1),
      sim.config.killRange, sim.config.reportRange, TargetFps,
      bot.stuck, bot.path.len
    ]
  try:
    bot.runtime.restart()
    for index, value in values:
      bot.runtime.setData(bot.dataIds[index], value.int32)
    discard bot.runtime.run()
    inc bot.decisions
    result = bot.output
  except BasicError as error:
    bot.failed = true
    bot.lastError = error.msg
    bot.output = InputState()
    bot.chat.setLen(0)
    bot.choice = -1
    echo "Crewrift bot ", slot + 1, " BASIC error: ", error.msg
  bot.lastWork = bot.runtime.workUsed
  bot.lastInstructions = bot.runtime.instructionsUsed
