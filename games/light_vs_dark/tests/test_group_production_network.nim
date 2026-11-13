## Real relay binary payloads, authority, accepted production and peer hashes.
## In-process relay only: no sockets/server/browser.
import jsony, polyworld/[rooms, relays, roomclients, tapes]
import ../[multiplayer, presets, sim, replays, content, controls]

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
  doAssert false, "Group relay exchange did not settle"

for i in 0 ..< 2:
  clients.add RoomClient(identity: lvdIdentity(), name: "Group human " & $i)
  clients[i].opened()
  exchange()
var config = defaultConfig(2)
config.maxTicks = 96
clients[0].send(RoomMessage(kind: CreateRoom, name: "Producer group fixture", number: 2,
  tickRate: TickRate.uint32, flag: false, payload: config.toJson()))
exchange()
clients[1].send(RoomMessage(kind: JoinRoom, room: clients[0].snapshot.room))
exchange()
clients[0].claimHumanSeat(0)
clients[1].claimHumanSeat(1)
exchange()
var initial: World
var groups: array[2, seq[int32]]
for client in clients:
  let session = prepareNetworkMatch(client, ["", ""])
  let w = session.game.world
  var localGroups: array[2, seq[int32]]
  for player in 0'i32 .. 1:
    w.players[player].gold = 10000
    w.players[player].wood = 10000
    w.players[player].foodCap = 100
    var worker: int32
    for u in w.units:
      if u.owner == player: worker = u.id; break
    for y in countup(10'i32, w.map.side - 10, 6):
      for x in countup(10'i32, w.map.side - 10, 6):
        if localGroups[player].len < 3 and w.canPlace(BarracksBuilding, x, y):
          doAssert w.applyBuild(player, worker, BarracksBuilding.ord.int32, x, y)
          w.buildings[^1].state = BuildingComplete
          w.buildings[^1].hp = w.buildings[^1].maxHp
          localGroups[player].add w.buildings[^1].id
          doAssert w.applyCancel(player, worker)
    doAssert localGroups[player].len == 3
    for i, count in [2, 2, 1]:
      for n in 0 ..< count:
        doAssert w.applyTrain(player, localGroups[player][i], SoldierUnit.ord.int32)
    # Exactly four clicks can be afforded after fixture work.
    w.players[player].gold = unitOf(player, SoldierUnit).gold * 4
  if initial == nil:
    groups = localGroups
    initial = w.clone()
  else: doAssert groups == localGroups
  sessions.add session
  client.send(RoomMessage(kind: PreparedDuration, durationTicks: uint32(session.game.maximumTicks), revision: session.revision, hash: session.game.networkHash()))
exchange()
clients[0].send(RoomMessage(kind: StartMatch))
exchange()
for session in sessions:
  doAssert session.client.events.len == 1
  session.start(session.client.events[0])
exchange()
clearPlayerCommands()
for i, session in sessions:
  let baseline = session.game.stateHash()
  for n in 0 ..< 4:
    doAssert session.game.world.queueSelectedTrain(i.int32, groups[i], SoldierUnit)
    session.flushSubmissions() # retain reservations after submissions is cleared
  doAssert not session.game.world.queueSelectedTrain(i.int32, groups[i], SoldierUnit)
  doAssert session.game.stateHash() == baseline
  for id in groups[i]: queueSetRally(i.int32, id, 40, 40)
  session.flushSubmissions()
exchange()
var checkedApplied = false
for frame in 0 ..< config.maxTicks + 80:
  now += 1.0 / TickRate.float64
  relay.advance(now)
  exchange()
  for session in sessions: discard session.pump(16)
  exchange()
  if sessions[0].game.world.tick == sessions[1].game.world.tick:
    doAssert sessions[0].game.stateHash() == sessions[1].game.stateHash()
  if not checkedApplied and sessions[0].game.recorder.data.actions.len == 14:
    checkedApplied = true
    for session in sessions:
      for i in 0 .. 1:
        doAssert session.game.world.selectedTrainingCount(i.int32, groups[i], SoldierUnit) == 9,
          "Reservations must retire at application without double-counting accepted queue"
        for id in groups[i]:
          let b = session.game.world.buildings[session.game.world.buildingIndex(id)]
          doAssert b.queueLength == 3
          doAssert b.hasRally and b.rally == tile2(40, 40)
  if sessions[0].finished and sessions[1].finished: break

doAssert checkedApplied
for session in sessions:
  doAssert session.finished
  doAssert session.game.recorder.data.actions.len == 14
  for player in 0'i32 .. 1:
    var trainIds: seq[int32]
    for action in session.game.recorder.data.actions:
      if action.playerId == player and action.kind == ActionTrain:
        trainIds.add action.entityId
        doAssert action.first == SoldierUnit.ord.int32
    doAssert trainIds == @[groups[player][2], groups[player][0], groups[player][1], groups[player][2]]
  let data = decodeReplay(encodeReplay(session.game.recorder.data))
  let playback = Game(world: initial.clone())
  let cursor = initReplayPlayer(data)
  proc replay(w: World) =
    var action: ReplayAction
    while cursor.takeActionAt(w.tick.uint32, action): doAssert w.applyReplayAction(action)
  for hash in data.hashes:
    playback.world.tickWorld(replay)
    doAssert playback.stateHash() == hash
  doAssert playback.stateHash() == session.game.stateHash()
doAssert sessions[0].game.recorder.data.hashes == sessions[1].game.recorder.data.hashes
echo "PASS group production: 8 accepted trains balanced 3/3/3 per human, 6 rallies, ",
  sessions[0].game.world.tick, " peer ticks, reservation retirement and both serialized replays"
