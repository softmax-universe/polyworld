proc closeWorldBarRenderer*(renderer: var WorldBarRenderer) =
  ## Releases the billboard program, buffer, and owned fallback texture.
  destroy(renderer.gpu.program)
  destroy(renderer.gpu.vertexBuffer)
  destroy(renderer.gpu.whiteTexture)
  renderer = WorldBarRenderer()

proc initWorldBarRenderer*(): WorldBarRenderer =
  ## Creates the billboard program and its reusable dynamic vertex buffer.
  try:
    result.gpu.program = newProgram(
      nativeStage(barVertex, shaderVertex),
      nativeStage(barFragment, shaderFragment),
      VertexLayout(
        stride: VertexFloats * sizeof(float32),
        attributes: @[
          VertexAttribute(name: "worldCenter", format: Float3, offset: 0),
          VertexAttribute(name: "billboardOffset", format: Float2, offset: 12),
          VertexAttribute(name: "vertexColor", format: Float4, offset: 20),
          VertexAttribute(name: "vertexUv", format: Float2, offset: 36),
          VertexAttribute(name: "vertexTextureMode", format: Float1, offset: 44)
        ]
      )
    )
    when defined(useMetal4): result.gpu.vertexBuffer = newBuffer([0.0'f])
    let white = newImage(1, 1)
    white.fill(rgba(255, 255, 255, 255))
    result.gpu.whiteTexture = newTexture(white)
  except CatchableError as error:
    result.closeWorldBarRenderer()
    raise newException(WorldBarError, "Unable to create GPU worldbars: " &
      error.msg)

proc draw*(
    renderer: var WorldBarRenderer,
    viewProjection: Mat4,
    cameraRight,
    cameraUp: Vec3,
    textureId = default(WorldBarTexture)
) =
  ## Draws camera-facing resource bars and atlas glyphs against scene depth.
  if renderer.vertices.len == 0:
    return
  setUniform(renderer.gpu.program, "barViewProjection", viewProjection)
  setUniform(renderer.gpu.program, "barCameraRight", cameraRight)
  setUniform(renderer.gpu.program, "barCameraUp", cameraUp)
  bindTexture(
    renderer.gpu.program,
    "barTexture",
    if textureId == nil: renderer.gpu.whiteTexture else: textureId
  )
  let state = DrawState(depthTest: true, blend: StraightAlpha)
  when defined(useMetal4):
    updateBuffer(renderer.gpu.vertexBuffer, renderer.vertices)
    draw(renderer.gpu.program, renderer.gpu.vertexBuffer, renderer.vertices.len div VertexFloats, state)
  else:
    drawStream(renderer.gpu.program, renderer.vertices, renderer.vertices.len div VertexFloats, state)
