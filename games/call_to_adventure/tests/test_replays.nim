## CTA mailbox traffic shares the command tape without replaying private VMs.

import
  std/[os, strutils, tempfiles],
  bassy,
  polyworld/[cli, mailboxes, pathing, tapes],
  ../[bots, content, replays, sim]

const
  MatchTicks = 6
  Program = """
first = walkTo(currentLevel, x + 0.25, y)
sent = sendChat(-2, "repeat 雪")
message$ = pullMailbox$()
if message$ <> "" then
  second = walkTo(currentLevel, x - 0.25, y)
end if
sentAgain = sendChat(-2, "repeat 雪")
while mailboxCount() > 0
  ignored$ = pullMailbox$()
wend
"""

template rejects(body: untyped) =
  ## Requires malformed recordings to report a replay-specific error.
  block:
    var rejected = false
    try:
      body
    except ReplayError:
      rejected = true
    doAssert rejected

proc visibleChats(data: ReplayData, tick: uint32): seq[ReplayAction] =
  ## Collects only this test's playhead view from the single action tape.
  for action in data.chatsAt(tick):
    result.add action

echo "Testing CTA actual BASIC action/chat/action/repeat recording"
let
  directory = createTempDir("cta-chat-replay-", "")
  path = directory / "chat.bas"
  live = newGame(2026, MatchTicks)
writeFile(path, Program)
live.loadBots([BotGroup(path: path, count: PartySize)])
removeDir(directory)
live.recorder = initReplayRecorder(live.world.setup)
let initialHash = live.stateHash()
doAssert live.sendChat(0, -2, "startup") == PartySize
doAssert live.stateHash() == initialHash
for tick in 1 .. MatchTicks:
  live.tickWorld(proc(game: Game, slot: int32) =
    ## Executes real mailbox-consuming policies only while recording.
    game.runBotDecisions(slot)
  )
  live.recorder.recordHash(live.stateHash())
for vm in live.heroVms:
  doAssert not vm.failed, vm.lastError
  doAssert vm.runtime.getGlobal("sent") == PartySize
  doAssert vm.runtime.getGlobal("sentAgain") == PartySize
let
  data = decodeReplay(live.recorder.data.encodeReplay())
  expectedChatCount = 1 + MatchTicks * PartySize * 2
doAssert data.actions == live.recorder.data.actions
doAssert data.actions.len == 1 + MatchTicks * PartySize * 4
doAssert data.hashes == live.recorder.data.hashes
doAssert data.actions[0].tick == 0
doAssert data.actions[0].text == "startup"
for index in countup(1, data.actions.high, 4):
  let
    first = data.actions[index]
    chat = data.actions[index + 1]
    second = data.actions[index + 2]
    repeated = data.actions[index + 3]
  doAssert first.kind == ActionWalkTo
  doAssert second.kind == ActionWalkTo
  doAssert first.offset.x == 0.25'fx
  doAssert second.offset.x == -0.25'fx
  doAssert chat.kind == ActionChat
  doAssert repeated == chat, "identical consecutive messages must survive"
  doAssert chat.tick == first.tick and second.tick == first.tick
  doAssert chat.heroId == first.heroId and second.heroId == first.heroId
  doAssert chat.target == -2 and chat.recipients == 0b1111'u8
  doAssert chat.text == "repeat 雪"
doAssert data.visibleChats(0).len == 1
doAssert data.visibleChats(MatchTicks).len == expectedChatCount
doAssert data.visibleChats(MatchTicks)[^1].tick == MatchTicks

echo "Testing CTA replay hashes, seek, repeat, and absent private VMs"
let
  playback = newGame(2026, MatchTicks)
  player = initReplayPlayer(data)
  initialWorld = playback.world.clone()
var checkpoint: World
playback.replayMode = true
playback.historyPlayback = true

proc replayDecision(game: Game, slot: int32) =
  ## Applies recorded gameplay and consumes chat without a live mailbox.
  let actor = game.world.actors[slot]
  if not actor.alive or actor.busy:
    return
  var action: ReplayAction
  while player.takeActionAt(uint32(game.world.tick), actor.id, action):
    if action.kind != ActionChat:
      discard game.applyHeroAction(slot, action)

proc replayThrough(tick: int32) =
  ## Verifies every resulting world hash while replay advances.
  while playback.world.tick < tick:
    playback.tickWorld(replayDecision)
    doAssert playback.stateHash() == data.hashes[playback.world.tick - 1]
  for vm in playback.heroVms:
    doAssert vm == nil
  for inbox in playback.inboxes:
    doAssert inbox == nil, "replay must not re-deliver private mailbox state"

replayThrough(3)
checkpoint = playback.world.clone()
doAssert data.visibleChats(3).len == 1 + 3 * PartySize * 2
replayThrough(MatchTicks)
doAssert player.finished
let finalHash = playback.stateHash()
for repetition in 0 ..< 2:
  playback.world.restore(initialWorld)
  player.syncCursor(0)
  doAssert player.actionIndex == 1, "tick-zero chat belongs to the playhead"
  doAssert data.visibleChats(0).len == 1
  replayThrough(MatchTicks)
  doAssert player.finished and playback.stateHash() == finalHash
  doAssert data.visibleChats(MatchTicks).len == expectedChatCount
playback.world.restore(checkpoint)
player.syncCursor(uint32(playback.world.tick))
doAssert data.visibleChats(3).len == 1 + 3 * PartySize * 2
replayThrough(MatchTicks)
doAssert player.finished and playback.stateHash() == finalHash

echo "Testing CTA recorded recipients, binary payloads, and rejected sends"
block:
  let game = newGame(2026, MatchTicks)
  game.recorder = initReplayRecorder(game.world.setup)
  for inbox in game.inboxes.mitems:
    inbox = newMailbox()
  game.world.actors[1].home = game.world.actors[0].home
  game.world.actors[2].home.level = 1
  for i in 0 ..< MaxMailboxMessages:
    doAssert game.inboxes[3].push(-2, "full")
  let before = game.stateHash()
  doAssert game.sendChat(0, -2, "\x00\xFFprivate bytes") == 2
  doAssert game.recorder.data.actions.len == 1
  doAssert game.recorder.data.actions[0].recipients == 0b0011'u8
  doAssert game.recorder.data.actions[0].text == "\x00\xFFprivate bytes"
  doAssert game.stateHash() == before
  doAssert game.sendChat(-1, -2, "bad sender") == 0
  doAssert game.sendChat(PartySize, -2, "bad sender") == 0
  for target in [-3, -1, 0, PartySize]:
    doAssert game.sendChat(0, target, "bad target") == 0
  doAssert game.sendChat(0, -2, "") == 0
  doAssert game.sendChat(0, -2, repeat('x', MaxChatBytes + 1)) == 0
  doAssert game.recorder.data.actions.len == 1
  doAssert game.sendChat(0, -2, repeat('x', MaxChatBytes)) == 2
  game.historyPlayback = true
  doAssert game.sendChat(0, -2, "rewound") == 0
  game.historyPlayback = false
  game.replayMode = true
  doAssert game.sendChat(0, -2, "replaying") == 0
  game.replayMode = false
  for inbox in game.inboxes.mitems:
    inbox = newMailbox()
    for i in 0 ..< MaxMailboxMessages:
      doAssert inbox.push(-2, "full")
  doAssert game.sendChat(0, -2, "all full") == 0
  doAssert game.recorder.data.actions.len == 2
  let restored = decodeReplay(game.recorder.data.encodeReplay())
  doAssert restored.actions == game.recorder.data.actions
  doAssert initReplayPlayer(restored).finished,
    "a recording containing only startup messages is already at its end"

echo "Testing CTA chat validation, version rejection, and bounded counts"
block:
  let original = data.actions[2]
  doAssert original.kind == ActionChat
  template invalid(change: untyped) =
    ## Rejects malformed action bytes through the public decoder.
    block:
      var bad {.inject.} = original
      change
      var candidate = initReplayData(data.header.setup)
      candidate.hashes = data.hashes
      candidate.actions = @[bad]
      rejects:
        discard decodeReplay(encodeReplayFile(
          ReplayGame, ReplayGameVersion, candidate, MaxReplayBytes))
  invalid: bad.heroId = 99
  invalid: bad.heroId = 100 + PartySize
  invalid: bad.target = -1
  invalid: bad.target = 0
  invalid: bad.recipients = 0
  invalid: bad.recipients = 1'u8 shl PartySize
  invalid: bad.text = ""
  invalid: bad.text = repeat('x', MaxChatBytes + 1)
  invalid: bad.tick = MatchTicks + 1
  invalid: bad.first = 1
  invalid: bad.offset.x = 0.25'fx
  invalid:
    bad.kind = ActionDropItem
    bad.first = 0
  rejects:
    discard decodeReplay(encodeReplayFile(
      ReplayGame, ReplayGameVersion - 1, data, MaxReplayBytes))
  var oldFormat = data
  dec oldFormat.header.formatVersion
  rejects:
    discard oldFormat.encodeReplay()
  let recorder = initReplayRecorder(data.header.setup)
  var chat = original
  chat.tick = 0
  for i in 0 ..< MaxReplayChats:
    recorder.recordChat(chat)
  rejects:
    recorder.recordChat(chat)
  recorder.data.actions.add chat
  rejects:
    discard decodeReplay(encodeReplayFile(
      ReplayGame, ReplayGameVersion, recorder.data, MaxReplayBytes))
  recorder.data.actions.setLen(MaxReplayChats)
  let capped = newGame(2026, MatchTicks)
  capped.recorder = recorder
  for inbox in capped.inboxes.mitems:
    inbox = newMailbox()
  rejects:
    discard capped.sendChat(0, -2, "must not deliver without recording")
  for inbox in capped.inboxes:
    doAssert inbox.count == 0

echo "Testing CTA duration-event ordering and bounds"
block:
  let recorder = initReplayRecorder(data)
  recorder.recordDuration(MatchTicks + 1, MatchTicks + 3)
  recorder.recordHash(0)
  recorder.data.validate()
  template invalidDuration(change: untyped) =
    ## Rejects malformed duration events through the public validator.
    block:
      var candidate {.inject.} = recorder.data
      change
      rejects:
        candidate.validate()
  invalidDuration: candidate.actions[^1].tick = 0
  invalidDuration: candidate.actions[^1].first = MatchTicks
  invalidDuration: candidate.actions[^1].first = MaxReplayHashes + 1
  invalidDuration: candidate.actions[^1].heroId = 100
  invalidDuration: candidate.actions[^1].second = 1
  invalidDuration: candidate.actions[^1].text = "unexpected"
  invalidDuration: candidate.config.maxTicks = MatchTicks
  invalidDuration:
    candidate.actions[^1].tick = MatchTicks
  invalidDuration:
    candidate.actions[^1].tick = MatchTicks + 2
    candidate.hashes.add(0)
  rejects:
    recorder.recordDuration(MatchTicks + 1, MatchTicks + 4)

echo "Testing CTA chat after a command makes its sender busy"
block:
  const BusyProgram = """
healed = healTarget(selfId)
sent = sendChat(-2, "casting")
walked = walkTo(currentLevel, x + 0.25, y)
sentAgain = sendChat(-2, "casting")
"""
  let
    directory = createTempDir("cta-busy-chat-", "")
    path = directory / "busy.bas"
    live = newGame(2026, MatchTicks)
    slot = int32(ClericClass)
  writeFile(path, BusyProgram)
  live.loadBots([BotGroup(path: path, count: PartySize)])
  removeDir(directory)
  dec live.world.actors[slot].hp
  let initialWorld = live.world.clone()
  live.recorder = initReplayRecorder(live.world.setup)
  for tick in 1 .. MatchTicks:
    live.tickWorld(proc(game: Game, hero: int32) =
      ## Runs only the cleric while its ability keeps later turns busy.
      if hero == slot:
        game.runBotDecisions(hero)
    )
    live.recorder.recordHash(live.stateHash())
  let vm = live.heroVms[slot]
  doAssert not vm.failed, vm.lastError
  doAssert vm.runtime.getGlobal("healed") == 1
  doAssert vm.runtime.getGlobal("walked") == 0
  doAssert vm.runtime.getGlobal("sent") == PartySize
  doAssert vm.runtime.getGlobal("sentAgain") == PartySize
  doAssert live.world.actors[slot].busy
  let data = decodeReplay(live.recorder.data.encodeReplay())
  doAssert data.actions.len == 4
  doAssert data.actions[0].kind == ActionHealTarget
  doAssert data.actions[1].kind == ActionChat
  doAssert data.actions[2].kind == ActionWalkTo
  doAssert data.actions[3] == data.actions[1]
  let
    replay = newGame(2026, MatchTicks)
    player = initReplayPlayer(data)
  replay.world.restore(initialWorld)
  replay.historyPlayback = true
  replay.replayMode = true
  for tick in 1 .. MatchTicks:
    replay.tickWorld(proc(game: Game, hero: int32) =
      ## Consumes the whole turn even after its first command starts casting.
      let actor = game.world.actors[hero]
      if not actor.alive or actor.busy:
        return
      var action: ReplayAction
      while player.takeActionAt(uint32(game.world.tick), actor.id, action):
        if action.kind != ActionChat:
          discard game.applyHeroAction(hero, action)
    )
    doAssert replay.stateHash() == data.hashes[tick - 1]
  doAssert player.finished
  doAssert replay.heroVms[slot] == nil
  doAssert replay.inboxes[slot] == nil

echo "Testing CTA replay initialization invalidates derived sight caches"
block:
  let
    original = newGame(2026, MatchTicks)
    initial = original.world.clone()
  for layer in layers:
    for tile in layer.tiles.mitems:
      tile.kind = TreeTile
  let rebuilt = newWorld(initial.setup)
  rebuilt.restore(initial)
  rebuilt.rebuildVision()
  doAssert rebuilt.visible != initial.visible,
    "a replacement world must read its current map's sight blockers"
  rebuilt.restore(initial)
  doAssert rebuilt.visible == initial.visible
  rebuilt.rebuildVision()
  doAssert rebuilt.visible != initial.visible,
    "restoring the same world must invalidate its cached sight keys"
  let replay = newGame(2026, MatchTicks)
  doAssert replay.stateHash() == initial.hashWorld(),
    "fresh replay initialization must not inherit a previous map's sight"

echo "CTA ordered mailbox replay tests passed"
