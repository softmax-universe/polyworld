## Checks queued rendering, upload snapshots, and shutdown without frame waits.

import
  pixie, shady, vmath, windy,
  polyworld/backends/metal/[common, textures]

const
  FrameCount = 12
  StripeCount = 6
  UnchangedLayer = rgbx(31, 67, 131, 255)
  UnchangedMip = rgbx(191, 113, 47, 255)
  Poison = rgbx(255, 0, 255, 255)

type
  RecordedFrame = object
    target: RenderTarget
    index: int
    expected: array[StripeCount, ColorRGBX]

var
  sourceColor: Uniform[Sampler2D]
  sourceLayers: Uniform[Sampler2DArray]
  palette: Uniform[array[300, Vec4]]
  paletteIndex: Uniform[int32]
  arraySource: Uniform[bool]
  layer, mip: Uniform[float32]

proc vertex(position: Vec2, gl_Position: var Vec4) =
  ## Places an independently uploaded stripe in clip space.
  gl_Position = vec4(position, vec2(0, 1))

proc fragment(fragColor: var Vec4) =
  ## Samples full or partial uploads through a uniform block above four KiB.
  var sampled = texture(sourceColor, vec2(0.5))
  if arraySource:
    # A two-texel footprint selects mip one of the fixed 3 by 2 array.
    sampled = textureGrad(
      sourceLayers, vec3(0.5, 0.5, layer),
      vec2(mip * (2'f / 3'f), 0), vec2(0, mip)
    )
  fragColor = sampled * palette[paletteIndex]

proc frameColor(index, variant: int): ColorRGBX =
  ## Gives each queued upload a distinct byte-exact opaque color.
  case variant
  of 0:
    rgbx(uint8(20 + index * 7), uint8(70 + index * 5),
      uint8(210 - index * 4), 255)
  of 1:
    rgbx(uint8(200 - index * 3), uint8(40 + index * 6),
      uint8(50 + index * 5), 255)
  of 2:
    rgbx(uint8(40 + index * 4), uint8(180 - index * 2),
      uint8(90 + index * 3), 255)
  else:
    rgbx(uint8(170 - index * 5), uint8(110 + index * 2),
      uint8(25 + index * 7), 255)

proc paletteColor(stripe: int): Vec4 =
  ## Changes the large uniform block independently of the uploaded pixels.
  case stripe mod 3
  of 0: vec4(1, 0, 1, 1)
  of 1: vec4(0, 1, 1, 1)
  else: vec4(1, 1, 0, 1)

proc expectedColor(value: ColorRGBX, stripe: int): ColorRGBX =
  ## Computes the exact output for one texture sample and channel mask.
  result = value
  case stripe mod 3
  of 0: result.g = 0
  of 1: result.r = 0
  else: result.b = 0

proc stripeVertices(stripe: int): array[6, Vec2] =
  ## Reuses one vertex buffer for six distinct rectangles in each frame.
  let
    left = stripe.float32 * 2'f / StripeCount.float32 - 1'f
    right = (stripe + 1).float32 * 2'f / StripeCount.float32 - 1'f
  [vec2(left, -1), vec2(right, -1), vec2(right, 1),
    vec2(left, -1), vec2(right, 1), vec2(left, 1)]

proc verify(image: Image, frame: RecordedFrame) =
  ## Checks every pixel after all queued writes and resource changes finish.
  doAssert image.width == frame.target.width
  doAssert image.height == frame.target.height
  let stripeWidth = image.width div StripeCount
  for y in 0 ..< image.height:
    for x in 0 ..< image.width:
      doAssert image[x, y] == frame.expected[x div stripeWidth],
        "Queued frame " & $frame.index & " changed at " & $x & "," & $y

let window = newWindow("Metal queued frame validation", ivec2(96, 48),
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
  vertices = newBuffer(stripeVertices(0))
  colorImage = newImage(3, 2)
  layerImage = newImage(3, 2)
  originalLayer = newImage(3, 2)
  originalMip = newImage(1, 1)
  untouchedMip = newImage(1, 1)
colorImage.fill(Poison)
layerImage.fill(Poison)
originalLayer.fill(UnchangedLayer)
originalMip.fill(UnchangedLayer)
untouchedMip.fill(UnchangedMip)
let
  colorTexture = newTexture(colorImage, linear = false)
  arrayTexture = createTextureArray(@[
    @[originalLayer, originalMip], @[layerImage, untouchedMip]
  ], repeat = false)
arrayTexture.setTextureSampling(linear = false)
program.bindTexture("sourceColor", colorTexture)
program.bindTexture("sourceLayers", arrayTexture)

proc record(index: int): RecordedFrame =
  ## Encodes changing resources without explicitly waiting for GPU completion.
  result.index = index
  let
    width = (12 + index) * StripeCount
    height = 24 + (index mod 4) * 2
  # These queued uploads precede beginFrame, including its resize path.
  colorImage.fill(frameColor(index, 0))
  colorTexture.updateTexture(colorImage)
  colorImage.fill(Poison)
  layerImage.fill(frameColor(index, 2))
  arrayTexture.updateTextureArrayLayer(1, @[layerImage])
  layerImage.fill(Poison)
  beginFrame(width, height, color(0, 0, 0, 1))
  doAssert metalRenderer.frameTarget.width == width
  doAssert metalRenderer.frameTarget.height == height
  result.target = newRenderTarget(width, height, depth = false)
  var colors: array[300, Vec4]
  for stripe in 0 ..< StripeCount:
    if stripe == 1:
      colorImage.fill(frameColor(index, 1))
      colorTexture.updateTexture(colorImage)
      colorImage.fill(Poison)
    elif stripe == 3:
      # Updating one slice and mip must preserve the others.
      layerImage.fill(frameColor(index, 3))
      arrayTexture.updateTextureArrayLayer(1, @[layerImage])
      layerImage.fill(Poison)
    let
      selected = int32((index * 31 + stripe * 17) mod colors.len)
      source = case stripe
        of 0: frameColor(index, 0)
        of 1: frameColor(index, 1)
        of 2: frameColor(index, 2)
        of 3: frameColor(index, 3)
        of 4: UnchangedLayer
        else: UnchangedMip
    for value in colors.mitems:
      value = vec4(0)
    colors[selected] = paletteColor(stripe)
    program.setUniform("palette", colors)
    program.setUniform("paletteIndex", selected)
    program.setUniform("arraySource", stripe >= 2)
    program.setUniform("layer", if stripe == 4: 0'f else: 1'f)
    program.setUniform("mip", if stripe == 5: 1'f else: 0'f)
    vertices.updateBuffer(stripeVertices(stripe))
    draw(program, vertices, 6)
    result.expected[stripe] = expectedColor(source, stripe)
  # Retain each result while later frame resizes retire its scene attachments.
  copyTarget(metalRenderer.frameTarget, result.target, depth = false)
  endFrame(present = false)
  doAssert inflightCount() <= MaxFramesInFlight,
    "Submitted frames must stay within the configured resource bound"

var frames: seq[RecordedFrame]
for index in 0 ..< FrameCount:
  frames.add(record(index))
  if index mod 2 == 1:
    pollGpu()
drainGpu()
doAssert inflightCount() == 0
doAssert metalRenderer.commandBuffer.isNil
for frame in frames:
  verify(captureTargetImage(frame.target), frame)
  destroy(frame.target)

# Shutdown must complete submitted draws even after wrappers are released.
var finalFrames: seq[RecordedFrame]
for index in FrameCount ..< FrameCount + MaxFramesInFlight:
  finalFrames.add(record(index))
let
  finalFrame = finalFrames[^1]
  retainedPixels = finalFrame.target.color.handle
retainedPixels.retain()
for frame in finalFrames:
  destroy(frame.target)
destroy(vertices)
destroy(program)
destroy(colorTexture)
destroy(arrayTexture)
shutdownMetal()
let finalImage = newImage(finalFrame.target.width, finalFrame.target.height)
retainedPixels.getBytes(
  finalImage.data[0].addr, (finalImage.width * 4).uint,
  MTLRegion(origin: MTLOrigin(), size: MTLSize(
    width: finalImage.width.uint, height: finalImage.height.uint, depth: 1
  )), 0
)
verify(finalImage, finalFrame)
retainedPixels.release()
window.close()
echo "Metal queued frames, partial uploads, resizing and shutdown passed"
