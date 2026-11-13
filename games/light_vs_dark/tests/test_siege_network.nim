## Real binary relay + two human control queues; replay from declared fixture.
## No socket/server/browser. Fixture isolates combat from construction economy.
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
  doAssert false, "Siege relay exchange did not settle"

for i in 0 ..< 2:
  clients.add RoomClient(identity: lvdIdentity(), name: "Siege human " & $i)
  clients[i].opened()
  exchange()
var config = defaultConfig(2)
config.maxTicks = 1800
clients[0].send(RoomMessage(kind: CreateRoom, name: "Siege fixture", number: 2,
  tickRate: TickRate.uint32, flag: false, payload: config.toJson()))
exchange()
clients[1].send(RoomMessage(kind: JoinRoom, room: clients[0].snapshot.room))
exchange()
clients[0].claimHumanSeat(0)
clients[1].claimHumanSeat(1)
exchange()
var initial: World
var bomber, archer, victim: int32
var towers: seq[int32]
var centre: int32
for client in clients:
  let session = prepareNetworkMatch(client, ["", ""])
  let w = session.game.world
  centre = w.map.side div 2
  var builder = NoEntity
  for u in w.units:
    if u.owner == 1: builder = u.id; break
  w.players[1].gold = 20000
  w.players[1].wood = 20000
  var ids: seq[int32]
  for dx in [2'i32, 8'i32]:
    doAssert w.applyBuild(1, builder, FarmBuilding.ord.int32, centre + dx, centre)
    doAssert w.applyCancel(1, builder)
    w.buildings[^1].kind = TowerBuilding
    w.buildings[^1].state = BuildingComplete
    w.buildings[^1].hp = BuildingTable[TowerBuilding].hp
    w.buildings[^1].maxHp = BuildingTable[TowerBuilding].hp
    ids.add w.buildings[^1].id
  if towers.len == 0: towers = ids
  else: doAssert towers == ids
  bomber = w.spawnUnit(0, CatapultUnit, tile2(centre - 8, centre))
  # Hidden-to-victim ranged fire in a separate lane, beyond peon sight.
  archer = w.spawnUnit(1, CatapultUnit, tile2(centre + 7, centre - 12))
  victim = w.spawnUnit(0, PeonUnit, tile2(centre, centre - 12))
  w.units[w.unitIndex(victim)].hp = 10000
  doAssert w.applyCancel(0, victim)
  w.rebuildVision()
  sessions.add session
  if initial == nil: initial = w.clone()
  client.send(RoomMessage(kind: PreparedDuration, durationTicks: uint32(session.game.maximumTicks), revision: session.revision,
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
  if i == 0: queueAttackMove(0, bomber, centre + 14, centre)
  else: queueAttack(1, archer, victim)
  session.flushSubmissions()
  doAssert session.game.stateHash() == baseline, "Input mutated before authority"
exchange()
var sawReveal = false
var sawHiddenShooter = false
for frame in 0 ..< config.maxTicks + 80:
  now += 1.0 / TickRate.float64
  relay.advance(now)
  exchange()
  for session in sessions: discard session.pump(16)
  exchange()
  let w = sessions[0].game.world
  sawReveal = sawReveal or w.rangedReveals.len > 0
  if w.rangedReveals.len > 0 and w.unitVisible(0, w.units[w.unitIndex(archer)]):
    sawHiddenShooter = true
  if w.tick == sessions[1].game.world.tick:
    doAssert sessions[0].game.stateHash() == sessions[1].game.stateHash()
  if sessions[0].finished and sessions[1].finished: break

doAssert sawReveal and sawHiddenShooter
for session in sessions:
  let w = session.game.world
  doAssert session.finished
  doAssert session.game.recorder.data.actions.len == 2
  for tower in towers: doAssert not w.entityAlive(tower)
  doAssert w.units[w.unitIndex(bomber)].hp == unitOf(0, CatapultUnit).hp
  doAssert w.units[w.unitIndex(bomber)].tile.x >= centre + 12
  doAssert w.units[w.unitIndex(victim)].hp < 10000
  let data = decodeReplay(encodeReplay(session.game.recorder.data))
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
echo "PASS siege: two human intents, two tower kills without retaliation, hidden ranged reveal, ",
  sessions[0].game.world.tick, " peer ticks and both serialized fixture replays"
