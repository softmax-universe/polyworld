import
  std/sequtils,
  bassy,
  ../[bots, content, maps, replays, sim]

let game = newGame(generateMap(DefaultSeed), 1)
game.loadBots(repeat("""
  decisions = decisions + 1
  accepted = gather(0)
  noticed = orderFailed()
""", VillagerCount))
game.world.villagers[0].orderFailed = true
game.historyPlayback = true
game.warmingPolicies = true
let originalHash = game.stateHash()
game.runBotDecisions()
doAssert game.stateHash() == originalHash
doAssert not game.world.villagers[0].orderFailed
for brain in game.brains:
  doAssert not brain.failed
  doAssert brain.runtime.getGlobal("decisions") == 1
  doAssert brain.runtime.getGlobal("accepted") == 0

game.historyPlayback = false
game.warmingPolicies = false
game.runBotDecisions()
doAssert game.brains[0].runtime.getGlobal("decisions") == 2
doAssert not game.world.villagers[0].orderFailed
doAssert game.stateHash() != originalHash
echo "Heartleaf replay warm-up preserves world and policy memory"

let
  live = newGame(generateMap(DefaultSeed), 1)
  warm = newGame(generateMap(DefaultSeed), 1)
  source = "accepted = gather(0)\nstopped = cancel()\nagain = gather(0)"
live.world.tick = DecisionTicks
warm.world.tick = DecisionTicks
live.recorder = ReplayRecorder()
live.loadBots(repeat(source, VillagerCount))
live.runBotDecisions()
warm.replayPlayer = ReplayPlayer(data: live.recorder.data)
warm.historyPlayback = true
let viewerHash = warm.stateHash()
doAssert not warm.applyGather(1, 0)
doAssert warm.replayPlayer.actionIndex == 0
doAssert warm.stateHash() == viewerHash
warm.warmingPolicies = true
var sources = repeat(source, VillagerCount)
sources[1] = "accepted = gather(1)"
warm.loadBots(sources)
warm.runBotDecisions()
doAssert warm.stateHash() == live.stateHash()
doAssert warm.replayPlayer.actionIndex == live.recorder.data.actions.len
for slot, brain in warm.brains:
  doAssert not brain.failed
  if slot == 1:
    doAssert brain.runtime.getGlobal("accepted") == 0
  else:
    doAssert brain.runtime.getGlobal("accepted") == 1
    doAssert brain.runtime.getGlobal("stopped") == 1
    doAssert brain.runtime.getGlobal("again") == 1
echo "Heartleaf warm-up preserves command results and flushes replaced actions"
