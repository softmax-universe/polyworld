import ../[content, matchnotices, sim]

proc fixture(limit = 182 * TickRate): Game =
  ## Creates only the state read by the local presentation clock.
  result = Game(world: World(phase: Playing))
  result.replayData.config.maxTicks = limit

echo "Testing local notice threshold excludes draft and preparation"
let game = fixture()
game.world.tick = 2 * TickRate - 1
doAssert not game.matchNoticeDue()
inc game.world.tick
doAssert game.matchNoticeDue()
inc game.world.tick
doAssert not game.matchNoticeDue()
game.world.drafting = true
game.world.draftTicks = 17
game.world.phase = Drafting
doAssert game.matchNoticeTick() == 0
game.world.phase = Playing
game.world.preparationTicks = PreparationTicks
let due = 17 + PreparationTicks + 2 * TickRate
doAssert game.matchNoticeTick() == due.uint32
game.world.tick = due
doAssert game.matchNoticeDue()
game.world.gameOver = true
doAssert not game.matchNoticeDue(), "Finished matches do not announce time left"

echo "Testing short matches and truncated replays"
for limit in [1'i32, 180 * TickRate]:
  let shortMatch = fixture(limit)
  shortMatch.world.tick = 1
  doAssert shortMatch.matchNoticeTick() == 0
  doAssert not shortMatch.matchNoticeDue()
let replay = fixture()
replay.replayMode = true
replay.replayData.hashes = @[0'u64]
replay.world.tick = 2 * TickRate
doAssert replay.matchNoticeDue(), "Replay length must not redefine match time"
echo "PASS local warning uses game timing without a room or server event"
