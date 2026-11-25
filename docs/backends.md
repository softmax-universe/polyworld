# Rendering backends

Polyworld selects a rendering backend at compile time, following glTF and Silky.
OpenGL is the default for desktop and WebGL 2. Build with `-d:useMetal4` to use
Metal on macOS. `-d:useDirectX` and `-d:useVulkan` select explicit placeholders
and report that the backend is not implemented.

```sh
nim c -r -d:useMetal4 games/crewrift/crewrift.nim
nim c -r -d:useMetal4 games/monster/monster.nim --offline
nim c -d:emscripten games/crewrift/crewrift.nim
```

Use the dependencies in `nimby.lock`. A worktree-local `.deps` directory keeps
dependency branches isolated; `POLYWORLD_DEPS` can select another checkout root.
The lock includes Shady's Metal compiler fixes and Silky's application-owned
rendering support.

## Boundaries

Public feature modules select implementations in `backends/opengl` or
`backends/metal`. CPU geometry, simulation, settings, and Shady procedures are
shared. Cards and Casters and the smaller game-specific passes use the same
layout within their game directories.

`polyworld/renderer` owns frame operations, UI submission, atlas views, capture
targets, and readback. Games use this facade instead of native graphics handles
or commands. `tests/test_backend_boundaries.nim` checks engine and game production
sources. OpenGL-specific test fixtures and standalone developer experiments
remain explicit OpenGL clients.

The Metal implementation owns one device, presentation surface, and command
buffer per frame. Terrain, models, shadows, water, effects, and UI encode into
that frame. Offscreen passes restore the previous target and viewport. Character
rendering uploads glTF CPU geometry to Polyworld's cache and draws immediately;
it does not invoke glTF's separate window presentation path.

Silky receives the application's device and current color attachment. Its UI
pass loads existing scene pixels and leaves command submission and presentation
to Polyworld. Call `finishUi` after `beginUi` and UI drawing. Multiple UI passes
and atlas instances are supported. MSAA resolves before UI composition, and
subsequent passes preserve that composition.

## Shader coordinates

All stages are authored in Shady. Backends select `glsl3`/`glsl4`, `glsl3WebGL`,
or `metalMSL`. Metal uniforms use Shady's reflected field offsets and alignment.
There are no handwritten GLSL or Metal shader source strings.

Metal textures and fragment positions use a top-left origin. Shared screen
effects explicitly convert coordinates when their math uses OpenGL's bottom-left
convention. Shady converts vertex clip depth to Metal's zero-to-one range;
screen-space reconstruction converts sampled depth back to the shared convention.

## Verification

Run `nim check` before compiling each game. All seven entry points are listed in
[the shader guide](shaders.md), along with screenshot and browser commands.
The normal unit suite checks shader authorship and backend boundaries.

Metal regression tests use actual device compilation and pixel readback:

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
