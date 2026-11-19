## Pile tooltips follow the closest rendered surface under the pointer.
import
  std/options,
  vmath,
  ../play as tableplay, ../core/sim, ../scene/table

const PointerRay = (origin: vec3(0, 10, 0), direction: vec3(0, -1, 0))

var
  game: GameState
  play: TablePlay
  handPositions, boardPositions, deckPositions, discardPositions,
    spellPositions: array[2, Vec3]

proc handPoses(player, count: int): seq[CardPose] =
  ## Places each hand card at its fixture's projected location.
  for _ in 0 ..< count:
    result.add CardPose(position: handPositions[player])

proc boardPoses(player, count: int): seq[CardPose] =
  ## Places live and held board cards at their fixture location.
  for _ in 0 ..< count:
    result.add CardPose(position: boardPositions[player])

proc deckPose(player: int): CardPose =
  ## Places the deck independently from the other cards.
  CardPose(position: deckPositions[player])

proc discardPose(player: int): CardPose =
  ## Places the discard independently from the other cards.
  CardPose(position: discardPositions[player])

proc spellPose(player: int): CardPose =
  ## Places a spell whose effects are still resolving.
  CardPose(position: spellPositions[player])

proc handVisible(player: int): bool =
  ## The opponent's hand is rendered face down.
  player == 0

proc testLayout(): TableLayout =
  ## Supplies deterministic poses without opening a window.
  TableLayout(
    handPoses: handPoses,
    boardPoses: boardPoses,
    deckPose: deckPose,
    discardPose: discardPose,
    spellPose: spellPose,
    handVisible: handVisible
  )

proc reset(discarded: bool, count = 3) =
  ## Leaves one selected pile under the ray and everything else to its side.
  game = newGame(Archer, Warrior, 17)
  play = initTablePlay(1)
  for player in 0 ..< game.playerCount:
    game.players[player].hand.setLen(0)
    game.players[player].board.setLen(0)
    game.players[player].deck.setLen(0)
    game.players[player].discardPile.setLen(0)
    let away = vec3(20 + player.float32 * 5, 0, 0)
    handPositions[player] = away
    boardPositions[player] = away
    deckPositions[player] = away
    discardPositions[player] = away
    spellPositions[player] = away
  if discarded:
    discardPositions[0] = vec3(0, 0, 0)
    for _ in 0 ..< count:
      game.players[0].discardPile.add baseCardNamed("Bear")
  else:
    deckPositions[0] = vec3(0, 0, 0)
    for _ in 0 ..< count:
      game.players[0].deck.add baseCardNamed("Bear")

proc checkPile(discarded: bool, count = 3) =
  ## Requires the expected pile to retain its correct identity and count.
  let pile = hoveredPile(PointerRay, game, play, testLayout(), viewer = 0)
  doAssert pile.found
  doAssert pile.player == 0
  doAssert pile.discarded == discarded
  doAssert pile.count == count

proc checkCovered() =
  ## A visible foreground card must consume the pile's hover.
  doAssert not hoveredPile(
    PointerRay, game, play, testLayout(), viewer = 0
  ).found

for discarded in [false, true]:
  echo "Checking ", (if discarded: "discard" else: "deck"), " occlusion"
  reset(discarded)
  checkPile(discarded)

  game.players[0].hand = @[baseCardNamed("Bear")]
  handPositions[0] = vec3(0, 1, 0)
  checkCovered()
  handPositions[0] = vec3(0, -1, 0)
  checkPile(discarded)

  # A face-down hand still covers objects behind its card backs.
  game.players[0].hand.setLen(0)
  game.players[1].hand = @[baseCardNamed("Bear")]
  handPositions[1] = vec3(0, 1, 0)
  checkCovered()
  game.players[1].hand.setLen(0)

  # A destination card suppressed by a flight must not block empty space.
  game.players[0].hand = @[baseCardNamed("Bear")]
  handPositions[0] = vec3(0, 1, 0)
  play.animations = @[newCardAnimation(
    baseCardNamed("Bear"), Archer,
    CardPose(position: vec3(20, 1, 0)),
    CardPose(position: vec3(20, 1, 0)),
    suppressHandOwner = 0, suppressHandIndex = 0
  )]
  checkPile(discarded)
  play.animations.setLen(0)
  play.queuedEvents = @[
    VisualEvent(kind: DrawVfx, target: heroChoice(0), boardIndex: 0)
  ]
  checkPile(discarded)

  reset(discarded)
  game.players[0].board = @[
    MinionState(id: 1, owner: 0, card: baseCardNamed("Bear"))
  ]
  boardPositions[0] = vec3(0, 1, 0)
  checkCovered()
  boardPositions[0] = vec3(0, -1, 0)
  checkPile(discarded)
  boardPositions[0] = vec3(0, 1, 0)
  play.queuedEvents = @[
    VisualEvent(kind: SummonVfx, target: creatureChoice(0, 1))
  ]
  checkPile(discarded)

  reset(discarded)
  play.animations = @[newCardAnimation(
    baseCardNamed("Bear"), Archer,
    CardPose(position: vec3(0, 1, 0)),
    CardPose(position: vec3(0, 1, 0)),
    hidden = true
  )]
  checkCovered()

  reset(discarded)
  play.castSpell = some(CastSpell(
    card: baseCardNamed("Bear"), heroClass: Archer, owner: 0
  ))
  spellPositions[0] = vec3(0, 1, 0)
  checkCovered()

  reset(discarded)
  play.dyingMinions = @[DyingMinion(
    target: creatureChoice(0, 1), card: baseCardNamed("Bear"),
    heroClass: Archer, boardIndex: 0, home: 1
  )]
  boardPositions[0] = vec3(0, 1, 0)
  checkCovered()

  reset(discarded, count = 0)
  checkPile(discarded, count = 0)
  game.players[0].hand = @[baseCardNamed("Bear")]
  handPositions[0] = vec3(0, 1, 0)
  checkCovered()

echo "Checking overlapping piles use depth instead of player iteration order"
reset(false)
discardPositions[1] = vec3(0, 1, 0)
game.players[1].discardPile = @[baseCardNamed("Bear")]
block:
  let pile = hoveredPile(PointerRay, game, play, testLayout())
  doAssert pile.found and pile.player == 1 and pile.discarded
  doAssert pile.count == 1

echo "Checking a raised hovered card covers a pile beneath its visible face"
reset(false, count = 1)
game.players[0].hand = @[baseCardNamed("Bear")]
handPositions[0] = vec3(0, -0.1, 0)
checkPile(false, count = 1)
doAssert not hoveredPile(
  PointerRay, game, play, testLayout(), viewer = 0, hoverIndex = 0
).found

echo "Checking a waiting draw stays part of the deck until it takes flight"
reset(false)
play.animations = @[newDrawAnimation(
  baseCardNamed("Bear"), Archer,
  stackTopPose(deckPose(0), game.players[0].deck.len),
  CardPose(position: vec3(0, 2, 0)), 0, 0, hidden = false
)]
play.animations[0].elapsed = -0.1
checkPile(false)
play.animations[0].elapsed = DrawMoveDuration * 0.5
checkCovered()

echo "Pile hover follows visible card depth and leaves exposed piles usable."
