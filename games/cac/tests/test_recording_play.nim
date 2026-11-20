import
  std/[options, sequtils],
  vmath,
  ../play, ../core/[bots, replays, sim], ../scene/table

proc poses(player, count: int): seq[CardPose] =
  ## Supplies a neutral table for exercising input without a renderer.
  for _ in 0 ..< count:
    result.add CardPose()

proc origin(player: int): CardPose =
  ## Places every single-card anchor at the test table's origin.
  CardPose()

proc feet(player: int): Vec3 =
  ## Keeps opposing hero targets distinct for attack presentation.
  vec3(player.float32 * 5, 0, 0)

proc shown(player: int): bool =
  ## Makes every test seat's hand visible.
  true

proc flatTable(): TableLayout =
  ## Provides the public table interface without a graphics context.
  TableLayout(handPoses: poses, boardPoses: poses, deckPose: origin,
    discardPose: origin, spellPose: origin, heroPosition: feet,
    handVisible: shown)

proc fixture(card: string, heroClass: HeroClass,
    players = 2): tuple[play: TablePlay, game: GameState] =
  ## Deals repeatable base-card decks so actions remain legal on replay.
  var seats: seq[Seat]
  for player in 0 ..< players:
    seats.add Seat(heroClass: heroClass,
      deck: @[(card, 30)])
  result.game = newGame(seats, 35, recordEvents = true)
  result.play = initTablePlay(1)
  result.play.recorder = initReplayRecorder(matchSetup(seats, 35, 1000),
    GameConfig(seed: 35, maxTicks: 1000, players: unnamedPlayers(players)))

proc endTurn(play: var TablePlay, game: var GameState) =
  ## Records the same direct end-turn operation used by graphical modes.
  let player = game.currentPlayer
  doAssert not game.waitingChoice and not game.gameOver
  game.finishTurn()
  play.recordAccepted(game,
    ReplayAction(kind: ActionEndTurn, playerId: player.int32))

proc readyFor(play: var TablePlay, game: var GameState, cost: int,
    player = 0) =
  ## Waits through legal recorded turns until a seat can play its card.
  while game.currentPlayer != player or game.players[player].energy < cost:
    doAssert game.turnNumber < 30
    play.endTurn(game)

proc verify(play: TablePlay, expected: GameState) =
  ## Decodes and replays every admitted command, checking each state hash.
  let data = play.recorder.data.encodeReplay().decodeReplay()
  var
    replay = newGame(data.header.setup)
    cursor = data.initReplayCursor()
    action: ReplayAction
    tick = 0'u32
  while data.takeReplayAction(cursor, tick, action):
    doAssert replay.applyAction(action), "Recorded action must remain legal."
    discard replay.takeVisualEvents()
    doAssert replay.stateHash() == data.hashes[action.tick.int - 1],
      "Replay diverged at action " & $action.tick
    tick = action.tick
  doAssert cursor.actionIndex == data.actions.len
  doAssert replay.stateHash() == expected.stateHash()

proc testLocalActions() =
  ## Covers human cards, pending targeting, and delayed attack admission.
  for players in [2, 7]:
    var (play, game) = fixture("Sharpshooter", Archer, players)
    play.readyFor(game, 3)
    let before = play.recorder.data.hashes.len
    doAssert play.playHandCard(game, flatTable(), 0)
    doAssert play.pendingTargeting
    doAssert play.recorder.data.hashes.len == before,
      "A permanent is recorded only after its pending choices finish."
    discard play.recorder.data.encodeReplay()
    play.takePick(game, flatTable(), heroChoice(1))
    doAssert play.recorder.data.hashes.len == before + 1
    doAssert play.recorder.data.actions[^1].handIndex == 0
    play.verify(game)

    let attacker = game.players[0].board[0].id
    play.endTurn(game)
    play.readyFor(game, 0)
    let attackTick = play.recorder.data.hashes.len
    play.startAttack(game, flatTable(), @[attacker], heroChoice(1))
    doAssert play.recorder.data.hashes.len == attackTick
    discard play.advanceAttack(game, AttackLungeDuration * 0.5'f)
    doAssert play.recorder.data.hashes.len == attackTick
    discard play.advanceAttack(game, AttackLungeDuration)
    doAssert play.recorder.data.hashes.len == attackTick + 1
    doAssert play.recorder.data.actions[^1].kind == ActionAttack
    discard play.advanceAttack(game, AttackReturnDuration * 2)
    doAssert play.recorder.data.hashes.len == attackTick + 1
    play.verify(game)

  block:
    var (play, game) = fixture("Sniper", Archer)
    play.readyFor(game, 2)
    doAssert play.playHandCard(game, flatTable(), 0)
    doAssert not play.pendingTargeting
    play.verify(game)

  block:
    var (play, game) = fixture("Bolt", Archer)
    play.readyFor(game, 1)
    discard play.playHandCard(game, flatTable(), 0)
    doAssert play.pendingTargeting
    play.takePick(game, flatTable(), heroChoice(1))
    doAssert play.recorder.data.actions[^1].kind == ActionPlayCard
    play.verify(game)

  block:
    var (play, game) = fixture("Study", Mage)
    play.readyFor(game, 2)
    doAssert play.playHandCard(game, flatTable(), 0)
    doAssert game.waitingToss
    play.startTossPicking(game)
    play.updateTossPicking(game, 0, pick = true, clear = false)
    doAssert not game.waitingToss
    doAssert play.recorder.data.actions[^1].kind == ActionToss
    play.verify(game)

  block:
    var (play, game) = fixture("Morphosis Chamber", Mage)
    play.readyFor(game, 3)
    doAssert play.playHandCard(game, flatTable(), 0)
    play.endTurn(game)
    play.readyFor(game, 0)
    doAssert game.waitingTrigger
    play.startTriggerTargeting(game)
    play.updateChoosing(game, flatTable(), -1,
      pick = false, cancel = true, time = 0)
    doAssert not game.waitingTrigger
    doAssert play.recorder.data.actions[^1].kind == ActionResolveTrigger
    play.verify(game)

  block:
    var (play, game) = fixture("Burnout", Mage, 3)
    let
      player = game.currentPlayer
      turn = game.turnNumber
    doAssert play.playHandCard(game, flatTable(), 0)
    play.endTurn(game)
    doAssert game.waitingToss
    doAssert game.currentPlayer == player and game.turnNumber == turn
    doAssert play.recorder.data.actions[^1].kind == ActionEndTurn,
      "An accepted turn end is recorded even while its trigger awaits input."
    play.startTossPicking(game)
    play.updateTossPicking(game, 0, pick = true, clear = false)
    doAssert game.currentPlayer != player and game.turnNumber > turn
    doAssert play.recorder.data.actions[^1].kind == ActionToss
    play.verify(game)
  echo "CaC local human actions, delayed attacks, and choices replay exactly."

proc testBotMail() =
  ## Records repeated mailbox messages before the bot's accepted action.
  const Talking = """
sent = sendChat(enemyPlayer, "same message")
sent = sendChat(enemyPlayer, "same message")
endTurn()
end
"""
  for players in [2, 7]:
    var
      fixture = fixture("Footsoldier", Warrior, players)
      clock = initBotClock()
    let bots = loadBots(newSeqWith(players, Talking))
    for _ in 0 ..< 5:
      fixture.play.resetTable()
      discard fixture.game.takeVisualEvents()
      clock.wait = 0
      discard fixture.play.updateBots(fixture.game, flatTable(), bots, clock,
        proc(): bool = false, 0)
    let data = fixture.play.recorder.data
    doAssert data.hashes.len == 5
    doAssert data.actions.len == 15
    for tick in 0 ..< 5:
      doAssert data.actions[tick * 3].kind == ActionMailbox
      doAssert data.actions[tick * 3 + 1].kind == ActionMailbox
      doAssert data.actions[tick * 3].tick == tick.uint32
      doAssert data.actions[tick * 3 + 2].kind == ActionEndTurn
      doAssert data.actions[tick * 3 + 2].tick == tick.uint32 + 1
    fixture.play.verify(fixture.game)
  echo "CaC local bot actions and repeated mailbox messages retain order."

proc testPermanentChoiceCancel() =
  ## Declining a permanent's branch matches core play, including its watchers.
  let
    card = Card(name: "Branching guard", energyCost: 0,
      class: some(Archer), kind: Minion, power: 1, toughness: 2,
      rules: rules(
        choose(rules(draw(1)), rules(damage(1, You))),
        draw(1)))
    watcher = Card(name: "Watcher", energyCost: 0,
      class: some(Archer), kind: Trinket,
      rules: rules(on(played(You, {kind: {Minion}}), damage(2, You))))
  var (play, game) = fixture("Sniper", Archer)
  play.recorder = nil
  let player = game.currentPlayer
  game.players[player].hand = @[card]
  game.players[player].board = @[MinionState(id: 1, owner: player,
    card: watcher, enteredTurn: game.turnNumber)]
  game.nextMinionId = 2
  var expected = game.copyGameState()
  let action = ReplayAction(kind: ActionPlayCard, playerId: player.int32,
    handIndex: 0, choices: @[NoTarget].toReplay)
  doAssert expected.applyAction(action)
  doAssert play.playHandCard(game, flatTable(), 0)
  doAssert play.choosing
  play.updateChoosing(game, flatTable(), -1,
    pick = false, cancel = true, time = 0)
  doAssert not play.pendingTargeting
  doAssert game.players[player].hand.len == 1,
    "The remaining draw must run exactly once after declining the branch."
  doAssert game.players[player].life == StartingLife - 2,
    "The played-card watcher must fire exactly once."
  # Snapshots only support base-set cards. Replace the same fixture cards
  # in both completed states before comparing the rest of their snapshots.
  for state in [addr game, addr expected]:
    for seat in state[].players.mitems:
      for minion in seat.board.mitems:
        if minion.card.name in [card.name, watcher.name]:
          minion.card = baseCardNamed("Sniper")
  doAssert game.stateHash() == expected.stateHash()
  echo "CaC permanent choice cancellation matches canonical play exactly."

testLocalActions()
testBotMail()
testPermanentChoiceCancel()
