# Game backend benchmarks

## Benchmark an ordinary native build

All seven Polyworld games accept `--benchmark PATH` wherever they accept
`--screenshot PATH`. For example, from the repository root, this runs a seeded
Gods of the Arena match with ten bots and writes a report for the selected backend.

```sh
nim r games/gods_of_the_arena/gota.nim --bot games/gods_of_the_arena/players/base.bas:10 --seed 42 --benchmark tmp/livetest/benchmarks/gota.json --windowSize 800x560 --warmup 30 --frames 180
```

The game creates a hidden window, renders its usual capture scene offscreen,
writes the report, and exits. Both the warmup and sample counts default to 30.
The normal match, menu, and replay arguments select what gets measured.

`frameMs` contains wall-clock intervals between consecutive content frames.
The clock starts after the warmup GPU work finishes. Subsequent frames submit
asynchronously, and the last interval includes the final GPU drain.
`summary.meanMs` gives the elapsed time per completed frame over the whole
sample. The report also includes the median, p95, minimum, maximum, game,
backend, and render dimensions. These offscreen timings exclude display pacing.

## Benchmark matrix

Build the benchmark matrix, then measure it with one game process at a time:

```sh
python3 tools/bench_backends.py build --jobs 3
python3 tools/bench_backends.py run --trials 3 --warmup 120 --frames 600
```

The browser runner requires Node, Playwright and hardware-accelerated Chrome.
Set `NODE_PATH` if Playwright is installed outside the repository, and
`BENCH_CHROMIUM` to select the Chrome executable. The default executable is the
macOS Google Chrome application. Builds need Nim and the repository's normal
native and Emscripten toolchains.

The runner builds all seven games for native OpenGL, native Metal and WebGL.
`--games gota,lvd` and `--backends opengl,metal` select smaller matrices. Outputs,
build logs, per-frame JSON and summaries are written under `tmp/benchmarks`.
Each run uses a new directory so previous measurements remain available.

## Workload

Benchmark builds use `-d:release -d:backendBench`, 1280 by 800 physical pixels,
single-sample rendering, default presentation preferences, seed 42, and a fixed
1/60-second simulation step. Native windows are hidden and render offscreen.
The browser uses a fresh context with device pixel ratio 1 for each trial.
Normal game builds do not enable the timing hooks or these overrides.

The launchers use matching BASIC bot rosters: GotA 10, LvD 2, CTA 4 and
Heartleaf 9. Crewrift uses its default eight bots in spectator mode. CaC runs
the default two-player Archer/Warrior duel with visual seed 42. Monster starts
a fresh offline world without voice. Benchmark autosaving is disabled.

GotA advances 120 simulation seconds before the first benchmark frame. CaC
class selection and Crewrift's role reveal are excluded. Warmup then consumes
120 gameplay frames; the following 600 frames are measured. Most games run
their simulation at 24 Hz, Monster at 30 Hz, and CaC reports turn numbers.
Compare the raw per-frame tick arrays to verify matching simulation progress.

Every timed trial runs alone. The runner shuffles game order and rotates the
backend order across trials. All builds finish before timing starts, with a
cooldown between the build and run phases. It records a source fingerprint
and rejects stale builds or source changes during measurement.

## Timing

The primary metric is elapsed gameplay update and rendering time through a
synchronous one-pixel RGBA readback. It includes CPU simulation, render command
encoding, driver work, GPU completion and readback overhead. Loading, event-loop
waiting and display presentation are outside this interval. Serial completion
also prevents the CPU/GPU overlap possible in a normal pipelined application.
These numbers therefore describe completed frame work, not displayed FPS or
isolated GPU execution time.

OpenGL and WebGL use `readPixels` from the active draw framebuffer with a CPU
destination. Metal submits and waits for its command buffer, then reads one
pixel from the active resolved texture. Framebuffer and pixel-pack state are
preserved. Browser readback adds an IPC round trip that is part of this metric.

Do not replace the browser barrier with `finish()`: Chromium implements it as
a flush. See the [Chromium implementation](https://github.com/chromium/chromium/blob/main/third_party/blink/renderer/modules/webgl/webgl_rendering_context_base.cc)
and [WebGL 2 readPixels synchronization rules](https://registry.khronos.org/webgl/specs/latest/2.0/#3.7.10).

`cpuMs` ends just before readback; `gpuWaitMs` is the remaining barrier and
readback cost, not a GPU timestamp. `workMs` includes both. `intervalMs` measures
the time between consecutive gameplay frame starts; the browser report uses
it to report cadence separately from frame work.

The summary's `medianFrameMs` is the median of the three trial medians. Its
P95 is the median of the three nearest-rank trial P95 values. The full range
of trial medians is retained. `workFpsEquivalent` is 1000 divided by
`medianFrameMs`; the raw game's `fpsEquivalent` instead uses mean frame time.
Use milliseconds for comparison to avoid mixing these definitions.

## Interpretation

This compares the complete game/runtime/backend stacks. On this Mac, WebGL 2
runs through Chrome's ANGLE Metal renderer and WebAssembly. Native builds use
ARM64 and can use BASIC JIT execution; browser BASIC runs in the interpreter.
Browser scheduling and readback overhead are not representative of a native
Metal API call. Minor platform UI and muted audio bookkeeping also differ.

The seeded scenes cover ten simulation seconds after warmup. They do not
represent every map, late-game battle, resolution or graphics setting. Results
from a working desktop can include background application and thermal effects;
retain the trial range and repeat the matrix when comparing optimizations.

## Recorded results

[Apple M4 Pro, November 25, 2026](benchmarks/2026-11-25-m4-pro/report.md)
contains the seven-game comparison, trial variation, browser cadence and all
37,800 measured frames. It records the exact measured commit, `e65a5dee`,
which predates the concurrent DirectX/Vulkan backend update.

[Metal allocation and render-pass investigation](benchmarks/2026-11-25-metal-performance/report.md)
records the before/after comparison, GPU timestamps, allocation counters,
remaining synchronization limitation and all 37,800 measured frames.

[GotA asynchronous Metal and throughput](gota-metal-performance.md) documents
bounded frames in flight, corrected OpenGL AO targeting, explicit sampling
parity, and the distinction between latency and completed-frame throughput.
The interrupted shared-machine timing run does not establish a winner.
