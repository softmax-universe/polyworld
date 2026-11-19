import
  std/sequtils,
  bassy,
  ../[bots, content, maps, sim]

let game = newGame(generateMap(DefaultSeed), 1)
game.loadBots(repeat("""
  decisions = decisions + 1
  accepted = gather(0)
  noticed = orderFailed()
""", VillagerCount))
game.world.villagers[0].orderFailed = true
game.historyPlayback = true
let originalHash = game.stateHash()
game.runBotDecisions()
doAssert game.stateHash() == originalHash
doAssert game.world.villagers[0].orderFailed
for brain in game.brains:
  doAssert not brain.failed
  doAssert brain.runtime.getGlobal("decisions") == 1
  doAssert brain.runtime.getGlobal("accepted") == 0

game.historyPlayback = false
game.runBotDecisions()
doAssert game.brains[0].runtime.getGlobal("decisions") == 2
doAssert not game.world.villagers[0].orderFailed
doAssert game.stateHash() != originalHash
echo "Heartleaf replay warm-up preserves world and policy memory"
