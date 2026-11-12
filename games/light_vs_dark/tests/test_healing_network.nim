## Real in-process relay: two human Cleric moves + Shift successors, actual
## heals, no pre-pump mutation and serialized fixture replay hashes.
import jsony, polyworld/[rooms, relays, roomclients, tapes],
  ../[multiplayer, presets, sim, replays, content, controls]

var relay = Relay()
var clients: seq[RoomClient]
var sessions: seq[NetworkMatch]
var now = 0.0
proc exchange() =
  for _ in 0 ..< 30:
    var sent = false
    for i, client in clients:
      let outgoing = client.outgoing
      client.outgoing = @[]
      for bytes in outgoing:
        relay.process(i + 1, bytes, now)
        sent = true
    let outgoing = relay.outgoing
    relay.outgoing = @[]
    for message in outgoing:
      doAssert not message.close
      if message.bytes.len > 0:
        clients[message.connection - 1].accept(message.bytes)
        doAssert clients[message.connection - 1].error.len == 0,
          clients[message.connection - 1].error
        sent = true
    if not sent: return
  doAssert false, "Healing relay exchange did not settle"

for i in 0 ..< 2:
  clients.add RoomClient(identity: lvdIdentity(), name: "Healing human " & $i)
  clients[i].opened()
  exchange()
var config = defaultConfig(2)
# This tests support/movement, not post-arrival combat against nearby bases.
# Completed moves now restore ordinary acquisition; keep these lanes neutral.
config.diplomacySettings.neutralStart = true
config.maxTicks = TickRate * 8
config.mapSettings = MapSettings(layout: RandomLayout, expansions: 0)
clients[0].send(RoomMessage(kind: CreateRoom, name: "Healing fixture", number: 2,
  tickRate: TickRate.uint32, flag: false, payload: config.toJson()))
exchange()
clients[1].send(RoomMessage(kind: JoinRoom, room: clients[0].snapshot.room))
exchange()
clients[0].claimHumanSeat(0)
clients[1].claimHumanSeat(1)
exchange()
var initial: World
var clerics, patients: seq[int32]
var starts, firstGoals, lastGoals: seq[Tile2]
for client in clients:
  let session = prepareNetworkMatch(client, ["", ""])
  # Explicit fixture setup before readiness; no gameplay mutation in UI/submission.
  let w = session.game.world
  var ids, targets: seq[int32]
  var origins, first, last: seq[Tile2]
  for owner in 0'i32 .. 1'i32:
    let origin = tile2(w.map.side div 2 + (owner * 2 - 1) * 10, w.map.side div 2)
    ids.add w.spawnUnit(owner, ClericUnit, origin)
    targets.add w.spawnUnit(owner, KnightUnit, tile2(origin.x.int32, origin.y.int32 + 1))
    w.units[w.unitIndex(targets[^1])].hp = 1
    origins.add origin
    first.add tile2(origin.x.int32 + 1, origin.y.int32 - 1)
    last.add tile2(origin.x.int32 + 2, origin.y.int32 - 1)
  clerics = ids
  patients = targets
  starts = origins
  firstGoals = first
  lastGoals = last
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
for player in 0'i32 .. 1'i32:
  let session = sessions[player]
  let baseline = session.game.stateHash()
  let first = firstGoals[player]
  let last = lastGoals[player]
  queueMove(player, clerics[player], first.x.int32, first.y.int32)
  queueMove(player, clerics[player], last.x.int32, last.y.int32, append = true)
  session.flushSubmissions()
  doAssert session.game.stateHash() == baseline
  doAssert session.game.world.units[session.game.world.unitIndex(patients[player])].hp == 1
exchange()
var visited: array[2, bool]
var healed = false
for _ in 0 ..< config.maxTicks + 50:
  now += 1.0 / TickRate.float64
  relay.advance(now)
  exchange()
  for session in sessions: discard session.pump(16)
  exchange()
  if sessions[0].game.world.tick == sessions[1].game.world.tick:
    doAssert sessions[0].game.stateHash() == sessions[1].game.stateHash()
  for owner in 0 .. 1:
    let w = sessions[0].game.world
    let cleric = w.units[w.unitIndex(clerics[owner])]
    if cleric.tile == firstGoals[owner]: visited[owner] = true
    if w.tick > 0:
      healed = healed or w.units[w.unitIndex(patients[owner])].hp > 1
  if sessions[0].finished and sessions[1].finished: break
for session in sessions:
  doAssert session.finished
  doAssert session.game.recorder.data.actions.len == 4
  for player in 0'i32 .. 1'i32:
    let w = session.game.world
    let cleric = w.units[w.unitIndex(clerics[player])]
    doAssert visited[player] and cleric.tile == lastGoals[player]
    doAssert cleric.tile != starts[player] and cleric.orderQueue.len == 0
    doAssert w.units[w.unitIndex(patients[player])].hp > 1
    doAssert cleric.mana < ClericMaxMana
  doAssert healed
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
echo "LvD healing: two humans, no immediate mutation, movement + Shift, heals and replay passed"
