import
  std/sequtils,
  bassy,
  polyworld/tapes,
  ../[bots, content, maps, replays, sim]

let game = newGame(generateMap(DefaultSeed), 1)
game.loadBots(repeat("""
  decisions = decisions + 1
  accepted = gather(0)
  noticed = orderFailed()
""", VillagerCount))
game.world.villagers[0].orderFailed = true
game.historyPlayback = true
game.warmingPolicies = true
let originalHash = game.stateHash()
game.runBotDecisions()
doAssert game.stateHash() == originalHash
doAssert not game.world.villagers[0].orderFailed
for brain in game.brains:
  doAssert not brain.failed
  doAssert brain.runtime.getGlobal("decisions") == 1
  doAssert brain.runtime.getGlobal("accepted") == 0

game.historyPlayback = false
game.warmingPolicies = false
game.runBotDecisions()
doAssert game.brains[0].runtime.getGlobal("decisions") == 2
doAssert not game.world.villagers[0].orderFailed
doAssert game.stateHash() != originalHash
echo "Heartleaf replay warm-up preserves world and policy memory"

let
  live = newGame(generateMap(DefaultSeed), 1)
  warm = newGame(generateMap(DefaultSeed), 1)
  source = "accepted = gather(0)\nstopped = cancel()\nagain = gather(0)"
live.world.tick = DecisionTicks
warm.world.tick = DecisionTicks
live.recorder = ReplayRecorder()
live.loadBots(repeat(source, VillagerCount))
live.runBotDecisions()
warm.replayPlayer = ReplayPlayer(data: live.recorder.data)
warm.historyPlayback = true
let viewerHash = warm.stateHash()
doAssert not warm.applyGather(1, 0)
doAssert warm.replayPlayer.actionIndex == 0
doAssert warm.stateHash() == viewerHash
warm.warmingPolicies = true
var sources = repeat(source, VillagerCount)
sources[1] = "accepted = gather(1)"
warm.loadBots(sources)
warm.runBotDecisions()
doAssert warm.stateHash() == live.stateHash()
doAssert warm.replayPlayer.actionIndex == live.recorder.data.actions.len
for slot, brain in warm.brains:
  doAssert not brain.failed
  if slot == 1:
    doAssert brain.runtime.getGlobal("accepted") == 0
  else:
    doAssert brain.runtime.getGlobal("accepted") == 1
    doAssert brain.runtime.getGlobal("stopped") == 1
    doAssert brain.runtime.getGlobal("again") == 1
echo "Heartleaf warm-up preserves command results and flushes replaced actions"

echo "Testing duration changes preserve the prefix and extend a timed ending"
block:
  let
    map = generateMap(DefaultSeed)
    original = newGame(map, 1)
    recorder = initReplayRecorder(Setup(
      mapSeed: DefaultSeed,
      tickRate: uint16(TickRate),
      gridTiles: uint16(GridSide),
      decisionTicks: uint16(DecisionTicks),
      dayCount: 1,
      maximumTicks: uint32(gameLengthTicks(1)),
      mapHash: map.hash,
      contentHash: contentHash()
    ))
  for tick in 1 .. gameLengthTicks(1):
    original.world.tickWorld(nil)
    recorder.recordHash(original.stateHash())
  doAssert original.world.over
  let tape = decodeReplay(encodeReplay(recorder.data))
  for cutoff in [0'i32, DayTicks + 10, gameLengthTicks(1)]:
    let resumed = newGame(map, 1)
    resumed.historyPlayback = true
    resumed.replayPlayer = initReplayPlayer(tape)
    for tick in 1 .. cutoff:
      resumed.world.tickWorld(nil)
      doAssert resumed.stateHash() == tape.hashes[tick - 1]
    resumed.recorder = ReplayRecorder(data: replayPrefix(tape, uint32(cutoff)))
    resumed.recorder.recordAction(
      uint32(cutoff + 1), 0, ActionDuration, gameLengthTicks(2))
    resumed.recorder.data.config.maxTicks = gameLengthTicks(2)
    resumed.recorder.data.config.dayCount = 2
    resumed.historyPlayback = false
    if cutoff > 0:
      doAssert resumed.stateHash() == tape.hashes[cutoff - 1]
    if cutoff == gameLengthTicks(1):
      doAssert resumed.world.over
      doAssert not resumed.replayEnded()
    for tick in cutoff + 1 .. gameLengthTicks(2):
      resumed.applyReplayDuration()
      resumed.world.tickWorld(nil)
      doAssert resumed.world.tick == tick
      resumed.recorder.recordHash(resumed.stateHash())
    doAssert resumed.world.over and resumed.world.dayCount == 2
    let branch = decodeReplay(encodeReplay(resumed.recorder.data))
    doAssert branch.hashes[0 ..< cutoff] == tape.hashes[0 ..< cutoff]
    doAssert branch.header.setup == tape.header.setup
    doAssert branch.durationAt(uint32(cutoff)) == gameLengthTicks(1)
    doAssert branch.durationAt(uint32(cutoff + 1)) == gameLengthTicks(2)
    var prefix = replayPrefix(branch, uint32(cutoff))
    prefix.config.maxTicks = prefix.durationAt(uint32(cutoff))
    prefix.config.dayCount = durationDays(prefix.config.maxTicks)
    prefix.validate()
    let playback = newGame(map, 1)
    playback.historyPlayback = true
    playback.replayPlayer = initReplayPlayer(branch)
    for tick in 1 .. gameLengthTicks(2):
      playback.applyReplayDuration()
      playback.world.tickWorld(nil)
      doAssert playback.stateHash() == branch.hashes[tick - 1]
    doAssert playback.replayEnded()
    doAssert playback.replayPlayer.finished
echo "Heartleaf duration controls preserve every replay hash"
