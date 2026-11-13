# LvD match clock and server notice contract

## Source contract

- Shared room envelope stays version 4. Existing opcodes and encodings are unchanged.
  Append `PreparedDuration` (revision u32, hash u64, durationTicks u32) and
  `ServerNotice` (match from envelope, noticeId u32, trigger tick u32, typed code u32).
  `ThreeMinutesRemain` is code 0; the only current per-match notice ID is 1.
- LvD game adapter protocol is now **4**. Its controllers automatically submit
  duration-bearing preparation, independently of cosmetic Ready. Every occupied
  controller must prepare the current revision, agree on hash and duration, and be
  connected at startup. Duration must be positive and at most `MaxHistoryTicks`.
  Legacy Ready/Prepared/StartMatch bytes and other adapters' startup gates remain
  unchanged. Revision changes and rematches retire duration/notice state.
- Relay `advance` checks completion reports first. If no known completion and the
  agreed duration exceeds `180 * tickRate`, the first occupied controller applied
  acknowledgement reaching/crossing `duration - 180 * tickRate` emits one typed
  notice to all participants. Issued ticks, spectator acknowledgements and elapsed
  wall time cannot trigger it. An already-applied threshold may be processed while
  paused; pausing alone cannot advance the countdown or create a notice.
- ServerNotice is not a client operation or a player command/chat payload. The
  existing authenticated connection/relay transport is the authority boundary.
  This adds no cryptographic signing or new transport authentication scheme.
- Relay retains one notice and resends it after BeginMatch/status on authenticated
  reconnect and late spectator join. RoomClient retains one immutable notice,
  rejects changed identities/content, and releases it only at its local applied
  tick. Match+ID deduplication survives reconnect and resets for a new match/lobby.
- LvD renders the notice as gold `Server: 3 minutes remain` with typed server
  attribution, not an invented player sender. Spectators see the same feed without
  gaining chat/diplomacy controls. Existing feed capacity remains 100 lines.
- Tab statistics opt into `StatsOptions.statusText`: `Time remaining: MM:SS`,
  ceiling-rounded from nonnegative `maximumTicks - world.tick`. The optional row
  has no height when empty, preserving other games' layouts. The same countdown
  follows local/playback applied simulation time, not transport wall time.

## Verification

New fixtures:

- `tests/test_match_notices.nim`: frozen legacy binary encodings, new codecs,
  invalid code/trailing data, bounded preparation, agreement, threshold crossing,
  issued-vs-applied progress, pause, short matches, same-batch early completion,
  spoof rejection, reconnect, late spectator, revision/rematch reset, client gate
  and immutable match/ID deduplication.
- `games/light_vs_dark/tests/test_match_clock.nim`: production preparation opt-in,
  typed feed and real three-client binary relay with actual LvD simulations,
  lagged controller/spectator gating and reconnect before/after display.
- `test_match_clock_ui.nim`: countdown boundaries and multi-size/roster/scale layout.
- `test_match_clock_render.nim`: native GL production overlay, glyph pixels and
  containment at 640x480, 1000x700, 1920x1080; actual seatless spectator feed rendering.
  Uses production toggle rather than claiming OS-focused held-key delivery.

Run native suites from repository root (distinct scratch caches/output):

```
nim c -r --hints:off tests/tests.nim
nim c -r --hints:off games/light_vs_dark/tests/tests.nim
nim c -r --hints:off games/light_vs_dark/tests/test_match_clock_ui.nim
nim c -r --hints:off games/light_vs_dark/tests/test_match_clock_render.nim
nim check --hints:off games/light_vs_dark/graphics.nim
```

## Deployment and limitations

Parent must rebuild/deploy the universal relay and rebuild/publish the LvD WASM
client together. An old relay rejects the new operation; adapter protocol 3 and 4
clients cannot join the same room. Existing matches are not migrated. Coordinate
relay replacement with active rooms; this patch does not restart any service.
Other games do not need a client rebuild for these opt-in additions.

No browser test, WASM build, live server restart, deployment or commit is included.
Notices are retained only in the live room/client memory: **no saved replay notice
support** and no recovery of server room memory after process restart is claimed.
