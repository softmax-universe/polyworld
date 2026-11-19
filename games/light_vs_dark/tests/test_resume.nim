import
  bassy,
  polyworld/cli,
  ../[bots, content, maps, multiplayer, presets, replays, sim],
  ../game as runner

const Policy = """
visits = visits + 1
accepted = setRally(obsId(0), obsX(ownBuildings), obsY(ownBuildings))
"""

let game = newGame(generateMap(2026, 2), 120)
game.loadBots([Policy, Policy])
game.historyPlayback = true
let original = game.stateHash()
for i in 0 ..< 2:
  game.runBotDecisions()
  doAssert game.stateHash() == original
  for brain in game.brains:
    doAssert not brain.failed
    doAssert brain.runtime.getGlobal("visits") == int32(i + 1)
    doAssert brain.runtime.getGlobal("accepted") == 0
game.historyPlayback = false
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
