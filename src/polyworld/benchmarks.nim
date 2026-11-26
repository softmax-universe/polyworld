## Opt-in latency or completed-work throughput, separate from display pace.

when defined(backendBench):
  import
    std/os,
    vmath,
    renderer, measurements

  when defined(backendThroughput) and defined(emscripten):
    {.error: "Throughput measurement currently requires a native backend".}

  let processStart = benchmarkNow()
  var
    report: BenchmarkReport
    initialized: bool
    clock: FrameClock
    windowStarted: float64

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

  proc beginBenchmarkFrame*(game: string, size: IVec2) =
    ## Starts timing one complete gameplay update and render submission.
    var now = benchmarkNow()
    if not initialized:
      initialized = true
      const mode = when defined(backendThroughput): Throughput else: Latency
      let defaults = benchmarkConfig(mode)
      clock.config = benchmarkConfig(mode, size.x.int, size.y.int,
        BackendBenchSamples, benchmarkSetting("WARMUP", defaults.warmup),
        benchmarkSetting("FRAMES", defaults.frames))
      report = newBenchmarkReport(clock.config, game)
      report.startupMs = now - processStart
      report.timings = @["cpuMs", "workMs", "intervalMs"]
      when defined(backendThroughput):
        report.timings.add "submitMs"
      else:
        report.timings.add "gpuWaitMs"
      when not defined(backendThroughput):
        report.metric = "Simulation and rendering through one-pixel readback; no presentation"
      when defined(emscripten):
        report.readyMs = now
      publish(report.benchmarkPayload())
    when defined(backendThroughput):
      if clock.frames == report.warmup:
        discard drainBenchmarkGpuFrames()
        resetBenchmarkGpuStats()
        when defined(metalProfile) and defined(useMetal4):
          resetMetalProfile()
        now = benchmarkNow()
        windowStarted = now
        clock.previousStarted = 0
    else:
      when defined(metalProfile) and defined(useMetal4):
        resetMetalProfile()
    doAssert size.x.int == report.width and size.y.int == report.height,
      "Rendering dimensions changed during benchmark"
    clock.beginMeasurement(now)
    when defined(backendThroughput):
      beginBenchmarkGpuFrame()

  proc endBenchmarkFrame*(tick: int): bool =
    ## Records readback latency or submits work for bounded native throughput.
    if not clock.active:
      return report.done
    let submitted = benchmarkNow()
    when defined(backendThroughput):
      submitBenchmarkGpuFrame()
    else:
      discard readFramePixel()
    let completed = benchmarkNow()
    if clock.finishMeasurement():
      if report.framesData.len == 0:
        report.startTick = tick
      var sample = FrameSample(
        frame: clock.frames, tick: tick,
        cpuMs: submitted - clock.started,
        gpuWaitMs: completed - submitted,
        workMs: completed - clock.started,
        intervalMs: clock.intervalMs
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
        raise newException(PolyworldBenchmarkError,
          "Throughput window did not complete the requested bounded work")
      report.throughputFps = gpu.completedFrames.float64 * 1000 / report.elapsedMs
      when defined(metalProfile) and defined(useMetal4):
        report.metal = readMetalProfile()
    report.completeReport(tick)
    publish(report.benchmarkPayload())
    true
else:
  template beginBenchmarkFrame*(game, size: untyped) =
    ## Removes benchmark instrumentation from ordinary game builds.
    discard

  template endBenchmarkFrame*(tick: untyped): bool =
    ## Leaves ordinary game loops running without benchmark overhead.
    false
