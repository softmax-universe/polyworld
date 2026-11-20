import
  std/[os, strutils, tempfiles],
  polyworld/[replaylibraries, tapes]

proc opaqueTicks(bytes: string): int =
  ## Validates a direct game payload without an inner Polyworld tape header.
  let data = decodeReplayFile("opaque", 7, bytes, string)
  if data != "valid payload":
    raise newException(ReplayError, "Invalid opaque replay payload.")
  42

proc testReplayPayloadHeaders() =
  ## Requires explicit opaque payloads without weakening the default tape checks.
  let root = createTempDir("polyworld-payload-headers-", "")
  defer: removeDir(root)
  var format = ReplayLibraryFormat(
    game: "opaque", gameVersion: 7, tapeVersion: 2,
    maxBytes: DefaultMaxReplayBytes
  )
  let current = root / "current.replay"
  writeFile(current, encodeReplayFile("opaque", 7, "valid payload"))
  doAssert format.payloadHeader == TapePayloadHeader
  let tape = inspectReplay(current, format, opaqueTicks)
  doAssert not tape.playable and "Replay format" in tape.problem
  format.payloadHeader = OpaquePayloadHeader
  let direct = inspectReplay(current, format, opaqueTicks)
  doAssert direct.playable and direct.ticks == 42
  doAssert direct.gameVersion == 7 and direct.tapeVersion == 0
  let old = root / "old.replay"
  writeFile(old, encodeReplayFile("opaque", 6, "obsolete payload"))
  let obsolete = inspectReplay(old, format, opaqueTicks)
  doAssert not obsolete.playable and "Game version 6" in obsolete.problem
  let invalid = root / "invalid.replay"
  writeFile(invalid, encodeReplayFile("opaque", 7, "bad payload"))
  let rejected = inspectReplay(invalid, format, opaqueTicks)
  doAssert not rejected.playable and "Invalid opaque" in rejected.problem
  writeFile(invalid, encodeReplayFile("another", 7, "valid payload"))
  doAssert not inspectReplay(invalid, format, opaqueTicks).playable
  writeFile(invalid, "POLYWORLDREPLAY")
  doAssert not inspectReplay(invalid, format, opaqueTicks).playable

testReplayPayloadHeaders()
echo "Shared tape and opaque replay payload header checks passed."
