import
  std/os,
  bassy,
  polyworld/cli,
  ../[bots, content, maps, replays, sim]

const
  Policies = currentSourcePath().parentDir.parentDir / "players"
  IdlePolicy = currentSourcePath().parentDir / "policies/idle.bas"

proc decide(game: Game) =
  ## Runs a real bounded policy decision without advancing movement.
  game.world.tick += 6
  game.runBotDecisions()
  let vm = game.heroVms[0]
  doAssert not vm.failed, vm.lastError
  doAssert vm.lastInstructions <= vm.limits.maxInstructions
  doAssert vm.lastWork <= vm.limits.maxWorkUnits

echo "Bundled bots accept artifact inventories when taking over a hero"
for policy in ["base", "puller", "black-kite", "red-kite", "khors",
    "cogas", "jev", "lane_sustain", "rusher"]:
  let game = newGame(generateMap(54), 100_000, 10, false,
    ReplayData(), drafting = false)
  game.loadBots([
    BotGroup(path: Policies / (policy & ".bas"), count: 1),
    BotGroup(path: IdlePolicy, count: 9)
  ])
  for i in 1 ..< game.heroVms.len:
    game.heroVms[i] = nil
  let hero = game.world.heroes[0]
  hero.gold = 0
  for slot, item in ArtifactItems:
    hero.inventory[slot] = item
    hero.itemCounts[slot] = 1
  hero.refreshHeroStats()
  game.decide()
  if policy in ["base", "puller", "black-kite", "red-kite"]:
    let vm = game.heroVms[0]
    for slot, item in ArtifactItems:
      doAssert vm.runtime.getArray("owned", item.ord.int32) == 1, policy
      doAssert vm.runtime.getArray("inventorySlot", item.ord.int32) == slot,
        policy
    doAssert game.world.applySellItem(hero.id, 1)
    doAssert game.world.applySwapItems(hero.id, 2, 5)
    game.decide()
    doAssert vm.runtime.getArray("owned", AbyssalPearl.ord) == 0, policy
    doAssert vm.runtime.getArray("inventorySlot", AbyssalPearl.ord) == -1,
      policy
    doAssert vm.runtime.getArray("owned", Worldbreaker.ord) == 1, policy
    doAssert vm.runtime.getArray("inventorySlot", Worldbreaker.ord) == 5,
      policy

echo "GOTA artifact bot compatibility tests passed"
