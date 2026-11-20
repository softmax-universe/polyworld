import polyworld/replaylibraries as sharedLibraries
import replays

export sharedLibraries.ReplayEntry

proc replayTicks(bytes: string): int =
  ## Validates this game's complete payload before marking a file playable.
  decodeReplay(bytes).hashes.len

const Library* = ReplayLibrary(
  gameFolder: "Light vs Dark",
  gamePrefix: "LvD",
  format: ReplayLibraryFormat(
    game: ReplayGame,
    gameVersion: ReplayGameVersion,
    tapeVersion: ReplayFormatVersion,
    maxBytes: MaxReplayBytes
  ),
  inspect: replayTicks
)

proc replayDirectory*(): string =
  ## Returns this game's replay folder in the current user's application data.
  sharedLibraries.replayDirectory(Library)

proc ensureReplayDirectory*(directory = replayDirectory()): string =
  ## Creates and returns the library directory without relying on the game path.
  sharedLibraries.ensureReplayDirectory(Library, directory)

proc inspectReplay*(path: string): ReplayEntry =
  ## Describes a valid, incompatible, or unreadable LvD recording.
  sharedLibraries.inspectReplay(Library, path)

proc listReplays*(directory = replayDirectory()): seq[ReplayEntry] =
  ## Lists this game's recordings with newest files first.
  sharedLibraries.listReplays(Library, directory)

proc saveLibraryReplay*(
  data: ReplayData, directory = replayDirectory()
): string =
  ## Validates and saves the complete match under a unique library filename.
  sharedLibraries.saveLibraryReplay(Library, encodeReplay(data), directory)

proc importReplay*(source: string, directory = replayDirectory()): string =
  ## Copies a LvD recording, preserving unsupported versions and the source.
  sharedLibraries.importReplay(Library, source, directory)
