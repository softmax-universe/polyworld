## Network inputs only change the table until their relay action arrives.
import vmath
import ../play, ../core/[replays, sim], ../scene/table

proc poses(player, count: int): seq[CardPose] =
  ## Supplies a harmless pose for every card in a headless table.
  for _ in 0 ..< count:
    result.add CardPose()

proc origin(player: int): CardPose =
  ## Places the piles at the table origin.
  CardPose()

proc feet(player: int): Vec3 =
  ## Places each hero at the table origin.
  vec3(0, 0, 0)

proc shown(player: int): bool =
  ## Shows hands while testing table input.
  true

proc flatTable(): TableLayout =
  ## Supplies the layout callbacks needed to collect target choices.
  TableLayout(handPoses: poses, boardPoses: poses, deckPose: origin,
    discardPose: origin, spellPose: origin, heroPosition: feet,
    handVisible: shown)

block:
  var
    game = newGame(Archer, Warrior, 11)
    play = initTablePlay(1)
    actions: seq[ReplayAction]
  let me = game.currentPlayer
  game.players[me].energy = 20
  game.players[me].hand = @[baseCardNamed("Bear")]
  play.submitAction = proc(action: ReplayAction): bool =
    ## Captures the command without applying it to the game.
    actions.add action
    true
  play.resetTable()
  let before = game.stateHash
  doAssert play.playHandCard(game, flatTable(), 0)
  doAssert game.stateHash == before
  doAssert play.animations.len == 0
  doAssert actions.len == 1
  doAssert actions[0].kind == ActionPlayCard
  doAssert actions[0].playerId == me.int32
  doAssert actions[0].handIndex == 0
  doAssert game.applyAction(actions[0])
  doAssert game.players[me].hand.len == 0
  doAssert game.players[me].board.len == 1

block:
  var
    game = newGame(Archer, Warrior, 13)
    play = initTablePlay(1)
    actions: seq[ReplayAction]
  let
    me = game.currentPlayer
    target = heroChoice(1 - me)
  game.players[me].energy = 20
  game.players[me].hand = @[baseCardNamed("Sharpshooter")]
  play.submitAction = proc(action: ReplayAction): bool =
    ## Captures the complete card play after its target is picked.
    actions.add action
    true
  let before = game.stateHash
  discard play.playHandCard(game, flatTable(), 0)
  doAssert play.pendingTargeting
  doAssert play.pendingCardIndex == 0
  doAssert play.pendingSourceId == game.nextMinionId
  doAssert actions.len == 0
  doAssert game.stateHash == before
  play.takePick(game, flatTable(), target)
  doAssert game.stateHash == before
  doAssert actions.len == 1
  doAssert actions[0].choices == @[target].toReplay
  doAssert not play.pendingTargeting
  doAssert game.applyAction(actions[0])
  doAssert game.players[me].board.len == 1
  doAssert game.players[1 - me].life < StartingLife

for name in ["Bouncer", "Sharpshooter", "Tactician"]:
  var
    game = newGame(Archer, Warrior, 29)
    play = initTablePlay(1)
    actions: seq[ReplayAction]
  let
    me = game.currentPlayer
    predictedId = game.nextMinionId
    self = creatureChoice(me, predictedId)
  game.players[me].energy = 20
  game.players[me].hand = @[baseCardNamed("Bear"), baseCardNamed(name)]
  play.submitAction = proc(action: ReplayAction): bool =
    ## Captures a permanent that targets itself before it enters play.
    actions.add action
    true
  let before = game.stateHash
  var expected = game.copyGameState()
  let sourceId = expected.playMinion(1)
  doAssert sourceId == predictedId
  doAssert expected.finishPlay(baseCardNamed(name), @[self], sourceId)
  discard play.playHandCard(game, flatTable(), 1)
  doAssert game.stateHash == before
  doAssert play.pendingSourceId == predictedId
  doAssert play.pendingChoices.choiceIsLegal(self)
  doAssert play.pendingHandTarget(game, 0).isCanceled
  doAssert play.pendingHandTarget(game, 1) == self
  doAssert actions.len == 0
  play.takePick(game, flatTable(), play.pendingHandTarget(game, 1))
  doAssert game.stateHash == before
  doAssert actions.len == 1
  doAssert actions[0].kind == ActionPlayCard
  doAssert actions[0].handIndex == 1
  doAssert actions[0].choices == @[self].toReplay
  doAssert play.pendingHandTarget(game, 1).isCanceled
  doAssert game.applyAction(actions[0])
  doAssert game.stateHash == expected.stateHash

block:
  var
    game = newGame(Archer, Warrior, 17)
    play = initTablePlay(1)
    actions: seq[ReplayAction]
  let
    me = game.currentPlayer
    first = creatureChoice(me, 1)
    second = creatureChoice(1 - me, 2)
  game.players[me].energy = 20
  game.players[me].hand = @[baseCardNamed("Duel")]
  game.players[me].board = @[MinionState(id: 1, owner: me,
    card: baseCardNamed("Bear"), currentToughness: 2)]
  game.players[1 - me].board = @[MinionState(id: 2, owner: 1 - me,
    card: baseCardNamed("Bear"), currentToughness: 2)]
  game.nextMinionId = 3
  play.submitAction = proc(action: ReplayAction): bool =
    ## Captures both targets in one atomic card command.
    actions.add action
    true
  let before = game.stateHash
  discard play.playHandCard(game, flatTable(), 0)
  play.takePick(game, flatTable(), first)
  doAssert play.pendingTargeting
  doAssert play.pendingPicks == @[first]
  doAssert play.pendingChoices.choiceIsLegal(second)
  doAssert actions.len == 0
  doAssert game.stateHash == before
  play.takePick(game, flatTable(), second)
  doAssert game.stateHash == before
  doAssert actions.len == 1
  doAssert actions[0].choices == @[first, second].toReplay
  doAssert game.applyAction(actions[0])
  doAssert game.players[me].hand.len == 0

block:
  var
    game = newGame(Archer, Warrior, 19)
    play = initTablePlay(1)
    actions: seq[ReplayAction]
  let
    me = game.currentPlayer
    owner = 1 - me
    card = baseCardNamed("Sharpshooter")
    target = creatureChoice(me, 2)
  game.players[owner].board = @[MinionState(id: 1, owner: owner, card: card)]
  game.players[me].board = @[MinionState(id: 2, owner: me,
    card: baseCardNamed("Bear"), currentToughness: 2)]
  game.nextMinionId = 3
  game.pendingTriggers = @[
    PendingTrigger(owner: owner, sourceId: 1, onPlay: true)]
  play.submitAction = proc(action: ReplayAction): bool =
    ## Captures a waiting trigger for its owner, even out of turn.
    actions.add action
    true
  let before = game.stateHash
  play.startTriggerTargeting(game)
  play.takePick(game, flatTable(), target)
  doAssert game.stateHash == before
  doAssert actions.len == 1
  doAssert actions[0].kind == ActionResolveTrigger
  doAssert actions[0].playerId == owner.int32
  doAssert actions[0].choices == @[target].toReplay
  doAssert game.applyAction(actions[0])
  doAssert not game.waitingTrigger

block:
  var
    game = newGame(Archer, Warrior, 23)
    play = initTablePlay(1)
    actions: seq[ReplayAction]
  let owner = 1 - game.currentPlayer
  game.players[owner].hand = @[
    baseCardNamed("Bear"), baseCardNamed("Bolt"), baseCardNamed("Sniper")]
  game.pendingToss = PendingToss(player: owner, count: 2, source: "Discard")
  play.submitAction = proc(action: ReplayAction): bool =
    ## Captures the chosen hand positions for the discarding player.
    actions.add action
    true
  let before = game.stateHash
  play.startTossPicking(game)
  play.updateTossPicking(game, 2, pick = true, clear = false)
  doAssert actions.len == 0
  doAssert game.stateHash == before
  play.updateTossPicking(game, 0, pick = true, clear = false)
  doAssert game.stateHash == before
  doAssert actions.len == 1
  doAssert actions[0].kind == ActionToss
  doAssert actions[0].playerId == owner.int32
  doAssert actions[0].indices == @[2'i32, 0'i32]
  doAssert game.applyAction(actions[0])
  doAssert game.players[owner].hand.len == 1
  doAssert game.players[owner].hand[0].name == "Bolt"
  doAssert not game.waitingToss

block:
  var
    game = newGame(Archer, Warrior, 31)
    play = initTablePlay(1)
  let
    me = game.currentPlayer
    target = heroChoice(1 - me)
  game.players[me].board = @[MinionState(id: 1, owner: me,
    card: baseCardNamed("Bear"), currentToughness: 2, canAttack: true)]
  game.nextMinionId = 2
  discard game.takeVisualEvents()
  let before = game.copyGameState()
  doAssert game.attack(1, target)
  let confirmed = game.stateHash
  play.startAttack(before, flatTable(), @[1], target)
  play.attackDamageApplied = true
  play.presentVisualEvents(game, flatTable(), 0)
  doAssert play.queuedEvents.len > 0
  doAssert play.activeVfx.len == 0
  discard play.advanceAttack(game, AttackLungeDuration)
  doAssert game.stateHash == confirmed
  play.presentVisualEvents(game, flatTable(), AttackLungeDuration)
  doAssert play.queuedEvents.len == 0
  doAssert play.activeVfx.len > 0

echo "Network table inputs wait for confirmed actions."
