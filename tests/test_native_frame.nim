import pixie, shady, vmath, windy
import polyworld/backends/native/common

var
  tint: Uniform[Vec4]
  sourceTexture: Uniform[Sampler2D]
  sampleUv: Uniform[Vec2]

proc vertex(gl_Position: var Vec4, position: Vec2) =
  ## Places the smoke triangle in clip space.
  gl_Position = vec4(position.x, position.y, 0, 1)

proc fragment(fragColor: var Vec4) =
  ## Emits a uniform color for pixel verification.
  fragColor = tint

proc textureFragment(fragColor: var Vec4) =
  ## Samples a texel for immutable texture upload verification.
  fragColor = texture(sourceTexture, sampleUv)

let window = newWindow("Native frame validation", ivec2(64, 64), visible = false)
initNative(window)
let
  program = newProgram(nativeStage(vertex, shaderVertex),
    nativeStage(fragment, shaderFragment), VertexLayout(stride: 8, attributes: @[
      VertexAttribute(name: "position", format: Float2)
    ]))
  vertices = newBuffer([-1.0'f, -1, 1, -1, 0, 1])
  fullscreen = newBuffer([-1.0'f, -1, 3, -1, -1, 3])
program.setUniform("tint", vec4(1, 0, 0, 1))
beginFrame(64, 64, color(0, 0, 0, 1))
draw(program, vertices, 3, DrawState(depthTest: true, depthWrite: true))
let firstImage = captureTargetImage()
doAssert firstImage[32, 32].r > 240
doAssert firstImage[0, 0].r == 0
let wire = newBuffer([7'u16, 0, 1, 2])
clear(color(0, 0, 0, 1))
draw(program, vertices, 3, DrawState(wireframe: true), indices = wire, first = 1, index32 = false)
let wireImage = captureTargetImage()
doAssert wireImage[32, 32].r == 0
var edgePixels = 0
for pixel in wireImage.data:
  if pixel.r > 240: inc edgePixels
doAssert edgePixels in 50 .. 250
beginFrame(64, 64, color(0, 0, 0, 1))
draw(program, vertices, 3)
let target = newRenderTarget(64, 64, samples = 4, stencil = true)
pushTarget(target)
clear(color(0, 0, 0, 1), stencil = true)
program.setUniform("tint", vec4(0, 1, 0, 1))
draw(program, vertices, 3, DrawState(depthTest: true, depthWrite: true,
  stencilTest: true, stencilWrite: true, stencilReference: 7,
  stencilCompare: Always))
let secondImage = captureTargetImage()
doAssert secondImage[32, 32].g > 240
let resolvedCopy = snapshotTarget()
pushTarget(resolvedCopy)
clear(color(1, 1, 1, 1), depth = false)
program.setUniform("tint", vec4(1, 0, 0, 1))
draw(program, fullscreen, 3, DrawState(stencilTest: true,
  stencilReference: 7, stencilCompare: Equal))
let stencilImage = captureTargetImage()
doAssert stencilImage[32, 32].r > 240 and stencilImage[32, 32].g < 5
doAssert stencilImage[0, 0].g > 240
popTarget()
popTarget()
let thirdImage = captureTargetImage()
doAssert thirdImage[32, 32].r > 240
let copy = snapshotTarget()
doAssert copy.depth.pixelFormat == DepthStencil
let copiedImage = captureTargetImage(copy)
doAssert copiedImage[32, 32].r > 240
beginFrame(64, 64, color(0, 0, 0, 1))
setRenderViewport(ivec2(24, 16))
pushTarget(target)
popTarget()
program.setUniform("tint", vec4(0, 0, 1, 1))
draw(program, fullscreen, 3, DrawState(cull: CullBack))
let viewportImage = captureTargetImage()
doAssert viewportImage[20, 12].b > 240
doAssert viewportImage[30, 20].b == 0
program.setUniform("tint", vec4(0, 1, 0, 1))
draw(program, fullscreen, 3)
let resumedImage = captureTargetImage()
doAssert resumedImage[20, 12].g > 240
doAssert resumedImage[30, 20].g == 0

beginFrame(64, 64, color(0, 0, 0, 1))
let
  image = newImage(1, 1)
  left = newBuffer([-1.0'f, -1, 0, -1, 0, 1,
    -1.0'f, -1, 0, 1, -1, 1])
  right = newBuffer([0.0'f, -1, 1, -1, 1, 1,
    0.0'f, -1, 1, 1, 0, 1])
  sampled = newProgram(nativeStage(vertex, shaderVertex),
    nativeStage(textureFragment, shaderFragment), VertexLayout(stride: 8, attributes: @[VertexAttribute(name: "position", format: Float2)]))
image.fill(color(1, 0, 0, 1))
let texture = newTexture(image)
sampled.setUniform("sampleUv", vec2(0.5))
sampled.bindTexture("sourceTexture", texture)
draw(sampled, left, 6)
image.fill(color(0, 1, 0, 1))
texture.updateTexture(image)
draw(sampled, right, 6)
let uploadImage = captureTargetImage()
doAssert uploadImage[16, 32].r > 240
# This verifies the earlier draw retained the original texture pixels.
doAssert uploadImage[48, 32].g > 240

let stripes = newImage(2, 2)
stripes[0, 0] = rgbx(255, 0, 0, 255)
stripes[1, 0] = rgbx(0, 255, 0, 255)
stripes[0, 1] = rgbx(0, 0, 255, 255)
stripes[1, 1] = rgbx(255, 255, 0, 255)
let striped = newTexture(stripes, linear = false)
striped.sampling.wrapS = MirrorRepeat
striped.sampling.wrapT = Repeat
sampled.bindTexture("sourceTexture", striped)
sampled.setUniform("sampleUv", vec2(1.25, 1.25))
draw(sampled, fullscreen, 3)
let wrapped = captureTargetImage()[32, 32]
doAssert wrapped.r == 0 and wrapped.g > 240 and wrapped.b == 0

pushTarget(target)
clear(color(0, 0, 1, 1), stencil = true)
discard resolveForUi()
doAssert target.renderSamples() == 1
program.setUniform("tint", vec4(1, 0, 0, 1))
draw(program, left, 6)
popTarget()
pushTarget(target)
program.setUniform("tint", vec4(0, 1, 0, 1))
draw(program, right, 6)
let overlayImage = captureTargetImage()
doAssert overlayImage[16, 32].r > 240
# This verifies rebinding cannot resolve stale multisample color over UI.
doAssert overlayImage[48, 32].g > 240
clear(color(0, 0, 0, 1), stencil = true)
doAssert target.renderSamples() == gpuRenderer.ctx.sampleCount(4, Rgba8, DepthStencil)
popTarget()
endFrame(false)
let msColor = newRenderTarget(64, 64, depth = false, samples = 4)
pushTarget(msColor)
clear(color(0, 0, 0, 1))
program.setUniform("tint", vec4(1, 1, 0, 1))
draw(program, vertices, 3)
let msImage = captureTargetImage()
doAssert msImage[32, 32].r > 240
if msColor.samples > 1:
  var intermediate = false
  for pixel in msImage.data:
    if pixel.r > 0 and pixel.r < 255: intermediate = true
  doAssert intermediate, "MSAA must resolve partial triangle coverage"
popTarget()
destroy(msColor)
endFrame(false)
setFrameSamples(4)
beginFrame(64, 64, color(0, 0, 1, 1))
doAssert gpuRenderer.frameTarget.renderSamples() == gpuRenderer.ctx.sampleCount(4, Rgba8, DepthStencil)
endFrame(true)
window.size = ivec2(80, 48)
beginFrame(80, 48, color(1, 0, 0, 1))
doAssert captureTargetImage().width == 80
endFrame(true)
# Each queued list owns its upload bytes and descriptors until its fence signals.
# Update in place between two draws, then retire that geometry before presenting.
setFrameSamples(1)
let leftQuad = [-1'f32, -1, 0, -1, 0, 1, -1, -1, 0, 1, -1, 1]
let rightQuad = [0'f32, -1, 1, -1, 1, 1, 0, -1, 1, 1, 0, 1]
for frame in 0 .. 6:
  beginFrame(80, 48, color(0, 0, 0, 1))
  let geometry = newBuffer(leftQuad)
  program.setUniform("tint", vec4(1, 0, 0, 1))
  draw(program, geometry, 6)
  geometry.updateBuffer(rightQuad)
  program.setUniform("tint", vec4(0, 1, 0, 1))
  draw(program, geometry, 6)
  destroy(geometry)
  if frame == 6:
    let pixels = captureTargetImage()
    doAssert pixels[10, 24].r == 255 and pixels[70, 24].g == 255
  endFrame(true)
beginFrame(80, 48, color(0, 0, 0, 1))
program.setUniform("tint", vec4(1, 0, 0, 1))
drawStream(program, leftQuad, 6, DrawState())
program.setUniform("tint", vec4(0, 0, 1, 1))
drawStream(program, rightQuad, 6, DrawState())
let streams = captureTargetImage()
doAssert streams[10, 24].r == 255 and streams[70, 24].b == 255
endFrame(false)
destroy(resolvedCopy)
destroy(copy)
destroy(target)
shutdownNative()
window.close()
echo "Native target, stencil, upload ordering, viewport and presentation passed"
