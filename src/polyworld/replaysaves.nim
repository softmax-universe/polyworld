import
  std/os,
  tapes

type
  ReplaySaveError* = object of ReplayError
  ReplayExportError* = object of ReplayError

  ReplaySaveState* = object
    savedPath*: string
    saveRequested*: bool
    automaticAttempted*: bool
    savedHashes, savedActions: int = -1

proc resetReplaySave*(state: var ReplaySaveState) =
  ## Starts a new match without carrying over its predecessor's saved prefix.
  state = ReplaySaveState()

proc requestReplaySave*(state: var ReplaySaveState) =
  ## Preserves a save request until its recorded prefix reaches the library.
  state.saveRequested = true

proc beginAutomaticReplaySave*(
  state: var ReplaySaveState, enabled, completed: bool
): bool =
  ## Allows one automatic completion attempt, leaving retries explicit.
  if enabled and completed and not state.automaticAttempted:
    state.automaticAttempted = true
    result = true

proc shouldSaveReplayOnExit*(
  state: ReplaySaveState, automatic: bool
): bool =
  ## Retries an unsuccessful manual save even when automatic saving is off.
  automatic or state.saveRequested

proc shouldRetainReplay*(
  automatic: bool, error: ref CatchableError
): bool =
  ## Preserves failed saves without duplicating a successful library write.
  error of ReplaySaveError or
    (automatic and not (error of ReplayExportError))

proc saveReplaySnapshot*[T](
  state: var ReplaySaveState,
  data: T,
  save: proc(data: T): string
): string =
  ## Writes an append-only recorded prefix once, recreating a removed file.
  state.requestReplaySave()
  if state.savedPath.len == 0 or not fileExists(state.savedPath) or
    state.savedHashes != data.hashes.len or
    state.savedActions != data.actions.len:
      let path = save(data)
      state.savedPath = path
      state.savedHashes = data.hashes.len
      state.savedActions = data.actions.len
  state.saveRequested = false
  state.savedPath

proc retryReplaySaves*[T](
  pending: var seq[T], save: proc(data: T): string
) =
  ## Removes a retained recording only after its library write succeeds.
  while pending.len > 0:
    discard save(pending[0])
    pending.delete(0)
