## Real harvesting, deposit submissions, authoritative peers and saved playback.
import jsony, polyworld/[rooms, roomclients, tapes]
import ../[multiplayer, presets, sim, replays, content, controls]

const Duration = TickRate * 120

proc clientFor(id: uint32): RoomClient =
  ## Creates a paired in-process room using the ordinary generated start.
  var config = defaultConfig(2)
  config.maxTicks = Duration
  config.mapSettings = MapSettings(layout: RandomLayout, size: 90, expansions: 0)
  result = RoomClient(identity: lvdIdentity(), participant: id, match: 1,
    began: true, welcomed: true, connected: true)
  result.snapshot = RoomMessage(kind: RoomState, revision: 2, phase: Playing,
    tickRate: uint32(TickRate), payload: config.toJson(), seats: @[
      Seat(owner: 1, name: "Human"), Seat(owner: 2, name: "Human")], participants: @[
      Participant(id: 1, name: "Alice"), Participant(id: 2, name: "Bob")])
  result.initialSnapshot = result.snapshot
  result.appliedSeats = result.snapshot.seats

proc takeCommands(session: NetworkMatch): seq[Command] =
  ## Captures new submissions without changing authoritative state.
  let before = session.game.stateHash()
  session.flushSubmissions()
  doAssert session.game.stateHash() == before,
    "Local deposit submission must not mutate authority"
  for bytes in session.client.outgoing:
    let message = decode(bytes)
    if message.kind == SubmitCommand:
      result.add Command(participant: session.client.participant,
        seat: message.seat, sequence: message.sequence, payload: message.payload)
  session.client.outgoing.setLen(0)

clearPlayerCommands()
let
  a = prepareNetworkMatch(clientFor(1), ["", ""])
  b = prepareNetworkMatch(clientFor(2), ["", ""])
  event = RoomMessage(kind: BeginMatch, revision: 2, match: 1,
    hash: setupHash(a.client.snapshot))
a.start(event)
b.start(event)
let world = a.game.world
var
  builder: Unit
  origin = NoTile
  hall = NoEntity
let size = BuildingTable[LumberMillBuilding].footprint
for unit in world.units:
  if unit.owner != 0: continue
  for y in unit.tile.y.int32 - size.depth + 1 .. unit.tile.y.int32:
    for x in unit.tile.x.int32 - size.width + 1 .. unit.tile.x.int32:
      if world.canPlace(0, LumberMillBuilding, x, y, unit.id):
        builder = unit
        origin = tile2(x, y)
        break
    if builder != nil: break
  if builder != nil: break
doAssert builder != nil
var workers: seq[Unit]
for unit in world.units:
  if unit.owner == 0 and unit.id != builder.id: workers.add unit
doAssert workers.len >= 2
let
  miner = workers[0]
  woodcutter = workers[1]
var
  mine = NoEntity
  mineDistance = int32.high
for structure in world.buildings:
  if structure.owner == 0 and structure.kind == TownHallBuilding:
    hall = structure.id
  if structure.kind == GoldMineBuilding:
    let distance = tileDistance(miner.tile, structure.origin)
    if distance < mineDistance:
      mine = structure.id
      mineDistance = distance
doAssert hall != NoEntity and mine != NoEntity
queueBuild(0, builder.id, LumberMillBuilding.ord.int32,
  origin.x.int32, origin.y.int32)
queueHarvest(0, miner.id, mine, 0)
var
  commands = a.takeCommands()
  mill = NoEntity
  goldSent, woodSent, woodHarvestSent: bool
  goldArrived, woodArrived: bool
  goldTargetSeen, woodTargetSeen: bool
  goldBefore, woodBefore, goldLoad, woodLoad: int32
  depositWire: seq[ReplayAction]
for tick in 1'u32 .. uint32(Duration):
  let packet = RoomMessage(kind: TickPacket,
    seats: a.client.snapshot.seats, match: 1, tick: tick,
    commands: commands)
  a.applyPacket(packet)
  b.applyPacket(packet)
  commands.setLen(0)
  doAssert a.game.stateHash() == b.game.stateHash(),
    "Deposit commands must produce identical peer hashes every tick"
  if goldSent:
    if miner.targetId == hall and
        miner.state in {UnitToDropGold, UnitDepositGold}:
      goldTargetSeen = true
    if goldTargetSeen and miner.carryGold == 0:
      goldArrived = true
      doAssert world.players[0].gold >= goldBefore + goldLoad
  if woodSent:
    if woodcutter.targetId == mill and
        woodcutter.state in {UnitToDropWood, UnitDepositWood}:
      woodTargetSeen = true
    if woodTargetSeen and woodcutter.carryWood == 0:
      woodArrived = true
      doAssert world.players[0].wood >= woodBefore + woodLoad
  if goldArrived and woodArrived: break
  if not goldSent and miner.carryGold > 0:
    goldBefore = world.players[0].gold
    goldLoad = miner.carryGold
    queueDeposit(0, miner.id, hall)
    goldSent = true
  if mill == NoEntity:
    for structure in world.buildings:
      if structure.owner == 0 and structure.kind == LumberMillBuilding and
          structure.state == BuildingComplete:
        mill = structure.id
        break
  if mill != NoEntity and not woodHarvestSent:
    let tree = world.nearestTree(woodcutter.tile)
    doAssert tree >= 0
    queueHarvest(0, woodcutter.id, tree, 1)
    woodHarvestSent = true
  if woodHarvestSent and not woodSent and woodcutter.carryWood > 0:
    woodBefore = world.players[0].wood
    woodLoad = woodcutter.carryWood
    # Interrupt automatic harvesting without discarding its actual cargo.
    queueMove(0, woodcutter.id, woodcutter.tile.x.int32,
      woodcutter.tile.y.int32)
    queueDeposit(0, woodcutter.id, mill, append = true)
    woodSent = true
  commands = a.takeCommands()
  for command in commands:
    let action = decodeSubmission(command.payload)
    if action.kind == ActionDeposit: depositWire.add action

doAssert goldArrived and woodArrived,
  "Both explicitly ordered loads must reach their clicked depots"
doAssert depositWire.len == 2
doAssert depositWire[0].first == hall and not depositWire[0].append
doAssert depositWire[1].first == mill and depositWire[1].append
let data = decodeReplay(encodeReplay(a.game.recorder.data))
var depositCount = 0
for action in data.actions:
  if action.kind == ActionDeposit:
    inc depositCount
    doAssert action.first in [hall, mill]
doAssert depositCount == 2
let
  playback = newGame(world.map, Duration, data.header.setup.diplomacySettings)
  cursor = initReplayPlayer(data)
proc replay(w: World) =
  ## Replays a fresh world without injecting cargo or completed buildings.
  var action: ReplayAction
  while cursor.takeActionAt(uint32(w.tick), action):
    doAssert w.applyReplayAction(action)
for tick in 0 ..< data.hashes.len:
  playback.world.tickWorld(replay)
  doAssert playback.stateHash() == data.hashes[tick],
    "Serialized deposit playback must match the original authority"

block invalidDepositPayloadsAreRejected:
  let valid = ReplayAction(kind: ActionDeposit, playerId: 0,
    entityId: miner.id, first: hall, tick: uint32(DecisionTicks), append: true)
  valid.validateAction(data.header.setup)
  for variant in 0 .. 4:
    var bad = valid
    case variant
    of 0: bad.entityId = hall
    of 1: bad.first = mine
    of 2: bad.second = 1
    of 3: bad.third = 1
    else: bad.offset = fixedVec2(0.1'fx, 0'fx)
    var refused = false
    try: bad.validateAction(data.header.setup)
    except ReplayError: refused = true
    doAssert refused, "Invalid deposit payload must fail replay validation"
  var old = data
  old.header.gameVersion = ReplayGameVersion - 1
  var refused = false
  try: old.validate()
  except ReplayError: refused = true
  doAssert refused, "Older clients must reject the new deposit rules"

echo "Deposit commands: real gold/wood delivery, peers, FIFO and replay passed"
