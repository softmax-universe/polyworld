## Active game-frame timings for builds made with -d:frameBench.
import std/[json, monotimes, times]
import windy, vmath, renderer
when not defined(emscripten): import sounds

const
  BenchWarmup* {.intdefine.} = 180
  BenchFrames* {.intdefine.} = 180
  BenchWidth* {.intdefine.} = 800
  BenchHeight* {.intdefine.} = 560
  BenchStep* = 1'f32 / 60
  Backend =
    when defined(emscripten): "WebGL"
    elif defined(useMetal4): "Metal"
    elif defined(useVulkan): "Vulkan"
    elif defined(useDirectX): "DirectX"
    else: "OpenGL"

static:
  doAssert BenchWarmup > 0 and BenchFrames > 0

var
  started, previousStart: MonoTime
  intervalMs: float64
  active: bool
  frames: int
  samples, intervals: seq[float64]

proc beginBenchFrame*(window: Window) =
  doAssert window.size == ivec2(BenchWidth, BenchHeight),
    "Benchmark viewport was " & $window.size
  active = true
  previousStart = started
  started = getMonoTime()
  intervalMs = (started - previousStart).inNanoseconds.float64 * 1e-6

proc report(window: Window) =
  if samples.len == BenchFrames:
    let record = %*{"backend": Backend, "width": window.size.x, "height": window.size.y,
      "mode": (when defined(pipelinedBench): "pipelined" else: "synchronized"),
      "warmup": BenchWarmup, "frame_ms": samples, "interval_ms": intervals}
    echo "POLYWORLD_FRAME_BENCH ", $record
    when not defined(emscripten): closeSounds()
    quit(0)

proc endBenchFrame*(window: Window) =
  if not active: return
  finishGpu()
  let elapsed = (getMonoTime() - started).inNanoseconds.float64 * 1e-6
  active = false
  inc frames
  if frames > BenchWarmup:
    samples.add elapsed
    intervals.add intervalMs
  report(window)

when defined(pipelinedBench):
  var previousPresent: MonoTime

  proc endPresentedBenchFrame*(window: Window) =
    # Account for every measured frame, event-loop time, and the final drain.
    # Only the warmup boundary and final boundary synchronize the GPU.
    if not active: return
    active = false
    inc frames
    if frames == BenchWarmup or frames == BenchWarmup + BenchFrames: finishGpu()
    let now = getMonoTime()
    if frames > BenchWarmup:
      samples.add (now - started).inNanoseconds.float64 * 1e-6
      intervals.add (now - previousPresent).inNanoseconds.float64 * 1e-6
    previousPresent = now
    report(window)
