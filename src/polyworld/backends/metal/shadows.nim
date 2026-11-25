import ./common as metal

var
  sunShadowTextures*: array[2, MetalTexture]
  sunTargets: array[2, RenderTarget]
  depthProgram, cutoutDepthProgram: MetalProgram
  unshadowedTarget: RenderTarget
  shadowPassActive = false

proc initSunShadows*(
  lightRadius = 100.0'f, lightDistance = 170.0'f
) =
  ## Creates depth-only targets and Shady programs for both sun steps.
  if sunTargets[0] != nil:
    return
  if getEnv("SUN_SHADOWS") == "0":
    sunShadowsEnabled = false
  sunLightRadius = lightRadius
  sunLightDistance = lightDistance
  depthProgram = newProgram(
    toShader(sunDepthVert, metalMSL, shaderVertex),
    "",
    VertexLayout(
      stride: 3 * sizeof(float32),
      attributes: @[
        VertexAttribute(name: "vertPos", format: Float3, offset: 0)
      ]
    )
  )
  cutoutDepthProgram = newProgram(
    toShader(sunCutoutDepthVert, metalMSL, shaderVertex),
    toShader(sunCutoutDepthFrag, metalMSL, shaderFragment),
    VertexLayout(
      stride: 6 * sizeof(float32),
      attributes: @[
        VertexAttribute(name: "vertPos", format: Float3, offset: 0),
        VertexAttribute(
          name: "vertUv", format: Float3, offset: 3 * sizeof(float32)
        )
      ]
    )
  )
  for step in 0 .. 1:
    sunTargets[step] = newRenderTarget(
      SunShadowMapSize, SunShadowMapSize, color = false, depth = true
    )
    sunTargets[step].depth.setComparisonSampling(anisotropy = 1)
    sunShadowTextures[step] = sunTargets[step].depth
    pushTarget(sunTargets[step])
    clearDepth()
    popTarget()
  updateSunMatrix()

proc sunShadowsActive*(): bool =
  ## Returns whether depth maps exist and directional shadows are enabled.
  sunShadowsEnabled and sunTargets[0] != nil

proc sunDepthProgramId*(): MetalProgram =
  ## Returns the plain caster program for a backend vertex layout.
  depthProgram

proc sunCutoutProgramId*(): MetalProgram =
  ## Returns the alpha-cutout caster program for a backend vertex layout.
  cutoutDepthProgram

proc sunShadowMvp*(step: int): Mat4 =
  ## Maps light clip coordinates into Metal's top-left shadow texture space.
  let lightMatrix = if step == 0: sunLightMvp0 else: sunLightMvp1
  scale(vec3(1, -1, 1)) * lightMatrix

proc beginSunDepthPass*(step: int) =
  ## Selects and clears one shadow target, retaining the caller's target.
  assert step in 0 .. 1
  assert sunTargets[step] != nil, "initSunShadows must run before drawing"
  if shadowPassActive:
    popTarget()
  pushTarget(sunTargets[step])
  shadowPassActive = true
  clearDepth()
  activeDepthMvp = if step == 0: sunLightMvp0 else: sunLightMvp1

proc bindSunDepth*(transform: Mat4) =
  ## Uploads the caster transform to the depth-only program.
  setUniform(depthProgram, "sunDepthMvp", transform)

proc bindSunCutoutDepth*(transform: Mat4, alphaCutoff: float32) =
  ## Uploads the cutout caster transform and alpha threshold.
  setUniform(cutoutDepthProgram, "sunDepthMvp", transform)
  setUniform(cutoutDepthProgram, "cutoutCutoff", alphaCutoff)

proc sunUploadModel*(transform: Mat4) =
  ## Uploads the plain shadow transform for backend-neutral terrain drawing.
  bindSunDepth(transform)

proc sunUploadCutoutModel*(transform: Mat4, alphaCutoff: float32) =
  ## Uploads the cutout shadow transform and alpha threshold.
  bindSunCutoutDepth(transform, alphaCutoff)

proc sunBindCutoutTexture*(texture: MetalTexture) =
  ## Binds the caster texture array used for alpha-tested shadows.
  bindTexture(cutoutDepthProgram, "cutoutTextures", texture)

proc endSunDepthPass*(windowSize: IVec2) =
  ## Restores the caller's target after the active shadow pass.
  if shadowPassActive:
    popTarget()
    shadowPassActive = false

template sunDepthPasses*(windowSize: IVec2, body: untyped) =
  ## Draws both cross-fade maps and restores the target if a draw fails.
  if sunShadowsActive():
    try:
      let lastShadowStep = (sunShadowBlend > 0).ord
      for sunPassIndex {.inject.} in 0 .. lastShadowStep:
        beginSunDepthPass(sunPassIndex)
        body
    finally:
      endSunDepthPass(windowSize)

proc initUnshadowedShadows*() =
  ## Supplies all-lit comparison textures for scenes without shadow maps.
  if unshadowedTarget != nil:
    return
  unshadowedTarget = newRenderTarget(1, 1, color = false, depth = true)
  unshadowedTarget.depth.setComparisonSampling(linear = false, anisotropy = 1)
  pushTarget(unshadowedTarget)
  clearDepth()
  popTarget()
  sunShadowTextures = [unshadowedTarget.depth, unshadowedTarget.depth]

proc closeUnshadowedShadows*() =
  ## Releases comparison textures created for an unshadowed scene.
  if unshadowedTarget == nil:
    return
  for texture in sunShadowTextures.mitems:
    if texture == unshadowedTarget.depth:
      texture = nil
  destroy(unshadowedTarget)
  unshadowedTarget = nil

proc closeSunShadows*() =
  ## Releases the sun targets and programs before the Metal context closes.
  endSunDepthPass(ivec2(0, 0))
  closeUnshadowedShadows()
  for step in 0 .. 1:
    sunShadowTextures[step] = nil
    destroy(sunTargets[step])
    sunTargets[step] = nil
  destroy(depthProgram)
  destroy(cutoutDepthProgram)
  depthProgram = nil
  cutoutDepthProgram = nil
