## Opt-in latency or completed-work throughput, separate from display pace.

when defined(backendBench):
  import
    std/[algorithm, math, monotimes, os, strutils],
    jsony, vmath,
    renderer

  when defined(backendThroughput) and defined(emscripten):
    {.error: "Throughput measurement currently requires a native backend".}

  type
    FrameSample = object
      frame, tick: int
      cpuMs, submitMs, gpuWaitMs, workMs, intervalMs: float64
      when defined(metalProfile) and defined(useMetal4) and
          not defined(backendThroughput):
        metal*: MetalFrameProfile
    Distribution = object
      meanMs, medianMs, p95Ms, minMs, maxMs: float64
    BenchmarkSummary = object
      cpu, submit, gpuWait, work, interval: Distribution
      fpsEquivalent: float64
    BenchmarkReport = object
      ready, done: bool
      game, backend, mode, metric: string
      width, height, samples, warmup, frames, startTick, endTick: int
      fixedStepSeconds, startupMs, readyMs: float64
      submittedFrames, completedFrames, maxOutstanding, capacity: int
      elapsedMs, drainMs, throughputFps: float64
      framesData: seq[FrameSample]
      summary: BenchmarkSummary
      when defined(metalProfile) and defined(useMetal4) and
          defined(backendThroughput):
        metal*: MetalFrameProfile

  when defined(emscripten):
    proc emscriptenGetNow(): float64 {.importc: "emscripten_get_now",
      header: "<emscripten/emscripten.h>".}

  proc benchmarkNow(): float64 =
    ## Reads a monotonic timestamp in milliseconds on either runtime.
    when defined(emscripten):
      emscriptenGetNow()
    else:
      getMonoTime().ticks.float64 / 1_000_000

  let processStart = benchmarkNow()
  var
    report: BenchmarkReport
    initialized, active: bool
    frameCount: int
    started, previousStarted, currentInterval: float64
    windowStarted: float64

  proc benchmarkSetting(name: string, fallback: int): int =
    ## Reads bounded run settings from the environment or browser query.
    when defined(emscripten):
      let key = if name == "WARMUP": "benchWarmup" else: "benchFrames"
      let keyData = key.cstring
      var value: int32
      {.emit: """
      `value` = EM_ASM_INT({
        const text = new URLSearchParams(location.search).get(
          UTF8ToString($0));
        if (text === null) return $1;
        const value = Number(text);
        return Number.isInteger(value) && value >= 0 && value <= 100000
          ? value : -1;
      }, `keyData`, `fallback`);
      """.}
      result = value.int
    else:
      result = parseInt(getEnv("POLYWORLD_BENCH_" & name, $fallback))
    if result < 0 or result > 100000 or (name == "FRAMES" and result == 0):
      raise newException(ValueError, "Invalid benchmark " & name)

  proc publish(payload: string) =
    ## Makes completed benchmark data available to the external runner.
    when defined(emscripten):
      let data = payload.cstring
      {.emit: """
      EM_ASM({ Module.polyworldBenchmark = JSON.parse(UTF8ToString($0)); },
        `data`);
      """.}
    else:
      if report.done:
        let path = getEnv("POLYWORLD_BENCH_OUTPUT")
        if path.len > 0:
          if path.parentDir.len > 0:
            createDir(path.parentDir)
          writeFile(path, payload & "\n")
        echo "POLYWORLD_BENCH_RESULT ", payload

  proc distribution(values: seq[float64]): Distribution =
    ## Summarizes samples using nearest-rank percentiles.
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

  proc beginBenchmarkFrame*(game: string, size: IVec2) =
    ## Starts timing one complete gameplay update and render submission.
    var now = benchmarkNow()
    if not initialized:
      initialized = true
      report = BenchmarkReport(
        ready: true, game: game,
        backend: RendererBackend, mode: "latency",
        metric: "Simulation and rendering through one-pixel readback; no presentation",
        width: size.x.int, height: size.y.int, samples: BackendBenchSamples,
        fixedStepSeconds: 1.0 / 60,
        warmup: benchmarkSetting("WARMUP", 120),
        frames: benchmarkSetting("FRAMES", 600),
        startupMs: now - processStart
      )
      when defined(backendThroughput):
        report.mode = "throughput"
        report.metric = "Completed offscreen frames / total wall time including final drain"
        report.warmup = benchmarkSetting("WARMUP", 240)
        report.frames = benchmarkSetting("FRAMES", 1800)
      when defined(emscripten):
        report.readyMs = now
      publish(report.toJson())
    when defined(backendThroughput):
      if frameCount == report.warmup:
        discard drainBenchmarkGpuFrames()
        resetBenchmarkGpuStats()
        when defined(metalProfile) and defined(useMetal4):
          resetMetalProfile()
        now = benchmarkNow()
        windowStarted = now
        previousStarted = 0
    else:
      when defined(metalProfile) and defined(useMetal4):
        resetMetalProfile()
    doAssert not active, "Benchmark frame begun before previous frame ended"
    doAssert size.x.int == report.width and size.y.int == report.height,
      "Rendering dimensions changed during benchmark"
    currentInterval = if previousStarted == 0: 0 else: now - previousStarted
    previousStarted = now
    started = now
    active = true
    when defined(backendThroughput):
      beginBenchmarkGpuFrame()

  proc endBenchmarkFrame*(tick: int): bool =
    ## Records readback latency or submits work for bounded native throughput.
    if not active:
      return report.done
    let submitted = benchmarkNow()
    when defined(backendThroughput):
      submitBenchmarkGpuFrame()
    else:
      discard readFramePixel()
    let completed = benchmarkNow()
    active = false
    inc frameCount
    if frameCount > report.warmup:
      if report.framesData.len == 0:
        report.startTick = tick
      var sample = FrameSample(
        frame: frameCount, tick: tick,
        cpuMs: submitted - started,
        gpuWaitMs: completed - submitted,
        workMs: completed - started,
        intervalMs: currentInterval
      )
      when defined(backendThroughput):
        sample.submitMs = completed - submitted
        sample.gpuWaitMs = 0
      when defined(metalProfile) and defined(useMetal4) and
          not defined(backendThroughput):
        sample.metal = readMetalProfile()
      report.framesData.add(sample)
    if report.framesData.len < report.frames:
      return false
    when defined(backendThroughput):
      let
        drainStarted = benchmarkNow()
        gpu = drainBenchmarkGpuFrames()
        drained = benchmarkNow()
      report.elapsedMs = drained - windowStarted
      report.drainMs = drained - drainStarted
      report.submittedFrames = gpu.submittedFrames
      report.completedFrames = gpu.completedFrames
      report.maxOutstanding = gpu.maxOutstanding
      report.capacity = gpu.capacity
      if gpu.submittedFrames != report.frames or
          gpu.completedFrames != report.frames or
          gpu.maxOutstanding > gpu.capacity:
        raise newException(ValueError,
          "Throughput window did not complete the requested bounded work")
      report.throughputFps = gpu.completedFrames.float64 * 1000 / report.elapsedMs
      when defined(metalProfile) and defined(useMetal4):
        report.metal = readMetalProfile()
    var cpu, submit, gpuWait, work, interval: seq[float64]
    for sample in report.framesData:
      cpu.add(sample.cpuMs)
      submit.add(sample.submitMs)
      gpuWait.add(sample.gpuWaitMs)
      work.add(sample.workMs)
      when defined(backendThroughput):
        if sample.intervalMs > 0:
          interval.add(sample.intervalMs)
      else:
        interval.add(sample.intervalMs)
    if interval.len == 0:
      interval.add(0)
    report.endTick = tick
    report.done = true
    report.summary = BenchmarkSummary(
      cpu: distribution(cpu), submit: distribution(submit),
      gpuWait: distribution(gpuWait),
      work: distribution(work), interval: distribution(interval),
      fpsEquivalent: 1000 / distribution(work).meanMs
    )
    when defined(backendThroughput):
      report.summary.fpsEquivalent = report.throughputFps
    publish(report.toJson())
    true
else:
  template beginBenchmarkFrame*(game, size: untyped) =
    ## Removes benchmark instrumentation from ordinary game builds.
    discard

  template endBenchmarkFrame*(tick: untyped): bool =
    ## Leaves ordinary game loops running without benchmark overhead.
    false
