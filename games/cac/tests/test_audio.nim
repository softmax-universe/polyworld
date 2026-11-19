## Semantic sound checks without opening a window or an audio device.
import
  polyworld/soundassets,
  ../audios, ../core/[replays, sim]

proc fixture(): GameState =
  ## Starts a deterministic match whose state can be checked after observation.
  newGame(Archer, Warrior, 42)

block boundedQueue:
  var audio: TableAudio
  for _ in 0 ..< 100:
    audio.queueSound(BowSound)
  audio.queueSound(MagicSound)
  doAssert audio.takeSounds() == @[BowSound, MagicSound]
  doAssert audio.takeSounds().len == 0
  for cue in SoundCue:
    audio.queueSound(cue)
  let cues = audio.takeSounds()
  doAssert cues.len == MaxTableSounds
  doAssert VictorySound in cues and DefeatSound in cues
  for first in 0 ..< cues.len:
    for second in first + 1 ..< cues.len:
      doAssert cues[first] != cues[second]
  doAssert audio.takeSounds().len == 0

block visualBeats:
  var audio: TableAudio
  for kind in [ArrowVfx, ManyArrowsVfx, ArrowVfx]:
    audio.queueVisualSound(kind)
  audio.queueVisualSound(NoVfx)
  doAssert audio.takeSounds() == @[BowSound]
  for kind in [DrawVfx, TossVfx, BounceVfx]:
    audio.queueVisualSound(kind)
  doAssert audio.takeSounds() == @[CardDrawSound]
  for kind in [SummonVfx, LightningVfx, ExplosionVfx, StabVfx,
      SwordClashVfx, MightyShieldsVfx, DeathVfx, HeroDeathVfx]:
    audio.queueVisualSound(kind)
  doAssert audio.takeSounds() == @[
    CardPlaySound, MagicSound, FireSound, SwordSound, ImpactSound,
    HealSound, CreatureDeathSound, HumanDeathSound]

block settledTurns:
  var
    audio: TableAudio
    game = fixture()
  let viewer = game.currentPlayer
  audio.updateAudio(game, viewer, settled = true)
  doAssert audio.takeSounds().len == 0
  inc game.turnNumber
  game.currentPlayer = 1 - viewer
  audio.updateAudio(game, viewer, settled = true)
  doAssert audio.takeSounds().len == 0
  inc game.turnNumber
  game.currentPlayer = viewer
  audio.updateAudio(game, viewer, settled = false)
  doAssert audio.takeSounds().len == 0
  audio.updateAudio(game, viewer, settled = true)
  doAssert audio.takeSounds() == @[ReadySound]
  for _ in 0 ..< 10:
    audio.updateAudio(game, viewer, settled = true)
  doAssert audio.takeSounds().len == 0

block results:
  for viewer in [-1, 0, 1, 4]:
    var
      audio: TableAudio
      game = fixture()
    audio.syncAudio(game)
    game.gameOver = true
    game.winner = 0
    let before = game.stateHash()
    audio.updateAudio(game, viewer, settled = false)
    doAssert audio.takeSounds().len == 0
    audio.updateAudio(game, viewer, settled = true)
    let expected =
      if viewer notin 0 ..< game.playerCount: ReadySound
      elif viewer == game.winner: VictorySound
      else: DefeatSound
    doAssert audio.takeSounds() == @[expected]
    for _ in 0 ..< 10:
      audio.updateAudio(game, viewer, settled = true)
    doAssert audio.takeSounds().len == 0
    doAssert game.stateHash() == before

block silentHistory:
  var
    audio: TableAudio
    game = fixture()
  audio.syncAudio(game)
  audio.queueSound(SwordSound)
  audio.silent = true
  audio.queueVisualSound(ExplosionVfx)
  doAssert audio.takeSounds().len == 0
  inc game.turnNumber
  game.gameOver = true
  game.winner = 0
  audio.updateAudio(game, 0, settled = false)
  audio.silent = false
  audio.updateAudio(game, 0, settled = true)
  doAssert audio.takeSounds().len == 0
  audio.queueVisualSound(DrawVfx)
  audio.syncAudio(game)
  doAssert audio.takeSounds().len == 0

block loadedResultAndRematch:
  var
    audio: TableAudio
    game = fixture()
  game.gameOver = true
  game.winner = 0
  audio.updateAudio(game, 0, settled = true)
  doAssert audio.takeSounds().len == 0
  audio = TableAudio()
  game = fixture()
  audio.updateAudio(game, 0, settled = true)
  game.gameOver = true
  game.winner = 0
  audio.updateAudio(game, 0, settled = true)
  doAssert audio.takeSounds() == @[VictorySound]
  audio.updateAudio(game, 0, settled = true)
  doAssert audio.takeSounds().len == 0

block drawAndSeek:
  var
    audio: TableAudio
    game = fixture()
  audio.syncAudio(game)
  game.gameOver = true
  game.winner = -1
  audio.updateAudio(game, 0, settled = true)
  doAssert audio.takeSounds() == @[ReadySound]
  game.gameOver = false
  game.turnNumber = 0
  audio.queueSound(FireSound)
  audio.updateAudio(game, 0, settled = true)
  doAssert audio.takeSounds().len == 0

echo "Card table audio: cues, turns, results, silence and rematches passed."
