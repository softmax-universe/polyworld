import content, sim

const ThreeMinuteNotice* = "3 minutes remain"

proc matchNoticeTick*(game: Game): uint32 =
  ## Derives the local warning tick from the game's actual completed draft.
  if game.world.phase == Drafting or game.config.maxTicks <= 180 * TickRate:
    return 0
  let opening = if game.world.drafting: PreparationTicks else: 0'i32
  let tick = int64(game.world.draftTicks) + opening +
    game.config.maxTicks - 180 * TickRate
  if tick > 0 and tick <= int64(uint32.high):
    result = uint32(tick)

proc matchNoticeDue*(game: Game): bool =
  ## Shows the warning only at its simulated tick in an unfinished match.
  let tick = game.matchNoticeTick()
  tick != 0 and not game.finished() and game.world.tick.int64 == tick.int64
