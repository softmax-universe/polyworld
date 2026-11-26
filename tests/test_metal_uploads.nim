## Checks upload immutability, aligned offsets, reuse, and retention limits.

import
  metal4,
  polyworld/backends/metal/uploads

proc bytes(slice: UploadSlice): ptr UncheckedArray[byte] =
  ## Borrows the bytes of one CPU-visible upload slice for exact checks.
  cast[ptr UncheckedArray[byte]](
    cast[uint](slice.buffer.contents()) + slice.offset
  )

let device = MTLCreateSystemDefaultDevice()
doAssert not device.isNil
var arena: UploadArena

block immutableSlices:
  var firstData: array[5000, byte]
  for i in 0 ..< firstData.len:
    firstData[i] = byte(i mod 251)
  let first = arena.upload(device, firstData[0].addr, firstData.len, 16_384)
  var secondData: array[6000, byte]
  for i in 0 ..< secondData.len:
    secondData[i] = byte(250 - i mod 251)
  let second = arena.upload(device, secondData[0].addr, secondData.len, 16_384)
  doAssert first.buffer.uint == second.buffer.uint
  doAssert first.offset == 0
  doAssert second.offset mod UploadAlignment.uint == 0
  doAssert second.offset >= first.offset + first.size.uint
  doAssert arena.allocationCount == 1
  for i, value in firstData:
    doAssert first.bytes[i] == value
  for i, value in secondData:
    doAssert second.bytes[i] == value
  firstData[0] = 255
  secondData[0] = 255
  doAssert first.bytes[0] == 0
  doAssert second.bytes[0] == 250

  let third = arena.upload(device, secondData[0].addr, secondData.len, 16_384)
  doAssert third.buffer.uint != first.buffer.uint
  doAssert arena.capacityBytes == 32_768
  doAssert arena.allocationCount == 2
  doAssert first.bytes[0] == 0
  doAssert second.bytes[0] == 250
  doAssert third.bytes[0] == 255

  arena.resetUploads()
  for _ in 0 ..< 100:
    discard arena.upload(device, firstData[0].addr, firstData.len, 16_384)
    discard arena.upload(device, secondData[0].addr, secondData.len, 16_384)
    discard arena.upload(device, secondData[0].addr, secondData.len, 16_384)
    arena.resetUploads()
  doAssert arena.capacityBytes == 32_768
  doAssert arena.allocationCount == 2

block retainedCapacity:
  arena.resetUploads(retainedLimit = 16_384)
  doAssert arena.capacityBytes == 16_384
  var larger: array[40_000, byte]
  let slice = arena.upload(device, larger[0].addr, larger.len, 16_384)
  doAssert slice.size == larger.len
  doAssert arena.allocationCount == 3
  doAssert arena.capacityBytes < 40_000 + UploadAlignment
  arena.resetUploads(retainedLimit = 16_384)
  doAssert arena.capacityBytes == 0

block invalidInputs:
  doAssert arena.upload(device, nil, 0).buffer.isNil
  for size in [-1, 1, int.high]:
    var rejected = false
    try:
      discard arena.upload(device, nil, size)
    except PolyworldMetalUploadError:
      rejected = true
    doAssert rejected

arena.destroy()
arena.destroy()
doAssert arena.capacityBytes == 0
device.release()
echo "Metal upload slices, bounded retention, and buffer reuse passed"
