## Deterministic pointer capture shared by the shop and its native fixtures.
## Target ids 0..5 are inventory slots; all other ids are caller-owned controls.
type
  ShopPointerFrame* = object
    target*: int
    x*, y*: float32
    leftPressed*, leftDown*, leftReleased*: bool
    rightPressed*, rightDown*, rightReleased*: bool
  ShopGestureKind* = enum
    ShopNoGesture, ShopClickGesture, ShopContextGesture, ShopSwapGesture
  ShopGesture* = object
    kind*: ShopGestureKind
    source*, target*: int
  ShopGestureState* = object
    leftCapture, rightCapture: int # target + 1; zero means no capture
    startX, startY: float32
    dragged*: bool

proc resetShopGesture*(state: var ShopGestureState) =
  state = ShopGestureState()

proc draggingShopSlot*(state: ShopGestureState): int =
  if state.dragged and state.leftCapture in 1..6: state.leftCapture - 1
  else: -1

proc updateShopGesture*(state: var ShopGestureState, frame: ShopPointerFrame,
    occupied: openArray[bool], allowed: bool): ShopGesture =
  if not allowed:
    state.resetShopGesture()
    return
  if frame.leftPressed:
    state.leftCapture = max(0, frame.target + 1)
    state.startX = frame.x
    state.startY = frame.y
    state.dragged = false
    state.rightCapture = 0
  if state.leftCapture > 0:
    let dx = frame.x - state.startX
    let dy = frame.y - state.startY
    if dx * dx + dy * dy >= 36: state.dragged = true
    if frame.leftReleased:
      let source = state.leftCapture - 1
      if state.dragged:
        if source in 0..<min(6, occupied.len) and occupied[source] and
            frame.target in 0..5 and frame.target != source:
          result = ShopGesture(kind: ShopSwapGesture, source: source,
            target: frame.target)
      elif frame.target == source:
        result = ShopGesture(kind: ShopClickGesture, source: source,
          target: frame.target)
      state.leftCapture = 0
      state.dragged = false
    elif not frame.leftDown:
      state.leftCapture = 0
      state.dragged = false
  if frame.rightPressed:
    state.leftCapture = 0
    state.dragged = false
    state.rightCapture = 0
    if frame.target in 0..<min(6, occupied.len) and occupied[frame.target]:
      state.rightCapture = frame.target + 1
  if state.rightCapture > 0:
    if frame.rightReleased:
      let source = state.rightCapture - 1
      if frame.target == source and occupied[source]:
        result = ShopGesture(kind: ShopContextGesture, source: source,
          target: source)
      state.rightCapture = 0
    elif not frame.rightDown:
      state.rightCapture = 0
