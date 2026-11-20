import
  std/[os, strutils, tempfiles],
  ../app, ../core/[replays, sim], ../modes/multiplayer, ../replaylibraries

proc verify(data: ReplayData) =
  ## Replays every saved action and requires its canonical fingerprint.
  data.validate()
  var
    game = newGame(data.header.setup)
    cursor = initReplayCursor(data)
    tick = 0'u32
  data.applyReplayMailboxes(cursor, tick)
  while tick < data.hashes.len.uint32:
    var action: ReplayAction
    doAssert data.takeReplayAction(cursor, tick, action)
    doAssert game.applyAction(action)
    tick = action.tick
    doAssert game.stateHash() == data.hashes[tick.int - 1]
    data.applyReplayMailboxes(cursor, tick)

proc testLibraryRecording() =
  ## Checks real saves, deduplication, opt-out, and failed-save recovery.
  const DataVariable = when defined(windows): "APPDATA" else: "XDG_DATA_HOME"
  let
    directory = createTempDir("cac-recording-library-", "")
    hadData = existsEnv(DataVariable)
    previousData = getEnv(DataVariable)
  putEnv(DataVariable, directory)
  defer:
    if hadData:
      putEnv(DataVariable, previousData)
    else:
      delEnv(DataVariable)
    removeDir(directory)
  let
    library = replayDirectory()
    app = App(replayPreferences: ReplayPreferences(saveReplay: true),
      playerNames: @["Alice", "Bob"])
    seats = @[precon(Archer), precon(Mage)]
    recorder = app.beginReplayRecording(seats, 2026)
  doAssert library.startsWith(directory)
  doAssert recorder != nil
  doAssert recorder.data.config.players[0].name == "Alice"
  var game = newGame(seats, 2026)
  for tick in 1'u32 .. 3'u32:
    let action = ReplayAction(kind: ActionEndTurn, tick: tick,
      playerId: game.currentPlayer.int32)
    doAssert game.applyAction(action)
    recorder.record(action)
    recorder.recordHash(game.stateHash())
  app.updateReplaySaving(completed = true)
  doAssert app.replaySaveError.len == 0
  let entries = listReplays()
  doAssert entries.len == 1 and entries[0].playable
  let completed = loadReplay(entries[0].path)
  completed.verify()
  doAssert completed.hashes.len == 3
  app.finishReplayRecording()
  doAssert listReplays().len == 1,
    "Completion and exit must not duplicate the same recording."
  discard app.saveCurrentReplay()
  doAssert listReplays().len == 1

  discard app.beginReplayRecording(seats, 77)
  app.finishReplayRecording()
  doAssert listReplays().len == 2,
    "Leaving a live match must save its completed action prefix."

  app.replayPreferences.saveReplay = false
  discard app.beginReplayRecording(seats, 78)
  app.updateReplaySaving(completed = true)
  app.finishReplayRecording()
  doAssert listReplays().len == 2
  discard app.saveCurrentReplay()
  doAssert listReplays().len == 3,
    "Manual saves remain available when automatic saving is disabled."

  let blocked = directory / "blocked"
  writeFile(blocked, "Not a directory")
  putEnv(DataVariable, blocked)
  app.replayPreferences.saveReplay = true
  discard app.beginReplayRecording(seats, 79)
  app.finishReplayRecording()
  doAssert app.replaySaveError.len > 0
  doAssert app.unsavedReplays.len == 1
  app.unsavedReplays[0].verify()
  app.retryPendingReplays()
  doAssert app.unsavedReplays.len == 1,
    "A failed retry must keep its original recording."
  putEnv(DataVariable, directory)
  app.retryPendingReplays()
  doAssert app.unsavedReplays.len == 0
  doAssert app.replaySaveError.len == 0
  doAssert listReplays().len == 4

  doAssert app.beginReplayRecording(seats, high(int64)) == nil
  doAssert "seed" in app.replaySaveError.toLowerAscii()
  doAssert listReplays().len == 4,
    "Unsupported seeds must never produce a divergent recording."

  const SetupChat = """
IF selectingClass THEN
  sent = sendChat(-2, "Setup message")
  pickClass(0)
  deckCard("Archer", 40)
  END
END IF
endTurn()
END
"""
  let prepared = newMultiplayerMatch(seats, -1, 80, @[SetupChat],
    botsChoose = true)
  doAssert prepared.setupMessages.len == 2
  let setupRecorder = app.beginReplayRecording(
    prepared.initialSeats, prepared.seed, prepared.setupMessages)
  doAssert setupRecorder.data.hashes.len == 0
  doAssert setupRecorder.data.actions.len == 2
  doAssert setupRecorder.data.actions[0].tick == 0
  doAssert setupRecorder.data.actions[0].playerId == 0
  doAssert setupRecorder.data.actions[1].playerId == 1
  setupRecorder.data.encodeReplay().decodeReplay().verify()

proc testManualSaveRecovery() =
  ## Retains a failed manual save when the automatic-save preference is off.
  const DataVariable = when defined(windows): "APPDATA" else: "XDG_DATA_HOME"
  let
    directory = createTempDir("cac-manual-replay-", "")
    hadData = existsEnv(DataVariable)
    previousData = getEnv(DataVariable)
    blocked = directory / "blocked"
    app = App(replayPreferences: ReplayPreferences(saveReplay: false))
  defer:
    if hadData:
      putEnv(DataVariable, previousData)
    else:
      delEnv(DataVariable)
    removeDir(directory)
  writeFile(blocked, "Not a directory")
  putEnv(DataVariable, blocked)
  discard app.beginReplayRecording(@[precon(Archer), precon(Mage)], 91)
  var rejected = false
  try:
    discard app.saveCurrentReplay()
  except ReplayError:
    rejected = true
  doAssert rejected
  app.finishReplayRecording()
  doAssert app.unsavedReplays.len == 1,
    "A failed manual save must survive leaving a match with autosave off."
  putEnv(DataVariable, directory)
  app.retryPendingReplays()
  doAssert app.unsavedReplays.len == 0
  doAssert app.replaySaveError.len == 0
  doAssert listReplays().len == 1

testLibraryRecording()
testManualSaveRecovery()
echo "CaC library save, deduplication, opt-out, and recovery tests passed."
