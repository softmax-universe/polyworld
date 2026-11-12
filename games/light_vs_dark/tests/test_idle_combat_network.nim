## In-process real binary relay, two control queues, both serialized replays.
## Declared fixture isolates idle combat/cancel from production economy; no sockets.
import jsony, polyworld/[rooms, relays, roomclients, tapes],
  ../[multiplayer, presets, sim, replays, content, controls]

var relay = Relay()
var clients: seq[RoomClient]
var sessions: seq[NetworkMatch]
var now = 0.0
proc exchange() =
  for attempt in 0 ..< 30:
    var sent = false
    for i, client in clients:
      var outgoing: seq[string]
      swap(outgoing, client.outgoing)
      for bytes in outgoing:
        relay.process(i + 1, bytes, now)
        sent = true
    var outgoing: seq[Outgoing]
    swap(outgoing, relay.outgoing)
    for message in outgoing:
      doAssert not message.close
      if message.bytes.len > 0:
        clients[message.connection - 1].accept(message.bytes)
        doAssert clients[message.connection - 1].error.len == 0,
          clients[message.connection - 1].error
        sent = true
    if not sent: return
  doAssert false, "Idle/cancel relay exchange did not settle"

for i in 0 ..< 2:
  clients.add RoomClient(identity: lvdIdentity(), name: "Idle human " & $i)
  clients[i].opened()
  exchange()
var config = defaultConfig(2)
config.maxTicks = 720
clients[0].send(RoomMessage(kind: CreateRoom, name: "Idle and cancellation", number: 2,
  tickRate: TickRate.uint32, flag: false, payload: config.toJson()))
exchange()
clients[1].send(RoomMessage(kind: JoinRoom, room: clients[0].snapshot.room))
exchange()
clients[0].claimHumanSeat(0)
clients[1].claimHumanSeat(1)
exchange()
var initial: World
var mover, attacker, siege, farm, cancelled, builder, hallBuilder: int32
var centre: int32
for client in clients:
  let session = prepareNetworkMatch(client, ["", ""])
  let w = session.game.world
  centre = w.map.side div 2
  for player in w.players.mitems:
    player.gold = 10000
    player.wood = 10000
  # Remote enemy farm, with legal ordinary placement and blockers.
  var remoteBuilder = NoEntity
  for u in w.units:
    if u.owner == 1: remoteBuilder = u.id; break
  doAssert w.applyBuild(1, remoteBuilder, FarmBuilding.ord.int32, centre + 4, centre - 12)
  farm = w.buildings[^1].id
  doAssert w.applyCancel(1, remoteBuilder)
  w.buildings[^1].state = BuildingComplete
  w.buildings[^1].hp = BuildingTable[FarmBuilding].hp
  w.buildings[^1].maxHp = BuildingTable[FarmBuilding].hp
  siege = w.spawnUnit(0, SoldierUnit, tile2(centre, centre - 12))
  mover = w.spawnUnit(0, SoldierUnit, tile2(centre - 2, centre))
  attacker = w.spawnUnit(1, ArcherUnit, tile2(centre + 2, centre + 4))
  w.units[w.unitIndex(mover)].hp = 500
  w.units[w.unitIndex(attacker)].hp = 500
  builder = w.spawnUnit(0, PeonUnit, tile2(centre - 8, centre + 12))
  doAssert w.applyBuild(0, builder, FarmBuilding.ord.int32, centre - 8, centre + 12)
  cancelled = w.buildings[^1].id
  # Declared progressed site, whose refund must still be the full original cost.
  w.buildings[^1].buildTicks = w.buildings[^1].buildTotal div 2
  w.buildings[^1].hp = w.buildings[^1].maxHp div 2
  doAssert w.applyMove(0, builder, centre - 3, centre + 12, append = true)
  hallBuilder = w.spawnUnit(1, PeonUnit, tile2(centre + 12, centre + 12))
  for b in w.buildings:
    if b.owner == 1 and b.kind == TownHallBuilding:
      w.damageEntity(b.id, b.hp)
  doAssert w.hallDefeatTicksRemaining(1) == TownHallDefeatGraceTicks
  w.rebuildVision()
  sessions.add session
  if initial == nil: initial = w.clone()
  client.send(RoomMessage(kind: Ready, revision: session.revision,
    hash: session.game.networkHash()))
exchange()
clients[0].send(RoomMessage(kind: StartMatch))
exchange()
for session in sessions:
  doAssert session.client.events.len == 1
  session.start(session.client.events[0])
exchange()
for i, session in sessions:
  let baseline = session.game.stateHash()
  if i == 0:
    queueMove(0, mover, centre, centre)
    queueMove(0, mover, centre + 2, centre, append = true)
    queueCancel(0, cancelled)
    queueCancel(0, cancelled) # duplicate authoritative command must not refund twice
  else:
    queueAttack(1, attacker, mover)
    queueBuild(1, hallBuilder, TownHallBuilding.ord.int32, centre + 12, centre + 12)
  session.flushSubmissions()
  doAssert session.game.stateHash() == baseline, "Input mutated before authority"
exchange()
var damagedUnit, damagedBuilding, arrived = false
var checked = 0
var hallCancelled = false
var deadline = 0'i32
for frame in 0 ..< config.maxTicks + 80:
  now += 1.0 / TickRate.float64
  relay.advance(now)
  exchange()
  for session in sessions: discard session.pump(16)
  exchange()
  let w = sessions[0].game.world
  if w.tick >= 120 and not hallCancelled:
    doAssert w.players[1].hallLossDeadline == 0
    var rebuilt = NoEntity
    for b in w.buildings:
      if b.owner == 1 and b.kind == TownHallBuilding and b.state == BuildingUnderConstruction:
        rebuilt = b.id
    doAssert rebuilt != NoEntity
    queueCancel(1, rebuilt)
    sessions[1].flushSubmissions()
    hallCancelled = true
  if hallCancelled and w.players[1].hallLossDeadline > 0:
    deadline = w.players[1].hallLossDeadline
    doAssert w.players[1].defeated == (w.tick >= deadline)
  let u = w.units[w.unitIndex(mover)]
  if u.state == UnitIdle and u.orderQueue.len == 0 and u.tile.x == centre + 2:
    arrived = true
  if w.units[w.unitIndex(attacker)].hp < 500: damagedUnit = true
  if not w.entityAlive(farm) or
      w.buildings[w.buildingIndex(farm)].hp < BuildingTable[FarmBuilding].hp:
    damagedBuilding = true
  if w.tick == sessions[1].game.world.tick:
    doAssert sessions[0].game.stateHash() == sessions[1].game.stateHash()
    inc checked
  if sessions[0].finished and sessions[1].finished: break

doAssert arrived and damagedUnit and damagedBuilding
doAssert hallCancelled and deadline > 120
for session in sessions:
  let w = session.game.world
  doAssert session.finished
  doAssert w.tick == deadline and w.players[1].defeated and w.winner == 0
  doAssert w.players[0].gold == 10000 and w.players[0].wood == 10000
  doAssert not w.entityAlive(cancelled)
  doAssert w.units[w.unitIndex(builder)].tile == tile2(centre - 3, centre + 12)
  doAssert w.units[w.unitIndex(builder)].constructionSiteId == NoEntity
  let data = decodeReplay(encodeReplay(session.game.recorder.data))
  doAssert data.actions.len == 6, "Only one duplicate site cancellation may be accepted"
  let playback = Game(world: initial.clone())
  let cursor = initReplayPlayer(data)
  proc replay(w: World) =
    var action: ReplayAction
    while cursor.takeActionAt(w.tick.uint32, action):
      doAssert w.applyReplayAction(action)
  for hash in data.hashes:
    playback.world.tickWorld(replay)
    doAssert playback.stateHash() == hash
  doAssert playback.stateHash() == session.game.stateHash()
doAssert sessions[0].game.recorder.data.hashes == sessions[1].game.recorder.data.hashes
echo "PASS idle/cancel: Move + Shift then retaliation, uncommanded siege, full one-shot refund, ",
  checked, " matching peer observations, hall rebuild/cancel/exact defeat, both serialized fixture replays"
