import polyworld/replaylibraries as sharedLibraries
import replays

export sharedLibraries.ReplayEntry

const LibraryFormat = ReplayLibraryFormat(
  game: ReplayGame,
  gameVersion: ReplayGameVersion,
  tapeVersion: ReplayFormatVersion,
  maxBytes: MaxReplayBytes
)

proc replayTicks(bytes: string): int =
  ## Validates this game's complete payload before marking a file playable.
  decodeReplay(bytes).hashes.len

proc replayDirectory*(): string =
  ## Returns this game's replay folder in the current user's application data.
  sharedLibraries.replayDirectory("Light vs Dark")

proc ensureReplayDirectory*(directory = replayDirectory()): string =
  ## Creates and returns the library directory without relying on the game path.
  sharedLibraries.ensureReplayDirectory(directory)

proc inspectReplay*(path: string): ReplayEntry =
  ## Describes a valid, incompatible, or unreadable LvD recording.
  sharedLibraries.inspectReplay(path, LibraryFormat, replayTicks)

proc listReplays*(directory = replayDirectory()): seq[ReplayEntry] =
  ## Lists this game's recordings with newest files first.
  sharedLibraries.listReplays(directory, LibraryFormat, replayTicks)

proc saveLibraryReplay*(
  data: ReplayData, directory = replayDirectory()
): string =
  ## Validates and saves the complete match under a unique library filename.
  sharedLibraries.saveLibraryReplay(encodeReplay(data), directory, "LvD")

proc importReplay*(source: string, directory = replayDirectory()): string =
  ## Copies a LvD recording, preserving unsupported versions and the source.
  sharedLibraries.importReplay(source, directory, LibraryFormat, replayTicks)
