import
  bumpy, vmath

type
  HoverState* = object
    initialized: bool
    frame: float64
    position, previousPosition: Vec2
    current, previous: seq[Rect]

proc hoverEntered*(
    state: var HoverState,
    frame: float64,
    position: Vec2,
    bounds, clip: Rect,
    enabled = true,
    blocked = false
): bool =
  ## Reports one pointer entry, retaining silent hovers during drags or disable.
  if not state.initialized:
    state.initialized = true
    state.frame = frame
    state.position = position
    state.previousPosition = position
  elif frame != state.frame:
    state.frame = frame
    state.previousPosition = state.position
    state.position = position
    swap(state.current, state.previous)
    state.current.setLen(0)

  if position.x < bounds.x or position.x >= bounds.x + bounds.w or
    position.y < bounds.y or position.y >= bounds.y + bounds.h or
    not position.overlaps(clip):
      return false
  if bounds in state.current:
    return false
  state.current.add(bounds)
  enabled and not blocked and position != state.previousPosition and
    bounds notin state.previous
