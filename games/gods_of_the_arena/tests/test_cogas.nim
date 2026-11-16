## Compatibility smoke for the exported co-gas tournament champion.
import
  std/os,
  bassy,
  polyworld/cli,
  ../[bots, content, maps, replays, sim]

const Policy = currentSourcePath().parentDir.parentDir /
  "players/cogas.bas"

proc checkVms(game: Game) =
  for vm in game.heroVms:
    doAssert vm != nil
    doAssert not vm.failed, vm.lastError
    doAssert vm.lastInstructions <= vm.limits.maxInstructions
    doAssert vm.lastWork <= vm.limits.maxWorkUnits

echo "Testing co-gas drafts and enters play within the VM budgets"
block:
  let game = newGame(generateMap(54), 100_000, 10, false, ReplayData())
  game.loadBots([BotGroup(path: Policy, count: 10)])
  game.checkVms()
  for tick in 0 ..< 3000:
    game.tickWorld(proc() = game.runBotDecisions())
    game.checkVms()
    if game.world.phase != Drafting:
      break
  doAssert game.world.phase == Playing

echo "Testing every co-gas hero on both teams for 1200 battle ticks"
for reverse in [false, true]:
  let game = newGame(generateMap(54), 100_000, 10, false,
    ReplayData(), drafting = false)
  game.loadBots([BotGroup(path: Policy, count: 10)])
  for i, hero in game.world.heroes:
    hero.class = HeroClass(if reverse: 9 - i else: i)
    hero.refreshHeroStats()
    hero.hp = hero.maxHp
    hero.mana = hero.maxMana
  game.recorder = initReplayRecorder(game.currentSetup(1200))
  for tick in 0 ..< 1200:
    game.tickWorld(proc() = game.runBotDecisions())
    game.checkVms()
  for hero in game.world.heroes:
    var acted = false
    for action in game.recorder.data.actions:
      if action.heroId == hero.id:
        acted = true
        break
    doAssert acted, "Co-gas emitted no actions for " & $hero.class
