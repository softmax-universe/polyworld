# Screenshot capture

Every native game uses the same runtime arguments:

```sh
./game --screenshot output/shot.png --frames 30 --windowSize 1280x720
```

Use an ordinary graphical build. Capture opens a hidden window, renders without
display pacing or sound, saves the image, and exits through normal cleanup.
Parent directories are created automatically. Relative output paths are resolved
from the launch directory, even when a game changes its working directory.

| Argument | Meaning |
| --- | --- |
| `--screenshot PATH` | Save one image to this path and exit. |
| `--frames N` | Capture the Nth rendered content frame; default 30. |
| `--windowSize WIDTHxHEIGHT` | Request the window dimensions used for rendering. |

All three arguments accept separate, equals, or colon values:

```sh
./game --screenshot output/shot.png --frames 3 --windowSize 1280x720
./game --screenshot=output/shot.png --frames=3 --windowSize=1280x720
./game --screenshot:output/shot.png --frames:3 --windowSize:1280x720
```

Quote paths containing spaces. Frame counts and dimensions must be positive
integers. `--frames` counts rendered frames, not simulation ticks or seconds.
Games retain their own menu, replay, pause, and match-start arguments. A capture
does not automatically start a match in a game that normally opens its menu.
Call to Adventure and Heartleaf supply bundled bots for an otherwise unspecified
capture launch because those clients open directly into a match.

Screenshot runs do not create automatic replay-library saves. An explicit
`--record` request still writes its replay. Monster's ordinary capture does not
invoke AI, listen to the microphone, or modify saved world/conversation data;
an explicit `--prompt` retains its separate wait-for-actions behavior.

Capture requires a native graphical client. Headless builds and browser clients
reject screenshot requests. It is not a headless simulation or browser download
feature.

## Clients

The shared arguments are used by GotA, Light vs Dark, Cards and Casters, Call to
Adventure, Heartleaf, Crewrift, and Monster in this repository, and by the native
Galcon, Pudge Wars, Generals, and Mini Diplomacy clients in their own repositories.

For example:

```sh
nim r games/gods_of_the_arena/gota.nim --screenshot output/gota.png --frames 3
nim r games/light_vs_dark/lvd.nim --screenshot output/lvd.png --frames 3
nim r games/cac/cac.nim --screenshot output/cac.png --frames 3
```

Game-specific scene setup remains separate. For example, Crewrift's explicit
`--capture-ticks` advances its simulation before rendering, Generals' `--at`
selects a position, and a replay argument opens the supplied recording.

## Shared implementation and checks

`polyworld/screenshots.nim` owns the graphics-free options, parsing, validation,
and capture state. `polyworld/cli.nim` exposes those options as
`GameOptions.capture`. `polyworld/viewers.nim` supplies the hidden framebuffer,
pixel writer, fixed capture clock, and one-shot completion helper. Games choose
their scene and perform their normal shutdown after a successful capture.

Some specialized developer fixtures still use `-d:takeScreenshot` and environment
variables. Runtime screenshot arguments take precedence and do not require that
build define. Parser and state tests run in CI; rendering checks are local only.
