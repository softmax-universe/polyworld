import
  bassy,
  polyworld/[cli, mailboxes],
  ../[bots, content, maps, multiplayer, presets, replays, sim],
  ../game as runner

const Policy = """
visits = visits + 1
accepted = setRally(obsId(0), obsX(ownBuildings), obsY(ownBuildings))
"""

let game = newGame(generateMap(2026, 2), 120)
game.loadBots([Policy, Policy])
game.historyPlayback = true
game.warmingPolicies = true
let original = game.stateHash()
for i in 0 ..< 2:
  game.runBotDecisions()
  doAssert game.stateHash() == original
  for brain in game.brains:
    doAssert not brain.failed
    doAssert brain.runtime.getGlobal("visits") == int32(i + 1)
    doAssert brain.runtime.getGlobal("accepted") == 0
game.historyPlayback = false
game.warmingPolicies = false
game.runBotDecisions()
doAssert game.stateHash() != original
for brain in game.brains:
  doAssert brain.runtime.getGlobal("visits") == 3
  doAssert brain.runtime.getGlobal("accepted") == 1
echo "Light vs Dark replay warm-up keeps policy state without applying actions"

block orderedChat:
  const Watcher = """
visits = visits + 1
while mailboxCount() > 0
  text$ = pullMailbox$()
  if text$ <> "candidate" then
    received = received + 1
  end if
wend
sent = sendChat(mailboxSelf(), "candidate")
"""
  var config = defaultConfig(2)
  config.maxTicks = 4 * DecisionTicks
  config.mapSettings = MapSettings(layout: RandomLayout, size: 90, expansions: 0)
  let original = newLocalMatch(config, ["", ""])
  runner.run = original
  doAssert original.sendChat(0, -2, "opening") == 2
  for tick in 1 .. config.maxTicks:
    runner.advanceGame()
    if tick == DecisionTicks:
      doAssert original.sendChat(0, 1, "private") == 1
    elif tick == 2 * DecisionTicks:
      doAssert original.sendChat(1, -2, "recorded") == 2
  let data = decodeReplay(encodeReplay(original.recorder.data))
  for cutoff in [0'i32, 2 * DecisionTicks]:
    let resumed = newGame(original.world.map, config.maxTicks,
      data.header.setup.diplomacySettings)
    resumed.loadBots([Watcher, Watcher])
    resumed.replayData = data
    resumed.replayPlayer = initReplayPlayer(data)
    resumed.replayMode = true
    resumed.historyPlayback = true
    resumed.warmingPolicies = true
    runner.options = GameOptions(resumeStep: cutoff)
    runner.run = resumed
    for tick in 1 .. cutoff:
      runner.advanceGame()
      for brain in resumed.brains:
        doAssert not brain.failed, brain.lastError
        doAssert brain.runtime.getGlobal("visits") == tick div DecisionTicks
        doAssert brain.runtime.getGlobal("sent") == 0
      doAssert resumed.stateHash() == data.hashes[tick - 1]
    if cutoff > 0:
      doAssert resumed.recorder.chatCount == 3
      doAssert resumed.recorder.data.actions == data.actions
      for player, brain in resumed.brains:
        doAssert brain.runtime.getGlobal("received") == int32(1 + player)
        doAssert resumed.inboxes[player].count == 1
    for tick in cutoff + 1 .. cutoff + DecisionTicks:
      runner.advanceGame()
    doAssert not resumed.historyPlayback and not resumed.replayMode
    doAssert not resumed.warmingPolicies
    for player, brain in resumed.brains:
      doAssert not brain.failed, brain.lastError
      doAssert brain.runtime.getGlobal("visits") == cutoff div DecisionTicks + 1
      doAssert brain.runtime.getGlobal("sent") == 1
      doAssert brain.runtime.getGlobal("received") ==
        (if cutoff == 0: 1'i32 else: int32(2 + player))
      doAssert resumed.inboxes[player].count == 1,
        "Only the newly accepted live message remains in each inbox"
    doAssert resumed.recorder.chatCount == (if cutoff == 0: 3 else: 5)
    let branch = decodeReplay(encodeReplay(resumed.recorder.data))
    let playback = newGame(original.world.map, config.maxTicks,
      data.header.setup.diplomacySettings)
    playback.replayData = branch
    playback.replayPlayer = initReplayPlayer(branch)
    playback.replayMode = true
    playback.historyPlayback = true
    runner.options = GameOptions()
    runner.run = playback
    for tick in 1 .. branch.hashes.len:
      runner.advanceGame()
      doAssert playback.stateHash() == branch.hashes[tick - 1]
    doAssert playback.hashCheck.mismatches == 0
  echo "Light vs Dark consumes recorded chat once and enables outgoing chat at handoff"

block matchingFeedback:
  const
    Feedback = """
visits = visits + 1
while mailboxCount() > 0
  message$ = pullMailbox$()
  if message$ = "peer" then
    peerMessages = peerMessages + 1
  end if
wend
sent = sendChat(mailboxSelf(), "echo")
if sent = 1 then
  message$ = pullMailbox$()
  if message$ = "echo" then
    echoes = echoes + 1
  end if
end if
rejected = setRally(obsId(0), -1, -1)
target = ownBuildings + ((successes + echoes) mod 3)
accepted = setRally(obsId(0), obsX(target), obsY(target))
if accepted = 1 then
  successes = successes + 1
end if
observed = rallyX(obsId(0))
if observed <> obsX(target) then
  readErrors = readErrors + 1
end if
broadcast = sendChat(-2, "peer")
"""
    Names = ["visits", "peerMessages", "sent", "echoes", "rejected",
      "accepted", "successes", "observed", "readErrors", "broadcast"]
  var config = defaultConfig(2)
  config.maxTicks = 8 * DecisionTicks
  config.mapSettings = MapSettings(layout: RandomLayout, size: 90, expansions: 0)
  let original = newLocalMatch(config, [Feedback, Feedback])
  var globals: seq[array[2, array[Names.len, int32]]]
  runner.options = GameOptions()
  runner.run = original
  for tick in 1 .. config.maxTicks:
    runner.advanceGame()
    var values: array[2, array[Names.len, int32]]
    for player, brain in original.brains:
      doAssert not brain.failed, brain.lastError
      for index, name in Names:
        values[player][index] = brain.runtime.getGlobal(name)
      doAssert brain.runtime.getGlobal("successes") == tick div DecisionTicks
      doAssert brain.runtime.getGlobal("echoes") == tick div DecisionTicks
      doAssert brain.runtime.getGlobal("readErrors") == 0
    globals.add values
  let
    data = decodeReplay(encodeReplay(original.recorder.data))
    resumed = newGame(original.world.map, config.maxTicks,
      data.header.setup.diplomacySettings)
  resumed.loadBots([Feedback, Feedback])
  resumed.replayData = data
  resumed.replayPlayer = initReplayPlayer(data)
  resumed.replayMode = true
  resumed.historyPlayback = true
  resumed.warmingPolicies = true
  runner.options = GameOptions(resumeStep: config.maxTicks div 2)
  runner.run = resumed
  for tick in 1 .. config.maxTicks:
    runner.advanceGame()
    doAssert resumed.stateHash() == data.hashes[tick - 1],
      "Unchanged policies must reproduce every world tick"
    for player, brain in resumed.brains:
      doAssert not brain.failed, brain.lastError
      for index, name in Names:
        doAssert brain.runtime.getGlobal(name) == globals[tick - 1][player][index],
          "Feedback differs at tick " & $tick & ", player " & $player &
          ", global " & name
  doAssert resumed.recorder.data.hashes == data.hashes
  doAssert resumed.recorder.data.actions == data.actions
  doAssert not resumed.warmingPolicies
  echo "Light vs Dark preserves command results, immediate chat and policy state"

block retryFullInbox:
  const Retry = """
first = sendChat(mailboxSelf(), "retry")
removed$ = pullMailbox$()
second = sendChat(mailboxSelf(), "retry")
while mailboxCount() > 0
  message$ = pullMailbox$()
  if message$ = "retry" then
    received = received + 1
  end if
wend
"""
  let game = newGame(generateMap(2026, 2), 120)
  game.loadBots([Retry, ""])
  game.world.tick = DecisionTicks
  for index in 0 ..< MaxMailboxMessages:
    doAssert game.inboxes[0].push(1, "full")
  game.replayPlayer = ReplayPlayer(data: ReplayData(actions: @[
    ReplayAction(kind: ActionChat, tick: uint32(DecisionTicks), playerId: 0,
      target: 0, text: "retry")
  ]))
  game.historyPlayback = true
  game.warmingPolicies = true
  let before = game.stateHash()
  game.runBotDecisions()
  let brain = game.brains[0]
  doAssert not brain.failed, brain.lastError
  doAssert brain.runtime.getGlobal("first") == 0
  doAssert brain.runtime.getGlobal("second") == 1,
    "A refused delivery must leave the recorded action available for retry"
  doAssert brain.runtime.getGlobal("received") == 1
  doAssert game.replayPlayer.actionIndex == 1
  doAssert game.replayPlayer.finished
  doAssert game.inboxes[0].count == 0,
    "The per-player drain must not deliver an accepted retry twice"
  doAssert game.stateHash() == before
  echo "Light vs Dark retries recorded chat after a full mailbox refusal"

block ordinaryHistory:
  let game = newGame(generateMap(2026, 2), 120)
  game.loadBots([Policy, Policy])
  var hall: Building
  for building in game.world.buildings:
    if building.owner == 0 and building.kind == TownHallBuilding:
      hall = building
      break
  doAssert hall.id != 0
  let
    unit = game.world.units[0]
    rally = ReplayAction(kind: ActionSetRally, playerId: hall.owner,
      entityId: hall.id, first: int32(unit.tile.x), second: int32(unit.tile.y))
    chat = ReplayAction(kind: ActionChat, playerId: 0, target: 0,
      text: "history")
    before = game.stateHash()
  doAssert game.world.clone().applyReplayAction(rally)
  game.historyPlayback = true
  doAssert not game.warmingPolicies
  for replayMode in [false, true]:
    game.replayMode = replayMode
    game.replayPlayer = ReplayPlayer(data: ReplayData(actions: @[rally]))
    doAssert not game.applySetRally(rally.playerId, rally.entityId,
      rally.first, rally.second)
    doAssert game.replayPlayer.actionIndex == 0
    doAssert game.stateHash() == before
    game.replayPlayer = ReplayPlayer(data: ReplayData(actions: @[chat]))
    doAssert game.sendChat(0, 0, chat.text) == 0
    doAssert game.replayPlayer.actionIndex == 0
    doAssert game.inboxes[0].count == 0
    doAssert game.stateHash() == before
  echo "Light vs Dark ordinary history never matches policy proposals"
