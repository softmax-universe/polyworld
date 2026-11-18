## Bounded presentation cues for the card table, independent of audio devices.
import
  polyworld/soundassets,
  core/sim

const MaxTableSounds* = 8

type TableAudio* = object
  silent*: bool
  ready: bool
  turn: int
  gameOver: bool
  pending: array[MaxTableSounds, SoundCue]
  count: int

proc noticePriority(cue: SoundCue): int =
  ## Preserves result and turn notices when effects fill the pending buffer.
  case cue
  of VictorySound, DefeatSound: 2
  of ReadySound: 1
  else: 0

proc queueSound*(audio: var TableAudio, cue: SoundCue) =
  ## Coalesces repeated effects until the next drain, within a fixed budget.
  if audio.silent:
    return
  for index in 0 ..< audio.count:
    if audio.pending[index] == cue:
      return
  if audio.count < audio.pending.len:
    audio.pending[audio.count] = cue
    inc audio.count
  elif cue.noticePriority > 0:
    var replace = audio.count - 1
    for index in countdown(audio.count - 1, 0):
      if audio.pending[index].noticePriority <
          audio.pending[replace].noticePriority:
        replace = index
    if audio.pending[replace].noticePriority < cue.noticePriority:
      audio.pending[replace] = cue

proc queueVisualSound*(audio: var TableAudio, kind: VfxKind) =
  ## Matches a displayed visual beat to the shared fantasy sound palette.
  case kind
  of NoVfx:
    discard
  of DrawVfx, TossVfx, BounceVfx:
    audio.queueSound(CardDrawSound)
  of SummonVfx:
    audio.queueSound(CardPlaySound)
  of ArrowVfx, ManyArrowsVfx:
    audio.queueSound(BowSound)
  of LightningVfx, BubbleVfx, GainControlVfx:
    audio.queueSound(MagicSound)
  of ExplosionVfx:
    audio.queueSound(FireSound)
  of SwordsIntoTheWindVfx, MeleeVfx, StabVfx:
    audio.queueSound(SwordSound)
  of DamageFlashVfx, SwordClashVfx, SwordBreakVfx, OozeSplatVfx:
    audio.queueSound(ImpactSound)
  of MightyShieldsVfx, SwordAndShieldVfx, LevelUpVfx, PrizeVfx:
    audio.queueSound(HealSound)
  of DeathVfx:
    audio.queueSound(CreatureDeathSound)
  of HeroDeathVfx:
    audio.queueSound(HumanDeathSound)

proc takeSounds*(audio: var TableAudio): seq[SoundCue] =
  ## Drains each pending cue once, discarding any effects silenced meanwhile.
  if not audio.silent:
    for index in 0 ..< audio.count:
      result.add audio.pending[index]
  audio.count = 0

proc syncAudio*(audio: var TableAudio, game: GameState) =
  ## Establishes a silent baseline after loading, seeking or skipping history.
  audio.ready = true
  audio.turn = game.turnNumber
  audio.gameOver = game.gameOver
  audio.count = 0

proc updateAudio*(
    audio: var TableAudio,
    game: GameState,
    viewer: int,
    settled: bool
) =
  ## Announces fresh settled turns and results from the actual player's seat.
  if not audio.ready or audio.silent or game.turnNumber < audio.turn or
      (audio.gameOver and not game.gameOver):
    audio.syncAudio(game)
    return
  if not settled:
    return
  if game.gameOver and not audio.gameOver:
    let cue =
      if viewer notin 0 ..< game.playerCount or game.winner < 0:
        ReadySound
      elif game.winner == viewer:
        VictorySound
      else:
        DefeatSound
    audio.queueSound(cue)
  elif not game.gameOver and game.turnNumber != audio.turn and
      game.currentPlayer == viewer:
    audio.queueSound(ReadySound)
  audio.turn = game.turnNumber
  audio.gameOver = game.gameOver
