proc closeShapeRenderer*(renderer: var ShapeRenderer) =
  ## Releases owned resources while preserving the borrowed atlas texture.
  destroy(renderer.gpu.program)
  destroy(renderer.gpu.vertexBuffer)
  destroy(renderer.gpu.whiteTexture)
  renderer = ShapeRenderer()

proc initShapeRenderer*(): ShapeRenderer =
  ## Creates the shape program and a reusable world-space vertex buffer.
  try:
    result.gpu.program = newProgram(
      toShader(shapeVertex, metalMSL, shaderVertex),
      toShader(shapeFragment, metalMSL, shaderFragment),
      VertexLayout(
        stride: VertexFloats * sizeof(float32),
        attributes: @[
          VertexAttribute(name: "worldPosition", format: Float3, offset: 0),
          VertexAttribute(name: "texturePosition", format: Float2, offset: 12),
          VertexAttribute(name: "vertexColor", format: Float4, offset: 20)
        ]
      )
    )
    result.gpu.vertexBuffer = newBuffer([0.0'f])
    let white = newImage(1, 1)
    white.fill(rgba(255, 255, 255, 255))
    result.gpu.whiteTexture = newTexture(white, linear = false)
  except CatchableError as error:
    result.closeShapeRenderer()
    raise newException(ShapeError, "Unable to create Metal shapes: " &
      error.msg)

proc draw*(
    renderer: var ShapeRenderer,
    viewProjection: Mat4,
    opaque = false
) =
  ## Draws the world-space batch and optionally writes opaque surface depth.
  if renderer.vertices.len == 0:
    return
  updateBuffer(renderer.gpu.vertexBuffer, renderer.vertices)
  setUniform(renderer.gpu.program, "shapeViewProjection", viewProjection)
  bindTexture(
    renderer.gpu.program,
    "shapeSampler",
    if renderer.texture == nil: renderer.gpu.whiteTexture else: renderer.texture
  )
  draw(
    renderer.gpu.program,
    renderer.gpu.vertexBuffer,
    renderer.vertices.len div VertexFloats,
    DrawState(
      depthTest: true,
      depthWrite: opaque,
      blend: if opaque: Opaque else: StraightAlpha
    )
  )
