import
  jsony,
  polyworld/[rooms, roomclients, tapes, metrics, mailboxes, bodies, hashes, menus],
  bots, chats, content, controls, maps, presets, replays, sim, matchnotices

const GotaNetworkProtocol* = 5'u32

type NetworkMatch* = ref object
  client*: RoomClient
  game*: Game
  revision*: uint32
  started*, finished*: bool
  match: uint32
  seats: seq[Seat]
  sources*: seq[string]
  loadedSources: seq[string]
  spectator: bool
  heroSeats: seq[int]
  decisionTick: int32 = -1
  humanChat*: seq[HumanChatMessage]
  noticeDelivered: bool

proc networkHash*(game: Game): uint64 =
  ## Includes immutable configuration alongside the normal replay state hash.
  var configHash = HashySeed
  configHash.addHashy(game.config.toJson())
  (uint64(configHash) shl 32) or game.stateHash()

proc gotaIdentity*(): GameIdentity =
  ## Identifies the exact gameplay and game-command protocol on this client.
  GameIdentity(
    game: ReplayGame, gameplay: uint32(ReplayGameVersion),
    protocol: GotaNetworkProtocol
  )

proc localActiveSeats*(policies: openArray[LocalPolicy], humanSeat: int): seq[int] =
  ## Empty policies are absent players, except for the explicitly assigned human.
  for i, policy in policies:
    if i == humanSeat or policy.bytes.len > 0:
      result.add i

proc humanSeatFor*(snapshot: RoomMessage, participant: uint32): int =
  ## Selects the first human-controlled slot for the local hero interface.
  result = -1
  for i, seat in snapshot.seats:
    if seat.owner == participant and participant != 0 and seat.kind == HumanSeat:
      return i

proc humanHeroIndex*(session: NetworkMatch): int =
  ## Maps the lobby's stable seat to the packed active-hero array used by UI.
  let seat = session.client.snapshot.humanSeatFor(session.client.participant)
  for i, heroSeat in session.heroSeats:
    if heroSeat == seat:
      return i
  -1

proc claimHumanSeat*(client: RoomClient, seat: int, previous = -1) =
  ## Moves the local human, including a claim still awaiting acknowledgement.
  if seat < 0 or seat >= client.snapshot.seats.len or
    (client.snapshot.participant != client.participant and
      client.snapshot.seats[seat].owner notin [0'u32, client.participant]):
      reject("Cannot take another participant's slot")
  for i, current in client.snapshot.seats:
    if i != seat and (i == previous or
      (current.owner == client.participant and current.kind == HumanSeat)):
        if current.owner in [0'u32, client.participant]:
          client.send(RoomMessage(kind: ReleaseSeat, seat: uint32(i)))
  client.send(RoomMessage(kind: ClaimSeat, seat: uint32(seat),
    seatKind: HumanSeat, name: client.name))

proc encodeSubmission*(submission: GameSubmission): string =
  ## Encodes game-owned bytes that the relay never interprets.
  let action = submission.action
  result.put32(if submission.humanChat: 2'u32 else: uint32(submission.mailbox))
  result.put32(cast[uint32](action.heroId))
  if submission.mailbox or submission.humanChat:
    result.put32(cast[uint32](action.first))
    result.putString(submission.text)
  else:
    result.put32(uint32(action.kind))
    result.put32(cast[uint32](action.slot))
    result.put32(cast[uint32](action.first))
    result.put32(cast[uint32](action.second))
    result.put32(cast[uint32](int32(action.offset.x)))
    result.put32(cast[uint32](int32(action.offset.y)))

proc decodeSubmission*(bytes: string): GameSubmission =
  ## Checks the complete game payload before it can reach the simulation.
  var reader = PacketReader(data: bytes)
  let kind = reader.get32()
  if kind > 2:
    reject("Unknown GotA command category")
  result.mailbox = kind == 1
  result.humanChat = kind == 2
  result.action.heroId = cast[int32](reader.get32())
  if result.mailbox or result.humanChat:
    result.action.first = cast[int32](reader.get32())
    result.text = reader.getString(MaxChatBytes)
    if result.humanChat and (not result.text.validHumanChat or
        result.action.first notin [-2'i32, -1'i32]):
      reject("Invalid GotA human chat")
  else:
    let actionKind = reader.get32()
    if actionKind notin [uint32(ActionWalkTo), ActionAttackTarget,
      ActionBuyItem, ActionUseItem, ActionAttackMove, ActionCastTarget,
      ActionCastPoint, ActionUseItemAt, ActionLevelAbility, ActionBuyback,
      ActionDraft, ActionStop, ActionSellItem, ActionSwapItems,
      ActionQueueWalkTo, ActionQueueAttackMove, ActionQueueAttackTarget]:
        reject("Unknown GotA action")
    result.action.kind = uint8(actionKind)
    result.action.slot = cast[int32](reader.get32())
    result.action.first = cast[int32](reader.get32())
    result.action.second = cast[int32](reader.get32())
    result.action.offset.x = Fixed(cast[int32](reader.get32()))
    result.action.offset.y = Fixed(cast[int32](reader.get32()))
    if not result.action.offset.validTileOffset:
      reject("Invalid fractional tile offset")
  if reader.cursor != bytes.len:
    reject("Trailing GotA command bytes")

proc returnedToLobby*(session: NetworkMatch): bool =
  ## A room snapshot retires the old result view even for guests who have not
  ## clicked Back. Setup revisions alone cannot identify a match lifetime.
  session != nil and session.started and
    (session.client.snapshot.room.len == 0 or session.client.snapshot.phase == Lobby)

proc prepareNetworkMatch*(
    client: RoomClient, sources: openArray[string]
): NetworkMatch =
  ## Loads only locally owned policies and builds the shared initial world.
  let snapshot = client.setupSnapshot()
  if snapshot.tickRate != uint32(TickRate) or
    snapshot.seats.len != HeroClassCount:
      reject("GotA requires ten seats and 24 ticks per second")
  var config = parseConfig(snapshot.payload)
  config.playerSlot = 0
  config.players = newSeq[PlayerConfig](HeroClassCount)
  var activeSeats: seq[int]
  for i, seat in snapshot.seats:
    if seat.owner == 0:
      continue
    let index = activeSeats.len
    activeSeats.add i
    config.players[index].name = seat.name
    if seat.kind == HumanSeat:
      config.players[index].name = ""
      for participant in snapshot.participants:
        if participant.id == seat.owner:
          config.players[index].name = participant.name
          break
      if config.players[index].name.len == 0:
        reject("Human seat has no named participant")
  if activeSeats.len == 0:
    reject("GotA requires at least one occupied seat")
  let
    map = generateMap(config.seed, config.mapPreset)
    game = newGame(
      map, config.spawnIntervalTicks, HeroClassCount, false, ReplayData(),
      draftMode = config.draftMode, activeSeats = activeSeats
    )
  game.networked = true
  game.recorder = initReplayRecorder(
    currentSetup(game, uint32(config.maxTicks)), map.preset
  )
  game.recorder.data.config = config
  game.replayPlayer = ReplayPlayer(data: game.recorder.data)
  var ownedSources = newSeq[string](activeSeats.len)
  for index, i in activeSeats:
    let seat = snapshot.seats[i]
    if seat.owner == client.participant and seat.kind == BotSeat and i < sources.len:
      ownedSources[index] = sources[i]
  game.loadBotSources(ownedSources)
  result = NetworkMatch(client: client, game: game, revision: snapshot.revision,
    spectator: true, heroSeats: activeSeats, sources: @sources,
    loadedSources: ownedSources)
  for seat in snapshot.seats:
    result.seats.add seat
    if seat.owner != 0 and seat.owner == client.participant:
      result.spectator = false

proc requestStart*(client: RoomClient, sources: openArray[string]): NetworkMatch =
  ## Host intent is independent of cosmetic Ready. Bind the initial world to the
  ## exact authoritative revision; peers prepare and verify it on BeginMatch.
  if client.snapshot.phase != Lobby or client.snapshot.participant != client.participant:
    reject("Only the owner can start a lobby")
  result = prepareNetworkMatch(client, sources)
  client.send(RoomMessage(kind: StartMatch, revision: result.revision,
    hash: setupHash(client.snapshot)))

proc isSpectator*(session: NetworkMatch): bool =
  ## Bot owners are controllers too; only seatless participants watch locally.
  ## Keep this match's role even after a lobby update clears/reassigns seats.
  session != nil and session.spectator

proc hasLocalControl*(session: NetworkMatch): bool =
  ## Only existing match actors can be taken over without a new game setup.
  if session == nil or session.client.participant == 0: return false
  for seat in session.heroSeats:
    if seat < session.client.snapshot.seats.len and
        session.client.snapshot.seats[seat].owner == session.client.participant:
      return true

proc syncControllers*(session: NetworkMatch) =
  ## Changes local policy ownership without resetting other private runtimes.
  var desired = newSeq[string](session.heroSeats.len)
  for index, seat in session.heroSeats:
    if seat >= session.seats.len or seat >= session.client.snapshot.seats.len:
      continue
    let
      applied = session.seats[seat]
      current = session.client.snapshot.seats[seat]
    if applied.owner == session.client.participant and
        current.owner == session.client.participant and
        applied.kind == BotSeat and current.kind == BotSeat and
        seat < session.sources.len:
      desired[index] = session.sources[seat]
  if desired != session.loadedSources:
    for index, source in desired:
      if index >= session.loadedSources.len or
          source != session.loadedSources[index]:
        session.game.heroVms[index] = nil
    session.game.loadBotSources(desired, preserve = true)
    session.loadedSources = desired

proc promoteController*(session: NetworkMatch) =
  ## Leaves local spectator playback only once the archive reaches its live edge.
  session.spectator = false
  session.seats = session.client.appliedSeats
  session.syncControllers()

proc liveControlReady*(session: NetworkMatch): bool =
  ## Recovery replays packets without generating new human or policy intents.
  session != nil and session.started and session.client.connected and
    session.client.welcomed and not session.client.catchingUp and
    session.client.snapshot.phase == Playing and not session.finished and
    uint32(session.game.world.tick) == session.client.applied

proc flushSubmissions*(session: NetworkMatch) =
  ## Submits human and private bot intents through one ownership-checked path.
  var rejected: RoomMessage
  while session.client.takeRejected(rejected):
    discard
  session.syncControllers()
  if not session.hasLocalControl() or not session.liveControlReady():
    clearPlayerCommands()
    session.game.submissions.setLen(0)
    return
  session.game.flushPlayerCommands()
  for submission in session.game.submissions:
    let index = session.game.world.heroIndex(submission.action.heroId)
    if index < 0:
      reject("Unable to find the local GotA actor")
    let seat = session.heroSeats[index]
    if seat >= session.client.snapshot.seats.len or
        session.client.snapshot.seats[seat].owner != session.client.participant or
        (submission.humanChat and
          session.client.snapshot.seats[seat].kind != HumanSeat):
      continue
    if not session.client.submit(uint32(seat), submission.encodeSubmission()):
      reject("Unable to queue a local GotA command")
  session.game.submissions.setLen(0)

proc canHumanChat*(session: NetworkMatch): bool =
  ## A bot controller or spectator cannot impersonate an unassigned human.
  session.liveControlReady() and session.humanHeroIndex() >= 0

proc sendHumanChat*(session: NetworkMatch, text: string, team = false): bool =
  ## Reuse the game submission envelope, never a second shared chat protocol.
  if not session.canHumanChat or not text.validHumanChat: return false
  let index = session.humanHeroIndex()
  result = session.client.submit(uint32(session.heroSeats[index]),
    GameSubmission(humanChat: true, text: text, action: ReplayAction(
      heroId: session.game.world.heroes[index].id,
      first: (if team: -1'i32 else: -2'i32))).encodeSubmission())

proc visibleHumanChat*(session: NetworkMatch): seq[HumanChatMessage] =
  ## Filters recorded chat by the viewer and playhead, including after seeking.
  if session == nil: return
  let viewer = session.humanHeroIndex()
  session.game.visibleReplayChat(
    if session.isSpectator: -1
    elif viewer >= 0: session.game.world.heroes[viewer].team.ord
    else: 2)

proc decide(session: NetworkMatch) =
  ## Runs owned VMs for live rooms while closed rooms only drain buffered ticks.
  session.syncControllers()
  if not session.hasLocalControl() or not session.liveControlReady() or
    session.decisionTick == session.game.world.tick or
    session.finished or session.client.snapshot.phase in {Ended, Desynced}:
      return
  session.decisionTick = session.game.world.tick
  session.game.runBotDecisions()
  session.flushSubmissions()

proc resumeControls*(session: NetworkMatch) =
  ## Resumes decisions after CaughtUp even when no new tick was delivered.
  session.decide()

proc start*(session: NetworkMatch, message: RoomMessage) =
  ## Confirms the immutable setup before any VM or live tick executes.
  if message.revision != session.revision:
    reject("GotA setup revision changed before startup")
  if setupHash(session.client.setupSnapshot()) != message.hash:
    reject("GotA initial configuration differs from the agreed setup hash")
  session.match = message.match
  session.client.send(RoomMessage(
    kind: ReportHash, match: session.client.match, tick: 0,
    hash: session.game.networkHash()
  ))
  session.started = true
  session.decide()

proc applyPacket*(session: NetworkMatch, packet: RoomMessage, localPlayback = false) =
  ## Validates game payloads and executes an admitted tick in canonical phases.
  let
    game = session.game
    client = session.client
  if not session.started or packet.kind != TickPacket or
    packet.match != session.match or packet.tick != uint32(game.world.tick + 1):
      reject("GotA received an unexpected simulation tick")
  # Validate the entire packet before applying any part of it.
  var submissions: seq[GameSubmission]
  for command in packet.commands:
    if command.participant == 0 or command.seat >= uint32(HeroClassCount):
      reject("GotA command refers to an invalid slot")
    let submission = decodeSubmission(command.payload)
    let heroIndex = game.world.heroIndex(submission.action.heroId)
    if heroIndex < 0 or session.heroSeats[heroIndex] != int(command.seat):
      reject("GotA command hero does not belong to this seat")
    if submission.humanChat and command.seatKind != HumanSeat:
      reject("Human chat requires a human seat")
    submissions.add submission
  # A cached spectator packet is replayed with its mailbox commands as well as
  # actions. Never append duplicate actions/hashes, run policies, or publish ACKs.
  let recorder = game.recorder
  let history = game.historyPlayback
  if localPlayback:
    if not session.isSpectator:
      reject("Local packet playback requires a spectator")
    if recorder != nil and int(packet.tick) <= recorder.data.hashes.len:
      game.recorder = ReplayRecorder(data: recorder.data)
      game.recorder.data.actions = @[]
      game.recorder.data.events = @[]
    game.historyPlayback = false
  defer:
    game.recorder = recorder
    game.historyPlayback = history
  for ordinal, submission in submissions:
    if submission.humanChat:
      let index = game.world.heroIndex(submission.action.heroId)
      game.recorder.recordChat(ReplayChat(
        tick: packet.tick, kind: HumanReplayChat,
        sender: submission.action.heroId, target: submission.action.first,
        text: submission.text))
      session.humanChat.appendHumanChat(HumanChatMessage(
        tick: packet.tick, ordinal: ordinal,
        sender: game.recorder.data.config.players[index].name,
        text: submission.text, team: submission.action.first == -1,
        senderTeam: game.world.heroes[index].team.ord))
    elif submission.mailbox:
      discard game.deliverChat(
        game.world.heroIndex(submission.action.heroId),
        int(submission.action.first), submission.text, int32(packet.tick)
      )
    else:
      var action = submission.action
      action.tick = packet.tick
      game.networkActions.add action
  game.tickWorld(nil)
  if uint32(game.world.tick) != packet.tick:
    reject("GotA failed to execute the authoritative tick")
  # The game clock owns presentation reminders, including during local replay.
  let noticeDue = game.matchNoticeDue()
  if noticeDue:
    game.recorder.recordChat(ReplayChat(
      tick: packet.tick, kind: SystemReplayChat,
      target: -2, text: ThreeMinuteNotice))
  if noticeDue and not session.noticeDelivered:
    session.noticeDelivered = true
    session.humanChat.appendHumanChat(HumanChatMessage(
      tick: packet.tick, ordinal: -1, system: true,
      text: ThreeMinuteNotice))
  for outcome in game.actionResults:
    if localPlayback:
      continue
    game.publishActionResult(outcome.action.heroId, outcome.accepted)
    let seat = game.world.heroIndex(outcome.action.heroId)
    if outcome.action.kind == ActionBuyItem and seat >= 0 and
      session.heroSeats[seat] < client.snapshot.seats.len and
      client.snapshot.seats[session.heroSeats[seat]].owner == client.participant and
      game.heroVms[seat] == nil:
        purchaseReceipt = PurchaseReceipt(
          serial: purchaseReceipt.serial + 1,
          heroId: outcome.action.heroId, itemId: outcome.action.first,
          accepted: outcome.accepted
        )
  game.actionResults.setLen(0)
  # Local viewing still completes metric ticks: finishTick deduplicates command
  # totals on rewind, and history.capture retains only first-traversal samples.
  game.sampleMetrics(game.finished())
  game.metrics.finishTick(game.world.tick)
  if localPlayback:
    if recorder != nil and int(packet.tick) <= recorder.data.hashes.len and
      recorder.data.hashes[int(packet.tick) - 1] != game.stateHash():
        reject("Spectator replay state hash differs")
    return
  client.appliedTick(packet.tick)
  if packet.seats.len > 0:
    session.seats = packet.seats
  if packet.tick mod uint32(TickRate) == 0:
    client.send(RoomMessage(
      kind: ReportHash, match: client.match, tick: packet.tick,
      hash: game.networkHash()
    ))
  session.finished = game.finished() or game.world.tick >= game.durationTicks()
  if session.finished:
    client.send(RoomMessage(
      kind: FinishMatch, match: client.match, tick: packet.tick,
      hash: game.networkHash()
    ))
  else:
    session.decide()

proc abort*(session: NetworkMatch, detail: string) =
  ## Stops explicitly on invalid input rather than recovering silently.
  session.client.error = detail
  session.client.snapshot.phase = Desynced
  session.client.send(RoomMessage(
    kind: AbortMatch, match: session.client.match, detail: detail
  ))
