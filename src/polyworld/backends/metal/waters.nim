## Metal water captures, textures and draws.

import metal4 except string
import
  pixie,
  ./common, ./textures

type ShoreField = object
  texture: MetalTexture
  origin, size: Vec2

var
  reflectionTarget, sceneCopy: RenderTarget
  blankTexture, foamNoiseTexture: MetalTexture
  shoreFields: seq[ShoreField]
  skyProgram: MetalProgram
  skyVertexBuffer: MetalBuffer
  reflectionActive: bool

proc endReflection*() =
  ## Restores the render target and viewport saved by beginReflection.
  if reflectionActive:
    popTarget()
    reflectionActive = false

proc destroyWaters*() =
  ## Releases every water resource and permits another initialization.
  endReflection()
  for field in shoreFields:
    destroy(field.texture)
  shoreFields.setLen(0)
  destroy(reflectionTarget)
  destroy(sceneCopy)
  destroy(blankTexture)
  destroy(foamNoiseTexture)
  destroy(skyProgram)
  destroy(skyVertexBuffer)
  reflectionTarget = nil
  sceneCopy = nil
  blankTexture = nil
  foamNoiseTexture = nil
  skyProgram = nil
  skyVertexBuffer = nil

proc installWaters*() =
  ## Selects the shared Shady water shader before terrain initialization.
  waterPremultipliedAlpha = true
  waterShaderOverride = (
    toShader(watersVert, metalMSL, shaderVertex),
    toShader(watersFrag, metalMSL, shaderFragment))

proc initWaters*() =
  ## Creates the water textures and reflection sky on the active Metal device.
  destroyWaters()
  var initialized = false
  defer:
    if not initialized:
      destroyWaters()
  let
    noise = tileableNoise()
    noiseImage = newImage(256, 256)
  for index, value in noise:
    noiseImage.data[index] = rgbx(value, value, value, 255)
  foamNoiseTexture = newTexture(noiseImage, linear = true, repeat = true,
    mipmaps = true)
  foamNoiseTexture.setTextureSampling(
    linear = true, repeat = true, anisotropy = 1
  )
  let white = newImage(1, 1)
  white.fill(rgba(255, 255, 255, 255))
  blankTexture = newTexture(white, linear = false)
  skyProgram = newProgram(
    toShader(waterSkyVert, metalMSL, shaderVertex),
    toShader(waterSkyFrag, metalMSL, shaderFragment),
    VertexLayout(stride: 2 * sizeof(float32), attributes: @[
      VertexAttribute(name: "vertPos", format: Float2, offset: 0)
    ])
  )
  skyVertexBuffer = newBuffer([-1.0'f, -1, 3, -1, -1, 3])
  initialized = true

proc drawWaterSky*(
  viewProjection: Mat4, eye: Vec3, zenith, horizon, ground: Color
) =
  ## Fills the reflection viewport with sky without writing depth.
  skyProgram.setUniform("skyInverseViewProjection", viewProjection.inverse)
  skyProgram.setUniform("skyEye", eye)
  skyProgram.setUniform("skyZenith", vec3(zenith.r, zenith.g, zenith.b))
  skyProgram.setUniform("skyHorizon", vec3(horizon.r, horizon.g, horizon.b))
  skyProgram.setUniform("skyGround", vec3(ground.r, ground.g, ground.b))
  draw(skyProgram, skyVertexBuffer, 3,
    DrawState(depthTest: false, depthWrite: false, cull: CullNone,
      blend: Opaque, primitive: Triangles))

proc beginReflection*(size: IVec2) {.measure.} =
  ## Starts a full-resolution HDR reflection, retaining the current target.
  if reflectionActive:
    raise newException(PolyworldWaterError, "water reflection is already active")
  if size.x <= 0 or size.y <= 0:
    raise newException(PolyworldWaterError, "water reflection size must be positive")
  if reflectionTarget == nil or reflectionTarget.width != size.x or
      reflectionTarget.height != size.y:
    destroy(reflectionTarget)
    reflectionTarget = newRenderTarget(size.x, size.y,
      colorFormat = MTLPixelFormatRGBA16Float)
    reflectionTarget.color.setTextureSampling(linear = true, anisotropy = 1)
  pushTarget(reflectionTarget)
  reflectionActive = true
  clearDepth()

proc buildShoreField(layerIndex: int): ShoreField =
  ## Uploads one layer's shared shore distance samples with linear filtering.
  let data = buildShoreFieldData(layerIndex)
  result.origin = data.origin
  result.size = data.size
  if data.distances.len > 0:
    result.texture = createR32fTexture(data.width, data.height,
      data.distances, linear = true)
  else:
    result.texture = createR32fTexture(1, 1, [ShoreFieldReach], linear = true)

proc buildShoreFields*() =
  ## Rebuilds every water layer's shore field from the current terrain.
  for field in shoreFields:
    destroy(field.texture)
  shoreFields = newSeq[ShoreField](layers.len)
  for i in 0 ..< layers.len:
    if layers[i].water and i < waterLayerSurfaces.len:
      shoreFields[i] = buildShoreField(i)

proc captureScene*(size: IVec2) {.measure.} =
  ## Copies the current color and resolved depth while preserving its target.
  if size.x <= 0 or size.y <= 0:
    raise newException(PolyworldWaterError, "water capture size must be positive")
  let source = metalRenderer.target
  if source == nil or source.color == nil or source.depth == nil:
    raise newException(PolyworldWaterError,
      "water capture needs a color and depth render target")
  if source.width != size.x or source.height != size.y:
    raise newException(PolyworldWaterError,
      "water capture size must match the current render target")
  if sceneCopy == nil or sceneCopy.width != size.x or
      sceneCopy.height != size.y or sceneCopy.stencil != source.stencil or
      sceneCopy.color.pixelFormat != source.color.pixelFormat:
    destroy(sceneCopy)
    sceneCopy = newRenderTarget(size.x, size.y,
      colorFormat = source.color.pixelFormat, stencil = source.stencil)
    sceneCopy.color.setTextureSampling(linear = true, anisotropy = 1)
    sceneCopy.depth.setTextureSampling(linear = false)
  copyTarget(source, sceneCopy, color = true, depth = true)

proc drawWaterBody*(body: WaterBody, viewProjection: Mat4, eye: Vec3, windowSize: IVec2,
    sunToward: Vec3, sunLight: Color, rect: IVec4, reflected: bool) {.measure.} =
  ## Draws one body of water over the captured scene.
  if shoreFields.len != layers.len:
    buildShoreFields()
  let
    params = body.params
    vertices = waterLayerRanges[body.layer]
    program = waterShaderProgram()
  if vertices.len == 0:
    return
  program.setUniform("inverseViewProjection", viewProjection.inverse)
  program.setUniform("depthViewport", vec4(
    rect.x / windowSize.x, rect.y / windowSize.y,
    rect.z / windowSize.x, rect.w / windowSize.y))
  template uniform(name: string, value: untyped) =
    program.setUniform(name, value)
  uniform("captureFlipY", 1.0'f)
  uniform("waterColor", params.color)
  uniform("sunColor", vec3(sunLight.r, sunLight.g, sunLight.b))
  uniform("waterSunToward", sunToward)
  uniform("waterLift", params.lift)
  # A view without its reflection pass reflects nothing at any angle.
  uniform("reflectiveness", if reflected: params.reflectiveness else: 0.0'f)
  uniform("fresnelStrength", if reflected: params.fresnelStrength else: 0.0'f)
  uniform("colorStrength", params.colorStrength)
  uniform("fresnelPower", params.fresnelPower)
  uniform("sheenStrength", params.sheenStrength)
  uniform("sheenSharpness", params.sheenSharpness)
  uniform("glintStrength", params.glintStrength)
  uniform("glintSharpness", params.glintSharpness)
  uniform("waveHeight", params.waveHeight)
  uniform("waveScale", max(params.waveScale, 0.001))
  uniform("waveSpeed", params.waveSpeed)
  uniform("waveDrag", params.waveDrag)
  uniform("waveCount", params.waveCount)
  uniform("rippleFade", max(params.rippleFade, 0.001))
  uniform("distortion", params.distortion)
  uniform("refraction", params.refraction)
  uniform("refractionDepth", max(params.refractionDepth, 0.001))
  uniform("foamColor", params.foamColor)
  uniform("foamDistance", params.foamDistance)
  uniform("foamOpacity", params.foamOpacity)
  # GLSL leaves smoothstep undefined for equal edges.
  uniform("foamSoftness", clamp(params.foamSoftness, 0.01, 1))
  uniform("foamNoise", clamp(params.foamNoise, 0, 1))
  uniform("foamScale", params.foamScale)
  uniform("foamSpeed", params.foamSpeed)
  uniform("fadeDistance", params.fadeDistance)
  uniform("fadeCurve", params.fadeCurve)
  let field = shoreFields[body.layer]
  program.setUniform("shoreFieldBounds", vec4(field.origin.x,
    field.origin.y, max(field.size.x, 0.001), max(field.size.y, 0.001)))
  # Wrapped every 10,000 s to keep float32 precision; the jump is rare and brief.
  uniform("rippleClock", float32((epochTime() - startTime) mod 10_000))
  program.bindTexture("reflectionTex",
    if reflected: reflectionTarget.color else: blankTexture)
  program.bindTexture("sceneDepthTex", sceneCopy.depth)
  program.bindTexture("sceneColorTex", sceneCopy.color)
  program.bindTexture("shoreField", field.texture)
  program.bindTexture("foamNoiseTex", foamNoiseTexture)
  drawWater(viewProjection, eye, firstVertex = vertices.a,
    vertexCount = vertices.len)
