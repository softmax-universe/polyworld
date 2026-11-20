import
  std/[os, strutils, tempfiles],
  polyworld/tapes,
  ../[content, controls, game, replaylibraries, replays, sim]

proc testRecordingLibrary() =
  ## Saves a real sparse match and preserves its full tape after rewinding.
  let
    directory = createTempDir("gota-recording-library-", "")
    library = directory / "Replays"
    previousRun = run
    previousOptions = options
    previousConfig = matchConfig
    previousPlayerName = localPlayerName
  defer:
    clearPlayerCommands()
    run = previousRun
    options = previousOptions
    matchConfig = previousConfig
    localPlayerName = previousPlayerName
    removeDir(directory)
  var sources: array[HeroClassCount, string]
  let config = parseConfig("""{
    "maxTicks":31,"draftMode":"open","mapPreset":{"mapSize":64}
  }""")
  initializeLocalMatch(config, sources, 8)
  let heroId = run.world.heroes[0].id
  queueDraft(heroId, VanguardKnight.ord.int32)
  var checkpoint: World
  while run.world.tick < 60:
    if run.world.tick == 40:
      queueStop(heroId)
    advanceGame()
    if run.world.tick == 24:
      checkpoint = run.world.clone()
  doAssert checkpoint != nil
  doAssert not run.finished()
  let partialPath = directory / "partial.replay"
  saveRecording(partialPath)
  let partial = loadReplay(partialPath)
  doAssert partial.hashes.len == 60
  doAssert partial.metrics.frames[^1].tick == 60
  doAssert partial.header.setup.heroes.len == 1
  doAssert partial.metrics.final.len == 1,
    "Sparse matches must save telemetry for occupied heroes only."

  while not run.finished():
    if run.world.tick mod 100 == 0:
      queueStop(heroId)
    advanceGame()
    doAssert run.world.tick < 1200,
      "The short match must finish without waiting for empty seats."
  let
    completed = recordingData()
    liveHash = run.stateHash()
    path = saveLibraryReplay(completed, library)
    loaded = loadReplay(path)
  doAssert completed.hashes.len == run.world.tick
  doAssert completed.actions[^1].tick > checkpoint.tick.uint32
  doAssert loaded.actions == completed.actions
  doAssert loaded.hashes == completed.hashes
  doAssert loaded.metrics == completed.metrics
  doAssert loaded.metrics.frames[^1].tick == run.world.tick
  let entries = listReplays(library)
  doAssert entries.len == 1
  doAssert entries[0].path == path
  doAssert entries[0].playable and entries[0].problem.len == 0
  doAssert entries[0].ticks == completed.hashes.len

  let replay = newGame(
    run.map, loaded.config.spawnIntervalTicks, 0, true, loaded
  )
  replay.historyPlayback = true
  replay.replayPlayer = initReplayPlayer(loaded)
  for tick in 0 ..< loaded.hashes.len:
    replay.tickWorld(nil)
  doAssert replay.hashCheck.mismatches == 0
  doAssert replay.replayPlayer.finished
  doAssert replay.stateHash() == liveHash

  run.world.restore(checkpoint)
  run.historyPlayback = true
  let rewound = recordingData()
  doAssert rewound.hashes == completed.hashes,
    "Saving while rewound must retain the complete recorded duration."
  doAssert rewound.actions == completed.actions,
    "Saving while rewound must retain actions after the current playhead."
  doAssert rewound.metrics == completed.metrics,
    "Saving while rewound must retain original late-match telemetry."
  let rewoundPath = saveLibraryReplay(rewound, library)
  doAssert loadReplay(rewoundPath).hashes == completed.hashes
  doAssert listReplays(library).len == 2

  run.recordingError = "Interrupted recording for the integration test"
  var rejected = false
  try:
    discard saveLibraryReplay(recordingData(), library)
  except ReplayError as error:
    rejected = true
    doAssert "Interrupted recording" in error.msg
  doAssert rejected, "An interrupted recorder must not create a replay file."
  doAssert listReplays(library).len == 2
  doAssert loadReplay(path).hashes == completed.hashes
  run.recordingError = ""
  run.recorder = nil
  rejected = false
  try:
    discard recordingData()
  except ReplayError:
    rejected = true
  doAssert rejected, "A missing recorder must be reported before saving."

testRecordingLibrary()
echo "Match recording, library playback, rewind retention, and errors passed."
