import
  polyworld/[rooms, relays, roomclients, mailboxes],
  ../src/core/[battlesetup, replays, sim],
  ../src/net/multiplayer

var
  relay = Relay()
  clients: seq[RoomClient]
  sessions: seq[NetworkMatch]
  now = 0.0

proc exchange() =
  ## Passes binary messages between independent clients and the real relay.
  for iteration in 0 ..< 30:
    var sent = false
    for index, client in clients:
      if not client.connected:
        continue
      let outgoing = client.outgoing
      client.outgoing = @[]
      for bytes in outgoing:
        relay.process(index + 1, bytes, now)
        sent = true
    let outgoing = relay.outgoing
    relay.outgoing = @[]
    for message in outgoing:
      let client = clients[message.connection - 1]
      if not client.connected:
        continue
      if message.bytes.len > 0:
        client.accept(message.bytes)
        doAssert client.error.len == 0, client.error
        sent = true
      if message.close:
        client.lost()
    if not sent:
      return
  doAssert false, "The synthetic network did not settle."

proc addClient(): RoomClient =
  ## Opens a separate client with its own participant and reconnect token.
  result = RoomClient(identity: cacIdentity(), name: "Player " & $clients.len)
  clients.add result
  result.opened()
  exchange()

proc compareGames() =
  ## Compares only simulations that have applied the same relay history.
  for first in sessions:
    for second in sessions:
      if first.tick == second.tick:
        doAssert first.actionCount == second.actionCount
        doAssert first.game.stateHash == second.game.stateHash
        doAssert first.recorder.data.actions == second.recorder.data.actions
        doAssert first.recorder.data.hashes == second.recorder.data.hashes

proc advanceClients() =
  ## Drains catch-up batches without advancing game state outside packets.
  for iteration in 0 ..< 40:
    var applied = false
    for session in sessions:
      if not session.client.connected:
        continue
      var packet: RoomMessage
      while session.client.takeTick(packet):
        session.applyPacket(packet)
        applied = true
    exchange()
    if not applied:
      compareGames()
      return
  doAssert false, "Client history did not drain."

proc step() =
  ## Advances one relay deadline and delivers its authoritative packet.
  now += 1.0 / CacNetworkTickRate.float64 + 0.0001
  for client in clients:
    if client.connected:
      client.send(RoomMessage(kind: Keepalive))
  exchange()
  relay.advance(now)
  exchange()
  advanceClients()
  doAssert relay.rooms[0].phase != Desynced, relay.rooms[0].detail

proc prepareAll(sources: seq[seq[string]] = @[]) =
  ## Prepares local simulations without declaring readiness to the relay.
  sessions.setLen(0)
  for index, client in clients:
    let source = if index < sources.len: sources[index] else: @[]
    let session = prepareNetworkMatch(client, source)
    sessions.add session
  exchange()

proc beginMatch() =
  ## Starts the prepared lobby and consumes its independent begin messages.
  sessions[0].client.send(RoomMessage(kind: StartMatch,
    revision: sessions[0].revision, hash: sessions[0].game.networkHash))
  exchange()
  for session in sessions:
    doAssert session.client.events.len == 1
    session.start(session.client.events[0])
    session.client.events.setLen(0)
    doAssert session.started
  exchange()
  compareGames()

proc endTurnAction(game: GameState): ReplayAction =
  ## Makes a legal passive move, including required hand-limit discards.
  result = ReplayAction(playerId: game.actingPlayer.int32, kind: ActionEndTurn)
  if game.waitingToss:
    result.kind = ActionToss
    for index in 0 ..< game.pendingToss.count:
      result.indices.add index.int32

proc submitHumans() =
  ## Queues each local human's move without changing any local simulation.
  for session in sessions:
    if session.finished or not session.client.connected or
      session.humanSeat != session.game.actingPlayer or session.pendingAction:
      continue
    let
      hashBefore = session.game.stateHash
      countBefore = session.actionCount
    doAssert session.submitAction(session.game.endTurnAction)
    doAssert session.pendingAction
    doAssert not session.submitAction(session.game.endTurnAction),
      "One turn must not queue multiple conflicting local intentions."
    doAssert session.game.stateHash == hashBefore
    doAssert session.actionCount == countBefore

proc finishMatch() =
  ## Finishes a bounded match while every controller retains its own policy.
  for iteration in 0 ..< 800:
    submitHumans()
    for session in sessions:
      session.pumpBots()
    step()
    var allFinished = true
    for session in sessions:
      allFinished = allFinished and session.finished
    if allFinished:
      exchange()
      relay.advance(now)
      exchange()
      doAssert relay.rooms[0].phase == rooms.Ended
      compareGames()
      return
  doAssert false, "The bounded match did not finish."

proc resetHarness() =
  ## Starts an unrelated relay instance without sharing client state.
  relay = Relay()
  clients = @[]
  sessions = @[]
  now = 0

proc createHumanMatch(players: int, maximumActions: uint32) =
  ## Creates a fresh minimal match for isolated network lifecycle regressions.
  resetHarness()
  for index in 0 ..< players:
    discard addClient()
  var battle = defaultBattleSetup(players)
  battle.maxActions = maximumActions
  clients[0].send(RoomMessage(kind: CreateRoom, name: "CaC regression test",
    number: players.uint32, tickRate: CacNetworkTickRate.uint32,
    payload: battle.encodeBattleSetup))
  exchange()
  for index in 1 ..< players:
    clients[index].send(RoomMessage(kind: JoinRoom,
      room: clients[0].snapshot.room))
  exchange()
  for index, client in clients:
    client.claimHumanSeat(index)
  exchange()
  prepareAll()
  beginMatch()

proc assertMailbox(session: NetworkMatch, player: int, expected: seq[string],
    sender = 0) =
  ## Checks inbox order and sender identity without consuming any messages.
  let inbox = session.inboxes[player]
  doAssert inbox.count == expected.len
  for index, message in expected:
    let slot = (inbox.first + index) mod MaxMailboxMessages
    doAssert inbox.messages[slot] == message
    doAssert inbox.ids[slot] == sender.int32

proc assertPacketRejected(session: NetworkMatch, commands: seq[Command]) =
  ## Verifies envelope validation is atomic even after an earlier valid intent.
  let
    originalHash = session.game.stateHash
    originalTick = session.tick
    originalActions = session.actionCount
  var rejected = false
  try:
    session.applyPacket(RoomMessage(kind: TickPacket,
      match: session.client.match, tick: session.tick + 1,
      commands: commands))
  except RoomsError:
    rejected = true
  doAssert rejected
  doAssert session.game.stateHash == originalHash
  doAssert session.tick == originalTick
  doAssert session.actionCount == originalActions
  doAssert session.recorder.data.actions.len.uint32 == originalActions

proc assertInvalidPackets(session: NetworkMatch) =
  ## Rejects malformed and wrongly attributed actions before any state changes.
  let
    action = session.game.endTurnAction
    player = action.playerId.int
    other = 1 - player
    valid = Command(participant: session.client.snapshot.seats[player].owner,
      seat: player.uint32, sequence: 500,
      payload: ActionSubmission(revision: session.actionCount,
        action: action).encodeSubmission)
  var invalid = valid
  invalid.seat = other.uint32
  session.assertPacketRejected(@[valid, invalid])
  invalid.participant = session.client.snapshot.seats[other].owner
  session.assertPacketRejected(@[valid, invalid])
  invalid = valid
  invalid.payload = "incomplete"
  session.assertPacketRejected(@[valid, invalid])
  invalid.payload = valid.payload & "trailing"
  session.assertPacketRejected(@[valid, invalid])

proc assertInitialHashesMatch() =
  ## Rejects a peer's mismatched state against the host's start checkpoint.
  let mismatchRelay = Relay()
  for connection in 1 .. 2:
    mismatchRelay.receive(connection, RoomMessage(kind: Hello,
      identity: cacIdentity(), name: "Hash test " & $connection), 0)
  mismatchRelay.receive(1, RoomMessage(kind: CreateRoom, name: "Hash test",
    number: 2, tickRate: CacNetworkTickRate.uint32,
    payload: defaultBattleSetup().encodeBattleSetup), 0)
  let room = mismatchRelay.rooms[0]
  mismatchRelay.receive(2, RoomMessage(kind: JoinRoom, room: room.id), 0)
  for connection in 1 .. 2:
    mismatchRelay.receive(connection, RoomMessage(kind: ClaimSeat,
      seat: (connection - 1).uint32, name: "Human"), 0)
  let
    host = RoomClient(participant: 1, snapshot: mismatchRelay.state(room))
    prepared = host.requestStart()
  for bytes in host.outgoing:
    mismatchRelay.receive(1, decode(bytes), 0)
  doAssert room.phase == Playing
  let
    peer = RoomClient(participant: 2, match: room.match,
      snapshot: mismatchRelay.state(room))
    incompatible = prepareNetworkMatch(peer)
  doAssert incompatible.game.networkHash == prepared.game.networkHash
  dec incompatible.game.players[0].life
  var begin: RoomMessage
  for outgoing in mismatchRelay.outgoing:
    let message = decode(outgoing.bytes)
    if outgoing.connection == 2 and message.kind == BeginMatch:
      begin = message
  doAssert begin.kind == BeginMatch
  var rejected = false
  try:
    incompatible.start(begin)
  except RoomsError:
    rejected = true
  doAssert rejected and not incompatible.started
  doAssert incompatible.tick == 0
  for bytes in peer.outgoing:
    mismatchRelay.receive(2, decode(bytes), 0)
  doAssert room.phase == Desynced
  doAssert room.tick == 0 and room.match > 0

assertInitialHashesMatch()

echo "Testing two human players, packet-only actions and spectator catch-up"
let
  first = addClient()
  second = addClient()
var setup = defaultBattleSetup(2)
setup.seed = 5721
setup.maxActions = 40
first.send(RoomMessage(kind: CreateRoom, name: "CaC human test", number: 2,
  tickRate: CacNetworkTickRate.uint32, flag: true,
  payload: setup.encodeBattleSetup))
exchange()
let roomId = first.snapshot.room
second.send(RoomMessage(kind: JoinRoom, room: roomId))
exchange()
first.claimHumanSeat(0)
second.claimHumanSeat(1)
exchange()
doAssert first.snapshot.controllersConnected
for participant in first.snapshot.participants:
  doAssert not participant.ready
var startRejected = false
try:
  relay.receive(1, RoomMessage(kind: StartMatch,
    revision: first.snapshot.revision - 1), now)
except RoomsError:
  startRejected = true
doAssert startRejected and relay.rooms[0].phase == Lobby
sessions = @[first.requestStart()]
exchange()
doAssert relay.rooms[0].phase == Playing
doAssert second.events.len == 1
sessions.add prepareNetworkMatch(second)
doAssert sessions[0].humanSeat == 0
doAssert sessions[1].humanSeat == 1
doAssert first.snapshot.humanSeatFor(second.participant) == 1
doAssert sessions[0].game.networkHash == sessions[1].game.networkHash
doAssert first.snapshot.controllersConnected
for session in sessions:
  doAssert session.client.events.len == 1
  session.start(session.client.events[0])
  session.client.events.setLen(0)
  doAssert session.started
exchange()
compareGames()
sessions[0].assertInvalidPackets()

let initialActor = sessions[0].game.actingPlayer
let wrongSession = sessions[1 - initialActor]
doAssert not wrongSession.submitAction(sessions[0].game.endTurnAction),
  "A human must not submit another player's move."
submitHumans()
exchange()
doAssert sessions[0].actionCount == 0
step()
doAssert sessions[0].actionCount == 1
doAssert sessions[1].actionCount == 1

echo "Testing stale actions and out-of-turn owned intents"
let
  staleAction = sessions[0].game.endTurnAction
  staleActor = staleAction.playerId.int
  staleCount = sessions[0].actionCount
  staleHash = sessions[0].game.stateHash
doAssert clients[staleActor].submit(staleActor.uint32,
  ActionSubmission(revision: staleCount - 1, action: staleAction).encodeSubmission)
let wrongActor = 1 - staleActor
doAssert clients[wrongActor].submit(wrongActor.uint32,
  ActionSubmission(revision: staleCount,
    action: ReplayAction(playerId: wrongActor.int32,
      kind: ActionEndTurn)).encodeSubmission)
step()
doAssert sessions[0].actionCount == staleCount
doAssert sessions[0].game.stateHash == staleHash

echo "Testing explicit pause and resume"
first.send(RoomMessage(kind: PauseMatch, match: first.match, flag: true))
exchange()
let pausedTick = relay.rooms[0].tick
for iteration in 0 ..< 3:
  step()
  doAssert relay.rooms[0].tick == pausedTick
  doAssert sessions[0].tick == pausedTick
first.send(RoomMessage(kind: PauseMatch, match: first.match, flag: false))
exchange()
step()
doAssert relay.rooms[0].phase == Playing
step()
doAssert relay.rooms[0].tick > pausedTick

echo "Testing late spectator and reconnect without replacing the simulation"
for iteration in 0 ..< 4:
  submitHumans()
  step()
let spectator = addClient()
spectator.send(RoomMessage(kind: JoinRoom, room: roomId))
exchange()
let watching = prepareNetworkMatch(spectator, [])
sessions.add watching
doAssert watching.humanSeat == -1
doAssert spectator.events.len == 1
watching.start(spectator.events[0])
spectator.events.setLen(0)
exchange()
advanceClients()
doAssert watching.tick == sessions[0].tick
doAssert watching.game.stateHash == sessions[0].game.stateHash
doAssert not watching.submitAction(watching.game.endTurnAction)

while sessions[0].game.actingPlayer != sessions[0].humanSeat:
  submitHumans()
  step()
let beforePendingAction = sessions[0].actionCount
doAssert sessions[0].submitAction(sessions[0].game.endTurnAction)
doAssert sessions[0].pendingAction
let
  reconnectToken = first.token
  participantId = first.participant
  beforeDisconnect = sessions[0].tick
relay.disconnect(1)
first.lost()
for iteration in 0 ..< 5:
  submitHumans()
  step()
doAssert relay.rooms[0].tick > beforeDisconnect
doAssert sessions[0].tick == beforeDisconnect
doAssert sessions[1].actionCount == beforePendingAction
first.opened()
exchange()
doAssert first.participant == participantId
doAssert first.token == reconnectToken
advanceClients()
doAssert sessions[0].tick == sessions[1].tick
doAssert sessions[0].game.stateHash == sessions[1].game.stateHash
doAssert sessions[0].pendingAction
step()
doAssert sessions[0].actionCount == beforePendingAction + 1
doAssert not sessions[0].pendingAction
finishMatch()

echo "Testing rematch in the same room"
let
  previousMatch = first.match
  previousActions = sessions[0].actionCount
doAssert previousActions > 1
first.send(RoomMessage(kind: ReturnLobby))
exchange()
for session in sessions:
  doAssert session.returnedToLobby
doAssert first.snapshot.room == roomId
doAssert first.snapshot.seats[0].owner == first.participant
doAssert first.snapshot.seats[1].owner == second.participant
for participant in first.snapshot.participants:
  doAssert not participant.ready
prepareAll()
for session in sessions:
  doAssert session.actionCount == 0
  doAssert session.recorder.data.actions.len == 0
beginMatch()
doAssert first.match > previousMatch
finishMatch()

echo "Testing distributed owned bots and ignored remote source"
resetHarness()
let
  owner = addClient()
  guest = addClient()
var botSetup = defaultBattleSetup(4)
botSetup.seed = 9182
botSetup.classes = @[Archer, Warrior, Mage, Archer]
botSetup.maxActions = 120
owner.send(RoomMessage(kind: CreateRoom, name: "CaC owned bot test", number: 4,
  tickRate: CacNetworkTickRate.uint32, flag: true,
  payload: botSetup.encodeBattleSetup))
exchange()
guest.send(RoomMessage(kind: JoinRoom, room: owner.snapshot.room))
exchange()
owner.claimHumanSeat(0)
guest.claimHumanSeat(1)
owner.send(RoomMessage(kind: ClaimSeat, seat: 2, name: "Mage bot"))
guest.send(RoomMessage(kind: ClaimSeat, seat: 3, name: "Archer bot"))
exchange()
let rosterRevision = owner.snapshot.revision
for ready in [true, false, true]:
  guest.send(RoomMessage(kind: ReadyStatus, flag: ready))
  exchange()
  doAssert owner.snapshot.revision == rosterRevision
  doAssert owner.snapshot.controllersConnected
  doAssert relay.guest(guest.participant).ready == ready
  doAssert not relay.guest(owner.participant).ready
let
  invalidRemoteSource = "THIS IS NOT VALID BASIC @@@"
  mage = readFile("games/cac/players/mage.bas")
  archer = readFile("games/cac/players/archer.bas")
block:
  var rejected = false
  try:
    discard owner.requestStart(["", "", invalidRemoteSource, ""])
  except RoomsError:
    rejected = true
  doAssert rejected
  doAssert owner.outgoing.len == 0
  doAssert relay.rooms[0].phase == Lobby
prepareAll(@[
  @["", "", mage, invalidRemoteSource],
  @["", "", invalidRemoteSource, archer]
])
doAssert sessions[0].bots[2] != nil
doAssert sessions[0].bots[3] == nil
doAssert sessions[1].bots[2] == nil
doAssert sessions[1].bots[3] != nil
beginMatch()
finishMatch()
var acted: array[4, bool]
for action in sessions[0].recorder.data.actions:
  acted[action.playerId] = true
for player in 0 ..< acted.len:
  doAssert acted[player], "Each independently owned seat must take a turn."
doAssert sessions[0].recorder.data.actions == sessions[1].recorder.data.actions
doAssert sessions[0].recorder.data.hashes == sessions[1].recorder.data.hashes

echo "Testing empty lobby slots retain their selected classes and seat owners"
resetHarness()
let
  sparseHost = addClient()
  sparseGuest = addClient()
var sparseSetup = defaultBattleSetup(4)
sparseSetup.classes = @[Warrior, Mage, Warrior, Archer]
sparseSetup.maxActions = 8
sparseHost.send(RoomMessage(kind: CreateRoom, name: "CaC sparse seats",
  number: 4, tickRate: CacNetworkTickRate.uint32,
  payload: sparseSetup.encodeBattleSetup))
exchange()
sparseGuest.send(RoomMessage(kind: JoinRoom, room: sparseHost.snapshot.room))
exchange()
sparseHost.claimHumanSeat(1)
sparseGuest.claimHumanSeat(3)
exchange()
prepareAll()
doAssert sessions[0].humanSeat == 0
doAssert sessions[1].humanSeat == 1
doAssert sessions[0].recorder.data.header.setup.classes == @[Mage.ord.uint8,
  Archer.ord.uint8]
beginMatch()
finishMatch()

echo "Testing elimination skips the dead controller's current turn"
resetHarness()
for index in 0 ..< 3:
  discard addClient()
var eliminationSetup = defaultBattleSetup(3)
eliminationSetup.maxActions = 8
clients[0].send(RoomMessage(kind: CreateRoom, name: "CaC elimination test",
  number: 3, tickRate: CacNetworkTickRate.uint32,
  payload: eliminationSetup.encodeBattleSetup))
exchange()
for index in 1 .. 2:
  clients[index].send(RoomMessage(kind: JoinRoom,
    room: clients[0].snapshot.room))
exchange()
for index, client in clients:
  client.claimHumanSeat(index)
exchange()
prepareAll()
beginMatch()
let eliminatedPlayer = sessions[0].game.currentPlayer
for session in sessions:
  session.game.players[eliminatedPlayer].life = 0
  session.game.checkWinCondition()
  doAssert session.game.dead(eliminatedPlayer)
  doAssert not session.game.gameOver
  let hashBefore = session.game.stateHash
  session.pumpBots()
  doAssert session.game.stateHash == hashBefore
for session in sessions:
  doAssert session.pendingAction == (session.humanSeat == eliminatedPlayer)
step()
for session in sessions:
  doAssert session.actionCount == 1
  doAssert session.game.currentPlayer != eliminatedPlayer
  doAssert session.recorder.data.actions[0].kind == ActionEndTurn
  doAssert session.recorder.data.actions[0].playerId == eliminatedPlayer.int32

echo "Testing a buffered history reports its finish checkpoint only once"
createHumanMatch(2, 1)
submitHumans()
exchange()
for index in 0 ..< 4:
  now += 1.0 / CacNetworkTickRate.float64 + 0.0001
  relay.advance(now)
  exchange()
for session in sessions:
  doAssert session.tick == 0
  doAssert session.client.packets.len == 4
advanceClients()
relay.advance(now)
exchange()
doAssert relay.rooms[0].phase == rooms.Ended
for session in sessions:
  doAssert session.finished
  doAssert session.actionCount == 1
  doAssert session.tick == 4

echo "Testing authoritative mailboxes, reconnect and late spectator history"
createHumanMatch(2, 40)
let mailboxGameHash = sessions[0].game.stateHash
doAssert sessions[1].submitMailbox(0, 1, "Wrong owner") == 0
doAssert sessions[0].submitMailbox(0, 1, "First remote message") == 1
exchange()
for session in sessions:
  session.assertMailbox(1, @[])
step()
for session in sessions:
  session.assertMailbox(1, @["First remote message"])
  doAssert session.actionCount == 0
  doAssert session.game.stateHash == mailboxGameHash
for client in clients:
  client.accept(relay.rooms[0].history[0])
advanceClients()
for session in sessions:
  session.assertMailbox(1, @["First remote message"])

relay.disconnect(2)
clients[1].lost()
doAssert clients[0].submit(0, ActionSubmission(mailbox: true, target: 1,
  text: "Delivered during reconnect",
  action: ReplayAction(playerId: 0)).encodeSubmission)
step()
sessions[0].assertMailbox(1, @["First remote message",
  "Delivered during reconnect"])
sessions[1].assertMailbox(1, @["First remote message"])
clients[1].opened()
exchange()
advanceClients()
for session in sessions:
  session.assertMailbox(1, @["First remote message",
    "Delivered during reconnect"])
  doAssert session.actionCount == 0

let mailboxSpectator = addClient()
mailboxSpectator.send(RoomMessage(kind: JoinRoom, room: clients[0].snapshot.room))
exchange()
let mailboxWatching = prepareNetworkMatch(mailboxSpectator)
sessions.add mailboxWatching
doAssert mailboxSpectator.events.len == 1
mailboxWatching.start(mailboxSpectator.events[0])
mailboxSpectator.events.setLen(0)
exchange()
advanceClients()
doAssert mailboxWatching.isSpectator
doAssert mailboxWatching.tick == sessions[0].tick
doAssert mailboxWatching.submitMailbox(0, 1, "Spectator message") == 0
mailboxWatching.assertMailbox(1, @["First remote message",
  "Delivered during reconnect"])
doAssert mailboxWatching.game.stateHash == mailboxGameHash

echo "Testing BASIC policy mail crosses independent bot owners"
resetHarness()
for index in 0 ..< 2:
  discard addClient()
var talkingSetup = defaultBattleSetup(2)
talkingSetup.maxActions = 2
clients[0].send(RoomMessage(kind: CreateRoom, name: "CaC talking policies",
  number: 2, tickRate: CacNetworkTickRate.uint32,
  payload: talkingSetup.encodeBattleSetup))
exchange()
clients[1].send(RoomMessage(kind: JoinRoom, room: clients[0].snapshot.room))
exchange()
for index, client in clients:
  client.send(RoomMessage(kind: ClaimSeat, seat: index.uint32,
    name: "Talking bot " & $index))
exchange()
let talkingPolicy = "sent = sendChat(enemyPlayer, \"From BASIC\")\nendTurn()\nend\n"
prepareAll(@[@[talkingPolicy, ""], @["", talkingPolicy]])
let firstTalker = sessions[0].game.actingPlayer
beginMatch()
for session in sessions:
  session.assertMailbox(0, @[])
  session.assertMailbox(1, @[])
step()
for session in sessions:
  session.assertMailbox(1 - firstTalker, @["From BASIC"], firstTalker)
  session.assertMailbox(firstTalker, @[])
  session.pumpBots()
step()
relay.advance(now)
exchange()
doAssert relay.rooms[0].phase == rooms.Ended
for session in sessions:
  session.assertMailbox(0, @["From BASIC"], 1)
  session.assertMailbox(1, @["From BASIC"], 0)
  doAssert session.finished and session.actionCount == 2

echo "CaC universal relay, humans, distributed bots and match lifecycle passed"
