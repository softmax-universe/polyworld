import
  std/[os, strutils, tempfiles, times],
  polyworld/tapes,
  ../content, ../replays, ../replaylibraries

const RecordedTicks = DecisionTicks * 2

proc sampleReplay(): ReplayData =
  ## Builds a tiny valid tape with commands and chat without creating a world.
  let recorder = initReplayRecorder(Setup(
    mapSeed: DefaultSeed,
    tickRate: uint16(TickRate),
    gridTiles: uint16(DefaultMapSize),
    decisionTicks: uint16(DecisionTicks),
    maximumTicks: uint32(RecordedTicks),
    mapHash: 0x123456789ABCDEF0'u64,
    contentHash: contentHash(),
    players: @[
      ReplayPlayerSetup(id: 0, startX: 19, startY: 19),
      ReplayPlayerSetup(
        id: 1, startX: DefaultMapSize - 22, startY: DefaultMapSize - 22
      )
    ]
  ))
  recorder.recordAction(
    uint32(DecisionTicks), LightPlayer, ActionMove, FirstUnitId, 64, 42
  )
  recorder.record ReplayAction(
    kind: ActionChat, tick: uint32(DecisionTicks),
    playerId: 0, target: -2, text: "Hold the line"
  )
  recorder.recordAction(
    uint32(RecordedTicks), DarkPlayer, ActionAttack,
    FirstUnitId + 5, FirstUnitId
  )
  for tick in 1 .. RecordedTicks:
    recorder.recordHash(uint64(tick))
  recorder.data

proc changeVersion(bytes: var string, offset: int, version: uint16) =
  ## Rewrites a header field without interpreting an obsolete game payload.
  bytes[offset] = char(version and 0xff)
  bytes[offset + 1] = char(version shr 8)

proc rejectsImport(path, directory: string) =
  ## Requires malformed imports to leave their source and library unchanged.
  let
    source = readFile(path)
    before = listReplays(directory).len
  var rejected = false
  try:
    discard importReplay(path, directory)
  except ReplayError:
    rejected = true
  doAssert rejected
  doAssert readFile(path) == source
  doAssert listReplays(directory).len == before

proc testLibrary() =
  ## Exercises saves, old versions, malformed files, and non-destructive imports.
  let
    root = createTempDir("lvd-replay-library-", "")
    library = root / "library with spaces"
    data = sampleReplay()
    bytes = encodeReplay(data)
    payloadOffset = ReplayMagic.len + 6 + ReplayGame.len
  defer:
    removeDir(root)

  echo "Testing user library locations and empty libraries"
  doAssert replayDirectory().isAbsolute()
  doAssert replayDirectory().endsWith(
    "Polyworld" / "Light vs Dark" / "Replays"
  )
  doAssert listReplays(library).len == 0
  doAssert not dirExists(library)
  doAssert ensureReplayDirectory(library) == library

  echo "Testing uniquely named atomic replay saves"
  let
    first = saveLibraryReplay(data, library)
    second = saveLibraryReplay(data, library)
  doAssert first != second
  doAssert first.parentDir == library
  doAssert first.splitFile().ext == ".replay"
  doAssert readFile(first) == bytes
  doAssert readFile(second) == bytes
  doAssert loadReplay(first).actions == data.actions
  doAssert first.splitFile().name.startsWith("LvD-")
  let entry = inspectReplay(first)
  doAssert entry.playable
  doAssert entry.problem.len == 0
  doAssert entry.ticks == RecordedTicks
  doAssert entry.fileVersion == ReplayFileVersion
  doAssert entry.gameVersion == ReplayGameVersion
  doAssert entry.tapeVersion == ReplayFormatVersion
  doAssert entry.size == bytes.len
  doAssert entry.path == first
  doAssert entry.name == first.splitFile().name
  for kind, path in walkDir(library):
    doAssert kind == pcFile
    doAssert path.endsWith(".replay")

  echo "Testing newest-first ordering and unrelated-file filtering"
  setLastModificationTime(first, fromUnix(100))
  setLastModificationTime(second, fromUnix(200))
  writeFile(library / "unfinished.partial", bytes)
  writeFile(library / "notes.txt", "not a replay")
  createDir(library / "directory.replay")
  let ordered = listReplays(library)
  doAssert ordered.len == 2
  doAssert ordered[0].path == second
  doAssert ordered[1].path == first

  echo "Testing import copies, repeated names, and importing library files"
  let source = root / "A match with spaces.REPLAY"
  writeFile(source, bytes)
  let
    imported = importReplay(source, library)
    importedAgain = importReplay(source, library)
  doAssert imported != importedAgain
  doAssert readFile(source) == bytes
  doAssert readFile(imported) == bytes
  doAssert imported.splitFile().name.startsWith("Imported-A-match-with-spaces-")
  let count = listReplays(library).len
  doAssert importReplay(imported, library) == imported
  doAssert listReplays(library).len == count

  echo "Testing incompatible versions remain visible and import unchanged"
  for kind in 0 ..< 4:
    var old = bytes
    case kind
    of 0:
      old.changeVersion(ReplayMagic.len + 2, ReplayGameVersion - 1)
      old.setLen(payloadOffset)
      old.add("old payload whose layout is intentionally unknown")
    of 1:
      old.changeVersion(ReplayMagic.len, ReplayFileVersion + 1)
      old.setLen(payloadOffset)
    of 2:
      old.changeVersion(payloadOffset, ReplayFormatVersion - 1)
      old.setLen(payloadOffset + 4)
    else:
      old.changeVersion(payloadOffset + 2, ReplayGameVersion + 1)
      old.setLen(payloadOffset + 4)
    let path = root / ("older-" & $kind & ".replay")
    writeFile(path, old)
    let
      copied = importReplay(path, library)
      incompatible = inspectReplay(copied)
    doAssert not incompatible.playable
    doAssert incompatible.problem.len > 0
    doAssert readFile(copied) == old
    doAssert readFile(path) == old

  echo "Testing invalid, truncated, and foreign replays are contained"
  for i, bad in [
    "not a replay",
    ReplayMagic,
    bytes[0 ..< payloadOffset + 4],
    encodeReplayFile("gods_of_the_arena", 84, 1'u32)
  ]:
    let path = root / ("invalid-" & $i & ".replay")
    writeFile(path, bad)
    let invalid = inspectReplay(path)
    doAssert not invalid.playable
    doAssert invalid.problem.len > 0
    rejectsImport(path, library)
  let broken = library / "broken.replay"
  writeFile(broken, "not a replay")
  var foundBroken = false
  for item in listReplays(library):
    if item.path == broken:
      foundBroken = true
      doAssert not item.playable
      doAssert item.problem.len > 0
  doAssert foundBroken

  echo "Testing oversized replays and failed saves"
  let oversized = root / "oversized.replay"
  block:
    let file = open(oversized, fmWrite)
    defer:
      file.close()
    file.setFilePos(MaxReplayBytes)
    file.write('x')
  doAssert not inspectReplay(oversized).playable
  doAssert "64 MiB" in inspectReplay(oversized).problem
  var rejected = false
  try:
    discard importReplay(oversized, library)
  except ReplayError:
    rejected = true
  doAssert rejected
  let occupied = root / "occupied"
  writeFile(occupied, "keep this file")
  rejected = false
  try:
    discard saveLibraryReplay(data, occupied)
  except ReplayError:
    rejected = true
  doAssert rejected
  doAssert readFile(occupied) == "keep this file"

testLibrary()
echo "LvD replay library checks passed without touching the user library."
