import
  pixie, shady, vmath, windy,
  polyworld/backends/metal/common

type PackedVertex = object
  position: Vec2
  color: array[4, uint8]

var
  sourceTexture: Uniform[Sampler2D]
  coordinate: Uniform[Vec2]

proc vertex(
  gl_Position: var Vec4, position: Vec2, packedColor: Vec4,
  vertexColor: var Vec4
) =
  ## Carries normalized packed bytes through the shared vertex description.
  gl_Position = vec4(position.x, position.y, 0.0'f, 1.0'f)
  vertexColor = packedColor

proc colorFragment(fragColor: var Vec4, vertexColor: Vec4) =
  ## Preserves the normalized attribute values for pixel verification.
  fragColor = vertexColor

proc textureFragment(fragColor: var Vec4) =
  ## Samples a uniform coordinate to distinguish sampler filtering and axes.
  fragColor = texture(sourceTexture, coordinate)

proc assertColor(actual, expected: ColorRGBX) =
  ## Allows only the rounding tolerance of normalized eight-bit storage.
  doAssert abs(actual.r.int - expected.r.int) <= 1 and
    abs(actual.g.int - expected.g.int) <= 1 and
    abs(actual.b.int - expected.b.int) <= 1 and
    abs(actual.a.int - expected.a.int) <= 1,
    "Expected " & $expected & ", got " & $actual

proc main() =
  ## Exercises shared vertex and sampling descriptions through real Metal.
  let window = newWindow("Metal shared sampling", ivec2(16), visible = false)
  initMetal(window)
  defer:
    shutdownMetal()
    window.close()
  let
    layout = VertexLayout(stride: sizeof(PackedVertex), attributes: @[
      VertexAttribute(name: "position", format: Float2,
        offset: offsetOf(PackedVertex, position)),
      VertexAttribute(name: "packedColor", format: Unorm8x4,
        offset: offsetOf(PackedVertex, color))
    ])
    vertices = newBuffer([
      PackedVertex(position: vec2(-1.0'f, -1.0'f),
        color: [64'u8, 128, 192, 255]),
      PackedVertex(position: vec2(3.0'f, -1.0'f),
        color: [64'u8, 128, 192, 255]),
      PackedVertex(position: vec2(-1.0'f, 3.0'f),
        color: [64'u8, 128, 192, 255])
    ])
    colorProgram = newProgram(toMSL(vertex, shaderVertex),
      toMSL(colorFragment, shaderFragment), layout)
    sampledProgram = newProgram(toMSL(vertex, shaderVertex),
      toMSL(textureFragment, shaderFragment), layout)
  beginFrame(16, 16, color(0, 0, 0, 1))
  draw(colorProgram, vertices, 3)
  assertColor(captureImage()[8, 8], rgbx(64, 128, 192, 255))
  endFrame(false)
  let image = newImage(2, 2)
  image[0, 0] = rgbx(255, 0, 0, 255)
  image[1, 0] = rgbx(0, 255, 0, 255)
  image[0, 1] = rgbx(0, 0, 255, 255)
  image[1, 1] = rgbx(255, 255, 255, 255)
  let texture = newTexture(image, mipmaps = true)
  sampledProgram.bindTexture("sourceTexture", texture)

  proc verify(state: SamplerState, uv: Vec2, expected: ColorRGBX) =
    ## Checks one sampler description without saving an image to disk.
    texture.setTextureSampling(state)
    sampledProgram.setUniform("coordinate", uv)
    beginFrame(16, 16, color(0, 0, 0, 1))
    draw(sampledProgram, vertices, 3)
    assertColor(captureImage()[8, 8], expected)
    endFrame(false)

  let nearest = linearSampler(linear = false, mipmaps = false)
  verify(nearest, vec2(1.25'f), rgbx(255, 255, 255, 255))
  var mixed = nearest
  mixed.wrapS = Repeat
  verify(mixed, vec2(1.25'f), rgbx(0, 0, 255, 255))
  mixed.wrapS = MirrorRepeat
  mixed.wrapT = Repeat
  verify(mixed, vec2(1.25'f), rgbx(0, 255, 0, 255))
  verify(nearest, vec2(0.4'f), rgbx(255, 0, 0, 255))
  verify(linearSampler(mipmaps = false), vec2(0.5'f),
    rgbx(128, 128, 128, 255))
  verify(linearSampler(maxAnisotropy = 99), vec2(0.5'f),
    rgbx(128, 128, 128, 255))
  echo "Metal normalized vertices, sampler axes, filtering, and limits passed"

main()
