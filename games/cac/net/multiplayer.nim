## Cards and Casters actions on Polyworld's game-independent room relay.
import
  polyworld/[configs, rooms, roomclients, mailboxes],
  ../core/[battlesetup, bots, replays, sim]

export battlesetup

const
  CacNetworkProtocol* = 2'u32
  CacNetworkTickRate* = SharedTickRate.int
  MaxActionChoices = 64

type
  ActionSubmission* = object
    revision*: uint32
    action*: ReplayAction
    mailbox*: bool
    target*: int32
    text*: string
  NetworkMatch* = ref object
    client*: RoomClient
    game*: GameState
    revision*, tick*, actionCount*: uint32
    started*, finished*: bool
    automaticBots*: bool = true
    humanSeat*: int
    playerNames*: seq[string]
    recorder*: ReplayRecorder
    bots*: seq[BotVm]
    inboxes*: seq[Mailbox]
    onAction*: proc(before, after: GameState, action: ReplayAction)
    roomSeats: seq[rooms.Seat]
    sources: seq[string]
    seed: int64
    playerSlots: seq[int]
    maximumActions: uint32
    matchId: uint32
    pendingPayload: string
    spectator: bool
    finishedReported: bool
    messagesQueued: int

proc cacIdentity*(): GameIdentity =
  ## Match only exact CaC gameplay and action-envelope versions.
  GameIdentity(game: ReplayGame, gameplay: ReplayGameVersion.uint32,
    protocol: CacNetworkProtocol)

proc networkHash*(game: GameState): uint64 =
  ## Reuse the canonical replay hash, excluding presentation event queues.
  game.stateHash()

proc humanSeatFor*(snapshot: RoomMessage, participant: uint32): int =
  ## Selects the first owned human slot for this client's local controls.
  result = -1
  if participant == 0:
    return
  for index, seat in snapshot.seats:
    if seat.owner == participant and seat.kind == HumanSeat:
      return index

proc claimHumanSeat*(client: RoomClient, seat: int, previous = -1) =
  ## Move the local human without taking another participant's seat.
  if seat notin 0 ..< client.snapshot.seats.len or
      client.snapshot.seats[seat].owner notin [0'u32, client.participant]:
    reject("Cannot take another participant's seat")
  for index, current in client.snapshot.seats:
    if index != seat and (index == previous or
        (current.owner == client.participant and current.kind == HumanSeat)):
      if current.owner in [0'u32, client.participant]:
        client.send(RoomMessage(kind: ReleaseSeat, seat: index.uint32))
  client.send(RoomMessage(kind: ClaimSeat, seat: seat.uint32,
    seatKind: HumanSeat, name: "Human"))

proc controllersConnected*(snapshot: RoomMessage): bool =
  ## Require two players and connected owners, independent of ready indicators.
  var occupied = 0
  for seat in snapshot.seats:
    if seat.owner == 0:
      continue
    inc occupied
    var connected = false
    for participant in snapshot.participants:
      if participant.id == seat.owner:
        connected = participant.connected
    if not connected:
      return false
  occupied in MinBattlePlayers .. MaxBattlePlayers

proc returnedToLobby*(session: NetworkMatch): bool =
  ## Leaves a retired battle or an explicitly removed room membership.
  session != nil and session.started and
    (session.client.snapshot.room.len == 0 or
      session.client.snapshot.phase == Lobby)

proc isSpectator*(session: NetworkMatch): bool =
  ## Reports whether the applied roster assigns any existing player locally.
  session != nil and session.spectator

proc pendingAction*(session: NetworkMatch): bool =
  ## Clears revoked intents and blocks clicks until the accepted action arrives.
  if session == nil:
    return false
  var rejected: RoomMessage
  while session.client.takeRejected(rejected):
    if rejected.payload == session.pendingPayload:
      session.pendingPayload.setLen(0)
  session.pendingPayload.len > 0

proc canApplyTick*(session: NetworkMatch, presentationReady: bool): bool =
  ## Keeps empty ticks flowing while an earlier action animates.
  if presentationReady or session.client.catchingUp:
    return true
  for packet in session.client.packets:
    if packet.tick == session.tick + 1:
      return packet.commands.len == 0
  # Let the client discover missing history even while the table is busy.
  true

proc encodeSubmission*(submission: ActionSubmission): string =
  ## Attach the accepted-action ordinal so delayed clicks cannot act twice.
  let action = submission.action
  result.put32(submission.mailbox.uint32)
  result.put32(submission.revision)
  result.put32(cast[uint32](action.playerId))
  if submission.mailbox:
    result.put32(cast[uint32](submission.target))
    result.putString(submission.text)
    return
  result.put32(action.kind.uint32)
  result.put32(cast[uint32](action.handIndex))
  result.put32(cast[uint32](action.attacker))
  result.put32(action.choices.len.uint32)
  for choice in action.choices:
    result.put32(choice.kind.uint32)
    result.put32(cast[uint32](choice.owner))
    result.put32(cast[uint32](choice.creatureId))
    result.put32(cast[uint32](choice.option))
  result.put32(action.indices.len.uint32)
  for index in action.indices:
    result.put32(cast[uint32](index))

proc decodeSubmission*(bytes: string): ActionSubmission =
  ## Validate all wire lengths and enum values before reading game state.
  if bytes.len > MaxCommandBytes:
    reject("CaC command is too large")
  var reader = PacketReader(data: bytes)
  let category = reader.get32()
  if category > 1:
    reject("Unknown CaC command category")
  result.mailbox = category == 1
  result.revision = reader.get32()
  result.action.playerId = cast[int32](reader.get32())
  if result.mailbox:
    result.target = cast[int32](reader.get32())
    result.text = reader.getString(MaxChatBytes)
    if result.text.len == 0:
      reject("CaC mailbox message is empty")
    if reader.cursor != bytes.len:
      reject("Trailing CaC mailbox bytes")
    return
  let kind = reader.get32()
  if kind notin ActionPlayCard.uint32 .. ActionGameKindHigh.uint32:
    reject("Unknown CaC action")
  result.action.kind = kind.uint8
  result.action.handIndex = cast[int32](reader.get32())
  result.action.attacker = cast[int32](reader.get32())
  let choices = reader.get32()
  if choices > MaxActionChoices.uint32:
    reject("Too many CaC action targets")
  for index in 0 ..< choices.int:
    let choiceKind = reader.get32()
    if choiceKind > ChoiceKind.high.ord.uint32:
      reject("Unknown CaC target kind")
    result.action.choices.add ReplayChoice(kind: choiceKind.uint8,
      owner: cast[int32](reader.get32()),
      creatureId: cast[int32](reader.get32()),
      option: cast[int32](reader.get32()))
  let indices = reader.get32()
  if indices > MaxActionChoices.uint32:
    reject("Too many CaC discard indices")
  for index in 0 ..< indices.int:
    result.action.indices.add cast[int32](reader.get32())
  if reader.cursor != bytes.len:
    reject("Trailing CaC command bytes")

proc ownsPlayer(session: NetworkMatch, player: int): bool =
  ## Requires applied ownership and the latest relay permission to agree.
  if player notin 0 ..< session.playerSlots.len:
    return false
  let slot = session.playerSlots[player]
  slot < session.roomSeats.len and
    session.roomSeats[slot].owner == session.client.participant and
    slot < session.client.snapshot.seats.len and
    session.client.snapshot.seats[slot].owner == session.client.participant

proc updateControllers(session: NetworkMatch, seats: seq[rooms.Seat]) =
  ## Transfers existing players after their authoritative roster tick applies.
  session.roomSeats = seats
  session.humanSeat = -1
  session.spectator = true
  for player, slot in session.playerSlots:
    if slot >= seats.len or seats[slot].owner != session.client.participant:
      continue
    session.spectator = false
    if seats[slot].kind == HumanSeat:
      if session.humanSeat < 0:
        session.humanSeat = player
    elif session.bots[player] == nil and slot < session.sources.len and
        session.sources[slot].len > 0:
      session.bots[player] = loadBot(session.sources[slot], player.int32)
      session.bots[player].ensureSeed(session.seed)

proc submitMailbox*(session: NetworkMatch, sender, target: int,
    text: openArray[char]): int32 =
  ## Send owned policy mail through the same ordered history as its actions.
  if not session.started or session.finished or not session.client.welcomed or
      session.client.catchingUp or session.client.snapshot.phase != Playing or
      sender notin 0 ..< session.playerSlots.len or target < -2 or target == -1 or
      target >= session.playerSlots.len or text.len == 0 or
      text.len > MaxChatBytes or session.messagesQueued >= MaxMailboxMessages:
    return 0
  let slot = session.playerSlots[sender]
  if not session.ownsPlayer(sender):
    return 0
  var message = newString(text.len)
  for index, value in text:
    message[index] = value
  let payload = ActionSubmission(mailbox: true, target: target.int32,
    text: message, action: ReplayAction(playerId: sender.int32))
  if session.client.submit(slot.uint32, payload.encodeSubmission()):
    inc session.messagesQueued
    result = if target == -2: session.playerSlots.len.int32 else: 1

proc prepareNetworkMatch*(client: RoomClient,
    sources: openArray[string] = []): NetworkMatch =
  ## Build identical public decks while compiling only privately owned bots.
  let
    snapshot = client.setupSnapshot()
    setup = parseBattleSetup(snapshot.payload)
  if snapshot.tickRate != CacNetworkTickRate.uint32 or
      snapshot.seats.len != setup.classes.len:
    reject("CaC room settings do not match its seat count or tick rate")
  result = NetworkMatch(client: client, revision: snapshot.revision,
    humanSeat: -1, spectator: true, maximumActions: setup.maxActions,
    roomSeats: snapshot.seats, seed: setup.seed.int64)
  for source in sources:
    result.sources.add source
  var
    selected: seq[sim.Seat]
    ownedSources: seq[string]
  for slot, seat in snapshot.seats:
    if seat.owner == 0:
      continue
    discard snapshot.humanSeatFor(seat.owner)
    var name = seat.name
    if seat.kind == HumanSeat:
      name = ""
      for participant in snapshot.participants:
        if participant.id == seat.owner:
          name = participant.name
      if name.len == 0:
        reject("A human seat has no named participant")
      if seat.owner == client.participant and result.humanSeat < 0:
        result.humanSeat = selected.len
    result.playerSlots.add slot
    result.playerNames.add name
    selected.add precon(setup.classes[slot])
    var source: string
    if seat.owner == client.participant:
      result.spectator = false
      if seat.kind == BotSeat and slot < sources.len:
        source = sources[slot]
    ownedSources.add source
  if selected.len notin MinBattlePlayers .. MaxBattlePlayers:
    reject("Assign at least two seats before preparing a battle")
  result.bots = loadBots(ownedSources)
  result.inboxes = bots.inboxes
  for bot in result.bots:
    if bot != nil:
      if bot.failed:
        reject("Cannot compile local policy: " & bot.lastError)
      bot.ensureSeed(setup.seed.int64)
  result.game = newGame(selected, setup.seed.int64, recordEvents = true)
  var config = GameConfig(seed: setup.seed, maxTicks: setup.maxActions.int32)
  for name in result.playerNames:
    config.players.add PlayerConfig(name: name)
  result.recorder = initReplayRecorder(
    matchSetup(selected, setup.seed, setup.maxActions), config)

proc requestStart*(client: RoomClient,
    sources: openArray[string] = []): NetworkMatch =
  ## Request a host start bound to the current authoritative setup revision.
  if client.snapshot.phase != Lobby or
      client.snapshot.participant != client.participant:
    reject("Only the host can start the lobby")
  result = prepareNetworkMatch(client, sources)
  client.send(RoomMessage(kind: StartMatch, revision: result.revision,
    hash: setupHash(client.snapshot)))

proc queueAction(session: NetworkMatch, action: ReplayAction): bool =
  ## Submit one legal owned intent without mutating the authoritative game.
  let player = action.playerId.int
  if not session.started or session.finished or session.pendingAction or
      not session.client.welcomed or session.client.catchingUp or
      session.client.snapshot.phase != Playing or
      player notin 0 ..< session.playerSlots.len or
      session.game.actingPlayer() != player:
    return false
  let slot = session.playerSlots[player]
  if not session.ownsPlayer(player):
    return false
  var probe = copyGameState(session.game)
  if not probe.applyAction(action):
    return false
  let payload = ActionSubmission(revision: session.actionCount,
    action: action).encodeSubmission()
  if session.client.submit(slot.uint32, payload):
    session.pendingPayload = payload
    result = true

proc submitAction*(session: NetworkMatch, action: ReplayAction): bool =
  ## Queue a local human's action; the relay packet owns its application.
  session != nil and action.playerId.int == session.humanSeat and
    session.queueAction(action)

proc pumpBots*(session: NetworkMatch) =
  ## Decide once per accepted action, after catch-up, only on the bot's owner.
  if session == nil or not session.started or session.finished or
      session.pendingAction or not session.client.welcomed or
      session.client.catchingUp or session.client.snapshot.phase != Playing:
    return
  let player = session.game.actingPlayer()
  if player notin 0 ..< session.bots.len or not session.ownsPlayer(player):
    return
  if session.game.dead(player) and not session.game.waitingChoice:
    discard session.queueAction(ReplayAction(kind: ActionEndTurn,
      playerId: player.int32))
    return
  if session.roomSeats[session.playerSlots[player]].kind != BotSeat or
      session.bots[player] == nil:
    return
  let bot = session.bots[player]
  session.messagesQueued = 0
  bots.inboxes = session.inboxes
  bot.onSendChat = proc(sender, target: int,
      text: openArray[char]): int32 =
    ## Preserve private policy ownership while queuing public mail.
    session.submitMailbox(sender, target, text)
  try:
    if bot.runDecision(session.game, apply = false) == BotFailed:
      reject("Local policy failed: " & bot.lastError)
  finally:
    bot.onSendChat = nil
  if not session.queueAction(bot.action):
    reject("Local policy selected an invalid action")

proc start*(session: NetworkMatch, message: RoomMessage) =
  ## Confirm shared initialization and report the separate game-state digest.
  if message.kind != BeginMatch or message.revision != session.revision or
      message.match != session.client.match:
    reject("CaC setup changed before the battle started")
  let hash = session.game.networkHash()
  session.client.send(RoomMessage(kind: ReportHash, match: message.match,
    tick: 0, hash: hash))
  if setupHash(session.client.setupSnapshot()) != message.hash:
    reject("CaC initial configuration differs from the agreed battle setup")
  session.matchId = message.match
  session.started = true
  if session.automaticBots:
    session.pumpBots()

proc applyPacket*(session: NetworkMatch, packet: RoomMessage) =
  ## Apply owned, current intents in relay order and acknowledge exactly once.
  if not session.started or packet.kind != TickPacket or
      packet.match != session.matchId or packet.tick != session.tick + 1:
    reject("CaC received an unexpected relay tick")
  var submissions: seq[ActionSubmission]
  for command in packet.commands:
    if command.participant == 0 or
        command.seat >= session.client.setupSnapshot().seats.len.uint32:
      reject("CaC command has an invalid participant or slot")
    let submission = decodeSubmission(command.payload)
    let player = submission.action.playerId.int
    if player notin 0 ..< session.playerSlots.len or
        session.playerSlots[player] != command.seat.int:
      reject("CaC action does not belong to its claimed player")
    if submission.mailbox and (submission.target < -2 or
        submission.target == -1 or
        submission.target >= session.playerSlots.len.int32):
      reject("CaC mailbox recipient does not exist")
    submissions.add submission
  for index, submission in submissions:
    let command = packet.commands[index]
    if command.participant == session.client.participant and
        command.payload == session.pendingPayload:
      session.pendingPayload.setLen(0)
    if submission.mailbox:
      if not session.finished:
        let message = ReplayAction(kind: ActionMailbox,
          tick: session.actionCount, playerId: submission.action.playerId,
          target: submission.target, text: submission.text)
        session.recorder.record(message)
        discard session.inboxes.applyMailbox(message)
      continue
    if session.finished or submission.revision != session.actionCount or
        submission.action.playerId.int != session.game.actingPlayer():
      continue
    var
      action = submission.action
      next = copyGameState(session.game)
    if not next.applyAction(action):
      continue
    let before = copyGameState(session.game)
    session.game = next
    inc session.actionCount
    action.tick = session.actionCount
    session.recorder.record(action)
    session.recorder.recordHash(session.game.stateHash())
    if session.onAction != nil:
      session.onAction(before, session.game, action)
    session.finished = session.game.gameOver or
      session.actionCount >= session.maximumActions
  session.tick = packet.tick
  session.client.appliedTick(packet.tick)
  session.updateControllers(packet.seats)
  if packet.tick mod CacNetworkTickRate.uint32 == 0:
    session.client.send(RoomMessage(kind: ReportHash,
      match: session.matchId, tick: packet.tick,
      hash: session.game.networkHash()))
  if session.finished and not session.finishedReported:
    session.finishedReported = true
    session.client.send(RoomMessage(kind: FinishMatch,
      match: session.matchId, tick: packet.tick,
      hash: session.game.networkHash()))
  elif session.automaticBots:
    session.pumpBots()

proc abort*(session: NetworkMatch, detail: string) =
  ## Stop failed sessions explicitly and retain the visible explanation.
  session.client.error = detail
  session.client.snapshot.phase = Desynced
  session.client.send(RoomMessage(kind: AbortMatch,
    match: session.client.match, detail: detail))
