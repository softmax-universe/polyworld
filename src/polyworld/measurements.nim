## Shared configuration, frame accounting, and result data for benchmarks.

import std/[algorithm, json, math, monotimes, os, strutils]
import jsony
when defined(metalProfile) and defined(useMetal4):
  import backends/metal/profiles

const
  BenchmarkSchemaVersion* = 1
  BenchmarkStep* = 1.0 / 60
  BenchmarkBackend* =
    when defined(emscripten): "webgl"
    elif defined(useMetal4): "metal"
    elif defined(useVulkan): "vulkan"
    elif defined(useDirectX): "directx"
    else: "opengl"

type
  PolyworldBenchmarkError* = object of ValueError
  MeasurementMode* = enum
    Latency, Throughput, Presentation
  BenchmarkConfig* = object
    mode*: MeasurementMode
    width*, height*, samples*, warmup*, frames*: int
    fixedStepSeconds*: float64
  FrameClock* = object
    config*: BenchmarkConfig
    frames*: int
    active*: bool
    started*, previousStarted*, intervalMs*: float64
  BenchmarkGpuStats* = object
    submittedFrames*, completedFrames*, maxOutstanding*, capacity*: int
  FrameSample* = object
    frame*, tick*: int
    cpuMs*, submitMs*, gpuWaitMs*, workMs*, intervalMs*: float64
    when defined(metalProfile) and defined(useMetal4) and
        not defined(backendThroughput):
      metal*: MetalFrameProfile
  Distribution* = object
    meanMs*, medianMs*, p95Ms*, minMs*, maxMs*: float64
  BenchmarkSummary* = object
    cpu*, submit*, gpuWait*, work*, interval*: Distribution
    fpsEquivalent*: float64
  BenchmarkReport* = object
    schemaVersion*: int
    configuration*: BenchmarkConfig
    ready*, done*: bool
    game*, backend*, mode*, metric*: string
    backendId*, measurementMode*: string
    timings*: seq[string]
    width*, height*, samples*, warmup*, frames*, startTick*, endTick*: int
    fixedStepSeconds*, startupMs*, readyMs*: float64
    submittedFrames*, completedFrames*, maxOutstanding*, capacity*: int
    elapsedMs*, drainMs*, throughputFps*: float64
    framesData*: seq[FrameSample]
    summary*: BenchmarkSummary
    when defined(metalProfile) and defined(useMetal4) and
        defined(backendThroughput):
      metal*: MetalFrameProfile

proc modeName*(mode: MeasurementMode): string =
  ## Names the completion contract independently of the legacy runner.
  case mode
  of Latency: "latency"
  of Throughput: "throughput"
  of Presentation: "presentation"

proc backendLabel*(backend: string): string =
  ## Keeps display names stable for the original native benchmark runner.
  case backend
  of "opengl": "OpenGL"
  of "webgl": "WebGL"
  of "metal": "Metal"
  of "directx": "DirectX"
  of "vulkan": "Vulkan"
  else: backend

proc benchmarkConfig*(mode: MeasurementMode, width = 1280, height = 800,
    samples = 1, warmup = -1, frames = -1): BenchmarkConfig =
  ## Applies mode defaults while allowing explicit reproducible profiles.
  result = BenchmarkConfig(mode: mode, width: width, height: height,
    samples: samples, fixedStepSeconds: BenchmarkStep)
  result.warmup = if warmup >= 0: warmup else:
    (case mode
    of Latency: 120
    of Throughput: 240
    of Presentation: 180)
  result.frames = if frames >= 0: frames else:
    (case mode
    of Latency: 600
    of Throughput: 1800
    of Presentation: 180)
  if warmup < -1 or frames < -1 or
      result.width <= 0 or result.height <= 0 or
      result.samples notin [1, 2, 4, 8] or result.warmup > 100000 or
      result.frames <= 0 or result.frames > 100000:
    raise newException(PolyworldBenchmarkError, "Invalid benchmark configuration")

proc newBenchmarkReport*(config: BenchmarkConfig, game = "",
    backend = BenchmarkBackend): BenchmarkReport =
  ## Builds one result schema for every completion mode and graphics backend.
  result = BenchmarkReport(schemaVersion: BenchmarkSchemaVersion,
    configuration: config, ready: true, game: game, backend: backend,
    backendId: backend, measurementMode: config.mode.modeName,
    timings: @["workMs", "intervalMs"],
    mode: config.mode.modeName, width: config.width, height: config.height,
    samples: config.samples, warmup: config.warmup, frames: config.frames,
    fixedStepSeconds: config.fixedStepSeconds)
  result.metric = case config.mode
    of Latency: "Simulation and rendering through GPU completion; no presentation"
    of Throughput: "Completed offscreen frames / total wall time including final drain"
    of Presentation: "Presented frame cadence including event loop and final GPU drain"

proc beginMeasurement*(clock: var FrameClock, now: float64) =
  ## Starts one frame without moving the warmup or completion boundary.
  doAssert not clock.active, "Benchmark frame begun before previous frame ended"
  doAssert clock.frames < clock.config.warmup + clock.config.frames,
    "Benchmark measurement is already complete"
  clock.intervalMs =
    if clock.previousStarted == 0: 0
    else: now - clock.previousStarted
  clock.previousStarted = now
  clock.started = now
  clock.active = true

proc finishMeasurement*(clock: var FrameClock): bool =
  ## Counts a finished frame and reports whether it belongs to measurement.
  doAssert clock.active, "Benchmark frame finished without a matching begin"
  clock.active = false
  inc clock.frames
  clock.frames > clock.config.warmup

proc measurementComplete*(clock: FrameClock): bool =
  ## Reports completion only after all warmup and measured frames finish.
  clock.frames == clock.config.warmup + clock.config.frames

proc distribution*(values: seq[float64]): Distribution =
  ## Summarizes samples using nearest-rank percentiles and an averaged median.
  doAssert values.len > 0
  let ordered = values.sorted()
  for value in values:
    result.meanMs += value / values.len.float64
  result.minMs = ordered[0]
  result.maxMs = ordered[^1]
  result.medianMs = ordered[(ordered.len - 1) div 2]
  if ordered.len mod 2 == 0:
    result.medianMs = (result.medianMs + ordered[ordered.len div 2]) / 2
  result.p95Ms = ordered[max(0, int(ceil(ordered.len.float64 * 0.95)) - 1)]

proc completeReport*(report: var BenchmarkReport, tick = 0) =
  ## Aggregates identical sample fields while preserving each mode's meaning.
  doAssert report.framesData.len == report.frames
  var cpu, submit, gpuWait, work, interval: seq[float64]
  for sample in report.framesData:
    cpu.add sample.cpuMs
    submit.add sample.submitMs
    gpuWait.add sample.gpuWaitMs
    work.add sample.workMs
    if report.configuration.mode != Throughput or sample.intervalMs > 0:
      interval.add sample.intervalMs
  if interval.len == 0:
    interval.add 0
  report.endTick = tick
  report.done = true
  report.summary = BenchmarkSummary(cpu: distribution(cpu),
    submit: distribution(submit), gpuWait: distribution(gpuWait),
    work: distribution(work), interval: distribution(interval))
  case report.configuration.mode
  of Throughput:
    report.summary.fpsEquivalent = report.throughputFps
  of Presentation:
    report.summary.fpsEquivalent = 1000 / report.summary.interval.meanMs
  of Latency:
    report.summary.fpsEquivalent = 1000 / report.summary.work.meanMs

when defined(emscripten):
  proc emscriptenGetNow(): float64 {.importc: "emscripten_get_now",
    header: "<emscripten/emscripten.h>".}
    ## Reads the browser's monotonic millisecond timer.

proc benchmarkNow*(): float64 =
  ## Reads a monotonic millisecond timestamp on native and browser runtimes.
  when defined(emscripten):
    emscriptenGetNow()
  else:
    getMonoTime().ticks.float64 / 1_000_000

proc benchmarkSetting*(name: string, fallback: int): int =
  ## Reads bounded run settings from the environment or browser query.
  when defined(emscripten):
    let
      key = if name == "WARMUP": "benchWarmup" else: "benchFrames"
      keyData = key.cstring
    var value: int32
    {.emit: """
    `value` = EM_ASM_INT({
      const text = new URLSearchParams(location.search).get(UTF8ToString($0));
      if (text === null) return $1;
      const value = Number(text);
      return Number.isInteger(value) && value >= 0 && value <= 100000
        ? value : -1;
    }, `keyData`, `fallback`);
    """.}
    result = value.int
  else:
    try:
      result = parseInt(getEnv("POLYWORLD_BENCH_" & name, $fallback))
    except ValueError as error:
      raise newException(PolyworldBenchmarkError,
        "Invalid benchmark " & name & ": " & error.msg)
  if result < 0 or result > 100000 or (name == "FRAMES" and result == 0):
    raise newException(PolyworldBenchmarkError, "Invalid benchmark " & name)

proc benchmarkPayload*(report: BenchmarkReport, legacyFrame = false): string =
  ## Serializes the common schema while retaining original frame-runner aliases.
  result = report.toJson()
  if not legacyFrame:
    return
  var record = parseJson(result)
  record["backend"] = %report.backend.backendLabel
  record["mode"] = %(if report.configuration.mode == Presentation:
    "pipelined" else: "synchronized")
  record["frame_ms"] = newJArray()
  record["interval_ms"] = newJArray()
  for sample in report.framesData:
    record["frame_ms"].add %sample.workMs
    record["interval_ms"].add %sample.intervalMs
  result = $record
