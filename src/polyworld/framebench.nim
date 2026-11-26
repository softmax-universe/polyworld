## Active game-frame timings for builds made with -d:frameBench.
import windy, vmath, renderer, measurements
when not defined(emscripten): import sounds

const
  BenchWarmup* {.intdefine.} = 180
  BenchFrames* {.intdefine.} = 180
  BenchWidth* {.intdefine.} = 800
  BenchHeight* {.intdefine.} = 560
  BenchStep* = BenchmarkStep.float32
  Mode = when defined(pipelinedBench): Presentation else: Latency

static:
  doAssert BenchWarmup > 0 and BenchFrames > 0

let configuration = benchmarkConfig(Mode, BenchWidth, BenchHeight,
  warmup = BenchWarmup, frames = BenchFrames)
var
  clock = FrameClock(config: configuration)
  measurement = newBenchmarkReport(configuration)

when defined(pipelinedBench) and not defined(emscripten):
  measurement.metric = "Offscreen frame cadence including event loop and final GPU drain"

proc beginBenchFrame*(window: Window) =
  ## Starts the shared measurement clock after validating the viewport.
  doAssert window.size == ivec2(configuration.width.int32, configuration.height.int32),
    "Benchmark viewport was " & $window.size
  when not defined(emscripten):
    doAssert not window.visible, "Native benchmarks require a hidden window"
  clock.beginMeasurement(benchmarkNow())

proc report() =
  ## Publishes the common report with aliases for existing native runners.
  if not clock.measurementComplete():
    return
  measurement.completeReport()
  echo "POLYWORLD_FRAME_BENCH ", measurement.benchmarkPayload(legacyFrame = true)
  when not defined(emscripten): closeSounds()
  quit(0)

proc endBenchFrame*(window: Window) =
  ## Measures completed work before presentation without changing its timing.
  if not clock.active:
    return
  finishGpu()
  let elapsed = benchmarkNow() - clock.started
  if clock.finishMeasurement():
    measurement.framesData.add FrameSample(frame: clock.frames,
      workMs: elapsed, intervalMs: clock.intervalMs)
  report()

when defined(pipelinedBench):
  var previousPresent: float64

  proc endPresentedBenchFrame*(window: Window) =
    ## Measures presentation cadence, draining only at measurement boundaries.
    if not clock.active:
      return
    let measured = clock.finishMeasurement()
    if clock.frames == clock.config.warmup or clock.measurementComplete():
      finishGpu()
    let now = benchmarkNow()
    if measured:
      measurement.framesData.add FrameSample(frame: clock.frames,
        workMs: now - clock.started, intervalMs: now - previousPresent)
    previousPresent = now
    report()
