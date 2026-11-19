import
  bassy,
  ../[bots, maps, sim]

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
