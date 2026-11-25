## Compile with -d:gpuCounters to inspect steady-state native frame traffic.
when defined(gpuCounters):
  import std/[times, monotimes]
  var draws*, submits*, bufferCreates*, textureCreates*, drawVertices*, uploadedBytes*, passCount*, barriers*: int
  var waitNs*: int64
  proc reportGpuCounts*() =
    echo "GPU counts: draws=", draws, " vertices=", drawVertices, " submissions=", submits,
      " buffers=", bufferCreates, " textures=", textureCreates, " bytes=", uploadedBytes,
      " passes=", passCount, " barriers=", barriers, " wait_ms=", waitNs.float / 1e6
    draws = 0
    submits = 0
    bufferCreates = 0
    textureCreates = 0
    drawVertices = 0
    uploadedBytes = 0
    passCount = 0
    barriers = 0
    waitNs = 0

template counted*(body: untyped) =
  when defined(gpuCounters): body

template timedWait*(body: untyped) =
  when defined(gpuCounters):
    let before = getMonoTime()
    body
    waitNs += (getMonoTime() - before).inNanoseconds
  else: body
