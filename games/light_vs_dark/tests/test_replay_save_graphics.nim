import
  std/[os, strutils, tempfiles],
  windy,
  polyworld/[replaysaves, sounds],
  ../[game, graphics, presets, replaylibraries, replays, sim]

proc testReplaySaving() =
  ## Exercises automatic recording through the native renderer and cleanup.
  const DataVariable = when defined(windows): "APPDATA" else: "XDG_DATA_HOME"
  let
    directory = createTempDir("lvd-graphics-replays-", "")
    hadData = existsEnv(DataVariable)
    previousData = getEnv(DataVariable)
    previousOptions = options
    previousRun = run
  doAssert window == nil, "This native graphics test needs its own process."
  putEnv(DataVariable, directory)
  defer:
    if window != nil:
      window.close()
      window = nil
    options = previousOptions
    run = previousRun
    if hadData:
      putEnv(DataVariable, previousData)
    else:
      delEnv(DataVariable)
    removeDir(directory)
  let library = replayDirectory()
  doAssert library.startsWith(directory)
  options.windowWidth = 640
  options.windowHeight = 480
  options.playerSlot = 1
  options.speed = 16
  options.pauseOnStart = false
  options.recordPath = ""
  options.vsync = false
  var config = defaultConfig(2)
  config.playerSlot = 1
  config.maxTicks = 6
  config.mapSettings = MapSettings(
    layout: RandomLayout, size: 48, expansions: 0, minDistance: 12
  )
  initializeLocalMatch(config, ["", ""])
  var frames = 0
  var completionSaved = false
  discard runGraphics(hidden = true, autoSaveReplay = true,
    hooks = GraphicsHooks(frame: proc(): bool =
      ## Observes a completed file before returning from the match renderer.
      inc frames
      setSoundMuted(true)
      doAssert frames < 300, "The short match did not finish."
      if run.world.tick < config.maxTicks:
        return false
      let entries = listReplays(library)
      doAssert entries.len == 1 and entries[0].playable
      doAssert loadReplay(entries[0].path).hashes.len == config.maxTicks
      completionSaved = true
      true
    )
  )
  doAssert completionSaved
  doAssert listReplays(library).len == 1,
    "Exiting a completed match must not save the same snapshot twice."
  doAssert window.onFrame == nil and window.onButtonPress == nil
  echo "LvD completed replay saves before exit without duplication."

  config.maxTicks = 300
  initializeLocalMatch(config, ["", ""])
  var exitTick = 0
  discard runGraphics(hidden = true, autoSaveReplay = true,
    hooks = GraphicsHooks(frame: proc(): bool =
      ## Stops a live match before its completion autosave can run.
      setSoundMuted(true)
      doAssert listReplays(library).len == 1
      exitTick = run.world.tick
      true
    )
  )
  doAssert exitTick < config.maxTicks
  let entries = listReplays(library)
  doAssert entries.len == 2 and entries[0].playable
  doAssert loadReplay(entries[0].path).hashes.len == exitTick
  echo "LvD leaving a partial match saves its available ticks."

  initializeLocalMatch(config, ["", ""])
  discard runGraphics(hidden = true, autoSaveReplay = false,
    hooks = GraphicsHooks(frame: proc(): bool =
      ## Leaves a match with automatic saving explicitly disabled.
      setSoundMuted(true)
      true
    )
  )
  doAssert listReplays(library).len == 2
  echo "LvD disabled automatic saving leaves the library unchanged."

  let blockedExport = directory / "blocked-export"
  writeFile(blockedExport, "Not a directory")
  options.recordPath = blockedExport / "requested.replay"
  initializeLocalMatch(config, ["", ""])
  var exportRejected = false
  try:
    discard runGraphics(hidden = true, autoSaveReplay = true,
      hooks = GraphicsHooks(frame: proc(): bool =
        ## Leaves with an unwritable CLI path and a working replay library.
        setSoundMuted(true)
        true
      )
    )
  except ReplayExportError:
    exportRejected = true
  doAssert exportRejected
  doAssert listReplays(library).len == 3,
    "A failed explicit export must not prevent the separate library save."
  doAssert window.onFrame == nil and window.onButtonPress == nil
  options.recordPath = ""
  echo "LvD saves to its library even when a requested CLI export fails."

  let blocked = directory / "blocked"
  writeFile(blocked, "Not a directory")
  putEnv(DataVariable, blocked)
  initializeLocalMatch(config, ["", ""])
  var rejected = false
  try:
    discard runGraphics(hidden = true, autoSaveReplay = true,
      hooks = GraphicsHooks(frame: proc(): bool =
        ## Leaves through the same exit path while its destination is blocked.
        setSoundMuted(true)
        true
      )
    )
  except ReplaySaveError as error:
    rejected = true
    doAssert "Cannot save replay" in error.msg
  doAssert rejected
  doAssert window.onFrame == nil and window.onButtonPress == nil
  discard recordingData()
  doAssert listReplays(library).len == 3
  echo "LvD failed saves clean callbacks and preserve the recording for retry."

testReplaySaving()
