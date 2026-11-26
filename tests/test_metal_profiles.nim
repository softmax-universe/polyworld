## Checks asynchronous profile attribution without creating a GPU context.

when not defined(metalProfile):
  {.error: "Run this CPU-only test with -d:metalProfile.".}

import polyworld/backends/metal/profiles

let firstEpoch = resetMetalProfile()
doAssert profileEpoch() == firstEpoch
profileRenderPass()
let oldSubmission = profileSubmitCommandBuffer()
doAssert oldSubmission == firstEpoch

let secondEpoch = resetMetalProfile()
doAssert secondEpoch != firstEpoch
profileEndRenderPass()
let newSubmission = profileSubmitCommandBuffer()
doAssert newSubmission == secondEpoch

profileCompleteCommandBuffer(1.0, 1.25, oldSubmission)
let pending = readMetalProfile()
doAssert pending.submittedBuffers == 1
doAssert pending.pendingBuffers == 1
doAssert pending.commandBuffers == 0
doAssert pending.gpuTimedBuffers == 0
doAssert pending.gpuMs == 0.0
doAssert pending.emptyPasses == 0
doAssert readMetalLifetimeProfile().pendingBuffers == 1

profileCompleteCommandBuffer(2.0, 2.5, newSubmission)
profileCommandBuffer(0.0, 0.0)
let interval = readMetalProfile()
doAssert interval.submittedBuffers == 2
doAssert interval.commandBuffers == 2
doAssert interval.pendingBuffers == 0
doAssert interval.gpuTimedBuffers == 1
doAssert interval.gpuUntimedBuffers == 1
doAssert interval.gpuMs == 500.0
doAssert interval.totalCommandBuffers == 3

let lifetime = readMetalLifetimeProfile()
doAssert lifetime.submittedBuffers == 3
doAssert lifetime.commandBuffers == 3
doAssert lifetime.pendingBuffers == 0
doAssert lifetime.gpuTimedBuffers == 2
doAssert lifetime.gpuUntimedBuffers == 1
doAssert lifetime.gpuMs == 750.0
doAssert lifetime.renderPasses == 1
doAssert lifetime.emptyPasses == 1

echo "Metal profile epoch accounting passed"
