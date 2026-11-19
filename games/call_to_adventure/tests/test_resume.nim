import
  std/[os, tempfiles],
  bassy,
  polyworld/[cli, mailboxes, tapes],
  ../[bots, content, replays, sim]

const
  Original = """
while mailboxCount() > 0
  ignored$ = pullMailbox$()
wend
accepted = walkTo(currentLevel, x + 0.25, y)
sent = sendChat(-2, "recorded")
sentAgain = sendChat(-2, "recorded")
"""
  Candidate = """
decisions = decisions + 1
while mailboxCount() > 0
  message$ = pullMailbox$()
  if message$ = "startup" then startupSeen = startupSeen + 1
  if message$ = "recorded" then recordedSeen = recordedSeen + 1
  if message$ = "candidate" then candidateSeen = candidateSeen + 1
wend
accepted = walkTo(objectiveLevel, objectiveX, objectiveY)
sent = sendChat(-2, "candidate")
"""
  Feedback = """
while mailboxCount() > 0
  ignored$ = pullMailbox$()
wend
if broken or successes < decisions then
  accepted = walkTo(objectiveLevel, objectiveX, objectiveY)
else
  accepted = walkTo(currentLevel, x + 0.25, y)
end if
decisions = decisions + 1
if accepted <> 0 then successes = successes + 1
sent = sendChat(-2, "feedback")
reply$ = pullMailbox$()
if sent = 0 or reply$ <> "feedback" then broken = 1
"""
  Retry = """
failedSend = sendChat(-2, "retry")
ignored$ = pullMailbox$()
retried = sendChat(-2, "retry")
"""

proc replayDecision(game: Game, slot: int32) =
  ## Matches calls inline, then drains any remaining authoritative actions.
  let actor = game.world.actors[slot]
  if not actor.alive or actor.busy:
    return
  if game.warmingPolicies:
    game.runBotDecisions(slot)
  var action: ReplayAction
  while game.replayPlayer.takeActionAt(
      uint32(game.world.tick), actor.id, action):
    if action.kind == ActionChat:
      if game.warmingPolicies:
        game.deliverChat(action)
    else:
      discard game.applyHeroAction(slot, action)

proc recordedBefore(data: ReplayData, tick: uint32, heroId: int32): int32 =
  ## Counts earlier messages in the original rotating hero decision order.
  for action in data.actions:
    if action.tick == tick and action.heroId == heroId:
      break
    if action.kind == ActionChat and action.text == "recorded":
      inc result

let directory = createTempDir("cta-resume-", "")
try:
  let
    originalPath = directory / "original.bas"
    path = directory / "candidate.bas"
    live = newGame(2026, 4)
  writeFile(originalPath, Original)
  writeFile(path, Candidate)
  live.loadBots([BotGroup(path: originalPath, count: PartySize)])
  live.recorder = initReplayRecorder(live.world.setup)
  doAssert live.sendChat(0, -2, "startup") == PartySize
  for tick in 1 .. 3:
    live.tickWorld(proc(game: Game, slot: int32) =
      ## Records actual commands and repeated chats from the original VMs.
      game.runBotDecisions(slot)
    )
    live.recorder.recordHash(live.stateHash())
  let
    data = decodeReplay(live.recorder.data.encodeReplay())
    game = newGame(2026, 4)
  game.loadBots([BotGroup(path: path, count: PartySize)])
  game.recorder = initReplayRecorder(game.world.setup)
  game.replayMode = true
  game.historyPlayback = true
  game.warmingPolicies = true
  game.replayPlayer = initReplayPlayer(data)
  for action in data.chatsAt(0):
    game.deliverChat(action)
  for tick in 1 .. 2:
    game.tickWorld(proc(game: Game, slot: int32) =
      ## Warms each VM before applying that hero's recorded command stream.
      let actor = game.world.actors[slot]
      if not actor.alive or actor.busy:
        return
      let before = game.stateHash()
      game.runBotDecisions(slot)
      doAssert game.stateHash() == before
      var action: ReplayAction
      while game.replayPlayer.takeActionAt(
          uint32(game.world.tick), actor.id, action):
        if action.kind == ActionChat:
          game.deliverChat(action)
        else:
          discard game.applyHeroAction(slot, action)
    )
    doAssert game.stateHash() == data.hashes[tick - 1]
    for slot, vm in game.heroVms:
      doAssert not vm.failed, vm.lastError
      doAssert vm.runtime.getGlobal("decisions") == tick.int32
      doAssert vm.runtime.getGlobal("startupSeen") == 1
      doAssert vm.runtime.getGlobal("recordedSeen") ==
        data.recordedBefore(tick.uint32, int32(100 + slot))
      doAssert vm.runtime.getGlobal("candidateSeen") == 0
      doAssert vm.runtime.getGlobal("accepted") == 0
      doAssert vm.runtime.getGlobal("sent") == 0
  doAssert game.recorder.data.actions.len == 0

  let prefix = data.replayPrefix(2)
  game.recorder = initReplayRecorder(prefix)
  game.warmingPolicies = false
  game.historyPlayback = false
  game.replayMode = false
  var
    handoffOrder: array[PartySize, int32]
    decision = 0'i32
  game.tickWorld(proc(game: Game, slot: int32) =
    ## Lets the same warmed VMs issue commands and send messages after handoff.
    handoffOrder[slot] = decision
    inc decision
    game.runBotDecisions(slot)
  )
  game.recorder.recordHash(game.stateHash())
  let branch = decodeReplay(game.recorder.data.encodeReplay())
  doAssert branch.actions.len == prefix.actions.len + PartySize * 2
  doAssert branch.replayPrefix(2).actions == prefix.actions
  doAssert branch.replayPrefix(2).hashes == prefix.hashes
  for slot, vm in game.heroVms:
    doAssert not vm.failed, vm.lastError
    doAssert vm.runtime.getGlobal("decisions") == 3
    doAssert vm.runtime.getGlobal("startupSeen") == 1
    doAssert vm.runtime.getGlobal("recordedSeen") == 2 * PartySize * 2
    doAssert vm.runtime.getGlobal("candidateSeen") == handoffOrder[slot]
    doAssert vm.runtime.getGlobal("sent") == PartySize
    doAssert game.inboxes[slot].count == PartySize - handoffOrder[slot]

  let viewer = newGame(2026, 4)
  viewer.loadBots([BotGroup(path: originalPath, count: PartySize)])
  viewer.historyPlayback = true
  viewer.replayMode = true
  viewer.replayPlayer = initReplayPlayer(data)
  let
    firstIndex = viewer.replayPlayer.actionIndex
    first = data.actions[firstIndex]
  viewer.world.tick = first.tick.int32
  let beforeViewerCommand = viewer.stateHash()
  viewer.runBotDecisions(first.heroId - 100)
  doAssert viewer.stateHash() == beforeViewerCommand
  doAssert viewer.replayPlayer.actionIndex == firstIndex
  doAssert viewer.sendChat(first.heroId.int - 100, -2, "recorded") == 0
  viewer.world.tick = 0
  viewer.loadBots([BotGroup(path: originalPath, count: PartySize)])
  for tick in 1 .. 3:
    viewer.tickWorld(replayDecision)
    doAssert viewer.stateHash() == data.hashes[tick - 1]
  for slot, vm in viewer.heroVms:
    doAssert vm.decisions == 0
    doAssert viewer.inboxes[slot].count == 0

  var full = initReplayData(game.world.setup)
  full.actions = newSeq[ReplayAction](MaxReplayChats)
  for action in full.actions.mitems:
    action = data.actions[0]
  let fullRecorder = initReplayRecorder(full)
  var rejected = false
  try:
    fullRecorder.recordChat(data.actions[0])
  except ReplayError:
    rejected = true
  doAssert rejected, "prefix chat still counts toward the recording limit"

  let
    feedbackPath = directory / "feedback.bas"
    feedbackGame = newGame(2026, 6)
  writeFile(feedbackPath, Feedback)
  feedbackGame.loadBots([BotGroup(path: feedbackPath, count: PartySize)])
  feedbackGame.recorder = initReplayRecorder(feedbackGame.world.setup)
  for tick in 1 .. 6:
    feedbackGame.tickWorld(proc(game: Game, slot: int32) =
      ## Records policies that retain command results and read their own chat.
      game.runBotDecisions(slot)
    )
    feedbackGame.recorder.recordHash(feedbackGame.stateHash())
  let feedbackData = decodeReplay(feedbackGame.recorder.data.encodeReplay())
  for cutoff in [0, 3, 6]:
    let resumed = newGame(2026, 6)
    resumed.loadBots([BotGroup(path: feedbackPath, count: PartySize)])
    resumed.replayPlayer = initReplayPlayer(feedbackData)
    resumed.recorder = initReplayRecorder(feedbackData.replayPrefix(cutoff.uint32))
    for tick in 1 .. 6:
      resumed.historyPlayback = tick <= cutoff
      resumed.replayMode = resumed.historyPlayback
      resumed.warmingPolicies = tick <= cutoff
      if resumed.warmingPolicies:
        resumed.tickWorld(replayDecision)
      else:
        resumed.tickWorld(proc(game: Game, slot: int32) =
          ## Continues the same feedback-dependent VMs after the cutoff.
          game.runBotDecisions(slot)
        )
        resumed.recorder.recordHash(resumed.stateHash())
      doAssert resumed.stateHash() == feedbackData.hashes[tick - 1]
    let branch = decodeReplay(resumed.recorder.data.encodeReplay())
    doAssert branch.hashes == feedbackData.hashes
    doAssert branch.actions == feedbackData.actions
    for slot, vm in resumed.heroVms:
      doAssert not vm.failed, vm.lastError
      for name in ["decisions", "successes", "broken", "accepted", "sent"]:
        doAssert vm.runtime.getGlobal(name) ==
          feedbackGame.heroVms[slot].runtime.getGlobal(name)
      doAssert vm.runtime.getGlobal("broken") == 0
      doAssert vm.runtime.getGlobal("successes") > 0

  let
    retryPath = directory / "retry.bas"
    retryGame = newGame(2026, 2)
  writeFile(retryPath, Retry)
  retryGame.loadBots([BotGroup(path: retryPath, count: PartySize)])
  retryGame.recorder = initReplayRecorder(retryGame.world.setup)
  for message in 0 ..< MaxMailboxMessages:
    doAssert retryGame.sendChat(0, -2, "startup") == PartySize
  for tick in 1 .. 2:
    retryGame.tickWorld(proc(game: Game, slot: int32) =
      ## Fails a full-mailbox send, then records the same send after reading.
      game.runBotDecisions(slot)
    )
    retryGame.recorder.recordHash(retryGame.stateHash())
  let
    retryData = decodeReplay(retryGame.recorder.data.encodeReplay())
    retryWarm = newGame(2026, 2)
  retryWarm.loadBots([BotGroup(path: retryPath, count: PartySize)])
  retryWarm.historyPlayback = true
  retryWarm.replayMode = true
  retryWarm.warmingPolicies = true
  retryWarm.replayPlayer = initReplayPlayer(retryData)
  for action in retryData.chatsAt(0):
    retryWarm.deliverChat(action)
  for tick in 1 .. 2:
    retryWarm.tickWorld(replayDecision)
    doAssert retryWarm.stateHash() == retryData.hashes[tick - 1]
    for vm in retryWarm.heroVms:
      doAssert not vm.failed, vm.lastError
      doAssert vm.runtime.getGlobal("failedSend") == 0
      doAssert vm.runtime.getGlobal("retried") == 1
  doAssert retryWarm.replayPlayer.finished
finally:
  removeDir(directory)

echo "Call to Adventure warm-up preserves world, memory, and ordered chat"
