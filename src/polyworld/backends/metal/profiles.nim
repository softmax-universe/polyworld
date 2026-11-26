## Opt-in interval and lifetime counters, updated on the renderer thread.
## Silky's internal encoders and allocations are outside the engine counters.

when defined(metalProfile):
  type MetalFrameProfile* = object
    gpuMs*: float64
    gpuTimedBuffers*, gpuUntimedBuffers*: int
    renderPasses*, emptyPasses*, drawCalls*, blitPasses*: int
    commandBuffers*, totalCommandBuffers*: int
    submittedBuffers*, pendingBuffers*: int
    backpressureWaits*, completionWaits*: int
    bufferAllocations*, bufferBytes*, uniformBytes*: int

  var
    frameProfile, lifetimeProfile: MetalFrameProfile
    currentEpoch, passEpoch: uint64
    passDraws: int

  proc resetMetalProfile*(): uint64 {.discardable.} =
    ## Starts a new interval and returns its submission attribution epoch.
    inc currentEpoch
    frameProfile = MetalFrameProfile()
    currentEpoch

  proc profileEpoch*(): uint64 {.inline.} =
    ## Returns the current interval's epoch without resetting its counters.
    currentEpoch

  proc readMetalProfile*(): MetalFrameProfile =
    ## Returns interval counters, whose pending count excludes older submissions.
    result = frameProfile
    result.totalCommandBuffers = lifetimeProfile.submittedBuffers

  proc readMetalLifetimeProfile*(): MetalFrameProfile =
    ## Returns cumulative counters and every submission still pending completion.
    result = lifetimeProfile
    result.totalCommandBuffers = lifetimeProfile.submittedBuffers

  proc profileRenderPass*() {.inline.} =
    ## Counts a new engine render encoder before its first possible draw.
    inc frameProfile.renderPasses
    inc lifetimeProfile.renderPasses
    passEpoch = currentEpoch
    passDraws = 0

  proc profileEndRenderPass*() {.inline.} =
    ## Counts passes without draw calls, including useful clear-only passes.
    if passDraws == 0:
      inc lifetimeProfile.emptyPasses
      if passEpoch == currentEpoch:
        inc frameProfile.emptyPasses

  proc profileDraw*() {.inline.} =
    ## Counts one engine draw command regardless of instance or vertex count.
    inc frameProfile.drawCalls
    inc lifetimeProfile.drawCalls
    inc passDraws

  proc profileBlitPass*() {.inline.} =
    ## Counts an engine texture-copy or mipmap command encoder.
    inc frameProfile.blitPasses
    inc lifetimeProfile.blitPasses

  proc profileBuffer*(bytes: int) {.inline.} =
    ## Counts new engine buffers and their allocated storage capacity.
    inc frameProfile.bufferAllocations
    frameProfile.bufferBytes += bytes
    inc lifetimeProfile.bufferAllocations
    lifetimeProfile.bufferBytes += bytes

  proc profileUniforms*(bytes: int) {.inline.} =
    ## Counts bound uniform bytes, a subset also uploaded through large buffers.
    frameProfile.uniformBytes += bytes
    lifetimeProfile.uniformBytes += bytes

  proc profileSubmitCommandBuffer*(): uint64 {.inline.} =
    ## Counts a submission and returns the epoch to retain until it completes.
    inc frameProfile.submittedBuffers
    inc frameProfile.pendingBuffers
    inc lifetimeProfile.submittedBuffers
    inc lifetimeProfile.pendingBuffers
    currentEpoch

  proc completeCommandBuffer(
    profile: var MetalFrameProfile, started, finished: float64
  ) {.inline.} =
    ## Records one completed submission and its available GPU execution span.
    inc profile.commandBuffers
    dec profile.pendingBuffers
    if started > 0 and finished >= started:
      inc profile.gpuTimedBuffers
      profile.gpuMs += (finished - started) * 1000
    else:
      inc profile.gpuUntimedBuffers

  proc profileCompleteCommandBuffer*(
    started, finished: float64, epoch: uint64
  ) {.inline.} =
    ## Attributes completion once to its original interval and lifetime totals.
    lifetimeProfile.completeCommandBuffer(started, finished)
    if epoch == currentEpoch:
      frameProfile.completeCommandBuffer(started, finished)

  proc profileCommandBuffer*(started, finished: float64) {.inline.} =
    ## Counts an already completed synchronous submission in the current epoch.
    let epoch = profileSubmitCommandBuffer()
    profileCompleteCommandBuffer(started, finished, epoch)

  proc profileBackpressureWait*() {.inline.} =
    ## Counts a CPU wait needed to make room for another queued submission.
    inc frameProfile.backpressureWaits
    inc lifetimeProfile.backpressureWaits

  proc profileCompletionWait*() {.inline.} =
    ## Counts a CPU wait requested for explicit completion or GPU readback.
    inc frameProfile.completionWaits
    inc lifetimeProfile.completionWaits
