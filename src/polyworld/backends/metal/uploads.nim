## Reuses CPU-visible upload chunks without changing earlier encoded draws.

import metal4

when defined(metalProfile):
  import profiles

const
  UploadAlignment* = 256
  UploadChunkBytes* = 1024 * 1024
  UploadRetainedBytes* = 16 * 1024 * 1024

type
  PolyworldMetalUploadError* = object of CatchableError
  UploadSlice* = object
    buffer*: MTLBuffer
    offset*: uint
    size*: int
  UploadChunk = object
    buffer: MTLBuffer
    address: pointer
    capacity, used: int
  UploadArena* = object
    chunks: seq[UploadChunk]
    current: int
    allocations: uint64

proc aligned(size: int): int =
  ## Rounds a valid byte count to the shared upload alignment.
  if size < 0 or size > int.high - (UploadAlignment - 1):
    raise newException(PolyworldMetalUploadError, "Invalid Metal upload size")
  (size + UploadAlignment - 1) and not (UploadAlignment - 1)

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
  UploadChunk(buffer: buffer, address: address, capacity: capacity)

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
  let capacity = aligned(max(chunkBytes, required))
  while arena.current < arena.chunks.len:
    let chunk = addr arena.chunks[arena.current]
    if required <= chunk.capacity - chunk.used:
      break
    if chunk.used == 0:
      let replacement = allocate(device, capacity)
      chunk.buffer.release()
      chunk[] = replacement
      inc arena.allocations
      break
    inc arena.current
  if arena.current == arena.chunks.len:
    arena.chunks.add allocate(device, capacity)
    inc arena.allocations
  let chunk = addr arena.chunks[arena.current]
  result = UploadSlice(
    buffer: chunk.buffer, offset: chunk.used.uint, size: size
  )
  copyMem(cast[pointer](cast[uint](chunk.address) + result.offset), data, size)
  chunk.used += required

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
    var chunk = arena.chunks[i]
    if chunk.capacity <= retainedLimit - retained:
      chunk.used = 0
      arena.chunks[count] = chunk
      inc count
      retained += chunk.capacity
    else:
      chunk.buffer.release()
  arena.chunks.setLen(count)
  arena.current = 0

proc capacityBytes*(arena: UploadArena): int =
  ## Reports retained storage without counting per-draw slices twice.
  for chunk in arena.chunks:
    result += chunk.capacity

proc allocationCount*(arena: UploadArena): uint64 =
  ## Reports native buffer creations for allocation regression checks.
  arena.allocations

proc destroy*(arena: var UploadArena) =
  ## Releases all owned chunks after their final submitted use has completed.
  for chunk in arena.chunks:
    chunk.buffer.release()
  arena = UploadArena()
