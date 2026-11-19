## Replay transcripts preserve text, audiences, ordering, and seekable history.
import
  std/strutils,
  polyworld/[mailboxes, metrics, tapes],
  ../[chats, content, replays]

proc recording(maximumTicks = 8'u32): ReplayRecorder =
  ## Uses sparse hero IDs and mixed seat order to check sender resolution.
  result = initReplayRecorder(Setup(
    mapSeed: 2026, mapHash: 0x123456789ABCDEF0'u64,
    tickRate: TickRate.uint16, gridTiles: 116,
    spawnIntervalTicks: (TickRate * 10).uint32,
    maximumTicks: maximumTicks,
    heroes: @[
      ReplayHero(id: 108, team: 1, slot: 3, lane: 0,
        class: DeathKnight.ord.uint8),
      ReplayHero(id: 101, team: 0, slot: 1, lane: 0,
        class: VanguardKnight.ord.uint8),
      ReplayHero(id: 104, team: 0, slot: 4, lane: 1,
        class: Ranger.ord.uint8)]))
  result.data.config.players[0].name = "蓝队 🙂"
  result.data.config.players[1].name = "Red <lead>"
  result.data.config.players[2].name = "Ally (guest)"
  for tick in 1'u32 .. maximumTicks:
    result.recordHash(tick.uint64)

proc human(tick = 1'u32, sender = 101'i32, target = -2'i32,
    text = "hello"): ReplayAction =
  ## Constructs one ordinary chat action for codec and validation cases.
  ReplayAction(tick: tick, kind: ActionHumanChat, heroId: sender,
    first: target, text: text)

proc rejects(data: ReplayData) =
  ## Requires both the validated writer and untrusted decoder to reject data.
  var rejected = false
  try:
    discard data.encodeReplay()
  except ReplayError:
    rejected = true
  doAssert rejected, "The replay writer accepted invalid chat"
  rejected = false
  try:
    discard decodeReplay(encodeReplayFile(
      ReplayGame, ReplayGameVersion, data))
  except ReplayError:
    rejected = true
  doAssert rejected, "The replay reader accepted invalid chat"

echo "Testing exact transcript bytes, same-tick order, and sender metadata"
block:
  let recorder = recording()
  let actions = @[
    ReplayAction(tick: 1, heroId: 101, kind: ActionStop),
    human(text = "你好 🙂 <b>literal</b>"),
    human(sender = 108, target = -1, text = "blue team"),
    ReplayAction(tick: 1, kind: ActionPolicyChat, heroId: 101,
      first: 0, text: "\x00\xFF\nmail\x1B"),
    human(sender = 104, text = "all reply"),
    ReplayAction(tick: 1, heroId: 104, kind: ActionWalkTo, first: 4, second: 5),
    ReplayAction(tick: 2, kind: ActionSystemNotice, heroId: 0,
      first: -2, text: "3 minutes remain"),
    human(tick = 3, sender = 101, target = -1, text = "red team")]
  for action in actions:
    recorder.record(action)
  let data = decodeReplay(recorder.data.encodeReplay())
  doAssert data.actions == actions
  doAssert data.hashes == recorder.data.hashes
  var view: ReplayChatView
  doAssert view.chatAt(data, 0).len == 0
  let first = view.chatAt(data, 1)
  doAssert first.len == 3, "Private policy traffic must stay out of human UI"
  doAssert first[0].text == actions[1].text
  doAssert first[0].sender == "Red <lead>" and first[0].senderTeam == 0
  doAssert first[1].text == "blue team" and first[1].team
  doAssert first[1].sender == "蓝队 🙂" and first[1].senderTeam == 1
  doAssert first[2].text == "all reply"
  doAssert first[2].sender == "Ally (guest)"
  doAssert first[0].ordinal == 1
  doAssert first[1].ordinal == 2
  doAssert first[2].ordinal == 4
  doAssert data.actions[0].kind == ActionStop
  doAssert data.actions[5].kind == ActionWalkTo
  let complete = view.chatAt(data, 8)
  doAssert complete.len == 5
  doAssert complete[3].system and complete[3].sender.len == 0
  doAssert complete[3].chatDisplayText() == "[System] 3 minutes remain"
  doAssert complete[4].team and complete[4].senderTeam == 0
  for team in [0, 1, 2]:
    let visible = view.chatAt(data, 8, team)
    doAssert visible.len == (if team == 2: 3 else: 4)
    for message in visible:
      doAssert not message.team or message.senderTeam == team
  doAssert view.chatAt(data, 1) == first
  doAssert view.chatAt(data, 8) == complete
  doAssert view.chatAt(data, 8) == complete, "Repeated views must not duplicate"

echo "Testing repeated messages and accepted mailbox audiences"
block:
  let recorder = recording()
  recorder.record(human())
  recorder.record(human())
  for target in [-2'i32, -1, 0, 1, 2]:
    recorder.record(ReplayAction(tick: 1, kind: ActionPolicyChat,
      heroId: 108, first: target, text: "raw\xFF"))
  recorder.record(human(tick = 8, text = repeat("🙂", 256)))
  let data = decodeReplay(recorder.data.encodeReplay())
  doAssert data.actions == recorder.data.actions
  var view: ReplayChatView
  let repeated = view.chatAt(data, 1)
  doAssert repeated.len == 2
  doAssert repeated[0].text == repeated[1].text
  doAssert repeated[0].ordinal != repeated[1].ordinal
  doAssert view.chatAt(data, 8)[^1].text.len == MaxChatBytes

echo "Testing full transcript retention and backward/forward seek"
block:
  let recorder = recording(140)
  for tick in 1'u32 .. 135'u32:
    recorder.record(human(tick = tick, text = "message " & $tick))
  var view: ReplayChatView
  let data = decodeReplay(recorder.data.encodeReplay())
  doAssert data.actions.len == 135
  let latest = view.chatAt(data, 135)
  doAssert latest.len == MaxHumanChatMessages
  doAssert latest[0].text == "message 36"
  doAssert latest[^1].text == "message 135"
  for tick in [3'u32, 0, 120, 1, 135, 80, 8]:
    var fresh: ReplayChatView
    let messages = view.chatAt(data, tick)
    doAssert messages == fresh.chatAt(data, tick)
    doAssert messages.len == min(tick.int, MaxHumanChatMessages)
    for message in messages:
      doAssert message.tick <= tick, "Seeking must hide future chat"
  doAssert view.chatAt(data, 1)[0].text == "message 1",
    "Display eviction must never erase early replay history"
  recorder.record(human(tick = 136, text = "new live message"))
  doAssert view.chatAt(recorder.data, 136)[^1].text == "new live message"
  doAssert recorder.data.actions.len == 136

echo "Testing invalid chat metadata and text is rejected at both boundaries"
block:
  let invalid = @[
    human(sender = 0), human(sender = -1), human(sender = 999),
    human(target = -3), human(target = 0), human(target = 3),
    human(text = ""), human(text = "   "), human(text = "bad\nline"),
    human(text = "\xFF"), human(text = repeat("x", MaxChatBytes + 1)),
    ReplayAction(tick: 1, heroId: 101, kind: ActionStop, text: "ignored text"),
    ReplayAction(tick: 1, heroId: 101, kind: ActionHumanChat, first: -2,
      slot: 1, text: "unused slot"),
    ReplayAction(tick: 1, heroId: 101, kind: ActionHumanChat, first: -2,
      second: 1, text: "unused field"),
    ReplayAction(tick: 1, heroId: 101, kind: ActionHumanChat, first: -2,
      offset: fixedVec2(1, 0), text: "unused aim offset"),
    ReplayAction(tick: 1, kind: 0, heroId: 101, first: -2, text: "bad kind"),
    ReplayAction(tick: 1, kind: 255, heroId: 101, first: -2, text: "bad kind"),
    ReplayAction(tick: 1, kind: ActionPolicyChat, heroId: 999,
      first: -2, text: "bad sender"),
    ReplayAction(tick: 1, kind: ActionPolicyChat, heroId: 101,
      first: -3, text: "bad recipient"),
    ReplayAction(tick: 1, kind: ActionPolicyChat, heroId: 101,
      first: 3, text: "bad recipient"),
    ReplayAction(tick: 1, kind: ActionPolicyChat, heroId: 101,
      first: 0, text: ""),
    ReplayAction(tick: 1, kind: ActionPolicyChat, heroId: 101,
      first: 0, text: repeat("x", MaxChatBytes + 1)),
    ReplayAction(tick: 1, kind: ActionSystemNotice, heroId: 101,
      first: -2, text: "forged sender"),
    ReplayAction(tick: 1, kind: ActionSystemNotice, heroId: 0,
      first: -1, text: "bad audience"),
    ReplayAction(tick: 1, kind: ActionSystemNotice, heroId: 0,
      first: -2, text: "\xFF")]
  for event in invalid:
    let recorder = recording()
    var rejected = false
    try:
      recorder.record(event)
    except ReplayError:
      rejected = true
    doAssert rejected, "The live recorder accepted invalid chat"
    doAssert recorder.data.actions.len == 0
    recorder.data.actions = @[event]
    recorder.data.rejects()

echo "Testing canonical action ordering, duration, and chat count limits"
block:
  let recorder = recording()
  recorder.record(human(tick = 2))
  var rejected = false
  try:
    recorder.record(human(tick = 1))
  except ReplayError:
    rejected = true
  doAssert rejected and recorder.data.actions.len == 1
  recorder.data.actions.add human(tick = 1)
  recorder.data.rejects()
  recorder.data.actions = @[human(tick = 9)]
  recorder.data.rejects()
  recorder.data.actions = @[human(tick = 5)]
  recorder.data.hashes.setLen(4)
  recorder.data.rejects()
  recorder.data.actions.setLen(MaxReplayChats)
  for action in recorder.data.actions.mitems:
    action = human(tick = 4)
  rejected = false
  try:
    recorder.record(human(tick = 5))
  except ReplayError:
    rejected = true
  doAssert rejected and recorder.data.actions.len == MaxReplayChats
  recorder.data.actions.add human(tick = 5)
  recorder.data.rejects()

echo "Testing aggregate chat text and encoded file byte limits"
block:
  let recorder = recording()
  let text = repeat("x", MaxChatBytes)
  recorder.data.actions.setLen(MaxReplayBytes div MaxChatBytes)
  for action in recorder.data.actions.mitems:
    action = human(text = text)
  var rejected = false
  try:
    recorder.record(human())
  except ReplayError:
    rejected = true
  doAssert rejected, "The recorder must cap aggregate chat bytes"
  rejected = false
  try:
    discard recorder.data.encodeReplay()
  except ReplayError:
    rejected = true
  doAssert rejected, "Metadata and text must fit the encoded replay budget"
  rejected = false
  try:
    discard decodeReplay(repeat("x", MaxReplayBytes + 1))
  except ReplayError:
    rejected = true
  doAssert rejected, "The reader must reject oversized files before parsing"

echo "Testing every chat sender has a configured player name"
block:
  let recorder = recording()
  recorder.data.header.setup.heroes.setLen(
    recorder.data.config.players.len + 1)
  for i, hero in recorder.data.header.setup.heroes.mpairs:
    hero = ReplayHero(id: 1000 + i.int32, team: (i mod 2).uint8,
      slot: 0, lane: 0, class: DeathKnight.ord.uint8)
  recorder.data.actions = @[
    human(sender = recorder.data.header.setup.heroes[^1].id)]
  recorder.data.rejects()

echo "Testing legacy replay versions are rejected before payload decoding"
block:
  let recorder = recording()
  let old = ActionTape[Setup, ReplayAction, ReplayMetrics, GotaConfig](
    header: recorder.data.header, config: recorder.data.config,
    hashes: recorder.data.hashes)
  let bytes = encodeReplayFile(ReplayGame, ReplayGameVersion - 1, old)
  var rejected = false
  try:
    discard decodeReplay(bytes)
  except ReplayError:
    rejected = true
  doAssert rejected
  recorder.data.header.formatVersion = ReplayFormatVersion - 1
  recorder.data.rejects()

echo "PASS replay chat codec, audiences, retention, seeks, and validation"
