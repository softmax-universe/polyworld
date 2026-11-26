## Verifies shared measurement boundaries and both public result protocols.
import std/json
import polyworld/measurements

let latency = benchmarkConfig(Latency, warmup = 2, frames = 3)
var
  clock = FrameClock(config: latency)
  report = newBenchmarkReport(latency, "fixture", "metal")
for frame in 1 .. 5:
  clock.beginMeasurement(100.0 + frame.float64 * 10)
  if clock.finishMeasurement():
    report.framesData.add FrameSample(frame: clock.frames, tick: frame,
      cpuMs: 5, gpuWaitMs: 15, workMs: 20, intervalMs: clock.intervalMs)
  doAssert clock.measurementComplete() == (frame == 5)
doAssert report.framesData.len == 3
doAssert report.framesData[0].frame == 3
report.completeReport(5)
doAssert report.done and report.endTick == 5
doAssert report.summary.work.meanMs == 20
doAssert report.summary.interval.medianMs == 10
doAssert report.summary.fpsEquivalent == 50
let payload = parseJson(report.benchmarkPayload())
doAssert payload["schemaVersion"].getInt == BenchmarkSchemaVersion
doAssert payload["backend"].getStr == "metal"
doAssert payload["measurementMode"].getStr == "latency"
doAssert payload["framesData"].len == 3
doAssert payload["warmup"].getInt == 2
let legacy = parseJson(report.benchmarkPayload(legacyFrame = true))
doAssert legacy["backend"].getStr == "Metal"
doAssert legacy["backendId"].getStr == "metal"
doAssert legacy["mode"].getStr == "synchronized"
doAssert legacy["measurementMode"].getStr == "latency"
doAssert legacy["frame_ms"].len == legacy["framesData"].len
for i, sample in report.framesData:
  doAssert legacy["frame_ms"][i].getFloat == sample.workMs
  doAssert legacy["interval_ms"][i].getFloat == sample.intervalMs

let throughput = benchmarkConfig(Throughput, warmup = 0, frames = 2)
var throughputClock = FrameClock(config: throughput)
for i in 0 ..< 2:
  throughputClock.beginMeasurement(50.0 + i.float64 * 5)
  doAssert throughputClock.finishMeasurement()
doAssert throughputClock.measurementComplete()
var completed = newBenchmarkReport(throughput)
completed.framesData = @[
  FrameSample(frame: 1, workMs: 1, submitMs: 0.5, intervalMs: 0),
  FrameSample(frame: 2, workMs: 1, submitMs: 0.5, intervalMs: 5)
]
completed.throughputFps = 125
completed.completeReport()
doAssert completed.summary.fpsEquivalent == 125
# Throughput submission work is not completed-frame latency.
doAssert completed.summary.work.meanMs == 1
doAssert completed.summary.interval.meanMs == 5

var presented = newBenchmarkReport(benchmarkConfig(Presentation,
  warmup = 1, frames = 2))
presented.framesData = @[
  FrameSample(frame: 2, workMs: 2, intervalMs: 20),
  FrameSample(frame: 3, workMs: 3, intervalMs: 30)
]
presented.completeReport()
doAssert presented.summary.fpsEquivalent == 40
let presentedLegacy = parseJson(presented.benchmarkPayload(legacyFrame = true))
doAssert presentedLegacy["mode"].getStr == "pipelined"
doAssert presentedLegacy["measurementMode"].getStr == "presentation"
doAssert presentedLegacy["interval_ms"][1].getFloat == 30

for config in [benchmarkConfig(Latency), benchmarkConfig(Throughput),
    benchmarkConfig(Presentation)]:
  doAssert config.fixedStepSeconds == BenchmarkStep
  doAssert config.frames > 0 and config.warmup >= 0
for invalid in [0, 100001]:
  var rejected = false
  try:
    discard benchmarkConfig(Latency, frames = invalid)
  except ValueError:
    rejected = true
  doAssert rejected
let stats = distribution(@[40.0, 10.0, 30.0, 20.0])
doAssert stats.meanMs == 25 and stats.medianMs == 25
# Nearest-rank P95 includes the tail of a short sample set.
doAssert stats.p95Ms == 40 and stats.minMs == 10 and stats.maxMs == 40
echo "Shared benchmark timing, configuration and result contracts passed"
