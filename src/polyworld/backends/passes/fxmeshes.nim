## GPU renderer for procedural visual effects.

import
  pixie, shady, vmath,
  ../../[fxmeshdata, fxmeshshaders],
  common as driver

type
  FxRenderer* = object
    program: ShaderProgram
    vertexBuffer: VertexBuffer
    indexBuffer: VertexBuffer
    patternTextures: array[FxTexture, GpuImage]
    indexCount*: int
    vertexCount*: int

proc closeFxRenderer*(renderer: var FxRenderer) =
  ## Releases the fx program, buffers, and pattern textures.
  renderer.program.destroy()
  renderer.vertexBuffer.destroy()
  renderer.indexBuffer.destroy()
  for kind in FxTexture:
    renderer.patternTextures[kind].destroy()
  renderer = FxRenderer()

proc makePatternTexture(kind: FxTexture): GpuImage =
  ## Uploads one repeating mipmapped grayscale pattern texture.
  let
    pixels = buildFxPattern(kind)
    image = newImage(FxTextureSize, FxTextureSize)
  copyMem(image.data[0].addr, pixels[0].unsafeAddr, pixels.len)
  result = newTexture(image, linear = true, repeat = true, mipmaps = true)
  result.setPassSampling(linear = true, repeat = true)

proc initFxRenderer*(): FxRenderer {.raises: [FxMeshError].} =
  ## Compiles the shared Shady program and creates its pattern textures.
  try:
    result.program = newProgram(
      nativeStage(fxVertex, shaderVertex),
      nativeStage(fxFragment, shaderFragment),
      VertexLayout(
        stride: 12 * sizeof(float32),
        attributes: @[
          VertexAttribute(name: "vertPos", format: Float3, offset: 0),
          VertexAttribute(name: "vertNormal", format: Float3,
            offset: 3 * sizeof(float32)),
          VertexAttribute(name: "vertUv", format: Float2,
            offset: 6 * sizeof(float32)),
          VertexAttribute(name: "vertData", format: Float4,
            offset: 8 * sizeof(float32))
        ]
      )
    )
    result.vertexBuffer = newBuffer([0.0'f])
    result.indexBuffer = newBuffer([0'u32])
    for kind in FxTexture:
      result.patternTextures[kind] = makePatternTexture(kind)
  except Exception as error:
    result.closeFxRenderer()
    raise newException(FxMeshError, "Unable to create GPU fx renderer: " &
      error.msg)

proc uploadFxMesh*(
    renderer: var FxRenderer,
    mesh: tuple[vertices: seq[float32], indices: seq[uint32]]
) =
  ## Uploads packed geometry, including map-projected effect meshes.
  renderer.vertexCount = mesh.vertices.len div 12
  renderer.indexCount = mesh.indices.len
  updateBuffer(renderer.vertexBuffer, mesh.vertices)
  updateBuffer(renderer.indexBuffer, mesh.indices)

proc uploadFxMesh*(renderer: var FxRenderer, settings: FxSettings) =
  ## Rebuilds the current shape and uploads it to the GPU buffers.
  renderer.uploadFxMesh(buildFxMesh(settings))

proc drawFxMesh*(
    renderer: FxRenderer,
    settings: FxSettings,
    viewProjection,
    model: Mat4,
    time,
    life: float32,
    wireframe = false,
    sizeScale = 2.0'f
) =
  ## Encodes one uploaded fx mesh into the current frame without clearing.
  if renderer.program == nil or renderer.indexCount == 0:
    return
  let program = renderer.program
  program.setUniform("uViewProjection", viewProjection)
  program.setUniform("uModel", model * scale(vec3(sizeScale)))
  program.setUniform("uTime", time)
  program.setUniform("uLifeT", life)
  program.setUniform("uAlpha", fxAlpha(settings, life))
  program.setUniform("uDissolve", fxDissolve(settings, life))
  program.setUniform("uDissolveEdge", settings.dissolveEdge)
  program.setUniform("uSpinSpeed", settings.spinSpeed)
  program.setUniform("uTwistAngle", settings.twistAngle)
  program.setUniform("uWaveAmp", settings.waveAmp)
  program.setUniform("uWaveFreq", settings.waveFreq)
  program.setUniform("uWaveSpeed", settings.waveSpeed)
  program.setUniform("uRippleAmp", settings.rippleAmp)
  program.setUniform("uRippleFreq", settings.rippleFreq)
  program.setUniform("uRippleSpeed", settings.rippleSpeed)
  program.setUniform("uInflate", settings.inflate)
  program.setUniform("uPulseAmp", settings.pulseAmp)
  program.setUniform("uPulseSpeed", settings.pulseSpeed)
  program.setUniform("uExpandStart", settings.expandStart)
  program.setUniform("uExpandEnd", settings.expandEnd)
  program.setUniform("uExpandPower", settings.expandPower)
  program.setUniform("uSweepSource", settings.sweepSource.ord.int32)
  program.setUniform("uSweepBand", settings.sweepBand)
  program.setUniform("uSweepSoft", settings.sweepSoft)
  program.setUniform("uUvScale", settings.uvScale)
  program.setUniform("uScroll", settings.scroll)
  program.setUniform("uNoiseScale", settings.noiseScale)
  program.setUniform("uGradientSource", settings.gradientSource.ord.int32)
  program.setUniform("uStartColor", settings.startColor)
  program.setUniform("uEndColor", settings.endColor)
  program.setUniform("uEdgeColor", settings.edgeColor)
  program.setUniform("uEdgeFade", fxEdgeFade(settings))
  program.setUniform("uEdgeShape", fxEdgeShape(settings))
  program.bindTexture("uPattern", renderer.patternTextures[settings.texture])
  program.bindTexture("uNoise", renderer.patternTextures[NoiseTexture])
  program.draw(
    renderer.vertexBuffer,
    renderer.indexCount,
    DrawState(
      depthTest: true,
      depthWrite: false,
      depthCompare: LessEqual,
      cull: CullNone,
      blend:
        if settings.blendMode == fxmeshdata.AlphaBlend: driver.AlphaBlend
        else: Additive,
      primitive: Triangles,
      wireframe: wireframe
    ),
    indices = renderer.indexBuffer
  )
