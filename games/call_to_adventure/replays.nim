## Call to Adventure ordered command and mailbox replay.

import
  std/os,
  fixxy,
  polyworld/[bodies, pathing, tapes, metrics, mailboxes],
  content

export fixxy

const
  ReplayGame* = "call_to_adventure"
  ReplayFormatVersion* = 5'u16
  ## This client supports only this gameplay version. Bump it when rules change.
  ## Older replays use their archived client; never add compatibility branches.
  ReplayGameVersion* = 28'u16
  ActionWalkTo* = 1'u8
  ActionAttackTarget* = 2'u8
  ActionPickupTarget* = 3'u8
  ActionHealTarget* = 4'u8
  ActionUseItem* = 5'u8
  ActionDropItem* = 6'u8
  ActionChat* = 7'u8
  ActionDuration* = 8'u8
  ActionKindHigh* = ActionDuration
  MaxReplayBytes* = 64 * 1024 * 1024
  MaxReplayActions* = 4_000_000
  MaxReplayHashes* = 10_000_000
  MaxReplayChats* = 64 * 1024

type
  ReplayAction* = object
    tick*: uint32
    heroId*: int32
    kind*: uint8
    offset*: FixedVec2
      ## Movement and ground aim offsets from the named tile center.
    first*, second*, third*: int32
      ## Walk uses level, x, z. Target actions use `first` as the target ID.
      ## Use and drop use `first` as the inventory slot.
    target*: int32
      ## Chat only: -2 for a nearby broadcast.
    recipients*: uint8
      ## Chat only: party slots whose mailboxes accepted this message.
    text*: string
      ## Chat only: original bounded mailbox bytes, never BASIC source.

  ReplayHeader* = TapeHeader[Setup]
  ReplayData* = ActionTape[Setup, ReplayAction, ReplayMetrics]
  ReplayRecorder* = ref object
    data*: ReplayData
    chatCount: int
      ## Derived append count, never serialized separately from actions.
  ReplayPlayer* = TapePlayer[Setup, ReplayAction, ReplayMetrics]

proc fail(message: string) {.noreturn.} =
  ## Raises one Call to Adventure replay error.
  raise newException(ReplayError, message)

proc initReplayData*(setup: Setup): ReplayData =
  ## Creates a replay containing the match setup, config, and action tape.
  result.header = initActionTape[Setup, ReplayAction](
    setup,
    ReplayFormatVersion,
    ReplayGameVersion
  ).header
  result.config = GameConfig(
    seed: setup.seed,
    maxTicks: int32(setup.maximumTicks),
    players: unnamedPlayers(PartySize)
  )

proc initReplayRecorder*(setup: Setup): ReplayRecorder =
  ## Creates an in-memory recorder owning the complete replay data.
  ReplayRecorder(data: initReplayData(setup))

proc durationAt*(data: ReplayData, tick: uint32): int32 =
  ## Returns the time limit after the recorded commands through this tick.
  result = int32(data.header.setup.maximumTicks)
  for action in data.actions:
    if action.tick > tick:
      break
    if action.kind == ActionDuration:
      result = action.first

proc replayPrefix*(data: ReplayData, tick: uint32): ReplayData =
  ## Trims future commands and restores the duration at the branch point.
  result = tapes.replayPrefix(data, tick)
  result.config.maxTicks = data.durationAt(tick)

proc recordDuration*(
    recorder: ReplayRecorder, tick: uint32, maximumTicks: int32
) =
  ## Records a time-limit change before the next tick's policy commands.
  if tick == 0 or maximumTicks < int64(tick) or
    maximumTicks > MaxReplayHashes or
    (recorder.data.actions.len > 0 and
      recorder.data.actions[^1].tick >= tick):
      fail("replay duration change has invalid bounds or ordering")
  recorder.data.actions.appendAction(
    ReplayAction(tick: tick, kind: ActionDuration, first: maximumTicks),
    MaxReplayActions
  )
  recorder.data.config.maxTicks = maximumTicks

proc validateChat(action: ReplayAction, setup: Setup) =
  ## Validates one nearby message without interpreting its private bytes.
  if action.heroId < 100 or action.heroId >= 100 + PartySize:
    fail("replay chat names an unknown hero")
  if action.target != -2:
    fail("replay chat target must be a nearby broadcast")
  if action.recipients == 0 or int(action.recipients) >= (1 shl PartySize):
    fail("replay chat has invalid recipients")
  if action.text.len == 0 or action.text.len > MaxChatBytes:
    fail("replay chat has an invalid message length")
  if action.tick > setup.maximumTicks:
    fail("replay chat exceeds the configured duration")
  if action.first != 0 or action.second != 0 or action.third != 0 or
      action.offset != FixedVec2Zero:
    fail("replay chat has an invalid command payload")

proc recordChat*(recorder: ReplayRecorder, action: ReplayAction) =
  ## Appends a delivered mailbox message in the same order as hero commands.
  if recorder == nil:
    return
  if action.kind != ActionChat:
    fail("replay chat action kind is invalid")
  var setup = recorder.data.header.setup
  setup.maximumTicks = uint32(recorder.data.config.maxTicks)
  action.validateChat(setup)
  if recorder.chatCount >= MaxReplayChats:
    fail("replay chat limit exceeded")
  recorder.data.actions.appendAction(action, MaxReplayActions)
  inc recorder.chatCount

iterator chatsAt*(data: ReplayData, tick: uint32): ReplayAction =
  ## Reads messages through the playhead directly from the ordered tape.
  for action in data.actions:
    if action.tick > tick:
      break
    if action.kind == ActionChat:
      yield action

proc initReplayRecorder*(data: ReplayData): ReplayRecorder =
  ## Continues a replay prefix with its derived chat quota intact.
  result = ReplayRecorder(data: data)
  for action in data.actions:
    if action.kind == ActionChat:
      inc result.chatCount

proc recordAction*(
    recorder: ReplayRecorder,
    tick: uint32,
    heroId: int32,
    kind: uint8,
    first = 0'i32,
    second = 0'i32,
    third = 0'i32,
    offset = FixedVec2Zero
) =
  ## Records one attempted hero command without storing its BASIC source.
  if recorder == nil:
    return
  if not offset.validTileOffset:
    fail("replay point offset is outside its tile")
  if kind == 0 or kind >= ActionChat:
    fail("replay action kind is invalid")
  recorder.data.actions.appendAction(
    ReplayAction(
      tick: tick,
      heroId: heroId,
      kind: kind,
      first: first,
      second: second,
      third: third,
      offset: offset
    ),
    MaxReplayActions
  )

proc recordHash*(recorder: ReplayRecorder, hash: uint64) =
  ## Appends the canonical hash for one completed simulation tick.
  if recorder != nil:
    recorder.data.hashes.appendHash(
      hash, uint32(recorder.data.config.maxTicks), MaxReplayHashes)

proc validateSetup(setup: Setup) =
  ## Validates the immutable expedition description.
  if setup.tickRate != uint16(TickRate):
    fail("replay setup has an unsupported tick rate")
  if setup.gridTiles != uint16(GridTiles):
    fail("replay setup has an unsupported map size")
  if setup.levels != uint8(LevelCount):
    fail("replay setup has an unsupported level count")
  if setup.decisionTicks != uint16(DecisionTicks):
    fail("replay setup has an unsupported decision interval")
  if setup.maximumTicks == 0 or setup.maximumTicks > uint32(MaxReplayHashes):
    fail("replay setup has an invalid duration")
  if setup.mapHash == 0:
    fail("replay setup has no deterministic map fingerprint")
  for slot, member in setup.party:
    if member.id != int32(100 + slot) or member.class != HeroClass(slot):
      fail("replay setup party is not in canonical order")

proc validateAction(action: ReplayAction, setup: Setup) =
  ## Validates one recorded hero command and its payload.
  if action.kind == ActionDuration:
    if action.tick == 0 or action.tick > setup.maximumTicks + 1 or
      action.first < int64(action.tick) or action.first > MaxReplayHashes or
      action.heroId != 0 or action.second != 0 or action.third != 0 or
      action.offset != FixedVec2Zero or action.text.len > 0 or
      action.target != 0 or action.recipients != 0:
        fail("replay duration change has an invalid payload")
    return
  if action.kind == ActionChat:
    action.validateChat(setup)
    return
  if action.text.len > 0 or action.target != 0 or action.recipients != 0:
    fail("replay command has an unexpected chat payload")
  if action.tick == 0 or action.tick > setup.maximumTicks or
      action.tick mod uint32(setup.decisionTicks) != 0:
    fail("replay action did not land on a decision tick")
  if action.heroId < 100 or action.heroId >= 100 + PartySize:
    fail("replay action names an unknown hero")
  if not action.offset.validTileOffset:
    fail("replay point offset is outside its tile")
  if action.kind == 0 or action.kind > ActionKindHigh:
    fail("replay action kind is invalid")
  if action.kind == ActionWalkTo:
    if action.first < 0 or action.first >= LevelCount or
        action.second < 0 or action.second >= GridTiles or
        action.third < 0 or action.third >= GridTiles:
      fail("replay walk names a tile outside the dungeon")
  elif action.kind == ActionUseItem or action.kind == ActionDropItem:
    if action.first < 0 or action.first >= InventorySlots:
      fail("replay item action names a slot outside the bag")
  elif action.first <= 0:
    fail("replay target action has an invalid target ID")

proc validate*(data: ReplayData) =
  ## Validates versions, setup, commands, and per-tick hash coverage.
  data.config.validateConfig(PartySize)
  if data.config.seed != data.header.setup.seed:
    fail("replay configuration does not match its simulation setup")
  data.header.requireTapeVersion(
    ReplayFormatVersion,
    ReplayGameVersion
  )
  data.header.setup.validateSetup()
  if data.actions.len > MaxReplayActions:
    fail("replay action limit exceeded")
  if data.hashes.len > data.config.maxTicks or
      data.hashes.len > MaxReplayHashes:
    fail("replay hashes exceed the configured duration")
  var
    lastTick = 0'u32
    chatCount = 0
    setup = data.header.setup
  for index, action in data.actions:
    if action.tick > uint32(data.hashes.len):
      fail("replay action exceeds the recorded duration")
    if index > 0 and action.tick < lastTick:
      fail("replay actions move backward in time")
    action.validateAction(setup)
    if action.kind == ActionDuration:
      if index > 0 and action.tick == lastTick:
        fail("replay duration change must be first at its tick")
      setup.maximumTicks = uint32(action.first)
    if action.kind == ActionChat:
      inc chatCount
      if chatCount > MaxReplayChats:
        fail("replay chat limit exceeded")
    lastTick = action.tick
  if data.config.maxTicks != int32(setup.maximumTicks):
    fail("replay configuration disagrees with its duration changes")
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
  ## Creates a playback cursor over validated commands.
  data.validate()
  result = initTapePlayer(data)
  result.syncCursor(0)

proc takeActionAt*(
    player: ReplayPlayer,
    tick: uint32,
    heroId: int32,
    action: var ReplayAction
): bool =
  ## Consumes the next command when it belongs to this decision slot.
  if player == nil:
    return false
  while not player.finished and
      player.data.actions[player.actionIndex].kind == ActionChat and
      player.data.actions[player.actionIndex].tick == 0:
    # Startup mailbox messages have no simulation effect or VM to deliver to.
    inc player.actionIndex
  if player.finished:
    return false
  let next = player.data.actions[player.actionIndex]
  if next.tick < tick:
    fail("replay playback skipped an action tick")
  if next.tick != tick or next.heroId != heroId:
    return false
  action = next
  inc player.actionIndex
  true
