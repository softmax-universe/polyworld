# Desktop replay libraries

GotA, Light vs Dark, Cards and Casters, and Galcon use the same desktop replay
library components. Game setup defaults to **Save replay** enabled. The choice
belongs to the local player and is stored separately from multiplayer match settings.
The replay menu, import dialog, folder button, and save controls are excluded
from browser builds.

## Shared responsibilities

- `polyworld/replaylibraries.nim` owns user folders, bounded reads, version
  checks, newest-first listing, imports, and unique atomic file writes. Each
  game supplies a `ReplayLibrary` descriptor and its payload validator.
- `polyworld/replaymenus.nim` owns the replay list, selection, scrolling,
  disabled incompatible entries, and browser actions. Games handle launching
  and leaving their own playback sessions. Galcon supplies its space background,
  original fonts, flat widgets, and green highlights to the shared renderer.
- `polyworld/replaysettings.nim` owns the recording preference format and
  persistence. Game wrappers supply their existing configuration namespace.
- `polyworld/replaysaves.nim` owns save deduplication, completion attempts,
  outstanding save requests, and retrying retained recordings.

Games retain their own recording and playback logic, including deterministic
state checks and ordered chat actions. GotA and LvD display elapsed time; CaC
displays action counts because its replay advances by accepted game actions.
Galcon supplies an opaque-payload descriptor because its existing recording
format uses only the outer Polyworld version header. Its decoder still
validates the complete payload before a replay becomes playable.

## Save behavior

For matches launched through the desktop menus, automatic saving writes the
recording at completion and when leaving a partial match. Repeated saves of
the same recorded prefix reuse its file. Further actions or chat create a new
snapshot, and deleting a saved file allows it to be recreated.

Manual saving remains available when automatic saving is disabled. A failed
manual request is retried on exit. Failed exit saves remain in memory for the
menu's **Retry saving replay** button; a failed retry does not discard them.
Completion failures are not retried every frame. Pending recordings are not
durable across process termination. Watching a replay never records another
replay.

## Compatibility

Recordings remain under the user's application data folder in
`Polyworld/<game name>/Replays`. Existing configuration namespaces, filenames,
and replay formats remain unchanged. Imports copy the source file. Old game
or replay versions remain visible but disabled, and selecting a playable
entry revalidates it before playback.

Shared behavior tests live in `tests/test_replaysettings.nim`,
`tests/test_replaysaves.nim`, `tests/test_replaylibraries.nim`, and
`tests/test_replay_browser.nim`.
Each game's tests retain coverage of its actual
recording, save/load, replay hashes, and native menu rendering.
