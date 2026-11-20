import
  std/[os, tempfiles],
  polyworld/replaysaves

type RecordedPrefix = object
  hashes, actions: seq[int]

proc testReplaySaves() =
  ## Checks completion, manual retry, deduplication, and removed saved files.
  let directory = createTempDir("polyworld-replay-saves-", "")
  defer: removeDir(directory)
  var
    state: ReplaySaveState
    writes = 0
    failWrite = false
    data = RecordedPrefix(hashes: @[11, 22], actions: @[1])

  proc save(data: RecordedPrefix): string =
    ## Writes a real file while allowing a failed library write to be injected.
    if failWrite:
      raise newException(IOError, "Replay destination is unavailable.")
    inc writes
    result = directory / ($writes & ".replay")
    writeFile(result, $data)

  doAssert not state.beginAutomaticReplaySave(false, true)
  doAssert not state.beginAutomaticReplaySave(true, false)
  doAssert not state.shouldSaveReplayOnExit(false)
  doAssert state.shouldSaveReplayOnExit(true)
  doAssert state.beginAutomaticReplaySave(true, true)
  let first = state.saveReplaySnapshot(data, save)
  doAssert writes == 1 and fileExists(first)
  doAssert not state.saveRequested
  doAssert not state.beginAutomaticReplaySave(true, true)
  doAssert state.saveReplaySnapshot(data, save) == first
  doAssert writes == 1, "Completion and exit must share the same saved prefix."

  data.actions.add(2)
  let withChat = state.saveReplaySnapshot(data, save)
  doAssert writes == 2 and withChat != first,
    "Chat-only additions must make a new snapshot without another game tick."
  removeFile(withChat)
  let recreated = state.saveReplaySnapshot(data, save)
  doAssert writes == 3 and fileExists(recreated),
    "A removed replay must be recreated rather than reported as saved."

  data.hashes.add(33)
  failWrite = true
  var rejected = false
  try:
    discard state.saveReplaySnapshot(data, save)
  except IOError:
    rejected = true
  doAssert rejected and state.saveRequested
  doAssert state.savedPath == recreated
  doAssert state.shouldSaveReplayOnExit(false),
    "A failed manual save must survive automatic saving being disabled."
  failWrite = false
  doAssert state.saveReplaySnapshot(data, save) != recreated
  doAssert writes == 4 and not state.saveRequested
  doAssert not state.shouldSaveReplayOnExit(false)

  state.resetReplaySave()
  doAssert state.savedPath.len == 0 and not state.saveRequested
  doAssert state.beginAutomaticReplaySave(true, true)
  discard state.saveReplaySnapshot(data, save)
  doAssert writes == 5, "A new match cannot reuse its predecessor's snapshot."
  state.resetReplaySave()
  state.requestReplaySave()
  doAssert state.shouldSaveReplayOnExit(false),
    "A failure while capturing the recording must preserve manual intent."
  let
    libraryFailure = newException(ReplaySaveError, "Library is full.")
    exportFailure = newException(ReplayExportError, "Export path is invalid.")
    matchFailure = newException(IOError, "Match was interrupted.")
  doAssert shouldRetainReplay(false, libraryFailure),
    "The frontend must retain a failed manual save with automatic saving off."
  doAssert shouldRetainReplay(true, libraryFailure)
  doAssert shouldRetainReplay(true, matchFailure)
  doAssert not shouldRetainReplay(false, matchFailure)
  doAssert not shouldRetainReplay(true, exportFailure),
    "A successful library save must not be queued again after an export fails."

proc testPendingReplaySaves() =
  ## Keeps failed and unattempted recordings after a partial retry succeeds.
  var
    pending = @[1, 2, 3]
    saved: seq[int]
    failure = 2
  proc save(data: int): string =
    ## Records successful writes and fails at a chosen retained recording.
    if data == failure:
      raise newException(IOError, "Replay destination is full.")
    saved.add(data)
    $data
  var rejected = false
  try:
    pending.retryReplaySaves(save)
  except IOError:
    rejected = true
  doAssert rejected and saved == @[1] and pending == @[2, 3]
  failure = 0
  pending.retryReplaySaves(save)
  doAssert saved == @[1, 2, 3] and pending.len == 0

testReplaySaves()
testPendingReplaySaves()
echo "Shared replay save lifecycle tests passed."
