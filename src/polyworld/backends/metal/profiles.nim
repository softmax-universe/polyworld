## Opt-in counters for engine encoders and completed shared command buffers.
## Silky's internal encoders and allocations are outside the engine counters.

when defined(metalProfile):
  type MetalFrameProfile* = object
    gpuMs*: float64
    gpuTimedBuffers*, gpuUntimedBuffers*: int
    renderPasses*, emptyPasses*, drawCalls*, blitPasses*: int
    commandBuffers*, totalCommandBuffers*: int
    bufferAllocations*, bufferBytes*, uniformBytes*: int

  var
    frameProfile: MetalFrameProfile
    passDraws, totalCommandBuffers: int

  proc resetMetalProfile*() =
    ## Starts a new measurement interval without resetting lifetime submissions.
    frameProfile = MetalFrameProfile()

  proc readMetalProfile*(): MetalFrameProfile =
    ## Copies counters, including cumulative submissions outside timed intervals.
    result = frameProfile
    result.totalCommandBuffers = totalCommandBuffers

  proc profileRenderPass*() {.inline.} =
    ## Counts a new engine render encoder before its first possible draw.
    inc frameProfile.renderPasses
    passDraws = 0

  proc profileEndRenderPass*() {.inline.} =
    ## Counts passes without draw calls, including useful clear-only passes.
    if passDraws == 0:
      inc frameProfile.emptyPasses

  proc profileDraw*() {.inline.} =
    ## Counts one engine draw command regardless of instance or vertex count.
    inc frameProfile.drawCalls
    inc passDraws

  proc profileBlitPass*() {.inline.} =
    ## Counts an engine texture-copy or mipmap command encoder.
    inc frameProfile.blitPasses

  proc profileBuffer*(bytes: int) {.inline.} =
    ## Counts new engine buffers and their allocated storage capacity.
    inc frameProfile.bufferAllocations
    frameProfile.bufferBytes += bytes

  proc profileUniforms*(bytes: int) {.inline.} =
    ## Counts bound uniform bytes, a subset also uploaded through large buffers.
    frameProfile.uniformBytes += bytes

  proc profileCommandBuffer*(started, finished: float64) {.inline.} =
    ## Sums completed GPU execution spans in milliseconds without CPU waits.
    inc frameProfile.commandBuffers
    inc totalCommandBuffers
    if started > 0 and finished >= started:
      inc frameProfile.gpuTimedBuffers
      frameProfile.gpuMs += (finished - started) * 1000
    else:
      inc frameProfile.gpuUntimedBuffers
