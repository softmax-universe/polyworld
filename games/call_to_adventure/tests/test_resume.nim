import
  std/[os, tempfiles],
  bassy,
  polyworld/[cli, tapes],
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
finally:
  removeDir(directory)

echo "Call to Adventure warm-up preserves world, memory, and ordered chat"
