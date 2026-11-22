import
  bumpy, vmath,
  polyworld/hovers

const
  ButtonA = rect(20, 20, 100, 40)
  ButtonB = rect(140, 20, 100, 40)
  Screen = rect(0, 0, 300, 200)
  Outside = vec2(10, 10)
  InsideA = vec2(40, 40)
  InsideB = vec2(160, 40)

echo "Testing initial hover observation stays silent"
block:
  var state: HoverState
  doAssert not state.hoverEntered(0, InsideA, ButtonA, Screen)
  doAssert not state.hoverEntered(1, InsideA, ButtonA, Screen)
  doAssert not state.hoverEntered(2, vec2(50, 40), ButtonA, Screen)

echo "Testing hover entry emits once across redraws and internal movement"
block:
  var state: HoverState
  doAssert not state.hoverEntered(0, Outside, ButtonA, Screen)
  doAssert state.hoverEntered(1, InsideA, ButtonA, Screen)
  doAssert not state.hoverEntered(1, InsideA, ButtonA, Screen),
    "Registering the same control twice must not duplicate its entry."
  for frame in 2 .. 500:
    doAssert not state.hoverEntered(frame.float64, InsideA, ButtonA, Screen),
      "A sustained hover must stay silent beyond the sound cooldown."
  doAssert not state.hoverEntered(501, vec2(60, 40), ButtonA, Screen)
  doAssert not state.hoverEntered(502, vec2(90, 40), ButtonA, Screen)
  doAssert not state.hoverEntered(503, InsideA, ButtonA, Screen)

echo "Testing moving between controls and returning after an exit"
block:
  var state: HoverState
  doAssert not state.hoverEntered(0, Outside, ButtonA, Screen)
  doAssert not state.hoverEntered(0, Outside, ButtonB, Screen)
  doAssert state.hoverEntered(1, InsideA, ButtonA, Screen)
  doAssert not state.hoverEntered(1, InsideA, ButtonB, Screen)
  doAssert not state.hoverEntered(2, InsideB, ButtonA, Screen)
  doAssert state.hoverEntered(2, InsideB, ButtonB, Screen)
  doAssert not state.hoverEntered(3, InsideB, ButtonA, Screen)
  doAssert not state.hoverEntered(3, InsideB, ButtonB, Screen)
  doAssert not state.hoverEntered(4, Outside, ButtonA, Screen)
  doAssert not state.hoverEntered(4, Outside, ButtonB, Screen)
  doAssert not state.hoverEntered(5, InsideA, ButtonB, Screen)
  doAssert state.hoverEntered(5, InsideA, ButtonA, Screen)
  doAssert not state.hoverEntered(5, InsideA, ButtonA, Screen)

echo "Testing adjacent controls share no hover boundary"
block:
  const Adjacent = rect(120, 20, 100, 40)
  var state: HoverState
  doAssert not state.hoverEntered(0, Outside, ButtonA, Screen)
  doAssert not state.hoverEntered(0, Outside, Adjacent, Screen)
  doAssert not state.hoverEntered(1, vec2(120, 40), ButtonA, Screen)
  doAssert state.hoverEntered(1, vec2(120, 40), Adjacent, Screen),
    "A shared horizontal edge belongs only to the control on its right."
  doAssert state.hoverEntered(2, vec2(119, 40), ButtonA, Screen)
  doAssert not state.hoverEntered(2, vec2(119, 40), Adjacent, Screen)
  doAssert not state.hoverEntered(3, vec2(119, 60), ButtonA, Screen),
    "The bottom edge lies outside the control."
  doAssert state.hoverEntered(4, vec2(119, 59), ButtonA, Screen)

echo "Testing enabling a hovered control does not generate a late entry"
block:
  var state: HoverState
  doAssert not state.hoverEntered(0, Outside, ButtonA, Screen)
  doAssert not state.hoverEntered(
    1, InsideA, ButtonA, Screen, enabled = false
  )
  doAssert not state.hoverEntered(2, InsideA, ButtonA, Screen)
  doAssert not state.hoverEntered(3, vec2(50, 40), ButtonA, Screen)
  doAssert not state.hoverEntered(4, Outside, ButtonA, Screen)
  doAssert state.hoverEntered(5, InsideA, ButtonA, Screen)

echo "Testing blocked pointer entry stays silent after a drag release"
block:
  var state: HoverState
  doAssert not state.hoverEntered(0, Outside, ButtonA, Screen)
  doAssert not state.hoverEntered(
    1, InsideA, ButtonA, Screen, blocked = true
  )
  doAssert not state.hoverEntered(
    2, vec2(60, 40), ButtonA, Screen, blocked = true
  )
  doAssert not state.hoverEntered(3, vec2(60, 40), ButtonA, Screen)
  doAssert not state.hoverEntered(4, InsideA, ButtonA, Screen)
  doAssert not state.hoverEntered(5, Outside, ButtonA, Screen)
  doAssert state.hoverEntered(6, InsideA, ButtonA, Screen)

echo "Testing consumed hover does not replay from another registration"
block:
  var state: HoverState
  doAssert not state.hoverEntered(0, Outside, ButtonA, Screen)
  doAssert not state.hoverEntered(
    1, InsideA, ButtonA, Screen, blocked = true
  )
  doAssert not state.hoverEntered(1, InsideA, ButtonA, Screen)
  doAssert not state.hoverEntered(2, vec2(60, 40), ButtonA, Screen)
  doAssert not state.hoverEntered(3, Outside, ButtonA, Screen)
  doAssert state.hoverEntered(4, InsideA, ButtonA, Screen)

echo "Testing clipped controls only sound on visible pointer entry"
block:
  const Clip = rect(70, 20, 50, 40)
  var state: HoverState
  doAssert not state.hoverEntered(0, Outside, ButtonA, Clip)
  doAssert not state.hoverEntered(1, InsideA, ButtonA, Clip)
  doAssert state.hoverEntered(2, vec2(80, 40), ButtonA, Clip)
  doAssert not state.hoverEntered(3, vec2(90, 40), ButtonA, Clip)
  doAssert not state.hoverEntered(4, InsideA, ButtonA, Clip)
  doAssert state.hoverEntered(5, vec2(80, 40), ButtonA, Clip)

echo "Testing clip and layout changes beneath a stationary pointer stay silent"
block:
  const Clip = rect(70, 20, 50, 40)
  var state: HoverState
  doAssert not state.hoverEntered(0, Outside, ButtonA, Clip)
  doAssert not state.hoverEntered(1, InsideA, ButtonA, Clip)
  doAssert not state.hoverEntered(2, InsideA, ButtonA, Screen)
  doAssert not state.hoverEntered(3, vec2(50, 40), ButtonA, Screen)
  doAssert not state.hoverEntered(4, vec2(50, 40), ButtonB, Screen)
  doAssert not state.hoverEntered(5, vec2(50, 40), ButtonA, Screen)
  doAssert not state.hoverEntered(6, InsideA, ButtonA, Screen)

echo "Testing disappeared controls can receive a fresh pointer entry"
block:
  var state: HoverState
  doAssert not state.hoverEntered(0, Outside, ButtonA, Screen)
  doAssert state.hoverEntered(1, InsideA, ButtonA, Screen)
  doAssert not state.hoverEntered(2, Outside, ButtonB, Screen)
  doAssert state.hoverEntered(3, InsideA, ButtonA, Screen)

echo "PASS hover sounds play only on pointer entry"
