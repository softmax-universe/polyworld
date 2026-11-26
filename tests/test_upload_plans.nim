import polyworld/uploadplans

template rejects(body: untyped) =
  ## Requires invalid plans to fail even in release builds.
  block:
    var rejected = false
    try:
      body
    except PolyworldUploadError:
      rejected = true
    doAssert rejected

block failedAllocation:
  var plan: UploadPlan
  let failed = plan.reserveUpload(19, 16, 64)
  doAssert failed.allocate and failed.page == 0 and failed.offset == 0
  # A backend may fail to allocate or map this page without consuming the plan.
  let retry = plan.reserveUpload(19, 16, 64)
  doAssert plan.pages.len == 0
  doAssert retry.page == failed.page and retry.offset == failed.offset
  plan.commitUpload(retry)
  doAssert plan.pages[0].used == 19
  rejects:
    plan.commitUpload(failed)
  var overlapping = plan.reserveUpload(8, 16, 64)
  overlapping.offset = 0
  rejects:
    plan.commitUpload(overlapping)
  doAssert plan.pages[0].used == 19

block immutableSlices:
  var
    plan: UploadPlan
    recorded: seq[UploadReservation]
    allocations = 0
  for size in [1, 23, 17, 128, 8, 16, 200, 1]:
    let next = plan.reserveUpload(size, 16, 64, 64)
    doAssert next.offset mod 16 == 0
    doAssert next.capacity mod 64 == 0
    for previous in recorded:
      if previous.page == next.page:
        doAssert previous.offset + previous.size <= next.offset
    if next.allocate:
      inc allocations
    plan.commitUpload(next)
    recorded.add next
  let retained = plan.capacityBytes()
  doAssert retained >= 394 and allocations > 1
  plan.resetUploadPlan()
  for index, size in [1, 23, 17, 128, 8, 16, 200, 1]:
    let next = plan.reserveUpload(size, 16, 64, 64)
    doAssert not next.allocate
    doAssert next.page == recorded[index].page
    doAssert next.offset == recorded[index].offset
    plan.commitUpload(next)
  doAssert plan.capacityBytes() == retained

block reusableEmptyPages:
  var plan: UploadPlan
  plan.commitUpload(plan.reserveUpload(32, 16, 64))
  plan.resetUploadPlan()
  let replacement = plan.reserveUpload(129, 16, 64, 64, replaceEmpty = true)
  doAssert replacement.allocate and replacement.page == 0
  doAssert replacement.capacity == 192
  doAssert plan.capacityBytes() == 64
  plan.commitUpload(replacement)
  doAssert plan.pages.len == 1 and plan.capacityBytes() == 192
  # Occupied pages cannot be replaced before their submission completes.
  let next = plan.reserveUpload(256, 16, 64, 64, replaceEmpty = true)
  doAssert next.page == 1 and next.allocate
  plan.commitUpload(next)
  doAssert plan.pages[0].used == 129

block uniformPages:
  var plan: UploadPlan
  for expected in [0, 256, 512, 768]:
    let slice = plan.reserveUpload(256, 256, 1024)
    doAssert slice.page == 0 and slice.offset == expected
    plan.commitUpload(slice)
  let overflow = plan.reserveUpload(256, 256, 1024)
  doAssert overflow.page == 1 and overflow.offset == 0
  plan.commitUpload(overflow)
  doAssert plan.pages[0].used == 1024 and plan.pages[1].used == 256
  # Non-power-of-two alignments and unpadded ranges are valid device policies.
  plan = UploadPlan()
  plan.commitUpload(plan.reserveUpload(17, 24, 96))
  let aligned = plan.reserveUpload(17, 24, 96)
  doAssert aligned.offset == 24

block invalidInputs:
  var plan: UploadPlan
  let empty = plan.reserveUpload(0, 16, 64)
  plan.commitUpload(empty)
  doAssert plan.pages.len == 0
  rejects:
    discard alignedBytes(-1, 16)
  rejects:
    discard alignedBytes(1, 0)
  rejects:
    discard alignedBytes(int.high, 2)
  rejects:
    discard plan.reserveUpload(-1, 16, 64)
  rejects:
    discard plan.reserveUpload(1, 16, 0)
  rejects:
    discard plan.reserveUpload(int.high, 16, 64, 64)
  let stale = plan.reserveUpload(1, 16, 64)
  plan.resetUploadPlan()
  rejects:
    plan.commitUpload(stale)

echo "Upload page planning, immutable slices, reuse, and failure recovery passed"
