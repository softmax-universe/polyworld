## Owns a bounded queue of submissions and their immutable upload storage.

import
  metal4,
  uploads

when defined(metalProfile):
  import profiles

const MaxFramesInFlight* = when defined(metalSynchronous): 1 else: 3

type
  PolyworldMetalSubmissionError* = object of CatchableError
  SubmissionSlot = object
    commands: MTLCommandBuffer
    uploads: UploadArena
    when defined(metalProfile):
      epoch: uint64
  SubmissionQueue* = object
    slots: array[MaxFramesInFlight, SubmissionSlot]
    pending: seq[int]
    active: bool
    activeIndex: int
    nextIndex: int

when defined(metalProfile):
  objc:
    proc GPUStartTime(self: MTLCommandBuffer): float64
    proc GPUEndTime(self: MTLCommandBuffer): float64

proc completed(commands: MTLCommandBuffer): bool =
  ## Tests terminal states without forcing the CPU to wait for the GPU.
  commands.status() >= MTLCommandBufferStatusCompleted

proc pollSubmissions*(queue: var SubmissionQueue) =
  ## Reclaims completed uploads and reports asynchronous command failures.
  var failure: system.string
  while queue.pending.len > 0:
    let index = queue.pending[0]
    let commands = queue.slots[index].commands
    if not commands.completed():
      break
    let error = commands.error()
    if not error.isNil and failure.len == 0:
      failure = messageNSError(error, "Polyworld Metal submission failed")
    elif commands.status() == MTLCommandBufferStatusError and failure.len == 0:
      failure = "Polyworld Metal submission failed without an error message"
    when defined(metalProfile):
      profileCompleteCommandBuffer(
        commands.GPUStartTime(), commands.GPUEndTime(), queue.slots[index].epoch
      )
    queue.slots[index].uploads.resetUploads()
    commands.release()
    queue.slots[index].commands = 0.MTLCommandBuffer
    queue.pending.delete(0)
  if failure.len > 0:
    raise newException(PolyworldMetalSubmissionError, failure)

proc acquireSubmission*(queue: var SubmissionQueue,
    nativeQueue: MTLCommandQueue): MTLCommandBuffer =
  ## Acquires a free slot, waiting only when the bounded queue is full.
  if queue.active:
    raise newException(PolyworldMetalSubmissionError,
      "A Metal submission is already being encoded")
  queue.pollSubmissions()
  if queue.pending.len == MaxFramesInFlight:
    let commands = queue.slots[queue.pending[0]].commands
    if not commands.completed():
      when defined(metalProfile):
        profileBackpressureWait()
      commands.waitUntilCompleted()
    queue.pollSubmissions()
  for offset in 0 ..< MaxFramesInFlight:
    let index = (queue.nextIndex + offset) mod MaxFramesInFlight
    if queue.slots[index].commands.isNil:
      result = nativeQueue.commandBuffer()
      checkNil(result, "Could not create a Metal submission")
      result.retain()
      queue.slots[index].commands = result
      queue.activeIndex = index
      queue.active = true
      queue.nextIndex = (index + 1) mod MaxFramesInFlight
      return
  raise newException(PolyworldMetalSubmissionError,
    "The Metal submission queue has no available slot")

proc uploadSubmission*(queue: var SubmissionQueue, device: MTLDevice,
    data: pointer, size: int): UploadSlice =
  ## Copies bytes into storage reserved until the active submission completes.
  if not queue.active:
    raise newException(PolyworldMetalSubmissionError,
      "Metal uploads require an active submission")
  queue.slots[queue.activeIndex].uploads.upload(device, data, size)

proc submitSubmission*(queue: var SubmissionQueue) =
  ## Commits the active slot without waiting or reusing any of its uploads.
  if not queue.active:
    return
  let index = queue.activeIndex
  when defined(metalProfile):
    queue.slots[index].epoch = profileSubmitCommandBuffer()
  queue.slots[index].commands.commit()
  queue.pending.add(index)
  queue.active = false

proc drainSubmissions*(queue: var SubmissionQueue) =
  ## Waits for all submitted commands and reclaims their upload storage.
  if queue.active:
    raise newException(PolyworldMetalSubmissionError,
      "Submit the active Metal command buffer before draining")
  if queue.pending.len > 0:
    let commands = queue.slots[queue.pending[^1]].commands
    if not commands.completed():
      when defined(metalProfile):
        profileCompletionWait()
      commands.waitUntilCompleted()
    queue.pollSubmissions()

proc pendingSubmissions*(queue: SubmissionQueue): int =
  ## Reports submitted command buffers that have not yet been reclaimed.
  queue.pending.len

proc retainedUploadBytes*(queue: SubmissionQueue): int =
  ## Reports the bounded arena capacity retained across all submission slots.
  for slot in queue.slots:
    result += slot.uploads.capacityBytes()

proc destroy*(queue: var SubmissionQueue) =
  ## Releases arenas after all encoding and submitted work have finished.
  if queue.active:
    raise newException(PolyworldMetalSubmissionError,
      "Cannot destroy a Metal queue while encoding commands")
  queue.drainSubmissions()
  for slot in queue.slots.mitems:
    slot.uploads.destroy()
  queue = SubmissionQueue()
