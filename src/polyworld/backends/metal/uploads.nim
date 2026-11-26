## Reuses CPU-visible upload chunks without changing earlier encoded draws.

import metal4, ../../uploadplans

when defined(metalProfile):
  import profiles

const
  UploadAlignment* = 256
  UploadChunkBytes* = 1024 * 1024
  UploadRetainedBytes* = 16 * 1024 * 1024

type
  PolyworldMetalUploadError* = PolyworldUploadError
  UploadSlice* = object
    buffer*: MTLBuffer
    offset*: uint
    size*: int
  UploadChunk = object
    buffer: MTLBuffer
    address: pointer
  UploadArena* = object
    chunks: seq[UploadChunk]
    plan: UploadPlan
    allocations: uint64

proc aligned(size: int): int =
  ## Rounds a valid byte count to the shared upload alignment.
  alignedBytes(size, UploadAlignment)

proc allocate(device: MTLDevice, capacity: int): UploadChunk =
  ## Allocates one persistently mapped shared buffer owned by the arena.
  let buffer = device.newBufferWithLength(capacity.uint, 0)
  if buffer.isNil:
    raise newException(PolyworldMetalUploadError,
      "Could not allocate a Metal upload chunk")
  let address = buffer.contents()
  if address == nil:
    buffer.release()
    raise newException(PolyworldMetalUploadError,
      "Could not map a Metal upload chunk")
  when defined(metalProfile):
    profileBuffer(capacity)
  UploadChunk(buffer: buffer, address: address)

proc upload*(
  arena: var UploadArena,
  device: MTLDevice,
  data: pointer,
  size: int,
  chunkBytes = UploadChunkBytes
): UploadSlice =
  ## Copies a distinct aligned slice, preserving every earlier upload.
  let required = aligned(size)
  if size == 0:
    return
  if data == nil or device.isNil or chunkBytes <= 0:
    raise newException(PolyworldMetalUploadError,
      "Metal uploads require data, a device, and positive chunk capacity")
  let reservation = arena.plan.reserveUpload(
    required, UploadAlignment, chunkBytes, UploadAlignment, replaceEmpty = true
  )
  if reservation.allocate:
    let replacement = allocate(device, reservation.capacity)
    if reservation.page == arena.chunks.len:
      arena.chunks.add replacement
    else:
      arena.chunks[reservation.page].buffer.release()
      arena.chunks[reservation.page] = replacement
    inc arena.allocations
  let chunk = addr arena.chunks[reservation.page]
  result = UploadSlice(
    buffer: chunk.buffer, offset: reservation.offset.uint, size: size
  )
  copyMem(cast[pointer](cast[uint](chunk.address) + result.offset), data, size)
  arena.plan.commitUpload(reservation)

proc resetUploads*(arena: var UploadArena,
    retainedLimit = UploadRetainedBytes) =
  ## Recycles chunks only after all commands using their slices have completed.
  ## Previous slices become invalid; excess retained capacity is released.
  if retainedLimit < 0:
    raise newException(PolyworldMetalUploadError,
      "Metal upload retention limit cannot be negative")
  var
    count = 0
    retained = 0
  for i in 0 ..< arena.chunks.len:
    let
      chunk = arena.chunks[i]
      page = arena.plan.pages[i]
    if page.capacity <= retainedLimit - retained:
      arena.chunks[count] = chunk
      arena.plan.pages[count] = page
      inc count
      retained += page.capacity
    else:
      chunk.buffer.release()
  arena.chunks.setLen(count)
  arena.plan.pages.setLen(count)
  arena.plan.resetUploadPlan()

proc capacityBytes*(arena: UploadArena): int =
  ## Reports retained storage without counting per-draw slices twice.
  arena.plan.capacityBytes()

proc allocationCount*(arena: UploadArena): uint64 =
  ## Reports native buffer creations for allocation regression checks.
  arena.allocations

proc destroy*(arena: var UploadArena) =
  ## Releases all owned chunks after their final submitted use has completed.
  for chunk in arena.chunks:
    chunk.buffer.release()
  arena = UploadArena()
