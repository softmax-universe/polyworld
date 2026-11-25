import pixie, shady, vmath, windy
import polyworld/backends/metal/common

var
  tint: Uniform[Vec4]
  sourceTexture: Uniform[Sampler2D]

proc vertex(gl_Position: var Vec4, position: Vec2) =
  ## Places the smoke triangle in clip space.
  gl_Position = vec4(position.x, position.y, 0, 1)

proc fragment(fragColor: var Vec4) =
  ## Emits a uniform color for pixel verification.
  fragColor = tint

proc textureFragment(fragColor: var Vec4) =
  ## Samples a texel for immutable texture upload verification.
  fragColor = texture(sourceTexture, vec2(0.5))

let window = newWindow("Metal core validation", ivec2(64, 64), visible = false)
initMetal(window)
let
  program = newProgram(toMSL(vertex, shaderVertex),
    toMSL(fragment, shaderFragment), VertexLayout(stride: 8, attributes: @[
      VertexAttribute(name: "position", format: Float2)
    ]))
  vertices = newBuffer([-1.0'f, -1, 1, -1, 0, 1])
  fullscreen = newBuffer([-1.0'f, -1, 3, -1, -1, 3])
program.setUniform("tint", vec4(1, 0, 0, 1))
beginFrame(64, 64, color(0, 0, 0, 1))
draw(program, vertices, 3, DrawState(depthTest: true, depthWrite: true))
let firstImage = captureImage()
doAssert firstImage[32, 32].r > 240
doAssert firstImage[0, 0].r == 0
let target = newRenderTarget(64, 64, samples = 4, stencil = true)
pushTarget(target)
clear(color(0, 0, 0, 1), stencil = true)
program.setUniform("tint", vec4(0, 1, 0, 1))
draw(program, vertices, 3, DrawState(depthTest: true, depthWrite: true,
  stencilTest: true, stencilWrite: true, stencilReference: 7,
  stencilCompare: Always))
let secondImage = captureImage()
doAssert secondImage[32, 32].g > 240
let resolvedCopy = snapshotTarget()
pushTarget(resolvedCopy)
clear(color(1, 1, 1, 1), depth = false)
program.setUniform("tint", vec4(1, 0, 0, 1))
draw(program, fullscreen, 3, DrawState(stencilTest: true,
  stencilReference: 7, stencilCompare: Equal))
let stencilImage = captureImage()
doAssert stencilImage[32, 32].r > 240 and stencilImage[32, 32].g < 5
doAssert stencilImage[0, 0].g > 240
popTarget()
popTarget()
let thirdImage = captureImage()
doAssert thirdImage[32, 32].r > 240
let copy = snapshotTarget()
doAssert copy.depth.pixelFormat == MTLPixelFormatDepth32Float_Stencil8
let copiedImage = captureTargetImage(copy)
doAssert copiedImage[32, 32].r > 240
beginFrame(64, 64, color(0, 0, 0, 1))
setRenderViewport(ivec2(24, 16))
pushTarget(target)
popTarget()
program.setUniform("tint", vec4(0, 0, 1, 1))
draw(program, fullscreen, 3, DrawState(cull: CullBack))
let viewportImage = captureImage()
doAssert viewportImage[20, 12].b > 240
doAssert viewportImage[30, 20].b == 0
program.setUniform("tint", vec4(0, 1, 0, 1))
draw(program, fullscreen, 3)
let resumedImage = captureImage()
doAssert resumedImage[20, 12].g > 240
doAssert resumedImage[30, 20].g == 0

beginFrame(64, 64, color(0, 0, 0, 1))
let
  image = newImage(1, 1)
  left = newBuffer([-1.0'f, -1, 0, -1, 0, 1,
    -1.0'f, -1, 0, 1, -1, 1])
  right = newBuffer([0.0'f, -1, 1, -1, 1, 1,
    0.0'f, -1, 1, 1, 0, 1])
  sampled = newProgram(toMSL(vertex, shaderVertex),
    toMSL(textureFragment, shaderFragment), program.layout)
image.fill(color(1, 0, 0, 1))
let texture = newTexture(image)
sampled.bindTexture("sourceTexture", texture)
draw(sampled, left, 6)
image.fill(color(0, 1, 0, 1))
texture.updateTexture(image)
draw(sampled, right, 6)
let uploadImage = captureImage()
doAssert uploadImage[16, 32].r > 240
# This verifies the earlier draw retained the original texture pixels.
doAssert uploadImage[48, 32].g > 240

pushTarget(target)
clear(color(0, 0, 1, 1), stencil = true)
discard resolveForUi()
program.setUniform("tint", vec4(1, 0, 0, 1))
draw(program, left, 6)
popTarget()
pushTarget(target)
program.setUniform("tint", vec4(0, 1, 0, 1))
draw(program, right, 6)
let overlayImage = captureImage()
doAssert overlayImage[16, 32].r > 240
# This verifies rebinding cannot resolve stale multisample color over UI.
doAssert overlayImage[48, 32].g > 240
clear(color(0, 0, 0, 1), stencil = true)
doAssert target.renderSamples() == 4
popTarget()
endFrame(false)
setFrameSamples(4)
beginFrame(64, 64, color(0, 0, 0, 1))
doAssert metalRenderer.frameTarget.samples == 4
draw(program, fullscreen, 3)
discard resolveForUi()
doAssert metalRenderer.target.renderSamples() == 1
endFrame(false)
destroy(resolvedCopy)
destroy(copy)
destroy(target)
shutdownMetal()
window.close()
echo "Metal rendering, MSAA, stencil, viewport, UI and uploads passed"
