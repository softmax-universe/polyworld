import
  std/[os, tempfiles],
  ../[game, replays, sim]

echo "Testing explicit negative Crewrift seeds remain deterministic"
block:
  let directory = createTempDir("crewrift-negative-seeds-", "")
  defer: removeDir(directory)
  for seed in [-1, -17, int32.low.int]:
    let
      options = parseOptions(@["--seed", $seed])
      first = newGame(options)
      second = newGame(options)
    doAssert first.world.config.seed == seed
    doAssert first.recording.config.seed == seed
    doAssert first.world.gameHash() == second.world.gameHash()
    for tick in 0 ..< 16:
      first.advance(record = true)
      second.advance(record = true)
    doAssert first.recording.frames == second.recording.frames
    doAssert first.world.rng == second.world.rng
    let
      expected = first.world.gameHash()
      path = directory / ($seed & ".json")
    saveReplay(path, first.recording)
    first.rewind()
    doAssert first.world.config.seed == seed
    for tick in 0 ..< 16:
      first.advance(record = true)
    doAssert first.world.gameHash() == expected
    let playback = newGame(parseOptions(@["--replay", path]))
    doAssert playback.world.config.seed == seed
    for tick in 0 ..< 16:
      playback.advance()
    doAssert playback.world.gameHash() == expected

echo "Testing implicit random seed resolution remains recorded"
block:
  var options = parseOptions(@[])
  options.seed = RandomSeedSentinel
  let game = newGame(options)
  doAssert game.world.config.seed >= 0
  doAssert game.recording.config.seed == game.world.config.seed
  let expected = game.world.gameHash()
  game.rewind()
  doAssert game.world.gameHash() == expected
  var config = defaultGameConfig()
  doAssert config.seed == RandomSeedSentinel
  config.resolveRandomSeed()
  doAssert config.seed >= 0

echo "Crewrift seed checks passed"
