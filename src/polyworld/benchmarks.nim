## Opt-in synchronized gameplay timing, separate from loading and display pace.

when defined(backendBench):
  import
    std/[algorithm, math, monotimes, os, strutils],
    jsony, vmath,
    renderer

  type
    FrameSample = object
      frame, tick: int
      cpuMs, gpuWaitMs, workMs, intervalMs: float64
    Distribution = object
      meanMs, medianMs, p95Ms, minMs, maxMs: float64
    BenchmarkSummary = object
      cpu, gpuWait, work, interval: Distribution
      fpsEquivalent: float64
    BenchmarkReport = object
      ready, done: bool
      game, backend, metric: string
      width, height, samples, warmup, frames, startTick, endTick: int
      fixedStepSeconds, startupMs, readyMs: float64
      framesData: seq[FrameSample]
      summary: BenchmarkSummary

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
    let now = benchmarkNow()
    if not initialized:
      initialized = true
      report = BenchmarkReport(
        ready: true, game: game,
        backend: RendererBackend,
        metric: "Simulation and rendering through one-pixel readback; no presentation",
        width: size.x.int, height: size.y.int, samples: 1,
        fixedStepSeconds: 1.0 / 60,
        warmup: benchmarkSetting("WARMUP", 120),
        frames: benchmarkSetting("FRAMES", 600),
        startupMs: now - processStart
      )
      when defined(emscripten):
        report.readyMs = now
      publish(report.toJson())
    doAssert not active, "Benchmark frame begun before previous frame ended"
    doAssert size.x.int == report.width and size.y.int == report.height,
      "Rendering dimensions changed during benchmark"
    currentInterval = if previousStarted == 0: 0 else: now - previousStarted
    previousStarted = now
    started = now
    active = true

  proc endBenchmarkFrame*(tick: int): bool =
    ## Waits for GPU completion, then records work excluding display pacing.
    if not active:
      return report.done
    let submitted = benchmarkNow()
    discard readFramePixel()
    let completed = benchmarkNow()
    active = false
    inc frameCount
    if frameCount > report.warmup:
      if report.framesData.len == 0:
        report.startTick = tick
      report.framesData.add FrameSample(
        frame: frameCount, tick: tick,
        cpuMs: submitted - started,
        gpuWaitMs: completed - submitted,
        workMs: completed - started,
        intervalMs: currentInterval
      )
    if report.framesData.len < report.frames:
      return false
    var cpu, gpuWait, work, interval: seq[float64]
    for sample in report.framesData:
      cpu.add(sample.cpuMs)
      gpuWait.add(sample.gpuWaitMs)
      work.add(sample.workMs)
      interval.add(sample.intervalMs)
    report.endTick = tick
    report.done = true
    report.summary = BenchmarkSummary(
      cpu: distribution(cpu), gpuWait: distribution(gpuWait),
      work: distribution(work), interval: distribution(interval),
      fpsEquivalent: 1000 / distribution(work).meanMs
    )
    publish(report.toJson())
    true
else:
  template beginBenchmarkFrame*(game, size: untyped) =
    ## Removes benchmark instrumentation from ordinary game builds.
    discard

  template endBenchmarkFrame*(tick: untyped): bool =
    ## Leaves ordinary game loops running without benchmark overhead.
    false
