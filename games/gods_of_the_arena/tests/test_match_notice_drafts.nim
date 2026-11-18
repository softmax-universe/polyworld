import ../[content, maps, matchnotices, presets, replays, sim]

echo "Testing local warning against actual draft outcomes"
for mode in DraftMode:
  for seed in [7'i32, 54'i32, 2026'i32]:
    for active in [@[1], @[1, 8], @[0, 2, 4, 6, 8],
        @[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]]:
      let game = newGame(generateMap(seed), 100_000, 10, false,
        ReplayData(), draftMode = mode, activeSeats = active)
      game.networked = true
      game.recorder = initReplayRecorder(
        currentSetup(game, uint32(182 * TickRate)))
      game.world.camps.setLen(0)
      while game.world.phase == Drafting:
        doAssert game.matchNoticeTick() == 0
        let tick = game.world.tick + 1
        if seed == 7 and tick mod 17 == 0:
          let hero = game.world.draftHeroId()
          var class = 0'i32
          while not game.world.heroAvailable(class):
            inc class
          let action = ReplayAction(heroId: hero, kind: ActionDraft,
            first: class)
          let invalid = ReplayAction(heroId: hero, kind: ActionDraft, first: -1)
          game.networkActions.add [invalid, action, action]
        game.tickWorld(nil)
        doAssert not game.matchNoticeDue()
      let due = game.world.draftTicks + PreparationTicks + 2 * TickRate
      doAssert game.matchNoticeTick() == due.uint32
      var notices = 0
      while game.world.tick <= due:
        game.tickWorld(nil)
        if game.matchNoticeDue():
          inc notices
          doAssert game.world.tick == due
          doAssert game.config.maxTicks - game.world.battleTick() ==
            180 * TickRate
      doAssert notices == 1
echo "PASS 36 actual drafts, sparse seats, draft modes, early and timeout picks"
