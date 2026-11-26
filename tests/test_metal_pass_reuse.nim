## Checks pass reuse without changing clears, viewport, stencil, or MSAA pixels.

when not defined(useMetal4) or not defined(metalProfile):
  {.error: "Run with -d:useMetal4 -d:metalProfile.".}

import
  pixie, shady, vmath, windy,
  polyworld/backends/metal/common

const Size = 64

var
  paintColor: Uniform[Vec4]
  clipDepth: Uniform[float32]

proc vertex(position: Vec2, gl_Position: var Vec4) =
  ## Places a test shape at an explicit clip depth.
  gl_Position = vec4(position.x, position.y, clipDepth, 1)

proc fragment(fragColor: var Vec4) =
  ## Emits an exact opaque test color.
  fragColor = paintColor

proc rectangle(left, right: float32): array[6, Vec2] =
  ## Returns a full-height rectangle within the chosen clip-space bounds.
  [vec2(left, -1), vec2(right, -1), vec2(right, 1),
    vec2(left, -1), vec2(right, 1), vec2(left, 1)]

proc paint(program: MetalProgram, vertices: MetalBuffer, value: Vec4,
    depth = 0.0'f, state = DrawState()) =
  ## Draws one colored rectangle without modifying the active target.
  program.setUniform("paintColor", value)
  program.setUniform("clipDepth", depth)
  draw(program, vertices, 6, state)

proc expectColor(image: Image, x, y: int, expected: ColorRGBX) =
  ## Checks an interior pixel away from multisample raster edges.
  doAssert image[x, y] == expected,
    "Unexpected pixel at " & $x & ", " & $y & ": " & $image[x, y]

proc checkPassReuse(program: MetalProgram,
    full, left, right: MetalBuffer, samples: int) =
  ## Exercises equivalent rendering while checking encoder lifetime counts.
  let
    target = newRenderTarget(Size, Size, samples = samples, stencil = true)
    other = newRenderTarget(Size, Size, stencil = true)
  defer:
    destroy(other)
    destroy(target)

  ensureFrame(Size, Size)
  setTarget(target)
  resetMetalProfile()
  setRenderViewport(ivec2(24, 16))
  doAssert readMetalProfile().renderPasses == 0,
    "Changing the viewport must not create an otherwise empty render pass"
  clear(color(0, 0, 0, 1), stencil = true)
  paint(program, full, vec4(1, 0, 0, 1))
  doAssert readMetalProfile().renderPasses == 1,
    "Clear and first draw must share one render pass"
  pushTarget(target)
  setRenderViewport(ivec2(12, 8))
  paint(program, full, vec4(0, 0, 1, 1))
  popTarget()
  paint(program, right, vec4(1, 1, 0, 1))
  setTarget(target)
  paint(program, right, vec4(0, 1, 0, 1))
  doAssert readMetalProfile().renderPasses == 1,
    "Rebinding the current target must retain its active render pass"
  endFrame(false)
  doAssert readMetalProfile().emptyPasses == 0
  let viewportImage = captureTargetImage(target)
  viewportImage.expectColor(4, 4, rgbx(0, 0, 255, 255))
  viewportImage.expectColor(16, 8, rgbx(255, 255, 0, 255))
  viewportImage.expectColor(16, 40, rgbx(0, 0, 0, 255))
  viewportImage.expectColor(48, 40, rgbx(0, 255, 0, 255))

  ensureFrame(Size, Size)
  setTarget(target)
  resetMetalProfile()
  clear(color(0, 0, 0, 1), stencil = true)
  paint(program, left, vec4(1, 0, 0, 1), -0.5'f, DrawState(
    depthTest: true, depthWrite: true, stencilTest: true,
    stencilWrite: true, stencilReference: 7, stencilCompare: Always
  ))
  paint(program, right, vec4(0, 0, 1, 1))
  clearDepth()
  paint(program, full, vec4(0, 1, 0, 1), 0.5'f, DrawState(
    depthTest: true, stencilTest: true,
    stencilReference: 7, stencilCompare: Equal
  ))
  doAssert readMetalProfile().renderPasses == 2,
    "Depth clear must share its pass with the following stencil-tested draw"
  endFrame(false)
  doAssert readMetalProfile().emptyPasses == 0
  let depthImage = captureTargetImage(target)
  depthImage.expectColor(16, 32, rgbx(0, 255, 0, 255))
  depthImage.expectColor(48, 32, rgbx(0, 0, 255, 255))

  ensureFrame(Size, Size)
  setTarget(target)
  resetMetalProfile()
  setRenderViewport(ivec2(20, 12))
  clear(color(0, 0, 0, 1), stencil = true)
  paint(program, full, vec4(1, 0, 0, 1))
  pushTarget(other)
  clear(color(0, 0, 1, 1), stencil = true)
  popTarget()
  paint(program, full, vec4(0, 1, 0, 1))
  doAssert readMetalProfile().renderPasses == 3,
    "Switching targets must preserve the necessary clear-only pass"
  endFrame(false)
  doAssert readMetalProfile().emptyPasses == 1
  let
    restoredImage = captureTargetImage(target)
    otherImage = captureTargetImage(other)
  restoredImage.expectColor(10, 6, rgbx(0, 255, 0, 255))
  restoredImage.expectColor(40, 40, rgbx(0, 0, 0, 255))
  otherImage.expectColor(40, 40, rgbx(0, 0, 255, 255))

  ensureFrame(Size, Size)
  setTarget(target)
  resetMetalProfile()
  clear(color(0, 0, 0, 1), stencil = true)
  paint(program, left, vec4(1, 0, 0, 1))
  discard resolveForUi()
  doAssert target.renderSamples() == 1
  paint(program, right, vec4(0, 1, 0, 1))
  setTarget(target)
  paint(program, left, vec4(0, 0, 1, 1))
  doAssert readMetalProfile().renderPasses == 2,
    "Rebinding after resolved UI drawing must not start another pass"
  endFrame(false)
  let resolvedImage = captureTargetImage(target)
  resolvedImage.expectColor(16, 32, rgbx(0, 0, 255, 255))
  resolvedImage.expectColor(48, 32, rgbx(0, 255, 0, 255))

  ensureFrame(Size, Size)
  setTarget(target)
  resetMetalProfile()
  clear(color(0, 0, 0, 1), stencil = true)
  doAssert target.renderSamples() == samples,
    "A full clear must restore the target's requested sample count"
  paint(program, full, vec4(1, 0, 0, 1))
  doAssert readMetalProfile().renderPasses == 1
  endFrame(false)
  captureTargetImage(target).expectColor(32, 32, rgbx(255, 0, 0, 255))
  echo "Metal pass reuse pixels and counters passed, samples=", samples

block metalPassReuse:
  let window = newWindow("Metal pass reuse", ivec2(Size, Size),
    visible = false, vsync = false)
  initMetal(window)
  defer:
    shutdownMetal()
    window.close()
  let
    program = newProgram(
      toShader(vertex, metalMSL, shaderVertex),
      toShader(fragment, metalMSL, shaderFragment),
      VertexLayout(stride: sizeof(Vec2), attributes: @[
        VertexAttribute(name: "position", format: Float2, offset: 0)
      ])
    )
    full = newBuffer(rectangle(-1, 1))
    left = newBuffer(rectangle(-1, 0))
    right = newBuffer(rectangle(0, 1))
  for samples in [1, 4]:
    checkPassReuse(program, full, left, right, samples)
