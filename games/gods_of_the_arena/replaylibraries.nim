import
  std/[algorithm, os, strutils, tempfiles, times],
  polyworld/tapes,
  replays

type
  ReplayEntry* = object
    path*, name*: string
    modified*: Time
    size*: int64
    gameVersion*, fileVersion*, tapeVersion*: uint16
    playable*: bool
    problem*: string
    ticks*: int

proc replayDirectory*(): string =
  ## Keeps recordings in the current user's application data directory.
  var base = getDataDir()
  if base.len == 0 or not base.isAbsolute():
    when defined(windows):
      base = getHomeDir() / "AppData" / "Roaming"
    elif defined(macosx):
      base = getHomeDir() / "Library" / "Application Support"
    else:
      base = getHomeDir() / ".local" / "share"
  base / "Polyworld" / "Gods of the Arena" / "Replays"

proc ensureReplayDirectory*(directory = replayDirectory()): string =
  ## Creates and returns the library directory without relying on the game path.
  if directory.len == 0:
    raise newException(ReplayError, "The replay folder is empty.")
  try:
    createDir(directory)
    result = absolutePath(directory)
  except IOError, OSError:
    raise newException(ReplayError,
      "Could not create the replay folder: " & getCurrentExceptionMsg())

proc readReplayBytes(path: string, headerOnly = false): string =
  ## Bounds an imported file before allocating or decoding its contents.
  try:
    let file = open(path, fmRead)
    defer:
      file.close()
    let size = file.getFileSize()
    if size < 0 or size > MaxReplayBytes:
      raise newException(ReplayError, "The replay exceeds the 64 MiB limit.")
    let count =
      if headerOnly:
        min(size.int, ReplayMagic.len + 10 + MaximumReplayGameBytes)
      else:
        size.int
    result = newString(count)
    if result.len > 0 and
      file.readBuffer(addr result[0], result.len) != result.len:
        raise newException(ReplayError, "The replay file is incomplete.")
    if not headerOnly and not file.endOfFile():
      raise newException(ReplayError, "The replay changed while it was read.")
  except IOError, OSError:
    raise newException(ReplayError,
      "Could not read the replay: " & getCurrentExceptionMsg())

proc inspectVersions(bytes: string, entry: var ReplayEntry): bool =
  ## Checks versions before attempting the current game's payload decoder.
  let header = replayFileHeader(bytes)
  entry.fileVersion = header.formatVersion
  entry.gameVersion = header.gameVersion
  if header.game != ReplayGame:
    raise newException(ReplayError, "This replay belongs to another game.")
  if header.formatVersion != ReplayFileVersion:
    entry.problem = "Replay file version " & $header.formatVersion &
      " (requires " & $ReplayFileVersion & ")"
    return
  if header.gameVersion != ReplayGameVersion:
    entry.problem = "Game version " & $header.gameVersion &
      " (requires " & $ReplayGameVersion & ")"
    return
  let offset = ReplayMagic.len + 6 + header.game.len
  if bytes.len < offset + 4:
    raise newException(ReplayError, "The replay payload is incomplete.")
  entry.tapeVersion = uint16(bytes[offset].ord) or
    uint16(bytes[offset + 1].ord shl 8)
  if entry.tapeVersion != ReplayFormatVersion:
    entry.problem = "Replay format " & $entry.tapeVersion &
      " (requires " & $ReplayFormatVersion & ")"
    return
  let gameVersion = uint16(bytes[offset + 2].ord) or
    uint16(bytes[offset + 3].ord shl 8)
  if gameVersion != ReplayGameVersion:
    entry.problem = "Game version " & $gameVersion &
      " (requires " & $ReplayGameVersion & ")"
    return
  true

proc inspectBytes(bytes: string, entry: var ReplayEntry) =
  ## Decodes only payloads whose outer and inner versions are supported.
  if not inspectVersions(bytes, entry):
    return
  let data = decodeReplay(bytes)
  entry.ticks = data.hashes.len
  entry.playable = true

proc inspectReplay*(path: string): ReplayEntry =
  ## Describes one valid, incompatible, or unreadable recording for the browser.
  result.path = absolutePath(path)
  result.name = path.splitFile().name
  try:
    result.modified = getLastModificationTime(path)
    result.size = getFileSize(path)
    if inspectVersions(readReplayBytes(path, headerOnly = true), result):
      inspectBytes(readReplayBytes(path), result)
  except CatchableError as error:
    result.problem = error.msg
  except IndexDefect, RangeDefect:
    result.problem = "The replay payload is invalid or incomplete."

proc listReplays*(directory = replayDirectory()): seq[ReplayEntry] =
  ## Lists newest recordings first, retaining disabled entries for old versions.
  if not dirExists(directory):
    return
  try:
    for kind, path in walkDir(directory, checkDir = true):
      if kind in {pcFile, pcLinkToFile} and
        path.splitFile().ext.toLowerAscii() == ".replay":
          result.add(inspectReplay(path))
  except OSError as error:
    raise newException(ReplayError,
      "Could not read the replay folder: " & error.msg)
  result.sort(proc(first, second: ReplayEntry): int =
    ## Orders ties by their full filename to keep refreshes stable.
    result = cmp(second.modified, first.modified)
    if result == 0:
      result = cmp(first.path, second.path)
  )

proc filenamePrefix(name: string): string =
  ## Retains readable imported names while avoiding platform filename syntax.
  for character in name:
    if result.len == 60:
      break
    if character in Letters + Digits + {'-', '_'}:
      result.add(character)
    elif character == ' ':
      result.add('-')
  if result.len == 0:
    result = "replay"
  result = "Imported-" & result & "-"

proc flushReplay(file: File) =
  ## Rejects buffered write failures before publishing a complete recording.
  proc fflush(stream: File): cint {.importc, header: "<stdio.h>".}
    ## Flushes the C stream while retaining its success or failure result.
  if fflush(file) != 0:
    raise newException(IOError, "Could not finish writing the replay file.")

proc storeReplayBytes(bytes, directory, prefix: string): string =
  ## Publishes a complete file with a unique name, without overwriting replays.
  let folder = ensureReplayDirectory(directory)
  try:
    while true:
      let (file, temporary) = createTempFile(prefix, ".partial", folder)
      let destination = temporary.changeFileExt(".replay")
      var closed = false
      try:
        if fileExists(destination) or dirExists(destination):
          continue
        file.write(bytes)
        flushReplay(file)
        closed = true
        file.close()
        moveFile(temporary, destination)
        return destination
      finally:
        if not closed:
          file.close()
        if fileExists(temporary):
          removeFile(temporary)
  except IOError, OSError:
    raise newException(ReplayError,
      "Could not save the replay: " & getCurrentExceptionMsg())

proc saveLibraryReplay*(
  data: ReplayData, directory = replayDirectory()
): string =
  ## Saves a validated match into the library with a time-stamped unique name.
  storeReplayBytes(
    encodeReplay(data),
    directory,
    "GotA-" & now().format("yyyy-MM-dd'_'HH-mm-ss") & "-"
  )

proc importReplay*(source: string, directory = replayDirectory()): string =
  ## Copies a GotA recording into the library, preserving unsupported versions.
  let bytes = readReplayBytes(source)
  var entry: ReplayEntry
  try:
    inspectBytes(bytes, entry)
  except IndexDefect, RangeDefect:
    raise newException(ReplayError, "The replay payload is invalid or incomplete.")
  except CatchableError as error:
    raise newException(ReplayError, error.msg)
  let folder = ensureReplayDirectory(directory)
  if source.splitFile().ext.toLowerAscii() == ".replay" and
    sameFile(source.absolutePath().parentDir, folder):
      return source.absolutePath()
  storeReplayBytes(bytes, folder, source.splitFile().name.filenamePrefix())
