## CPU bookkeeping for upload pages retained until their submission completes.

type
  PolyworldUploadError* = object of CatchableError
  UploadPagePlan* = object
    capacity*, used*: int
  UploadPlan* = object
    pages*: seq[UploadPagePlan]
    current*: int
    generation: uint64
  UploadReservation* = object
    page*, offset*, size*, capacity*: int
    allocate*: bool
    generation: uint64

proc alignedBytes*(value, alignment: int): int =
  ## Rounds a nonnegative byte count without overflowing native integers.
  if value < 0 or alignment <= 0:
    raise newException(PolyworldUploadError, "Invalid upload alignment or size")
  let remainder = value mod alignment
  if remainder == 0:
    return value
  let padding = alignment - remainder
  if value > int.high - padding:
    raise newException(PolyworldUploadError, "Upload alignment exceeds address space")
  value + padding

proc reserveUpload*(
  plan: UploadPlan,
  size, alignment, pageBytes: int,
  pageAlignment = 1,
  replaceEmpty = false
): UploadReservation =
  ## Plans one immutable slice without consuming storage before allocation.
  if size < 0 or alignment <= 0 or pageBytes <= 0 or pageAlignment <= 0:
    raise newException(PolyworldUploadError, "Invalid upload page request")
  if plan.current < 0 or plan.current > plan.pages.len:
    raise newException(PolyworldUploadError, "Invalid upload page cursor")
  result.generation = plan.generation
  result.page = plan.current
  result.size = size
  if size == 0:
    return
  while result.page < plan.pages.len:
    let page = plan.pages[result.page]
    if page.used < 0 or page.used > page.capacity:
      raise newException(PolyworldUploadError, "Invalid upload page usage")
    result.offset = alignedBytes(page.used, alignment)
    if result.offset <= page.capacity and size <= page.capacity - result.offset:
      result.capacity = page.capacity
      return
    if replaceEmpty and page.used == 0:
      break
    inc result.page
  result.offset = 0
  result.capacity = alignedBytes(max(pageBytes, size), pageAlignment)
  result.allocate = true

proc commitUpload*(plan: var UploadPlan, reservation: UploadReservation) =
  ## Consumes a reservation after its native storage has been created safely.
  if reservation.generation != plan.generation:
    raise newException(PolyworldUploadError, "Upload reservation is stale")
  if reservation.size == 0:
    return
  if reservation.page < plan.current or reservation.page > plan.pages.len or
      reservation.offset < 0 or reservation.capacity < reservation.offset or
      reservation.size < 0 or
      reservation.size > reservation.capacity - reservation.offset:
    raise newException(PolyworldUploadError, "Invalid upload reservation")
  if reservation.page < plan.pages.len:
    let previous = plan.pages[reservation.page]
    if reservation.allocate:
      if previous.used != 0 or reservation.offset != 0:
        raise newException(PolyworldUploadError, "Upload page is still occupied")
    elif reservation.capacity != previous.capacity or
        reservation.offset < previous.used:
      raise newException(PolyworldUploadError, "Upload reservation overlaps storage")
  elif not reservation.allocate or reservation.offset != 0:
    raise newException(PolyworldUploadError, "Upload reservation has no storage")
  let page = UploadPagePlan(
    capacity: reservation.capacity,
    used: reservation.offset + reservation.size
  )
  if reservation.page == plan.pages.len:
    plan.pages.add page
  else:
    plan.pages[reservation.page] = page
  plan.current = reservation.page
  inc plan.generation

proc resetUploadPlan*(plan: var UploadPlan) =
  ## Reuses page capacity after the backend confirms submission completion.
  for page in plan.pages.mitems:
    page.used = 0
  plan.current = 0
  inc plan.generation

proc capacityBytes*(plan: UploadPlan): int =
  ## Reports retained capacity without counting per-draw slices twice.
  for page in plan.pages:
    if page.capacity < 0 or page.capacity > int.high - result:
      raise newException(PolyworldUploadError, "Upload capacity exceeds address space")
    result += page.capacity
