import
  std/[os, strutils, tempfiles],
  polyworld/tapes,
  ../[bots, content, controls, game, multiplayer, presets, replaylibraries,
    replays, sim]

proc testRecordingLibrary() =
  ## Saves a real match and retains its complete actions and metrics on rewind.
  let
    directory = createTempDir("lvd-recording-library-", "")
    library = directory / "Replays"
    previousRun = run
  defer:
    clearPlayerCommands()
    run = previousRun
    removeDir(directory)
  var config = defaultConfig(2)
  config.maxTicks = 60
  config.mapSettings = MapSettings(
    layout: RandomLayout, size: 90, expansions: 0
  )
  run = newLocalMatch(config, ["", ""])
  let
    live = run
    worker = run.world.units[0]
    opening = run.world.clone()
  doAssert run.sendChat(0, -2, "Opening message") > 0
  queueMove(worker.owner, worker.id, worker.tile.x.int32 + 2,
    worker.tile.y.int32)
  while run.world.tick < 20:
    advanceGame()
  let partialPath = directory / "partial.replay"
  saveRecording(partialPath)
  let partial = loadReplay(partialPath)
  doAssert partial.hashes.len == 20
  doAssert partial.metrics.frames[^1].tick == 20
  doAssert partial.actions.len >= 2

  while run.world.tick < config.maxTicks and not run.world.over:
    if run.world.tick == 30:
      doAssert run.sendChat(1, -2, "Later message") > 0
      queueCancel(worker.owner, worker.id)
    advanceGame()
  doAssert run.world.tick == config.maxTicks
  let
    completed = recordingData()
    liveHash = run.stateHash()
    path = saveLibraryReplay(completed, library)
    loaded = loadReplay(path)
  doAssert completed.hashes.len == config.maxTicks
  doAssert completed.actions[^1].tick > 20
  doAssert loaded.actions == completed.actions
  doAssert loaded.hashes == completed.hashes
  doAssert loaded.metrics == completed.metrics
  doAssert loaded.metrics.frames[^1].tick == config.maxTicks
  let entries = listReplays(library)
  doAssert entries.len == 1
  doAssert entries[0].path == path and entries[0].playable
  doAssert entries[0].ticks == completed.hashes.len

  let playback = newGame(
    live.world.map, config.maxTicks, loaded.header.setup.diplomacySettings
  )
  playback.replayMode = true
  playback.historyPlayback = true
  playback.replayData = loaded
  playback.replayPlayer = initReplayPlayer(loaded)
  run = playback
  for tick in 1 .. loaded.hashes.len:
    advanceGame()
  doAssert playback.hashCheck.mismatches == 0
  doAssert playback.replayPlayer.finished
  doAssert playback.stateHash() == liveHash
  var rejected = false
  try:
    discard recordingData()
  except ReplayError:
    rejected = true
  doAssert rejected, "Watching a replay must not create a new recording."

  run = live
  run.world.restore(opening)
  run.historyPlayback = true
  let rewound = recordingData()
  doAssert rewound.hashes == completed.hashes
  doAssert rewound.actions == completed.actions
  doAssert rewound.metrics == completed.metrics,
    "Saving while rewound must keep original late-match telemetry."
  let rewoundPath = saveLibraryReplay(rewound, library)
  doAssert loadReplay(rewoundPath).hashes == completed.hashes
  doAssert listReplays(library).len == 2

  run.world.tick = config.maxTicks + 1
  rejected = false
  try:
    discard saveLibraryReplay(recordingData(), library)
  except ReplayError as error:
    rejected = true
    doAssert "missing the latest simulation tick" in error.msg
  doAssert rejected
  doAssert listReplays(library).len == 2
  run.recorder = nil
  rejected = false
  try:
    discard recordingData()
  except ReplayError:
    rejected = true
  doAssert rejected, "A missing recorder must be reported before saving."
  run = nil
  rejected = false
  try:
    discard recordingData()
  except ReplayError:
    rejected = true
  doAssert rejected, "An absent match must be reported before saving."

testRecordingLibrary()
echo "LvD match recording, library playback, rewind retention, and errors passed."
