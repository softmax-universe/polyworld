# Archived showcase mine transitions

Status: renderer patch prepared for the next browser release; the hosted
bundle has not been rebuilt or published.

The hosted showcase replay viewer identifies source revision
`4f9ad8e6482207fce294a92ebf69bd9879dbc13d` (viewer `2026.10.19.1`).
Its `captureUnitPoses` records peons inside mines. When a peon exits at a
different perimeter position, interpolation draws it sliding from the entrance
to the exit. The current game and the newer `/play/` build already exclude
hidden miners from position history.

Apply [showcase-mine-transitions.patch](showcase-mine-transitions.patch) to an
isolated export of that archived source, alongside the existing showcase
`viewer-compatibility.patch`. The change touches only
`examples/light_vs_dark/graphics.nim`: hidden miners have no previous visible
position or facing, so the renderer falls back to the exact emergence pose.

Retain gameplay version 23, the archived dependency lock, art revision
`f78d18d8eeb899ed3aa7a304944be448aec34dcf`, the canonical pathfinding patch,
and the native playback-speed hook. Do not substitute the current gameplay
client for this viewer: it cannot play those old recordings. Refresh the
bundle provenance only after building and verifying the archived viewer.

Validation ran the archived `captureUnitPoses`, `renderPoint`, and
`renderFacing` procedures with the existing full mining-cycle fixture in
`tests/test_mine_exit_interpolation.nim`. The original renderer failed at the
first exit, drawing the peon at its entrance position instead of its exit.
The patched renderer passed all eight exit positions, interpolation fractions
from 0 to 1, disappearance while mining, normal motion on the following tick,
and unchanged simulation hashes. The current game also passed the original
fixture and real ordinary/cargo character-pose checks. These checks exercise
the archived rendering procedures with the current simulation fixture; the
complete archived browser bundle still requires verification at release.
