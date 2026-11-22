## Sound cues follow visible beats and confirmed actions without a device.
import
  vmath,
  polyworld/soundassets,
  ../[audios, play], ../core/[replays, sim], ../scene/table

proc poses(player, count: int): seq[CardPose] =
  ## Supplies a harmless pose for every presented card.
  for _ in 0 ..< count:
    result.add CardPose()

proc origin(player: int): CardPose =
  ## Places the piles at the table origin.
  CardPose()

proc feet(player: int): Vec3 =
  ## Places each hero at the table origin.
  vec3(0, 0, 0)

proc shown(player: int): bool =
  ## Makes card faces visible without creating a window.
  true

proc flatTable(): TableLayout =
  ## Supplies all callbacks used by the presentation paths under test.
  TableLayout(handPoses: poses, boardPoses: poses, deckPose: origin,
    discardPose: origin, spellPose: origin, heroPosition: feet,
    handVisible: shown)

proc fixture(): GameState =
  ## Starts a quiet match with one ordinary card ready for either input path.
  result = newGame(Archer, Warrior, 42)
  discard result.takeVisualEvents()
  result.players[result.currentPlayer].hand = @[baseCardNamed("Bear")]
  result.players[result.currentPlayer].energy = 20

proc addBeat(game: var GameState, kind: VfxKind, beat: int) =
  ## Queues a presentation event with the same monotonically increasing beat.
  game.visualBeat = beat
  game.visualEvents.add VisualEvent(kind: kind,
    target: heroChoice(game.currentPlayer), beat: beat)

block soundsStartWithTheirBeat:
  var
    game = fixture()
    play = initTablePlay(1)
  play.audio.syncAudio(game)
  play.animations.add CardAnimation()
  game.addBeat(LightningVfx, 3)
  let before = game.stateHash()
  play.presentVisualEvents(game, flatTable(), 0)
  doAssert game.visualEvents.len == 0
  doAssert play.queuedEvents.len == 1
  doAssert play.audio.takeSounds().len == 0,
    "Taking an event into the queue must not sound before its visual beat"
  play.animations.setLen(0)
  play.presentVisualEvents(game, flatTable(), 1)
  doAssert play.queuedEvents.len == 0
  doAssert play.audio.takeSounds() == @[MagicSound]
  play.presentVisualEvents(game, flatTable(), 2)
  doAssert play.audio.takeSounds().len == 0
  doAssert game.stateHash() == before

block silenceSurvivesMenuResume:
  var
    game = fixture()
    play = initTablePlay(2)
  game.addBeat(ArrowVfx, 7)
  play.animations.add CardAnimation()
  play.presentVisualEvents(game, flatTable(), 0)
  doAssert play.queuedEvents.len == 1
  play.setAudioEnabled(game, false)
  play.setAudioEnabled(game, true)
  play.animations.setLen(0)
  play.presentVisualEvents(game, flatTable(), 1)
  doAssert play.queuedEvents.len == 0
  doAssert play.audio.takeSounds().len == 0,
    "A beat hidden by the menu must stay silent after the menu closes"
  play.activeVfx.setLen(0)
  game.addBeat(ArrowVfx, 8)
  play.presentVisualEvents(game, flatTable(), 2)
  doAssert play.audio.takeSounds() == @[BowSound],
    "Fresh action beats must become audible again"

block recoveryHistoryStaysSilent:
  var
    game = fixture()
    play = initTablePlay(3)
  game.addBeat(ExplosionVfx, 12)
  let before = game.stateHash()
  play.silenceAudioThrough(game)
  play.presentVisualEvents(game, flatTable(), 0)
  doAssert play.activeVfx.len == 1,
    "Recovery can retain visual presentation while silencing old effects"
  doAssert play.audio.takeSounds().len == 0
  doAssert game.stateHash() == before
  play.activeVfx.setLen(0)
  game.addBeat(ExplosionVfx, 13)
  play.presentVisualEvents(game, flatTable(), 1)
  doAssert play.audio.takeSounds() == @[FireSound]

block hiddenNewEventsStaySilent:
  var
    game = fixture()
    play = initTablePlay(4)
  play.setAudioEnabled(game, false)
  play.animations.add CardAnimation()
  game.addBeat(SwordClashVfx, 15)
  play.presentVisualEvents(game, flatTable(), 0)
  doAssert play.audio.takeSounds().len == 0
  play.setAudioEnabled(game, true)
  play.animations.setLen(0)
  play.presentVisualEvents(game, flatTable(), 1)
  doAssert play.audio.takeSounds().len == 0,
    "Events arriving during silence must not be replayed on resume"

block resetStartsFreshAudioHistory:
  var
    game = fixture()
    play = initTablePlay(5)
  game.addBeat(LightningVfx, 100)
  play.silenceAudioThrough(game)
  play.resetTable()
  game = fixture()
  game.addBeat(LightningVfx, 0)
  play.presentVisualEvents(game, flatTable(), 0)
  doAssert play.audio.takeSounds() == @[MagicSound],
    "A rematch must clear the preceding match's silent beat watermark"
  play.setAudioEnabled(game, false)
  play.resetTable()
  doAssert play.audio.silent,
    "Resetting the presentation must preserve current focus/menu silence"

block localPlaySoundsOnce:
  var
    game = fixture()
    play = initTablePlay(6)
  play.audio.syncAudio(game)
  doAssert play.playHandCard(game, flatTable(), 0)
  doAssert play.audio.takeSounds() == @[CardPlaySound]
  let after = game.stateHash()
  play.animations.setLen(0)
  play.presentVisualEvents(game, flatTable(), 1)
  doAssert CardPlaySound notin play.audio.takeSounds(),
    "Presenting the played card again must not duplicate its movement cue"
  doAssert game.stateHash() == after

block networkIntentWaitsForConfirmation:
  var
    game = fixture()
    play = initTablePlay(7)
    actions: seq[ReplayAction]
  play.audio.syncAudio(game)
  play.submitAction = proc(action: ReplayAction): bool =
    ## Captures an intent without applying it to the confirmed game.
    actions.add action
    true
  let beforeHash = game.stateHash()
  doAssert play.playHandCard(game, flatTable(), 0)
  doAssert actions.len == 1
  doAssert play.animations.len == 0
  doAssert CardPlaySound notin play.audio.takeSounds(),
    "An unconfirmed intent must not sound like a completed card play"
  doAssert game.stateHash() == beforeHash
  let before = game.copyGameState()
  doAssert game.applyAction(actions[0])
  let confirmedHash = game.stateHash()
  play.animateTransition(flatTable(), before, game,
    actions[0].choices.toChoices(), actions[0].handIndex.int)
  doAssert play.audio.takeSounds() == @[CardPlaySound]
  play.animations.setLen(0)
  play.presentVisualEvents(game, flatTable(), 1)
  doAssert CardPlaySound notin play.audio.takeSounds()
  doAssert game.stateHash() == confirmedHash
  doAssert before.stateHash() == beforeHash
  play.submitAction = nil

echo "Table audio presentation: beats, recovery, rematches and actions passed."
