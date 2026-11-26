import pixie, shady, vmath

const
  FixtureSize* = 64
  TriangleVertices* = [-1.0'f, -1, 1, -1, 0, 1]
  FullscreenVertices* = [-1.0'f, -1, 3, -1, -1, 3]
  LeftVertices* = [-1.0'f, -1, 0, -1, 0, 1, -1, -1, 0, 1, -1, 1]
  RightVertices* = [0.0'f, -1, 1, -1, 1, 1, 0, -1, 1, 1, 0, 1]

var
  tint*: Uniform[Vec4]
  sourceTexture*: Uniform[Sampler2D]
  sampleUv*: Uniform[Vec2]

proc vertex*(gl_Position: var Vec4, position: Vec2) =
  ## Places the shared conformance geometry in clip space.
  gl_Position = vec4(position.x, position.y, 0, 1)

proc fragment*(fragColor: var Vec4) =
  ## Emits a uniform color for pixel verification on every backend.
  fragColor = tint

proc textureFragment*(fragColor: var Vec4) =
  ## Samples an explicitly selected coordinate for upload-ordering checks.
  fragColor = texture(sourceTexture, sampleUv)

proc verifyPixel*(image: Image, x, y: int, expected: ColorRGBX) =
  ## Compares a fully covered pixel with a small normalized-format tolerance.
  let actual = image[x, y]
  doAssert abs(actual.r.int - expected.r.int) <= 5 and
    abs(actual.g.int - expected.g.int) <= 5 and
    abs(actual.b.int - expected.b.int) <= 5 and
    abs(actual.a.int - expected.a.int) <= 5,
      "Unexpected pixel at " & $x & ", " & $y & ": " & $actual

proc verifyTriangle*(image: Image, expected: ColorRGBX) =
  ## Checks the shared triangle's filled center and untouched corner.
  doAssert image.width == FixtureSize and image.height == FixtureSize
  image.verifyPixel(FixtureSize div 2, FixtureSize div 2, expected)
  image.verifyPixel(0, 0, rgbx(0, 0, 0, 255))

proc verifySplit*(image: Image, left, right: ColorRGBX) =
  ## Checks that two ordered draws retain independent uniform or texture data.
  image.verifyPixel(image.width div 4, image.height div 2, left)
  image.verifyPixel(image.width * 3 div 4, image.height div 2, right)
