## Cross-check the narrow relay draft clock against actual game rules.
import polyworld/rooms
import jsony
import std/importutils
import ../[content, maps, multiplayer, presets, relaynotice, replays, sim]
privateAccess(RelayNotice)

for mode in DraftMode:
  for seed in [7'i32, 54'i32, 2026'i32]:
    for active in [@[1], @[1, 8], @[0, 2, 4, 6, 8], @[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]]:
      var config = parseConfig("{}")
      config.seed = seed
      config.maxTicks = 182 * TickRate
      config.draftMode = mode
      var seats = newSeq[Seat](10)
      for seat in active: seats[seat] = Seat(owner: 1)
      var clock = initRelayNotice(gotaIdentity(), config.toJson(), 24, seats)
      let game = newGame(generateMap(seed), config.spawnIntervalTicks, 10, false,
        ReplayData(), draftMode = mode, activeSeats = active)
      game.networked = true
      game.recorder = initReplayRecorder(currentSetup(game, config.maxTicks.uint32))
      while game.world.phase == Drafting:
        let tick = game.world.tick.uint32 + 1
        var commands: seq[Command]
        if seed == 7 and tick mod 17 == 0:
          let hero = game.world.draftHeroId()
          let index = game.world.heroIndex(hero)
          var class = 0'i32
          while not game.world.heroAvailable(class): inc class
          let action = ReplayAction(heroId: hero, kind: ActionDraft, first: class)
          # Reject invalid class and duplicate picks without extending deadlines.
          let invalid = ReplayAction(heroId: hero, kind: ActionDraft, first: -1)
          for submitted in [invalid, action, action]:
            commands.add Command(participant: 1, seat: active[index].uint32,
              payload: GameSubmission(action: submitted).encodeSubmission())
            game.networkActions.add submitted
        doAssert not clock.advanceNotice(tick, commands)
        game.tickWorld(nil)
      # Timeout RNG, sparse team order and preparation budget must agree.
      for i, hero in game.world.heroes:
        doAssert clock.classes[active[i]] == hero.class.ord.int32
      let due = game.world.draftTicks.uint32 + PreparationTicks.uint32 + 2 * TickRate.uint32
      for tick in game.world.tick.uint32 + 1 .. due + 2:
        doAssert clock.advanceNotice(tick, []) == (tick == due)
echo "PASS draft-clock parity: 36 worlds, all draft modes, three seeds, 1/2/5/10 sparse seats, mixed early/timeout/invalid/duplicate picks"
