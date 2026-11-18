## Live slot ownership follows the relay timeline without rebuilding the world.
import jsony
import polyworld/[rooms, roomclients, relays]
import ../[multiplayer, presets, replays, sim]

let relay = Relay()
let clients = [RoomClient(identity: gotaIdentity(), name: "Host"),
  RoomClient(identity: gotaIdentity(), name: "First controller"),
  RoomClient(identity: gotaIdentity(), name: "Replacement")]
var now = 0.0
var holdRecoveryStatus = false
var heldRecoveryStatus: seq[string]

proc exchange() =
  ## Delivers real wire packets until the in-process transport is idle.
  for attempt in 0 ..< 30:
    var sent = false
    for i, client in clients:
      if not client.connected: continue
      let outgoing = client.outgoing
      client.outgoing = @[]
      for bytes in outgoing:
        relay.process(i + 1, bytes, now)
        sent = true
    let outgoing = relay.outgoing
    relay.outgoing = @[]
    for output in outgoing:
      if output.bytes.len > 0 and clients[output.connection - 1].connected:
        if holdRecoveryStatus and output.connection == 1 and
            decode(output.bytes).kind == CaughtUp:
          heldRecoveryStatus.add output.bytes
        else:
          clients[output.connection - 1].accept(output.bytes)
        sent = true
    for client in clients:
      doAssert client.error.len == 0, client.error
    if not sent:
      return
  doAssert false, "Live ownership transport did not settle"

for client in clients:
  client.opened()
exchange()
clients[0].send(RoomMessage(kind: CreateRoom, name: "Live routing", number: 10,
  tickRate: 24, payload: parseConfig("{\"maxTicks\":240,\"draftMode\":\"open\"}").toJson()))
exchange()
for i in 1 .. 2:
  clients[i].send(RoomMessage(kind: JoinRoom, room: clients[0].snapshot.room))
exchange()
clients[0].claimHumanSeat(1)
clients[1].claimHumanSeat(8)
clients[0].send(RoomMessage(kind: ClaimSeat, seat: 2,
  seatKind: BotSeat, name: "First private bot"))
clients[0].send(RoomMessage(kind: ClaimSeat, seat: 3,
  seatKind: BotSeat, name: "Second private bot"))
exchange()
let initial = clients[0].snapshot
var sources = newSeq[string](10)
sources[2] = "END\n"
sources[3] = "END\n"
let sessions = [clients[0].requestStart(sources),
  prepareNetworkMatch(clients[1], []), prepareNetworkMatch(clients[2], [])]
exchange()
for i, session in sessions:
  session.start(clients[i].events[0])
  clients[i].events.setLen(0)
exchange()

# Commands accepted before a transfer retain their original authorization.
let hero = sessions[1].game.world.heroes[3].id
doAssert clients[1].submit(8,
  GameSubmission(action: ReplayAction(heroId: hero,
    kind: ActionStop)).encodeSubmission())
exchange()
clients[0].send(RoomMessage(kind: ClaimSeat, seat: 8,
  participant: clients[2].participant, seatKind: HumanSeat, name: "Human"))
exchange()
doAssert clients[0].snapshot.seats[8].owner == clients[2].participant
for client in clients:
  doAssert client.initialSnapshot.seats == initial.seats
  doAssert setupHash(client.initialSnapshot) == setupHash(initial)
now += 1.0 / 24
relay.advance(now)
exchange()
for i, session in sessions:
  var packet: RoomMessage
  doAssert clients[i].takeTick(packet)
  doAssert packet.commands.len == 1
  doAssert packet.commands[0].participant == clients[1].participant
  doAssert packet.seats[8].owner == clients[2].participant
  session.applyPacket(packet)
exchange()
doAssert sessions[1].humanHeroIndex() == -1
# Slots map to the same existing hero without generating a new world.
doAssert sessions[2].humanHeroIndex() == 3
for session in sessions:
  doAssert session.game.world.heroes[3].id == hero
  doAssert session.game.stateHash() == sessions[0].game.stateHash()
doAssert relay.rooms[0].phase == rooms.Playing

# Releasing one bot drops its private runtime without resetting another bot.
let releasedVm = sessions[0].game.heroVms[1]
let retainedVm = sessions[0].game.heroVms[2]
doAssert releasedVm != nil and retainedVm != nil
clients[0].send(RoomMessage(kind: ReleaseSeat, seat: 2))
exchange()
sessions[0].syncControllers()
doAssert sessions[0].game.heroVms[1] == nil
doAssert sessions[0].game.heroVms[2] == retainedVm

proc step() =
  ## Applies the ordered ownership roster on every independently built peer.
  now += 1.0 / 24
  relay.advance(now)
  exchange()
  for i, session in sessions:
    if not clients[i].connected: continue
    var packet: RoomMessage
    while clients[i].takeTick(packet):
      session.applyPacket(packet)
  exchange()
  for session in sessions:
    if session.game.world.tick == sessions[0].game.world.tick:
      doAssert session.game.stateHash() == sessions[0].game.stateHash()

step()
clients[0].send(RoomMessage(kind: ClaimSeat, seat: 2,
  seatKind: BotSeat, name: "First private bot"))
exchange()
sessions[0].syncControllers()
doAssert sessions[0].game.heroVms[1] == nil,
  "Ownership must reach the applied timeline before private execution resumes"
step()
sessions[0].syncControllers()
doAssert sessions[0].game.heroVms[1] != nil
doAssert sessions[0].game.heroVms[1] != releasedVm
doAssert sessions[0].game.heroVms[2] == retainedVm

# Complete the game-owned draft so both private VMs make decisions each tick.
while sessions[0].game.world.phase == Drafting:
  let hero = sessions[0].game.world.draftHeroId()
  let slot = [1, 2, 3, 8][sessions[0].game.world.heroIndex(hero)]
  let owner = clients[0].snapshot.seats[slot].owner
  for client in clients:
    if client.participant == owner:
      doAssert client.submit(uint32(slot), GameSubmission(action: ReplayAction(
        heroId: hero, kind: ActionDraft, first: 0)).encodeSubmission())
  exchange()
  step()
doAssert retainedVm.decisions > 0

# Reconnection replays history without advancing private VMs or human controls.
let decisionsBeforeRecovery = retainedVm.decisions
relay.disconnect(1)
clients[0].lost()
sessions[0].resumeControls()
sessions[0].flushSubmissions()
doAssert retainedVm.decisions == decisionsBeforeRecovery
doAssert not sessions[0].canHumanChat()
for i in 0 ..< 4: step()
doAssert retainedVm.decisions == decisionsBeforeRecovery
holdRecoveryStatus = true
clients[0].opened()
exchange()
doAssert clients[0].catchingUp
var replayed = 0
var recoveredPacket: RoomMessage
while clients[0].takeTick(recoveredPacket):
  sessions[0].applyPacket(recoveredPacket)
  inc replayed
  doAssert retainedVm.decisions == decisionsBeforeRecovery,
    "Historical packet application must not execute new private decisions"
  doAssert not sessions[0].canHumanChat()
doAssert replayed == 4 and heldRecoveryStatus.len > 0
holdRecoveryStatus = false
for bytes in heldRecoveryStatus: clients[0].accept(bytes)
heldRecoveryStatus.setLen(0)
doAssert not clients[0].catchingUp
sessions[0].resumeControls()
doAssert retainedVm.decisions == decisionsBeforeRecovery + 1,
  "The live decision resumes even when CaughtUp follows the last packet"
sessions[0].resumeControls()
doAssert retainedVm.decisions == decisionsBeforeRecovery + 1,
  "Repeated recovery polls must not repeat the same decision"
doAssert sessions[0].canHumanChat()
exchange()
for session in sessions:
  doAssert session.game.stateHash() == sessions[0].game.stateHash()

# A delayed human command is canceled if its role changes before admission.
# Repeated cancellations are consumed by the adapter even with no submissions.
for attempt in 1 .. 3:
  let rejectedBefore = clients[2].rejectedCommands
  doAssert clients[2].submit(8, GameSubmission(action: ReplayAction(
    heroId: hero, kind: ActionStop)).encodeSubmission())
  clients[0].send(RoomMessage(kind: ClaimSeat, seat: 8,
    participant: clients[2].participant, seatKind: BotSeat, name: "Human"))
  exchange()
  doAssert clients[2].rejectedCommands == rejectedBefore + 1
  sessions[2].flushSubmissions()
  var canceled: RoomMessage
  doAssert not clients[2].takeRejected(canceled),
    "GotA must drain cancellation receipts rather than accumulating them"
  clients[0].send(RoomMessage(kind: ClaimSeat, seat: 8,
    participant: clients[2].participant, seatKind: HumanSeat,
    name: clients[2].name))
  exchange()

clients[0].send(RoomMessage(kind: KickParticipant,
  participant: clients[1].participant))
exchange()
doAssert clients[1].snapshot.room.len == 0
doAssert sessions[1].returnedToLobby(),
  "A kicked participant must leave the old graphics loop"
doAssert not sessions[0].returnedToLobby()
doAssert not sessions[2].returnedToLobby()

echo "Live ownership, private VM preservation, recovery, cancellation, queued commands and kicked exit passed"
