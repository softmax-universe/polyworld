# Rendering backends

Polyworld selects a rendering backend at compile time, following glTF and Silky.
OpenGL is the default for desktop and WebGL 2. Use `-d:useMetal4` on macOS.
On Windows, `-d:useDirectX` selects Direct3D 12 and `-d:useVulkan` selects
Vulkan 1.4. Each build uses the selected driver for scene rendering, UI, and
presentation.

```sh
nim c -r -d:useDirectX games/crewrift/crewrift.nim
nim c -r -d:useVulkan games/crewrift/crewrift.nim
nim c -r -d:useMetal4 games/crewrift/crewrift.nim
nim c -r -d:useMetal4 games/monster/monster.nim --offline
nim c -d:emscripten games/crewrift/crewrift.nim
```

Use the dependencies in `nimby.lock`. A worktree-local `.deps` directory keeps
dependency branches isolated; `POLYWORLD_DEPS` can select another checkout root.
The lock includes Shady's Metal compiler fixes and Silky's application-owned
rendering support. For DirectX and Vulkan builds, install the Vulkan SDK and put
`glslangValidator`, `spirv-cross`, and `dxc` on the build PATH. The executable
embeds its compiled shaders. Launch games from the repository root so they can
find their assets.

## Boundaries

The pipeline is shared scene preparation, shared rendering passes, then a
compile-time selected backend adapter. Public feature modules import
`backends/passes`; their old backend paths remain compatibility facades.
`backends/passes/common.nim` selects `opengl/passapi`, `metal/passapi`, or
`native/common`. DirectX and Vulkan implement the native command interface.

Scene traversal, transforms, skinning inputs, material extraction, culling,
transparent ordering, and shadow-caster caching live in `backends/passes/meshes`,
`toon`, and `charactercontexts`.
Terrain baking and scenery batches live in `backends/passes/quadterrain`.
The same pass implementations submit terrain, Toon characters, shadows, water,
particles, shapes, world bars, and screen effects on every backend. Cards and
Casters shares its card faces, courtyard, table, VFX, and post passes under its
own `backends/passes` directories. Crewrift stars and Light vs Dark fog follow
the same pattern. The OpenGL PBR facade retains glTF's existing PBR context and
IBL resources; Toon uses Polyworld's shared mesh preparation on every backend.

OpenGL and WebGL commands are confined to `backends/opengl`. Its `passprograms`
module owns shader compilation, reflected uniforms, vertex layouts, and draw
state; `passresources` owns buffers, images, and samplers; `passtargets` owns
attachments, resolves, copies, and readback. Legacy GLuint texture and framebuffer
APIs adapt to explicit borrowed resource views, so ownership stays with callers.
Shared draw groups save and restore OpenGL state once around a pass. Individual
low-level draws also preserve state when called outside a group. This allows
shared passes to compose with glTF, Silky, and existing OpenGL clients.

WebGL uses the same adapter with WebGL Shady output and supported attachment
formats. Water reflections use RGBA8 on WebGL and RGBA16F on desktop. Backend
sampling preserves per-axis wraps, mip filtering, comparison mode, and supported
anisotropy. Depth copies match the actual attachment format of borrowed targets,
including multisampled window framebuffers.

Shared data modules keep backend policy explicit. `renderdescriptions` and
`texturesampling` describe vertex layouts, draw state, formats, and samplers.
`texturedata` prepares validated upload payloads, and `shadermetadata` indexes
uniforms, inputs, and texture bindings. `targetplans` and `uploadplans` validate
attachment requirements and track reusable upload capacity without GPU handles.
`measurements` defines consistent benchmark configuration and frame accounting.

`polyworld/renderer` owns frame operations, UI submission, atlas views, capture
targets, and readback. Games use this facade instead of native graphics handles
or commands. `tests/test_backend_boundaries.nim` checks engine and game production
sources. OpenGL-specific test fixtures and standalone developer experiments
remain explicit OpenGL clients.

The Metal, DirectX, and Vulkan implementations each own the device and frame. Terrain, models, shadows, water, effects, and UI encode into
that frame. Offscreen passes restore the previous target and viewport. Character
rendering uploads glTF CPU geometry to Polyworld's cache and draws immediately;
it does not invoke glTF's separate window presentation path.

Use `newGameUi`, `beginGameUi`, and `finishUi` to draw Silky into the active
Polyworld target. Metal supplies its current attachment to the Silky drawer.
DirectX and Vulkan draw Silky’s queued layers with its Shady shaders and atlas. Multiple UI passes
and atlas instances are supported. MSAA resolves before UI composition, and
subsequent passes preserve that composition. The drivers choose a supported
sample count for each target. DirectX uses a single sample for depth-stencil
targets on devices that cannot resolve that format.

## Shader coordinates

All stages are authored in Shady. Backends select `glsl3`/`glsl4`, `glsl3WebGL`,
or `metalMSL`. The Windows drivers compile Shady stages at build time and embed
DXIL or SPIR-V with uniform and texture reflection. Metal uniforms use Shady's reflected field offsets and alignment.
There are no handwritten GLSL or Metal shader source strings.

Metal and native textures and fragment positions use a top-left origin.
OpenGL and WebGL retain their bottom-left framebuffer convention. Shared screen
effects explicitly convert coordinates when their math uses OpenGL's bottom-left
convention. Shady converts vertex clip depth to Metal's zero-to-one range;
screen-space reconstruction converts sampled depth back to the shared convention.

## Verification

Run `nim check` before compiling each game. All seven entry points are listed in
[the shader guide](shaders.md), along with screenshot and browser commands.
The normal unit suite checks shader authorship and backend boundaries.
Automated GPU fixtures create their windows with `visible = false` from the
outset and keep them hidden. They must not show, focus, or enter fullscreen.
Browser checks run headless. Manual visual tests are separate from automated
validation.

The Windows frame test draws through the selected API, checks offscreen pixels,
and exercises presentation and resize.

```sh
nim r -d:useDirectX tests/test_native_frame.nim
nim r -d:useVulkan tests/test_native_frame.nim
```

Metal regression tests use actual device compilation and pixel readback.

```sh
nim r -d:useMetal4 tests/test_metal_core.nim
nim r -d:useMetal4 tests/test_metal_viewers.nim
nim r -d:useMetal4 tests/test_metal_characters.nim
nim r -d:useMetal4 tests/test_effects_metal.nim
nim r -d:useMetal4 tests/test_metal_shadows_render.nim
nim r -d:useMetal4 tests/test_metal_water_body.nim
nim r -d:useMetal4 tests/test_screen_occlusions_metal.nim
nim r -d:useMetal4 tests/test_selection_outlines_metal.nim
nim r -d:useMetal4 tests/test_metal_xray_distortions.nim
```

The tests cover depth and stencil, cutout textures, skinning, independent model
instances, texture lifetime, visibility masks, screen coordinates, resizing,
MSAA, reflections, and UI composition. Browser smoke tests compile and link
generated shaders on WebGL 2, then check gameplay frames and resized canvases.

## Frame benchmarks

Build and run the seven games from the repository root. Put the locked
dependencies, Emscripten, the native shader compilers, and the game's audio
runtime on the build or run PATH as appropriate. The browser runner uses
Chrome on Windows. Set `BENCH_CHROMIUM` to use a different Chromium executable.

```sh
nim c -o:tmp/bench_backends tools/bench_backends.nim
tmp/bench_backends build
tmp/bench_backends run all all 3 local
nim r tools/bench_report.nim local
```

The runner also accepts comma-separated games and backends, for example
`tmp/bench_backends run gota,lvd OpenGL,WebGL,DirectX,Vulkan 3`. Each
repetition launches a fresh process at seed 42 and 800×560, with one sample
per pixel and a fixed simulation step of 1/60 second. GotA advances beyond its
draft and Crewrift advances beyond its role reveal before warmup. Monster uses
a fresh offline world. After 180 warmup frames the runner records 180 samples
from the start of the gameplay frame through GPU completion. Each finished
frame includes simulation, scene, and HUD work. The timer stops before the swap
or browser refresh wait. Loading, warmup, and display pacing are outside the
measurement. The separate `interval_ms` series records start-to-start cadence
with those waits included and the same per-frame GPU synchronization. The report
pools samples across launches and includes each launch’s mean for comparison. WebGL uses the game's normal browser asset pack. Per-run JSON in
`tmp/livetest/benchmarks` retains each sample and the browser GPU identity.

For Gods of the Arena alone, use `build gota all`, `run gota all 3 arena`,
and `nim r tools/bench_report.nim arena 3 gota`. The report includes mean,
median, and 95th-percentile frame times in milliseconds.

Set `BENCH_PIPELINED=1` before the build to measure normal presentation.
Use a new run ID. This mode drains outstanding GPU work at the end of warmup
and at the end of measurement. The mean frame interval includes every measured
presentation and the final drain. The fourth argument to the report selects
backends, for example `nim r tools/bench_report.nim arena-present 3 gota OpenGL,DirectX,Vulkan`.
