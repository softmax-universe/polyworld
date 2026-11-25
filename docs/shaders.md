# Shader authoring and validation

Author shader stages and helpers as Nim procedures compiled by Shady. All engine,
game, experiment, and rendering-test shaders use this path. Do not add GLSL files,
inline GLSL, or source-string patches. The unit suite checks this convention.

Use an explicit shader stage and target when calling `toShader`. Desktop renderers
use GLSL 330 or 410; browser renderers use `glsl3WebGL` and require WebGL 2.
The Shady commit in `nimby.lock` handles fragment depth, native fragment coordinate
origins, integer precision, and inverse sine. Use the locked dependencies when
building. A worktree-local `.deps` directory or symlink supplies isolated
dependencies; `POLYWORLD_DEPS` overrides it. Without either, builds use sibling
dependency checkouts.

Shader helpers with several statements should assign `result` explicitly. Check
the generated shaders on a real graphics driver: Nim type checking alone cannot
detect GLSL compiler and linker errors. Preserve explicit attribute bindings when
sharing vertex buffers across programs. Fragment coordinates retain OpenGL's
lower-left origin on desktop and WebGL.

## Native checks

From the repository root, with the sibling art checkout available:

```sh
nim check tests/unit_tests.nim
nim r tests/unit_tests.nim
nim check tests/tests.nim
nim r tests/tests.nim
nim r tests/test_screen_occlusions_render.nim
nim r tests/test_screen_effects_render.nim
nim r tests/manual_outlines.nim
nim r games/light_vs_dark/tests/test_strict_fog_composite.nim
nim r games/light_vs_dark/tests/manual_terrain_vision.nim
```

The rendering tests require a desktop OpenGL context. They check real pixels,
depth preservation, screen coordinates, fog, resizing, and MSAA behavior.

## Game builds

| Game | Entry point |
| --- | --- |
| Gods of the Arena | `games/gods_of_the_arena/gota.nim` |
| Light vs Dark | `games/light_vs_dark/lvd.nim` |
| Call to Adventure | `games/call_to_adventure/cta.nim` |
| Cards and Casters | `games/cac/cac.nim` |
| Heartleaf | `games/heartleaf/heartleaf.nim` |
| Crewrift | `games/crewrift/crewrift.nim` |
| Monster | `games/monster/monster.nim` |

For each entry point, run `nim check PATH`, `nim c PATH`, and
`nim c -d:emscripten PATH`. The last command requires Emscripten and writes a
browser bundle under the game's `emscripten` directory. Each game packs the art
it needs instead of embedding the entire art repository.

Native games support `--screenshot PATH --frames 30 --windowSize 1280x800`.
Pass an explicit bot roster where needed to enter a game instead of a menu.
GotA captures can use `SIM_SECONDS=120` to advance beyond drafting. Use
`--offline --save-dir tmp/backends/monster-save` for Monster captures.

## Browser checks

Install Playwright and pngjs, then serve the repository root:

```sh
python3 -m http.server 18934 --bind 127.0.0.1
```

In another terminal, run:

```sh
node tests/browser_shader_smoke.cjs
```

Pass game names to select a subset, such as `gota lvd cta`. Set `NODE_PATH` if the
Node packages are installed elsewhere, and `SHADER_SMOKE_CHROMIUM` to use a
specific Chrome or Chromium executable. The harness uses the normal HTTP bot
input interface with policies served from the repository. It checks gameplay,
shader compilation and linking, continued drawing, nonblank pixels, runtime
errors, resizing, and Crewrift's keyboard controls. Reports and screenshots go
to `tmp/backends/browser`.

Monster's browser build supports village simulation, selection, inspection, and
camera controls, with world progress and local-command history saved in browser
storage. Conversation with the model and voice require the desktop game because
the shared LLM transport is native-only. The browser UI states this limitation.
