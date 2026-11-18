## Gods of the Arena actions, chat transcript, and playback cursor.

import
  std/os,
  fixxy,
  polyworld/[bodies, tapes, metrics, mailboxes],
  chats, content, presets

export presets

export fixxy

const
  ReplayGame* = "gods_of_the_arena"
  ReplayFormatVersion* = 7'u16
  ## This client supports only this gameplay version. Bump it when rules change.
  ## Older replays use their archived client; never add compatibility branches.
  ReplayGameVersion* = 83'u16
  ActionWalkTo* = 1'u8
  ActionAttackTarget* = 2'u8
  ActionBuyItem* = 3'u8
  ActionUseItem* = 4'u8
  ActionAttackMove* = 5'u8
  ActionCastTarget* = 6'u8
  ActionCastPoint* = 10'u8
  ActionUseItemAt* = 15'u8
  ActionLevelAbility* = 16'u8
  ActionBuyback* = 17'u8
  ActionDraft* = 18'u8
  ActionStop* = 19'u8
  ActionSellItem* = 20'u8
  ActionSwapItems* = 21'u8
  ActionQueueWalkTo* = 22'u8
  ActionQueueAttackMove* = 23'u8
  ActionQueueAttackTarget* = 24'u8
  MaxReplayBytes* = 64 * 1024 * 1024
  MaxReplayActions* = 10_000_000
  MaxReplayHashes* = 100_000_000
  MaxReplayHeroes* = 256
  MaxReplayChats* = 1_000_000
  HumanReplayChat* = 1'u8
  PolicyReplayChat* = 2'u8
  SystemReplayChat* = 3'u8

type
  ReplayHero* = object
    id*: int32
    team*: uint8
    slot*: uint8
    lane*: uint8
    class*: uint8

  Setup* = object
    mapSeed*: int32
    mapHash*: uint64
    tickRate*: uint16
    gridTiles*: uint16
    spawnIntervalTicks*: uint32
    maximumTicks*: uint32
      ## Battle ticks only; draft deadlines and opening preparation are separate.
    heroes*: seq[ReplayHero]
    drafting*: bool
    draftMode*: DraftMode

  ReplayAction* = object
    tick*: uint32
    heroId*: int32
    kind*: uint8
    offset*: FixedVec2
      ## Movement and ground aim offsets from the named tile center.
    slot*: int32
    first*: int32
    second*: int32

  ReplayChat* = object
    tick*: uint32
    kind*: uint8
    sender*: int32
      ## Stable hero ID; system notices have no sender.
    target*: int32
      ## -2 is all, -1 is team, nonnegative is a policy mailbox index.
    text*: string

  ReplayHeader* = TapeHeader[Setup]
  ReplayData* = ActionTape[Setup, ReplayAction, ReplayMetrics,
    GotaConfig, ReplayChat]
  ReplayRecorder* = TapeRecorder[Setup, ReplayAction, ReplayMetrics,
    GotaConfig, ReplayChat]
  ReplayPlayer* = TapePlayer[Setup, ReplayAction, ReplayMetrics,
    GotaConfig, ReplayChat]
  ReplayChatView* = object
    processed: int
    viewerTeam: int
    history: seq[HumanChatMessage]

proc fail(message: string) {.noreturn.} =
  ## Raises one Gods of the Arena replay error.
  raise newException(ReplayError, message)

proc initReplayData*(
    setup: Setup, preset = defaultConfig()
): ReplayData =
  ## Creates a replay containing the match setup, config, and action tape.
  result.header = initActionTape[Setup, ReplayAction](
    setup,
    ReplayFormatVersion,
    ReplayGameVersion
  ).header
  result.config = GotaConfig(
    seed: setup.mapSeed,
    maxTicks: int32(setup.maximumTicks),
    players: unnamedPlayers(HeroClassCount),
    spawnIntervalTicks: int32(setup.spawnIntervalTicks),
    mapPreset: preset,
    draftMode: setup.draftMode
  )
  result.config.mapPreset.mapSize = setup.gridTiles.int

proc initReplayRecorder*(
    setup: Setup, preset = defaultConfig()
): ReplayRecorder =
  ## Creates an in-memory recorder owning the complete replay data.
  ReplayRecorder(data: initReplayData(setup, preset))

proc validateChat(setup: Setup, message: ReplayChat) =
  ## Checks chat metadata without treating private policy text as UI text.
  if message.text.len == 0 or message.text.len > MaxChatBytes:
    fail("replay chat text has an invalid length")
  case message.kind
  of SystemReplayChat:
    if message.sender != 0 or message.target != -2 or
        not message.text.validHumanChat:
      fail("replay system chat is invalid")
  of HumanReplayChat, PolicyReplayChat:
    var knownSender = false
    for hero in setup.heroes:
      if hero.id == message.sender:
        knownSender = true
        break
    if not knownSender:
      fail("replay chat references an unknown sender")
    if message.target < -2 or message.target >= setup.heroes.len.int32:
      fail("replay chat references an unknown recipient")
    if message.kind == HumanReplayChat and
        (message.target notin [-2'i32, -1'i32] or
        not message.text.validHumanChat):
      fail("replay human chat is invalid")
  else:
    fail("replay chat kind is invalid")

proc recordChat*(recorder: ReplayRecorder, message: ReplayChat) =
  ## Retains the full transcript independently of bounded on-screen history.
  if recorder == nil:
    return
  recorder.data.header.setup.validateChat(message)
  recorder.data.events.appendAction(message, MaxReplayChats)

proc chatAt*(view: var ReplayChatView, data: ReplayData, tick: uint32,
    viewerTeam = -1): seq[HumanChatMessage] =
  ## Shows human chat and notices up to the playhead, including after a seek.
  if view.processed > data.events.len or view.viewerTeam != viewerTeam:
    view = ReplayChatView(viewerTeam: viewerTeam)
  while view.processed < data.events.len:
    let
      ordinal = view.processed
      event = data.events[ordinal]
    inc view.processed
    if event.kind == PolicyReplayChat:
      continue
    var message = HumanChatMessage(
      tick: event.tick, ordinal: ordinal, text: event.text,
      system: event.kind == SystemReplayChat,
      team: event.target == -1)
    if not message.system:
      for i, hero in data.header.setup.heroes:
        if hero.id == event.sender:
          message.sender = data.config.players[i].name
          message.senderTeam = hero.team.int
          break
    if not message.team or viewerTeam < 0 or
        viewerTeam == message.senderTeam:
      view.history.add message
  var
    first = 0
    last = view.history.len
  while first < last:
    let middle = (first + last) div 2
    if view.history[middle].tick <= tick:
      first = middle + 1
    else:
      last = middle
  view.history[max(0, first - MaxHumanChatMessages) ..< first]

proc record*(recorder: ReplayRecorder, action: ReplayAction) =
  ## Appends one bot action in deterministic tick order.
  if recorder == nil:
    return
  if not action.offset.validTileOffset:
    fail("replay point offset is outside its tile")
  if action.kind != ActionWalkTo and
      action.kind != ActionAttackTarget and
      action.kind != ActionBuyItem and
      action.kind != ActionUseItem and
      action.kind != ActionUseItemAt and
      action.kind != ActionAttackMove and
      action.kind != ActionCastTarget and
      action.kind != ActionCastPoint and
      action.kind != ActionLevelAbility and
      action.kind != ActionBuyback and
      action.kind != ActionDraft and
      action.kind != ActionStop and action.kind != ActionSellItem and
        action.kind != ActionSwapItems and
        action.kind != ActionQueueWalkTo and
        action.kind != ActionQueueAttackMove and
        action.kind != ActionQueueAttackTarget:
    fail("replay action kind is invalid")
  recorder.data.actions.appendAction(action, MaxReplayActions)

proc recordCast*(
    recorder: ReplayRecorder,
    tick: uint32,
    heroId, slot, first, second: int32,
    ground: bool,
    offset = FixedVec2Zero
) =
  ## Records every submitted cast, including invalid signed slot arguments.
  recorder.record ReplayAction(
    tick: tick, heroId: heroId,
    kind: (if ground: ActionCastPoint else: ActionCastTarget), slot: slot,
    first: first, second: second, offset: offset
  )

proc recordLevelAbility*(
    recorder: ReplayRecorder, tick: uint32, heroId, slot: int32
) =
  ## Records an explicit unlock or upgrade, including rejected attempts.
  recorder.record ReplayAction(
    tick: tick, heroId: heroId, kind: ActionLevelAbility, slot: slot
  )

proc recordWalkTo*(
    recorder: ReplayRecorder,
    tick: uint32,
    heroId,
    x,
    y: int32,
    offset = FixedVec2Zero
) =
  ## Records one walkTo action without bot implementation details.
  recorder.record ReplayAction(
    tick: tick,
    heroId: heroId,
    kind: ActionWalkTo,
    first: x,
    second: y,
    offset: offset
  )

proc recordAttackMove*(
    recorder: ReplayRecorder,
    tick: uint32,
    heroId,
    x,
    y: int32,
    offset = FixedVec2Zero
) =
  ## Records one attack-move action without bot implementation details.
  recorder.record ReplayAction(
    tick: tick,
    heroId: heroId,
    kind: ActionAttackMove,
    first: x,
    second: y,
    offset: offset
  )

proc recordAttackTarget*(
    recorder: ReplayRecorder,
    tick: uint32,
    heroId,
    targetId: int32
) =
  ## Records one attackTarget action without bot implementation details.
  recorder.record ReplayAction(
    tick: tick,
    heroId: heroId,
    kind: ActionAttackTarget,
    first: targetId
  )

proc recordBuyItem*(
    recorder: ReplayRecorder,
    tick: uint32,
    heroId,
    itemId: int32
) =
  ## Records one buyItem action without bot implementation details.
  recorder.record ReplayAction(
    tick: tick,
    heroId: heroId,
    kind: ActionBuyItem,
    first: itemId
  )

proc recordUseItem*(
    recorder: ReplayRecorder,
    tick: uint32,
    heroId,
    slot: int32,
    targetId = 0'i32
) =
  ## Records one useItem action without bot implementation details.
  recorder.record ReplayAction(
    tick: tick,
    heroId: heroId,
    kind: ActionUseItem,
    first: slot,
    second: targetId
  )

proc recordBuyback*(
    recorder: ReplayRecorder,
    tick: uint32,
    heroId: int32
) =
  ## Records one buyback attempt for deterministic playback.
  recorder.record ReplayAction(
    tick: tick,
    heroId: heroId,
    kind: ActionBuyback
  )

proc maximumReplayTicks(setup: Setup): uint64 =
  ## Bounds the tape by battle time, all pick deadlines, and preparation.
  result = setup.maximumTicks.uint64
  if setup.drafting:
    result += setup.heroes.len.uint64 * DraftPickTicks.uint64 +
      PreparationTicks.uint64

proc recordHash*(recorder: ReplayRecorder, hash: uint64) =
  ## Appends the canonical simulation hash for one completed tick.
  if recorder == nil:
    return
  let maximum = recorder.data.header.setup.maximumReplayTicks()
  if maximum > MaxReplayHashes.uint64:
    fail("replay setup duration exceeds the hash limit")
  recorder.data.hashes.appendHash(hash, maximum.uint32, MaxReplayHashes)

proc recordUseItemAt*(
    recorder: ReplayRecorder,
    tick: uint32,
    heroId, slot, mapX, mapY: int32,
    offset = FixedVec2Zero
) =
  ## Records one targeted inventory use including fractional coordinates.
  recorder.record ReplayAction(
    tick: tick, heroId: heroId, kind: ActionUseItemAt,
    slot: slot, first: mapX, second: mapY, offset: offset
  )

proc validate*(data: ReplayData) =
  ## Validates versions, setup bounds, actor IDs, and action ordering.
  data.config.validateConfig(HeroClassCount)
  try:
    data.config.mapPreset.validate()
  except MapgenError as error:
    fail(error.msg)
  if data.config.seed != data.header.setup.mapSeed or
    data.config.maxTicks != int32(data.header.setup.maximumTicks):
      fail("replay configuration does not match its simulation setup")
  if data.config.spawnIntervalTicks !=
    int32(data.header.setup.spawnIntervalTicks):
      fail("replay configuration has a different spawn interval")
  data.header.requireTapeVersion(
    ReplayFormatVersion,
    ReplayGameVersion
  )
  let
    setup = data.header.setup
    totalTicks = setup.maximumReplayTicks()
  if setup.tickRate != uint16(TickRate):
    fail("replay setup has an unsupported tick rate")
  if setup.gridTiles.int != data.config.mapPreset.mapSize:
    fail("replay setup has an unsupported map size")
  if setup.mapHash == 0:
    fail("replay setup has no deterministic map fingerprint")
  if setup.spawnIntervalTicks == 0 or setup.maximumTicks == 0:
    fail("replay setup has an invalid duration")
  if setup.spawnIntervalTicks > uint32(int32.high):
    fail("replay setup spawn interval is too large")
  if totalTicks > uint64(MaxReplayHashes):
    fail("replay setup duration exceeds the hash limit")
  if setup.heroes.len == 0 or setup.heroes.len > MaxReplayHeroes:
    fail("replay setup has an invalid hero count")
  if setup.heroes.len > data.config.players.len:
    fail("replay setup has no player metadata for some heroes")
  if data.config.draftMode != setup.draftMode:
    fail("replay configuration has a different draft mode")
  if setup.drafting and setup.draftMode == UniqueDraft and
    setup.heroes.len > HeroClassCount:
      fail("replay draft has more players than available heroes")
  if data.actions.len > MaxReplayActions:
    fail("replay action limit exceeded")
  if data.events.len > MaxReplayChats:
    fail("replay chat limit exceeded")
  if data.hashes.len > MaxReplayHashes:
    fail("replay hash limit exceeded")
  if data.hashes.len.uint64 > totalTicks:
    fail("replay hashes exceed the configured duration")
  var teamPlayers: array[2, int]
  for i, hero in setup.heroes:
    if hero.team > 1 or hero.lane > 2 or
        hero.class > uint8(HeroClass.high.ord):
      fail("replay setup has invalid hero metadata")
    inc teamPlayers[hero.team]
    if setup.drafting and setup.draftMode == TeamDraft and
      teamPlayers[hero.team] > HeroClassCount:
        fail("replay team draft has more players than available heroes")
    for j in 0 ..< i:
      if setup.heroes[j].id == hero.id:
        fail("replay setup contains a duplicate hero ID")
  var lastTick = 0'u32
  for i, action in data.actions:
    if action.tick > uint32(data.hashes.len):
      fail("replay action exceeds the recorded duration")
    if i > 0 and action.tick < lastTick:
      fail("replay actions move backward in time")
    if action.tick.uint64 > totalTicks:
      fail("replay action exceeds the configured duration")
    if not action.offset.validTileOffset:
      fail("replay point offset is outside its tile")
    if action.kind != ActionWalkTo and
        action.kind != ActionAttackTarget and
        action.kind != ActionBuyItem and
        action.kind != ActionUseItem and
        action.kind != ActionUseItemAt and
        action.kind != ActionAttackMove and
        action.kind != ActionCastTarget and
        action.kind != ActionCastPoint and
        action.kind != ActionLevelAbility and
        action.kind != ActionBuyback and
        action.kind != ActionDraft and
        action.kind != ActionStop and action.kind != ActionSellItem and
        action.kind != ActionSwapItems and
        action.kind != ActionQueueWalkTo and
        action.kind != ActionQueueAttackMove and
        action.kind != ActionQueueAttackTarget:
      fail("replay action kind is invalid")
    var knownHero = false
    for hero in setup.heroes:
      if hero.id == action.heroId:
        knownHero = true
        break
    if not knownHero:
      fail("replay action references an unknown hero")
    lastTick = action.tick
  lastTick = 0
  for i, message in data.events:
    setup.validateChat(message)
    if message.tick > uint32(data.hashes.len) or
        message.tick.uint64 > totalTicks:
      fail("replay chat exceeds the recorded duration")
    if i > 0 and message.tick < lastTick:
      fail("replay chat moves backward in time")
    lastTick = message.tick
  try:
    data.metrics.validate(
      data.config.players.len,
      int32(data.header.setup.tickRate),
      data.hashes.len
    )
  except MetricsError as error:
    fail(error.msg)

proc encodeReplay*(data: ReplayData): string =
  ## Encodes a validated recording for this client's gameplay version.
  data.validate()
  encodeReplayFile(ReplayGame, ReplayGameVersion, data, MaxReplayBytes)

proc decodeReplay*(bytes: string): ReplayData =
  ## Rejects other gameplay versions before decoding the recording.
  result = decodeReplayFile(
    ReplayGame,
    ReplayGameVersion,
    bytes,
    ReplayData,
    MaxReplayBytes
  )
  result.validate()

proc saveReplay*(path: string, data: ReplayData) =
  ## Creates the parent directory and saves the complete recording.
  if path.len == 0:
    fail("replay output path is empty")
  let bytes = encodeReplay(data)
  try:
    let directory = path.parentDir
    if directory.len > 0:
      createDir(directory)
    writeFile(path, bytes)
  except IOError, OSError:
    fail("cannot save replay: " & getCurrentExceptionMsg())

proc loadReplay*(path: string): ReplayData =
  ## Loads one recording with its complete match configuration and metrics.
  try:
    result = decodeReplay(readFile(path))
  except IOError, OSError:
    fail("cannot load replay: " & getCurrentExceptionMsg())

proc initReplayPlayer*(data: ReplayData): ReplayPlayer =
  ## Creates a playback cursor over validated action data.
  data.validate()
  initTapePlayer(data)
