## Human build queues through authoritative packets and saved playback.
import jsony, polyworld/[rooms, roomclients, tapes]
import ../[multiplayer, presets, sim, replays, content, controls]

const Duration = TickRate * 120

proc clientFor(id: uint32): RoomClient =
  ## Creates a paired room with the ordinary generated match start.
  var config = defaultConfig(2)
  config.maxTicks = Duration
  config.mapSettings = MapSettings(layout: RandomLayout, size: 90, expansions: 0)
  result = RoomClient(identity: lvdIdentity(), participant: id, match: 1,
    began: true, welcomed: true)
  result.snapshot = RoomMessage(kind: RoomState, revision: 2, phase: Playing,
    tickRate: uint32(TickRate), payload: config.toJson(), seats: @[
      Seat(owner: 1, name: "Human"), Seat(owner: 2, name: "Human")], participants: @[
      Participant(id: 1, name: "Alice"), Participant(id: 2, name: "Bob")])

proc takeCommands(session: NetworkMatch): seq[Command] =
  ## Captures human submissions without changing authoritative state.
  let before = session.game.stateHash()
  session.flushSubmissions()
  doAssert session.game.stateHash() == before,
    "Submitting build plans must not mutate authority"
  for bytes in session.client.outgoing:
    let message = decode(bytes)
    if message.kind == SubmitCommand:
      result.add Command(participant: session.client.participant,
        seat: message.seat, sequence: message.sequence, payload: message.payload)
  session.client.outgoing.setLen(0)

proc buildingAt(w: World, origin: Tile2): Building =
  ## Finds a real construction site without treating plans as buildings.
  result.id = NoEntity
  for building in w.buildings:
    if building.owner == 0 and building.origin == origin:
      return building

clearPlayerCommands()
let
  a = prepareNetworkMatch(clientFor(1), ["", ""])
  b = prepareNetworkMatch(clientFor(2), ["", ""])
  event = RoomMessage(kind: BeginMatch, revision: 2, match: 1,
    hash: a.game.networkHash())
a.start(event)
b.start(event)
let world = a.game.world
var
  builder: Unit
  first = NoTile
  second = NoTile
  destination = NoTile
let size = BuildingTable[FarmBuilding].footprint
for unit in world.units:
  if unit.owner != 0:
    continue
  for y in unit.tile.y.int32 - size.depth + 1 .. unit.tile.y.int32:
    for x in unit.tile.x.int32 - size.width + 1 .. unit.tile.x.int32:
      if world.canPlace(0, FarmBuilding, x, y, unit.id):
        builder = unit
        first = tile2(x, y)
        break
    if builder != nil:
      break
  if builder != nil:
    break
doAssert builder != nil
for radius in 4'i32 .. 10'i32:
  for y in first.y.int32 - radius .. first.y.int32 + radius:
    for x in first.x.int32 - radius .. first.x.int32 + radius:
      let origin = tile2(x, y)
      if tileDistance(first, origin) == radius and
          world.canPlace(0, LumberMillBuilding, x, y, builder.id):
        second = origin
        break
    if second != NoTile:
      break
  if second != NoTile:
    break
doAssert second != NoTile
for y in second.y.int32 - 3 .. second.y.int32 + 3:
  for x in second.x.int32 - 3 .. second.x.int32 + 3:
    if world.tileFree(x, y) and
      not first.covers(size, x, y) and
      not second.covers(BuildingTable[LumberMillBuilding].footprint, x, y):
        destination = tile2(x, y)
        break
  if destination != NoTile:
    break
doAssert destination != NoTile
var workers: seq[Unit]
for unit in world.units:
  if unit.owner == 0 and unit.id != builder.id:
    workers.add unit
doAssert workers.len >= 2
let
  miner = workers[0]
  woodcutter = workers[1]
  tree = world.nearestTree(woodcutter.tile)
var
  mine = NoEntity
  mineDistance = int32.high
for building in world.buildings:
  if building.kind == GoldMineBuilding:
    let distance = tileDistance(miner.tile, building.origin)
    if distance < mineDistance:
      mine = building.id
      mineDistance = distance
doAssert mine != NoEntity and tree >= 0

queueBuild(0, builder.id, FarmBuilding.ord.int32,
  first.x.int32, first.y.int32)
queueBuild(0, builder.id, LumberMillBuilding.ord.int32,
  second.x.int32, second.y.int32, append = true)
queueMove(0, builder.id, destination.x.int32, destination.y.int32,
  append = true)
var commands = a.takeCommands()
doAssert commands.len == 3
let
  immediate = decodeSubmission(commands[0].payload)
  appended = decodeSubmission(commands[1].payload)
doAssert immediate.kind == ActionBuild and not immediate.append
doAssert appended.kind == ActionBuild and appended.append
doAssert appended.entityId == builder.id
doAssert appended.first == LumberMillBuilding.ord.int32
doAssert appended.second == second.x.int32
doAssert appended.third == second.y.int32
doAssert decodeSubmission(appended.encodeSubmission()) == appended
var
  started, waited, supplied, completed: bool
  waitingTicks = 0
for tick in 1'u32 .. uint32(Duration):
  let packet = RoomMessage(kind: TickPacket, match: 1, tick: tick,
    commands: commands)
  a.applyPacket(packet)
  b.applyPacket(packet)
  b.client.outgoing.setLen(0)
  commands.setLen(0)
  doAssert a.game.stateHash() == b.game.stateHash(),
    "Queued construction must produce identical peer hashes every tick"
  let
    farm = world.buildingAt(first)
    mill = world.buildingAt(second)
  if not started and farm.id != NoEntity:
    started = true
    doAssert farm.kind == FarmBuilding
    doAssert mill.id == NoEntity,
      "A future plan must not create a site immediately"
    doAssert world.players[0].gold == StartingGold -
      BuildingTable[FarmBuilding].gold
    doAssert world.players[0].wood == StartingWood -
      BuildingTable[FarmBuilding].wood
    doAssert builder.orderQueue.len == 2
    doAssert builder.orderQueue[0].kind == ActionBuild
    doAssert builder.orderQueue[0].third == second.y.int32
  if farm.id != NoEntity and farm.state == BuildingComplete and not supplied:
    doAssert mill.id == NoEntity
    doAssert builder.orderQueue.len == 2,
      "An unaffordable build must retain the move behind it"
    inc waitingTicks
    if waitingTicks >= DecisionTicks * 2:
      waited = true
      queueHarvest(0, miner.id, mine, 0)
      queueHarvest(0, woodcutter.id, tree, 1)
      supplied = true
  if mill.id != NoEntity:
    doAssert waited, "The second site must wait for real harvested resources"
    doAssert farm.id != NoEntity and farm.state == BuildingComplete,
      "The first building must finish before the second site starts"
    if mill.state == BuildingComplete and builder.state == UnitIdle and
        builder.orderQueue.len == 0:
      completed = true
      doAssert builder.tile == destination,
        "The final move must execute after both buildings complete"
      break
  commands = a.takeCommands()
doAssert started and waited and completed,
  "Queued builds must resume after harvesting and finish their final move"
doAssert world.players[0].goldGathered >= GoldPerTrip
doAssert world.players[0].woodGathered >= WoodPerTrip

let data = decodeReplay(encodeReplay(a.game.recorder.data))
doAssert data.actions.len == 5
doAssert data.actions[0].kind == ActionBuild
doAssert not data.actions[0].append
doAssert data.actions[1].kind == ActionBuild
doAssert data.actions[1].append
doAssert data.actions[1].third == second.y.int32
doAssert data.actions[2].kind == ActionMove and data.actions[2].append
let
  playback = newGame(world.map, Duration, data.header.setup.diplomacySettings)
  cursor = initReplayPlayer(data)
proc replay(w: World) =
  ## Replays the recorded commands without injecting sites or resources.
  var action: ReplayAction
  while cursor.takeActionAt(uint32(w.tick), action):
    doAssert w.applyReplayAction(action)
for tick in 0 ..< data.hashes.len:
  playback.world.tickWorld(replay)
  doAssert playback.stateHash() == data.hashes[tick],
    "Saved build queues must reproduce the authoritative hash every tick"

block invalidBuildPayloadsAreRejected:
  var valid = appended
  valid.tick = uint32(DecisionTicks)
  valid.validateAction(data.header.setup)
  for variant in 0 .. 5:
    var bad = valid
    case variant
    of 0:
      bad.first = BuildableHigh.ord.int32 + 1
    of 1:
      bad.entityId = FirstBuildingId
    of 2:
      bad.second = -1
    of 3:
      bad.third = data.header.setup.gridTiles.int32
    of 4:
      bad.offset = fixedVec2(0.1'fx, 0'fx)
    else:
      bad.kind = ActionKindHigh + 1
    var refused = false
    try:
      bad.validateAction(data.header.setup)
    except ReplayError:
      refused = true
    doAssert refused, "Invalid queued build payload must fail validation"

echo "Build queues: human controls, resources, peers, FIFO and replay passed"
