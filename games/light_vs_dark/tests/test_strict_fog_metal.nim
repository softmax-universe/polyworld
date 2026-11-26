## Real Metal depth capture and current-sight composite regression.

when not defined(useMetal4):
  {.error: "Compile this regression with -d:useMetal4.".}

import
  pixie, shady, vmath, windy,
  polyworld/backends/metal/common,
  ../strictfog

const Size = 64
const Side = 4

proc fixtureVertex(gl_Position: var Vec4) =
  ## Covers the screen with actual depth-writing geometry.
  let position = vec2(
    float32((gl_VertexID mod 2) * 2),
    float32((gl_VertexID div 2) * 2)
  )
  gl_Position = vec4(position * 2.0'f - 1.0'f, vec2(0.0'f, 1.0'f))

proc fixtureFragment(value: Uniform[Vec4], outputColor: var Vec4) =
  ## Emits one known fixture color for pixel comparisons.
  outputColor = value

let window = newWindow("Metal strict fog", ivec2(Size),
  visible = false, vsync = false)
initMetal(window)
let fixture = newProgram(
  toShader(fixtureVertex, metalMSL, shaderVertex),
  toShader(fixtureFragment, metalMSL, shaderFragment)
)
var fog = initStrictFog()
var sight = newSeq[uint8](Side * Side)
for y in 2 ..< Side:
  for x in 2 ..< Side:
    sight[y * Side + x] = 255
var inverse = mat4()
inverse[1, 1] = 0
inverse[2, 1] = 1
inverse[1, 2] = 1
inverse[2, 2] = 0

proc frame(values: seq[uint8], directCapture = true): Image =
  ## Captures ground then composites an asymmetric visible quadrant.
  beginFrame(Size, Size, color(0, 0, 0, 1))
  if directCapture:
    fog.beginStrictGround(ivec2(Size))
    clear(color(0, 0, 0, 1))
  fixture.setUniform("value", vec4(0.1, 0.2, 0.3, 1))
  draw(fixture, nil, 3, DrawState(depthTest: true, depthWrite: true))
  fog.captureStrictGround(ivec2(Size), inverse, values, Side)
  clear(color(1, 0, 0, 1), depth = false)
  fog.restoreHiddenGround()
  result = captureImage()
  endFrame(false)

proc checkQuadrants(image: Image) =
  ## Checks depth reconstruction and native upper-left texture coordinates.
  let
    hiddenLeft = image[16, 16]
    visibleTop = image[48, 16]
    hiddenBottom = image[48, 48]
  doAssert hiddenLeft.r < 30 and hiddenLeft.b > 70,
    "Hidden left pixels must restore the ground."
  doAssert visibleTop.r == 255 and visibleTop.b == 0,
    "Visible upper-right effects must remain."
  doAssert hiddenBottom.r < 30 and hiddenBottom.b > 70,
    "Hidden lower-right pixels must restore without a vertical flip."

checkQuadrants(frame(sight))
checkQuadrants(frame(sight, directCapture = false))
for value in sight.mitems:
  value = 255
let revealed = frame(sight)
doAssert revealed[16, 16].r == 255,
  "Sight restoration must reveal effects immediately."
for value in sight.mitems:
  value = 0
let hidden = frame(sight)
doAssert hidden[48, 16].r < 30,
  "Same-tick sight loss must hide effects immediately."
fog.closeStrictFog()
destroy(fixture)
shutdownMetal()
window.close()
echo "Metal strict fog: depth, quadrants, capture modes and transitions passed."
