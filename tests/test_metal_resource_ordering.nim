## Checks immutable vertex and uniform data across draws in one submission.

import
  pixie, shady, vmath, windy,
  polyworld/backends/metal/common

var
  palette: Uniform[array[300, Vec4]]
  paletteIndex: Uniform[int32]
  tint: Uniform[Vec4]

proc vertex(position: Vec2, gl_Position: var Vec4) =
  ## Places one independently uploaded rectangle in clip space.
  gl_Position = vec4(position, vec2(0, 1))

proc fragment(fragColor: var Vec4) =
  ## Reads both a small uniform and a block larger than Metal's inline limit.
  fragColor = palette[paletteIndex] * tint

proc rectangle(left, right: float32): array[6, Vec2] =
  ## Returns the vertices for one half of the render target.
  [vec2(left, -1), vec2(right, -1), vec2(right, 1),
    vec2(left, -1), vec2(right, 1), vec2(left, 1)]

let window = newWindow("Metal resource ordering", ivec2(16, 16),
  visible = false)
initMetal(window)
let
  program = newProgram(
    toShader(vertex, metalMSL, shaderVertex),
    toShader(fragment, metalMSL, shaderFragment),
    VertexLayout(stride: sizeof(Vec2), attributes: @[
      VertexAttribute(name: "position", format: Float2, offset: 0)
    ])
  )
  vertices = newBuffer(rectangle(-1, 0))
var colors: array[300, Vec4]
program.setUniform("paletteIndex", 299'i32)
for changePalette in [false, true]:
  beginFrame(16, 16, color(0, 0, 0, 1))
  vertices.updateBuffer(rectangle(-1, 0))
  colors[299] = if changePalette: vec4(1, 0, 0, 1) else: vec4(1)
  program.setUniform("palette", colors)
  program.setUniform("tint", if changePalette: vec4(1) else: vec4(1, 0, 0, 1))
  draw(program, vertices, 6)
  vertices.updateBuffer(rectangle(0, 1))
  if changePalette:
    colors[299] = vec4(0, 1, 0, 1)
    program.setUniform("palette", colors)
  else:
    program.setUniform("tint", vec4(0, 1, 0, 1))
  draw(program, vertices, 6)
  endFrame(false)
  let image = captureImage()
  for y in 0 ..< image.height:
    for x in 0 ..< image.width:
      let expected = if x < 8: rgbx(255, 0, 0, 255) else: rgbx(0, 255, 0, 255)
      doAssert image[x, y] == expected,
        "Later vertex and uniform uploads must not change earlier draws"
shutdownMetal()
window.close()
echo "Metal vertex and large-uniform draw ordering passed"
