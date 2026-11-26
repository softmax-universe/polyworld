## Shared CaC ambient occlusion, bloom, and final composition passes.

import
  pixie, shady, vmath,
  polyworld/backends/passes/common,
  polyworld/backends/shaders/screens,
  ../../postshared, ../shaders/post

from polyworld/renderer import FramebufferHandle

export postshared

when PostLayerControls:
  import std/[os, strutils]

type
  PostFx* = object
    settings*: PostSettings
    size: IVec2
    scene, materialNormals: RenderTarget
    occlusion: array[2, RenderTarget]
    beforeVfx: RenderTarget
    bloom: array[BloomLevels, RenderTarget]
    occlusionPass, blurPass, multiplyPass: ShaderProgram
    prefilterPass, downPass, upPass, finalPass, copyPass: ShaderProgram
    near, far: float32
    sceneActive: bool
    when PostLayerControls:
      layer*: PostLayer
      layerPass: ShaderProgram
      inverseProjection: Mat4

const
  FullscreenVertex = nativeStage(fullscreenTextureVertex, shaderVertex)
  OcclusionFragment = nativeStage(postOcclusion, shaderFragment)
  BlurFragment = nativeStage(postBlur, shaderFragment)
  MultiplyFragment = nativeStage(postMultiply, shaderFragment)
  PrefilterFragment = nativeStage(postPrefilter, shaderFragment)
  DownFragment = nativeStage(postDown, shaderFragment)
  UpFragment = nativeStage(postUp, shaderFragment)
  FinalFragment = nativeStage(postFinal, shaderFragment)
  CopyFragment = nativeStage(copyFragment, shaderFragment)

when PostLayerControls:
  const LayerFragment = nativeStage(postLayer, shaderFragment)

proc texel(target: RenderTarget): Vec2 =
  ## Returns the reciprocal texture dimensions for filter offsets.
  vec2(1.0'f / target.width.float32, 1.0'f / target.height.float32)

proc showing(post: PostFx, layer: PostLayer): bool =
  ## Reports whether the optional layer viewer selects this pass.
  when PostLayerControls:
    post.layer == layer
  else:
    false

proc releaseTargets(post: var PostFx) =
  ## Releases size-dependent attachments before rebuilding them.
  destroy(post.materialNormals)
  destroy(post.scene)
  destroy(post.beforeVfx)
  for target in post.occlusion.mitems:
    destroy(target)
  for target in post.bloom.mitems:
    destroy(target)

proc ensureSize(post: var PostFx, size: IVec2) =
  ## Allocates the scene, shared-depth normals, AO, and bloom attachments.
  if size == post.size:
    return
  post.releaseTargets()
  post.size = size
  post.scene = newRenderTarget(size.x, size.y, stencil = true)
  post.materialNormals = newRenderTarget(size.x, size.y, depth = false)
  shareDepth(post.materialNormals, post.scene)
  post.scene.depth.setTextureSampling(linear = false)
  post.materialNormals.color.setTextureSampling(linear = false)
  let half = ivec2(max(size.x div 2, 1), max(size.y div 2, 1))
  for target in post.occlusion.mitems:
    target = newRenderTarget(half.x, half.y, depth = false)
  post.beforeVfx = newRenderTarget(half.x, half.y, depth = false)
  var levelSize = half
  for target in post.bloom.mitems:
    target = newRenderTarget(levelSize.x, levelSize.y, depth = false)
    levelSize = ivec2(max(levelSize.x div 2, 1), max(levelSize.y div 2, 1))

proc newPostProgram(fragment: string): ShaderProgram =
  ## Compiles shared fullscreen stages with the target's sampling orientation.
  result = newProgram(FullscreenVertex, fragment)
  result.setUniform("screenTextureYTransform",
    (when PassTopLeftOrigin: vec2(-1, 1) else: vec2(1, 0)))

proc initPostFx*(): PostFx =
  ## Creates the AO, bloom, and composition programs.
  result.settings = defaultPostSettings()
  result.near = 0.1
  result.far = 100
  result.occlusionPass = newProgram(
    nativeStage(fullscreenPosition, shaderVertex), OcclusionFragment
  )
  result.blurPass = newPostProgram(BlurFragment)
  result.multiplyPass = newPostProgram(MultiplyFragment)
  result.prefilterPass = newPostProgram(PrefilterFragment)
  result.downPass = newPostProgram(DownFragment)
  result.upPass = newPostProgram(UpFragment)
  result.finalPass = newPostProgram(FinalFragment)
  result.copyPass = newPostProgram(CopyFragment)
  when PostLayerControls:
    result.layerPass = newPostProgram(LayerFragment)
    let key =
      try:
        parseInt(getEnv("CAC_POST_LAYER", "1"))
      except ValueError:
        1
    result.layer = PostLayer(((key + 9) mod 10 + 10) mod 10)

proc drawFullscreen(pass: ShaderProgram, blend = Opaque) =
  ## Draws a generated triangle without changing the caller's depth.
  draw(pass, nil, 3, DrawState(blend: blend))

proc drawTo(pass: ShaderProgram, target: RenderTarget, blend = Opaque) =
  ## Encodes one fullscreen pass and restores the enclosing target.
  pushTarget(target)
  pass.drawFullscreen(blend)
  popTarget()

proc beginScene*(post: var PostFx, size: IVec2, near, far: float32) =
  ## Routes opaque geometry into the scene target until final composition.
  if not post.settings.enabled:
    return
  if post.sceneActive:
    raise newException(ValueError, "CaC post scene was not presented.")
  post.ensureSize(ivec2(max(size.x, 1), max(size.y, 1)))
  post.near = near
  post.far = far
  pushTarget(post.materialNormals)
  clear(color(0, 0, 0, 0), depth = false)
  popTarget()
  pushTarget(post.scene)
  post.sceneActive = true

proc beginMaterialNormals*(post: PostFx): bool =
  ## Replays mapped normals against the completed scene depth attachment.
  if not post.settings.enabled or
    (not post.settings.occlusion and not post.showing(NormalLayer)):
      return false
  pushTarget(post.materialNormals)
  clearStencilState()
  true

proc endMaterialNormals*(post: PostFx) =
  ## Resumes the scene after its visible material normal replay.
  popTarget()

proc applyOcclusion*(post: var PostFx, projection: Mat4) =
  ## Filters scene occlusion and captures the scene before emissive effects.
  if not post.settings.enabled:
    return
  preserveDrawState:
    clearStencilState()
    let settings = post.settings
    when PostLayerControls:
      post.inverseProjection = projection.inverse
    if settings.occlusion:
      let pass = post.occlusionPass
      pass.bindTexture("depthTexture", post.scene.depth)
      pass.bindTexture("normalTexture", post.materialNormals.color)
      pass.setUniform("inverseProjection", projection.inverse)
      pass.setUniform("projectionY", (when PassTopLeftOrigin: -1.0'f else: 1.0'f))
      pass.setUniform("projectionScale", vec2(projection[0, 0], projection[1, 1]))
      pass.setUniform("texel", post.scene.texel)
      pass.setUniform("radius", settings.occlusionRadius)
      pass.setUniform("intensity", settings.occlusionIntensity)
      pass.setUniform("bias", settings.occlusionBias)
      pass.setUniform("normalDetail", settings.occlusionNormalDetail)
      pass.drawTo(post.occlusion[0])

      let blur = post.blurPass
      blur.bindTexture("depthTexture", post.scene.depth)
      blur.setUniform("sharpness", settings.occlusionSharpness)
      blur.setUniform("near", post.near)
      blur.setUniform("far", post.far)
      if not post.showing(RawOcclusionLayer):
        for (source, destination, axis) in
          [(0, 1, vec2(1, 0)), (1, 0, vec2(0, 1))]:
            blur.bindTexture("occlusionTexture", post.occlusion[source].color)
            blur.setUniform("direction", axis * post.occlusion[source].texel)
            blur.drawTo(post.occlusion[destination])

      post.multiplyPass.bindTexture("occlusionTexture", post.occlusion[0].color)
      post.multiplyPass.setUniform("tint", settings.occlusionTint)
      post.multiplyPass.drawFullscreen(Multiply)

    if settings.bloom:
      post.copyPass.bindTexture("copySource", post.scene.color)
      post.copyPass.drawTo(post.beforeVfx)

when PostLayerControls:
  proc layerAvailable*(post: PostFx): bool =
    ## Reports whether the selected diagnostic pass is currently enabled.
    case post.layer
    of RawOcclusionLayer, OcclusionLayer:
      post.settings.occlusion
    of BeforeVfxLayer, VfxLayer, BloomSourceLayer, BloomLayer:
      post.settings.bloom
    else:
      true

  proc drawLayer(post: var PostFx) =
    ## Displays an intermediate texture with the shared diagnostic shader.
    var
      color = post.scene.color
      other = post.scene.color
      mode = 0'i32
      scale = 1.0'f
    case post.layer
    of FinalLayer, SceneLayer:
      discard
    of DepthLayer:
      mode = 1
    of NormalLayer:
      mode = 2
    of RawOcclusionLayer, OcclusionLayer:
      color = post.occlusion[0].color
    of BeforeVfxLayer:
      color = post.beforeVfx.color
    of VfxLayer:
      mode = 3
      other = post.beforeVfx.color
    of BloomSourceLayer:
      color = post.bloom[0].color
    of BloomLayer:
      color = post.bloom[0].color
      scale = post.settings.bloomStrength
    if not post.layerAvailable():
      scale = 0
    let pass = post.layerPass
    pass.bindTexture("colorTexture", color)
    pass.bindTexture("otherTexture", other)
    pass.bindTexture("depthTexture", post.scene.depth)
    pass.bindTexture("normalTexture", post.materialNormals.color)
    pass.setUniform("inverseProjection", post.inverseProjection)
    pass.setUniform("projectionY", (when PassTopLeftOrigin: -1.0'f else: 1.0'f))
    pass.setUniform("texel", post.scene.texel)
    pass.setUniform("mode", mode)
    pass.setUniform("scale", scale)
    pass.setUniform("near", post.near)
    pass.setUniform("far", post.far)
    pass.drawFullscreen()

proc present*(post: var PostFx, windowSize: IVec2,
    outputFramebuffer: FramebufferHandle = default(FramebufferHandle)) =
  ## Composes into the caller's frame or screenshot target before its HUD.
  if not post.settings.enabled:
    return
  preserveDrawState:
    clearStencilState()
    let settings = post.settings
    if settings.bloom:
      let pass = post.prefilterPass
      pass.bindTexture("sceneTexture", post.scene.color)
      pass.bindTexture("beforeTexture", post.beforeVfx.color)
      pass.setUniform("texel", post.scene.texel)
      pass.setUniform("threshold", settings.bloomThreshold)
      pass.setUniform("vfxWeight", settings.bloomVfx)
      pass.setUniform("useVfx", 1.0'f)
      pass.drawTo(post.bloom[0])
      let levels =
        if post.showing(BloomSourceLayer):
          1
        else:
          BloomLevels
      for level in 1 ..< levels:
        post.downPass.bindTexture("sourceTexture", post.bloom[level - 1].color)
        post.downPass.setUniform("texel", post.bloom[level - 1].texel)
        post.downPass.drawTo(post.bloom[level])
      for level in countdown(levels - 1, 1):
        post.upPass.bindTexture("sourceTexture", post.bloom[level].color)
        post.upPass.setUniform("texel", post.bloom[level].texel)
        post.upPass.drawTo(post.bloom[level - 1], Additive)

    popTarget()
    post.sceneActive = false
    let output =
      when PassTopLeftOrigin:
        if outputFramebuffer != nil: outputFramebuffer
        else: gpuRenderer.frameTarget
      else:
        targetFromNative(outputFramebuffer, windowSize)
    pushTarget(output)
    let pass = post.finalPass
    pass.bindTexture("sceneTexture", post.scene.color)
    pass.bindTexture("bloomTexture", post.bloom[0].color)
    pass.setUniform("texel", post.scene.texel)
    pass.setUniform("useFxaa", if settings.fxaa: 1.0'f else: 0.0'f)
    pass.setUniform("bloomStrength",
      if settings.bloom: settings.bloomStrength else: 0.0'f)
    pass.setUniform("vignette", settings.vignette)
    pass.setUniform("vignetteStart", settings.vignetteStart)
    pass.setUniform("vignetteEnd", settings.vignetteEnd)
    pass.setUniform("saturation", settings.saturation)
    pass.setUniform("contrast", settings.contrast)
    when PostLayerControls:
      if post.layer == FinalLayer:
        pass.drawFullscreen()
      else:
        post.drawLayer()
    else:
      pass.drawFullscreen()
    popTarget()

proc dispose*(post: var PostFx) =
  ## Releases post-processing attachments and compiled shader programs.
  post.releaseTargets()
  for pass in [post.occlusionPass, post.blurPass, post.multiplyPass,
    post.prefilterPass, post.downPass, post.upPass, post.finalPass,
    post.copyPass]:
      destroy(pass)
  when PostLayerControls:
    destroy(post.layerPass)
  post = PostFx()
