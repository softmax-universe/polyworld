import ../[content, controls, maps, replays, sim]

proc shopGame(): Game =
  result = newGame(generateMap(54), 240, 10, false, ReplayData(), drafting = false)
  result.world.spawnTimerTicks = 100_000
  result.world.heroTurnTicks = 100_000

block deadPurchases:
  let game = shopGame()
  let hero = game.world.heroes[0]
  hero.state = Dying
  hero.hp = 0
  hero.mana = 0
  hero.gold = 100_000
  hero.deathTicks = 40
  hero.position.x = 0
  hero.position.z = 0
  doAssert hero.canShop, "dead heroes shop remotely at their own keep"
  doAssert game.world.purchaseReason(hero.id, KnightArmor.ord.int32) == ""
  doAssert game.world.applyBuyItem(hero.id, KnightArmor.ord.int32)
  doAssert hero.state == Dying and hero.hp == 0 and hero.mana == 0
  doAssert hero.deathTicks == 40

block sellingStacks:
  let game = shopGame()
  let hero = game.world.heroes[0]
  hero.state = Dying
  hero.hp = 0
  hero.mana = 0
  hero.gold = 10_000
  for i in 0 ..< 3:
    doAssert game.world.applyBuyItem(hero.id, ManaElixir.ord.int32)
  let gold = hero.gold
  doAssert game.world.sellReason(hero.id, 0) == ""
  doAssert game.world.sellPrice(hero.id, 0) == ManaElixir.itemSpec.cost * 3 div 2
  doAssert game.world.applySellItem(hero.id, 0)
  doAssert hero.gold == gold + ManaElixir.itemSpec.cost * 3 div 2
  doAssert hero.inventory[0] == NoItem and hero.itemCounts[0] == 0
  doAssert not game.world.applySellItem(hero.id, 0)
  doAssert hero.gold == gold + ManaElixir.itemSpec.cost * 3 div 2
  doAssert hero.hp == 0 and hero.mana == 0 and hero.state == Dying

block swapping:
  let game = shopGame()
  let hero = game.world.heroes[0]
  hero.inventory[4] = ManaPotion
  hero.itemCounts[4] = 3
  hero.inventory[0] = PortalScroll
  hero.itemCounts[0] = 2
  hero.potionCooldownEnds[ManaRecovery] = 110
  hero.portalCooldownEnds = 220
  let gold = hero.gold
  queueSwapItems(hero.id, 4, 0)
  doAssert hero.inventory[0] == PortalScroll
  game.flushPlayerCommands()
  doAssert hero.inventory[0] == ManaPotion and hero.itemCounts[0] == 3
  doAssert hero.inventory[4] == PortalScroll and hero.itemCounts[4] == 2
  doAssert hero.itemCooldown(0, 0) == 110 and hero.itemCooldown(4, 0) == 220
  doAssert game.world.applySwapItems(hero.id, 4, 1)
  doAssert hero.inventory[4] == NoItem and hero.itemCounts[4] == 0
  doAssert hero.inventory[1] == PortalScroll and hero.itemCounts[1] == 2
  let inventory = hero.inventory
  let counts = hero.itemCounts
  doAssert game.world.applySwapItems(hero.id, 1, 1)
  doAssert not game.world.applySwapItems(hero.id, -1, 0)
  doAssert not game.world.applySwapItems(hero.id, 1, InventorySlots)
  doAssert not game.world.applySwapItems(hero.id, 4, 0)
  doAssert inventory == hero.inventory and counts == hero.itemCounts
  doAssert hero.gold == gold
  hero.hp = 0
  hero.state = Dying
  doAssert game.world.applySwapItems(hero.id, 1, 5)
  doAssert hero.hp == 0 and hero.state == Dying

block weaponRestrictions:
  let game = shopGame()
  let hero = game.world.heroes[0]
  hero.state = Dying
  hero.hp = 0
  hero.mana = 0
  for class in HeroClass:
    hero.class = class
    for item in [BattleAxe, SunsteelLongsword, RuneCrossbow, RangerBow]:
      hero.gold = 10_000
      hero.inventory = default(typeof(hero.inventory))
      hero.itemCounts = default(typeof(hero.itemCounts))
      let allowed = class.heroSpec.attackStyle ==
        (if item in [BattleAxe, SunsteelLongsword]: MeleeAttack else: RangedAttack)
      let reason = game.world.purchaseReason(hero.id, item.ord.int32)
      doAssert (reason == "") == allowed, "weapon restriction: " & $class & " / " & $item
      if not allowed:
        doAssert reason == (if item in [BattleAxe, SunsteelLongsword]:
          "Melee heroes only" else: "Ranged heroes only")
      doAssert game.world.applyBuyItem(hero.id, item.ord.int32) == allowed
      doAssert hero.lastActionError.actionErrorMessage() == reason,
        "UI purchase reason and bot action error must agree"
      doAssert hero.gold == (if allowed: 10_000 - item.itemSpec.cost else: 10_000)
      doAssert hero.hp == 0 and hero.mana == 0
    # Other equipment remains generic, even for magic heroes.
    for item in [CrimsonDagger, AmethystWand, ThornwoodStaff, ArcaneSpellbook]:
      hero.inventory = default(typeof(hero.inventory))
      hero.itemCounts = default(typeof(hero.itemCounts))
      doAssert game.world.applyBuyItem(hero.id, item.ord.int32)
  doAssert BattleAxe.itemSpec.cost == 160 and RuneCrossbow.itemSpec.cost == 180
  doAssert SunsteelLongsword.itemSpec.cost == 130 and RangerBow.itemSpec.cost == 150
  doAssert BattleAxe.itemSpec.damage == 14 and RuneCrossbow.itemSpec.damage == 14
  doAssert SunsteelLongsword.itemSpec.damage == 10 and RangerBow.itemSpec.damage == 10

block sellingLowResources:
  let game = shopGame()
  let hero = game.world.heroes[0]
  hero.gold = 10_000
  doAssert game.world.applyBuyItem(hero.id, KnightArmor.ord.int32)
  doAssert game.world.applyBuyItem(hero.id, SapphireRing.ord.int32)
  hero.hp = 50
  hero.mana = 10
  doAssert game.world.applySellItem(hero.id, 0)
  doAssert hero.hp == 1 and hero.state != Dying
  doAssert game.world.applySellItem(hero.id, 1)
  doAssert hero.mana == 0 and hero.hp == 1 and hero.state != Dying

block sellingEquipmentAndGates:
  let game = shopGame()
  let hero = game.world.heroes[0]
  hero.gold = 10_000
  doAssert game.world.applyBuyItem(hero.id, KnightArmor.ord.int32)
  doAssert game.world.applyBuyItem(hero.id, SapphireRing.ord.int32)
  let maxHp = hero.maxHp
  doAssert game.world.applySellItem(hero.id, 0)
  doAssert hero.maxHp == maxHp - KnightArmor.itemSpec.maxHp
  doAssert hero.hp <= hero.maxHp and hero.hp > 0
  hero.position.x = 0
  hero.position.z = 0
  let inventory = hero.inventory
  let gold = hero.gold
  doAssert game.world.sellReason(hero.id, 1) == "Return to your keep"
  doAssert not game.world.applySellItem(hero.id, 1)
  doAssert game.world.sellPrice(hero.id, 1) == 0
  doAssert not game.world.applySellItem(hero.id, -1)
  doAssert not game.world.applySellItem(hero.id, InventorySlots)
  doAssert not game.world.applySellItem(-1, 0)
  doAssert hero.inventory == inventory and hero.gold == gold
  hero.state = Dying
  hero.hp = 0
  hero.mana = 0
  queueSellItem(hero.id, 1)
  doAssert hero.inventory[1] == SapphireRing
  game.flushPlayerCommands()
  doAssert hero.inventory[1] == NoItem and hero.hp == 0 and hero.mana == 0
  doAssert not game.world.applyBuyItem(hero.id, -1)
  doAssert not game.world.applyBuyItem(hero.id, int32.high)
  hero.gold = 0
  doAssert not game.world.applyBuyItem(hero.id, ManaPotion.ord.int32)
  doAssert hero.gold == 0
  game.world.phase = Drafting
  doAssert not game.world.applyBuyItem(hero.id, ManaPotion.ord.int32)
  doAssert not game.world.applySellItem(hero.id, 0)
  doAssert not game.world.applySwapItems(hero.id, 0, 1)
  game.world.phase = Playing
  game.world.gameOver = true
  doAssert not game.world.applyBuyItem(hero.id, ManaPotion.ord.int32)
  doAssert not game.world.applySellItem(hero.id, 0)
  doAssert not game.world.applySwapItems(hero.id, 0, 1)

echo "Shop backend tests passed"
