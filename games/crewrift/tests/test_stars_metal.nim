## Real Metal regression for shared night-sky shaders and depth behavior.

when not defined(useMetal4):
  {.error: "Compile this regression with -d:useMetal4.".}

import
  pixie, shady, vmath, windy,
  polyworld/backends/metal/common,
  ../stars

const Size = 64

proc foregroundVertex(gl_Position: var Vec4) =
  ## Places a foreground triangle in front of the sky's far plane.
  let point = vec2(
    float32((gl_VertexID mod 2) * 2),
    float32((gl_VertexID div 2) * 2)
  )
  gl_Position = vec4(point * 2.0'f - 1.0'f, vec2(0, 1))

proc foregroundFragment(outputColor: var Vec4) =
  ## Emits the exact foreground color used for depth assertions.
  outputColor = vec4(1, 0, 0, 1)

let window = newWindow("Metal star field", ivec2(Size),
  visible = false, vsync = false)
initMetal(window)
var field = initStarField()
let foreground = newProgram(
  toShader(foregroundVertex, metalMSL, shaderVertex),
  toShader(foregroundFragment, metalMSL, shaderFragment)
)
beginFrame(Size, Size, color(0, 0, 0, 1))
field.draw(mat4(), vec3(0, 0, -1), 0)
let first = captureImage()
endFrame(false)
var lit = 0
for pixel in first.data:
  if pixel.r > 0 or pixel.g > 0 or pixel.b > 0:
    inc lit
doAssert lit == Size * Size, "The sky must shade every background pixel."
beginFrame(Size, Size, color(0, 0, 0, 1))
field.draw(mat4(), vec3(0, 0, -1), 5)
let animated = captureImage()
endFrame(false)
var changed = 0
for i, pixel in first.data:
  if pixel != animated.data[i]:
    inc changed
doAssert changed > 0, "Replay time must animate the star field."
beginFrame(Size, Size, color(0, 0, 0, 1))
draw(foreground, nil, 3, DrawState(depthTest: true, depthWrite: true))
field.draw(mat4(), vec3(0, 0, -1), 0)
let occluded = captureImage()
endFrame(false)
for pixel in occluded.data:
  doAssert pixel == rgbx(255, 0, 0, 255),
    "The sky must preserve foreground depth."
field.close()
destroy(foreground)
shutdownMetal()
window.close()
echo "Metal stars: background coverage, replay animation and depth passed."
