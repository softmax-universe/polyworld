from ../shaders/screens import fullscreenPosition
## GPU screen-space ambient occlusion with resolved depth snapshots.

import
  shady, vmath,
  common, ../shaders/screenocclusions

export screenocclusions

type
  ScreenOcclusion* = object
    settings*: ScreenOcclusionSettings
    size: IVec2
    depth, ground: RenderTarget
    groundCaptured: bool
    occlusion: array[2, RenderTarget]
    occlusionPass, blurPass, multiplyPass: ShaderProgram

proc ensureSize(
    occlusion: var ScreenOcclusion, size: IVec2, source: RenderTarget
) =
  ## Matches depth snapshots to the scene and AO targets to half resolution.
  if occlusion.size == size and occlusion.depth.stencil == source.stencil:
    return
  destroy(occlusion.depth)
  destroy(occlusion.ground)
  for target in occlusion.occlusion:
    destroy(target)
  occlusion.size = size
  occlusion.groundCaptured = false
  occlusion.depth = newRenderTarget(size.x, size.y, color = false,
    stencil = source.stencil)
  occlusion.ground = newRenderTarget(size.x, size.y, color = false,
    stencil = source.stencil)
  occlusion.depth.depth.setTextureSampling(linear = false)
  occlusion.ground.depth.setTextureSampling(linear = false)
  for target in occlusion.occlusion.mitems:
    target = newRenderTarget(
      max(size.x div 2, 1), max(size.y div 2, 1), depth = false
    )
    target.color.setPassSampling(linear = true)

proc initScreenOcclusion*(
    settings = defaultScreenOcclusionSettings()
): ScreenOcclusion =
  ## Compiles the shared Shady passes for Native.
  result.settings = settings
  const Vertex = nativeStage(fullscreenVertex, shaderVertex)
  result.occlusionPass = newProgram(
    nativeStage(fullscreenPosition, shaderVertex), nativeStage(occlusionFragment, shaderFragment)
  )
  result.blurPass = newProgram(
    Vertex, nativeStage(blurFragment, shaderFragment)
  )
  result.multiplyPass = newProgram(
    Vertex, nativeStage(multiplyFragment, shaderFragment)
  )

proc closeScreenOcclusion*(occlusion: var ScreenOcclusion) =
  ## Releases every snapshot, target, and pipeline owned by the pass.
  destroy(occlusion.depth)
  destroy(occlusion.ground)
  for target in occlusion.occlusion:
    destroy(target)
  destroy(occlusion.occlusionPass)
  destroy(occlusion.blurPass)
  destroy(occlusion.multiplyPass)
  occlusion = ScreenOcclusion(settings: occlusion.settings)

proc captureGround*(
    occlusion: var ScreenOcclusion,
    size: IVec2,
    source: RenderTarget = nil
) =
  ## Captures scenery depth before bodies are drawn into the current target.
  if not occlusion.settings.enabled or size.x <= 0 or size.y <= 0:
    return
  let target = if source == nil: gpuRenderer.target else: source
  occlusion.ensureSize(size, target)
  copyTarget(target, occlusion.ground, color = false)
  occlusion.groundCaptured = true

proc applyScreenOcclusion*(
    occlusion: var ScreenOcclusion,
    size: IVec2,
    projection: Mat4,
    source: RenderTarget = nil
) =
  ## Darkens scene contact points while retaining its depth and alpha.
  defer:
    occlusion.groundCaptured = false
  let settings = occlusion.settings
  if not settings.enabled or size.x <= 0 or size.y <= 0:
    return
  let destination = if source == nil: gpuRenderer.target else: source
  occlusion.ensureSize(size, destination)
  let
    inverseProjection = projection.inverse
    clipW = vec2(projection[2, 3], projection[3, 3])
    depthTexel = vec2(1'f / size.x.float32, 1'f / size.y.float32)
    halfSize = vec2(
      occlusion.occlusion[0].width.float32,
      occlusion.occlusion[0].height.float32
    )
  copyTarget(destination, occlusion.depth, color = false)

  let samplePass = occlusion.occlusionPass
  samplePass.bindTexture("depthTexture", occlusion.depth.depth)
  samplePass.setUniform("inverseProjection", inverseProjection)
  samplePass.setUniform("projectionScale",
    vec2(projection[0, 0], projection[1, 1]))
  samplePass.setUniform("clipW", clipW)
  samplePass.setUniform("texel", depthTexel)
  samplePass.setUniform("radius", settings.radius)
  samplePass.setUniform("intensity", settings.intensity)
  samplePass.setUniform("bias", settings.bias)
  samplePass.setUniform("textureYTransform", vec2(-1, 1))
  samplePass.setUniform("fragmentYTransform", vec2(-1, halfSize.y))
  pushTarget(occlusion.occlusion[0])
  draw(samplePass, nil, 3)
  popTarget()

  let blurPass = occlusion.blurPass
  blurPass.bindTexture("depthTexture", occlusion.depth.depth)
  blurPass.setUniform("halfSize", halfSize)
  blurPass.setUniform("depthTexel", depthTexel)
  blurPass.setUniform("depthTerms", vec4(
    inverseProjection[2, 2], inverseProjection[3, 2],
    inverseProjection[2, 3], inverseProjection[3, 3]))
  blurPass.setUniform("clipW", clipW)
  blurPass.setUniform("edgeScale", settings.sharpness * projection[1, 1])
  blurPass.setUniform("textureYTransform", vec2(-1, 1))
  for (input, output, axis) in [(0, 1, vec2(1, 0)), (1, 0, vec2(0, 1))]:
    blurPass.bindTexture("occlusionTexture", occlusion.occlusion[input].color)
    blurPass.setUniform("direction", axis / halfSize)
    pushTarget(occlusion.occlusion[output])
    draw(blurPass, nil, 3)
    popTarget()

  let multiplyPass = occlusion.multiplyPass
  multiplyPass.bindTexture("occlusionTexture", occlusion.occlusion[0].color)
  multiplyPass.bindTexture("depthTexture", occlusion.depth.depth)
  multiplyPass.bindTexture("groundTexture",
    if occlusion.groundCaptured: occlusion.ground.depth
    else: occlusion.depth.depth)
  multiplyPass.setUniform("tint", settings.tint)
  multiplyPass.setUniform("bodyOcclusion", settings.bodyOcclusion)
  multiplyPass.setUniform("textureYTransform", vec2(-1, 1))
  pushTarget(destination)
  draw(multiplyPass, nil, 3, DrawState(blend: Multiply))
  popTarget()
