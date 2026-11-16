## Game-owned tick timing; never extrapolates with a client wall clock.
import std/strutils
import content, sim

# System notices are emitted only by relaynotice and consumed from TickPacket.

proc remainingMatchTicks*(game: Game): int32 =
  ## durationTicks includes draft deadlines and the full preparation budget.
  ## Do not use replay hash length: a recording may stop before the cutoff.
  if game.world.gameOver: return 0
  var cutoff = game.config.maxTicks + game.world.draftTicks
  if game.world.drafting: cutoff += PreparationTicks
  if game.world.phase == Drafting:
    cutoff += (game.world.draftOrder.len - game.world.draftTurn).int32 *
      DraftPickTicks - game.world.draftTurnTicks
  max(cutoff - game.world.tick, 0)

proc remainingMatchText*(game: Game): string =
  let seconds = (game.remainingMatchTicks().int64 + TickRate - 1) div TickRate
  $(seconds div 60) & ":" & align($(seconds mod 60), 2, '0')
