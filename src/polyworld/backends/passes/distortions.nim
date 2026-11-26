## GPU distortion rendering with a resolved copy of the finished scene.

import
  shady, vmath,
  common, ../shaders/distortions

export distortions

type
  DistortionRenderer* = object
    program: ShaderProgram
    vertexBuffer: VertexBuffer
    sceneCopy: RenderTarget
    floats: seq[float32]
    ready, unavailable: bool

proc setup(renderer: var DistortionRenderer) =
  ## Compiles the distortion program and declares its interleaved vertices.
  renderer.program = newProgram(
    nativeStage(distortionVertex, shaderVertex),
    nativeStage(distortionFragment, shaderFragment),
    VertexLayout(
      stride: VertexFloats * sizeof(float32),
      attributes: @[
        VertexAttribute(name: "position", format: Float3, offset: 0),
        VertexAttribute(name: "corner", format: Float2,
          offset: 3 * sizeof(float32)),
        VertexAttribute(name: "params", format: Float4,
          offset: 5 * sizeof(float32))
      ]
    )
  )
  renderer.ready = true

proc ensureSize(renderer: var DistortionRenderer, source: RenderTarget) =
  ## Creates a matching color copy without an unused depth attachment.
  if renderer.sceneCopy != nil and
      renderer.sceneCopy.width == source.width and
      renderer.sceneCopy.height == source.height and
      renderer.sceneCopy.color.pixelFormat == source.color.pixelFormat:
    return
  destroy(renderer.sceneCopy)
  renderer.sceneCopy = newRenderTarget(
    source.width,
    source.height,
    depth = false,
    colorFormat = source.color.pixelFormat
  )

proc drawDistortions*(
    renderer: var DistortionRenderer,
    distortions: openArray[Distortion],
    viewMatrix: Mat4,
    eye, right, up: Vec3,
    size: IVec2,
    clock: float32,
    source: RenderTarget = nil
) =
  ## Bends a scene target through depth-tested camera-facing effect quads.
  if distortions.len == 0 or size.x <= 0 or size.y <= 0:
    return
  ensureFrame(size.x, size.y)
  let target = if source == nil: gpuRenderer.frameTarget else: source
  if target == nil or target.color == nil:
    raise newException(DistortionError, "Distortions require a scene color target")
  if size.x.int != target.width or size.y.int != target.height:
    raise newException(DistortionError,
      "Distortion size must match its scene target")
  if not renderer.ready:
    renderer.setup()
  buildDistortionVertices(renderer.floats, distortions, viewMatrix,
    eye, right, up, size)
  if renderer.floats.len == 0:
    return
  renderer.ensureSize(target)
  copyTarget(target, renderer.sceneCopy, depth = false)
  if renderer.vertexBuffer == nil:
    renderer.vertexBuffer = newBuffer(renderer.floats)
  else:
    renderer.vertexBuffer.updateBuffer(renderer.floats)
  let program = renderer.program
  program.setUniform("viewMatrix", viewMatrix)
  program.setUniform("viewportSize", vec2(size.x.float32, size.y.float32))
  program.setUniform("clock", clock)
  program.setUniform("shiftScale",
    (when PassTopLeftOrigin: vec2(1.0'f, -1.0'f) else: vec2(1.0'f)))
  program.bindTexture("scene", renderer.sceneCopy.color)
  pushTarget(target)
  defer:
    popTarget()
  draw(program, renderer.vertexBuffer, renderer.floats.len div VertexFloats,
    DrawState(
      depthTest: true,
      depthWrite: false,
      depthCompare: LessEqual,
      blend: AlphaBlendPreserveAlpha
    ))

proc close*(renderer: var DistortionRenderer) =
  ## Releases the program, billboard buffer and resolved scene copy.
  destroy(renderer.program)
  destroy(renderer.vertexBuffer)
  destroy(renderer.sceneCopy)
  renderer = DistortionRenderer()
