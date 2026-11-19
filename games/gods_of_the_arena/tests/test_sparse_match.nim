import jsony
import polyworld/[rooms, roomclients, tapes, metrics]
import ../[content, maps, multiplayer, replays, sim]

let config = parseConfig("{\"maxTicks\":48,\"draftMode\":\"open\"}")
let base = readFile("games/gods_of_the_arena/players/base.bas")
var snapshot = RoomMessage(kind: RoomState, phase: rooms.Playing, revision: 1, tickRate: 24,
  payload: config.toJson(), seats: newSeq[Seat](10),
  participants: @[Participant(id: 1, name: "Alice"), Participant(id: 2, name: "Bob")])
snapshot.seats[3] = Seat(owner: 1, name: "Human")
snapshot.seats[8] = Seat(owner: 2, kind: BotSeat, name: "Base bot")
let a = RoomClient(began: true, connected: true, welcomed: true, match: 1, participant: 1, snapshot: snapshot, initialSnapshot: snapshot)
let b = RoomClient(began: true, connected: true, welcomed: true, match: 1, participant: 2, snapshot: snapshot, initialSnapshot: snapshot)
var sources = newSeq[string](10)
sources[8] = base
sources[0] = base # stale source on an empty slot must be ignored
let first = prepareNetworkMatch(a, sources)
let second = prepareNetworkMatch(b, sources)
doAssert first.game.world.heroes.len == 2, "Only occupied seats spawn heroes"
doAssert first.game.world.heroes[0].id == FirstHeroId + 3
doAssert first.game.world.heroes[1].id == FirstHeroId + 8
doAssert first.game.world.heroes[0].team != first.game.world.heroes[1].team
doAssert first.game.world.draftOrder.len == 2
let begin = RoomMessage(kind: BeginMatch, revision: 1, match: 1, hash: setupHash(snapshot))
doAssert second.game.networkHash() == first.game.networkHash()
first.start(begin)
second.start(begin)
var tick = 0'u32
var botCommands = 0
while not first.finished:
  inc tick
  var packet = RoomMessage(kind: TickPacket, match: 1, tick: tick, seats: snapshot.seats)
  # Drive draft from the real seat identifiers, not packed hero indices.
  let id = first.game.world.draftHeroId()
  if id == FirstHeroId + 3:
    let seat = if id == FirstHeroId + 3: 3'u32 else: 8'u32
    packet.commands.add Command(participant: if seat == 3: 1'u32 else: 2'u32,
      seat: seat, payload: GameSubmission(action: ReplayAction(heroId: id,
        kind: ActionDraft, first: 0)).encodeSubmission())
  for bytes in b.outgoing:
    let message = decode(bytes)
    if message.kind == SubmitCommand:
      inc botCommands
      doAssert message.seat == 8
      packet.commands.add Command(participant: 2, seat: message.seat, seatKind: BotSeat,
        sequence: message.sequence, payload: message.payload)
  b.outgoing.setLen(0)
  a.outgoing.setLen(0)
  first.applyPacket(packet)
  second.applyPacket(packet)
  doAssert first.game.stateHash() == second.game.stateHash()
  if tick == 12:
    # Save a live sparse match through the same telemetry path as the menu.
    first.game.sampleMetrics(true)
    var paused = first.game.recorder.data
    paused.metrics = first.game.history.replayMetrics()
    doAssert paused.config.players.len == HeroClassCount
    doAssert paused.header.setup.heroes.len == 2
    doAssert paused.metrics.final.len == 2
    let restored = decodeReplay(encodeReplay(paused))
    doAssert restored.actions == paused.actions
    doAssert restored.hashes == paused.hashes
    doAssert restored.metrics == paused.metrics
    var invalid = paused
    invalid.metrics.final.setLen(HeroClassCount)
    var rejected = false
    try:
      discard encodeReplay(invalid)
    except ReplayError:
      rejected = true
    doAssert rejected, "Replay telemetry must match active heroes, not empty slots"
  doAssert tick < uint32(100 + PreparationTicks)
doAssert botCommands > 0, "An actual sparse bot must submit commands"
first.game.recorder.data.metrics = first.game.history.replayMetrics()
let data = decodeReplay(encodeReplay(first.game.recorder.data))
data.validate()
doAssert data.metrics.final.len == data.header.setup.heroes.len
let replay = newGame(generateMap(data.config.seed, data.config.mapPreset),
  data.config.spawnIntervalTicks, 0, true, data)
replay.historyPlayback = true
replay.replayPlayer = initReplayPlayer(data)
for i in 0 ..< data.hashes.len:
  replay.tickWorld(nil)
doAssert replay.hashCheck.mismatches == 0
doAssert replay.stateHash() == first.game.stateHash()
for action in data.actions:
  doAssert action.heroId in [FirstHeroId + 3, FirstHeroId + 8]
doAssert first.humanHeroIndex() == 0
doAssert second.humanHeroIndex() == -1
doAssert first.game.heroVms.len == 2 and first.game.heroVms[0] == nil
for action in b.outgoing:
  let message = decode(action)
  if message.kind == SubmitCommand:
    doAssert message.seat == 8, "Bot submission must use original lobby seat"
echo "Sparse active heroes, draft, seat ownership, peer and replay hashes passed"
