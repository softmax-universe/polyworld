import ../[content, matchtiming, sim]

proc fixture(limit: int32): Game =
  result = Game(world: World(phase: Playing))
  result.replayData.config.maxTicks = limit

block configuredCutoff:
  let game = fixture(367 * TickRate)
  doAssert game.remainingMatchText() == "6:07"
  game.world.tick = 7 * TickRate + 1
  doAssert game.remainingMatchText() == "6:00", "Round partial seconds up"
  game.world.tick = 367 * TickRate
  doAssert game.remainingMatchText() == "0:00"
  game.world.tick += TickRate
  doAssert game.remainingMatchText() == "0:00"
  game.world.tick = 0
  game.world.gameOver = true
  doAssert game.remainingMatchText() == "0:00"
echo "PASS configured cutoff, minute formatting, partial seconds and game-over clamp"

block preparationAndReplayCutoff:
  let game = fixture(367 * TickRate)
  game.world.drafting = true
  doAssert game.remainingMatchText() == "6:37"
  game.world.tick = 17 * TickRate
  game.world.preparationTicks = 17 * TickRate
  doAssert game.remainingMatchText() == "6:20"
  game.world.tick = PreparationTicks
  game.world.preparationTicks = PreparationTicks
  doAssert game.remainingMatchText() == "6:07"
  game.replayMode = true
  doAssert game.remainingMatchText() == "6:07", "Short recording is not the configured cutoff"

echo "PASS prep/replay cutoff semantics (server notice coverage: test_server_notice_relay)"
