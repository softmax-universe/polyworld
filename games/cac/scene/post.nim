## Full-screen effects for the CaC client.
##
## The 3D scene renders into an offscreen target instead of the window:
##
## 1. Opaque pass (table, cards, characters) into `scene`.
## 2. Visible material normals are replayed against the finished depth. Other
##    surfaces retain the depth-reconstructed normal; the sky has no normal.
## 3. `applyOcclusion`: screen-space ambient occlusion from the scene depth,
##    at half resolution, blurred with a depth-aware filter and multiplied
##    into the scene. It runs before the VFX, so glows are never darkened.
## 4. The VFX draw on top. `present` extracts the light they added (plus the
##    brightest scene highlights) into a bloom chain, then writes the scene to
##    the window with FXAA, bloom, a gentle grade, vignette and dither.
##
## The HUD draws on the window afterwards and is not affected.
##
## CAC_POSTFX=0 disables everything (the old direct path). CAC_SSAO=0,
## CAC_BLOOM=0 and CAC_FXAA=0 disable one effect each. F8 toggles all of it.
##
## Build with -d:cacPostLayers to show one intermediate layer instead of the
## final image (see PostLayer; CAC_POST_LAYER=N picks one at startup).
## Build with -d:cacPostPanel for a window that tunes every setting live.

import
  std/[os, strutils, tables],
  opengl, shady, vmath,
  postshaders

const
  BloomLevels = 4
  PostLayerControls* {.booldefine: "cacPostLayers".} = false
    ## Compiles the layer views: the window can show any PostLayer.
  PostPanelControls* {.booldefine: "cacPostPanel".} = false
    ## Compiles the tuning window in postpanel.nim.

type
  PostLayer* = enum
    ## What the window shows. Key 1 is the final image, 2..9 then 0 the rest.
    FinalLayer = "final image"
    SceneLayer = "scene before bloom and grading"
    DepthLayer = "depth"
    NormalLayer = "surface normals"
    RawOcclusionLayer = "occlusion, unblurred"
    OcclusionLayer = "occlusion"
    BeforeVfxLayer = "scene before VFX"
    VfxLayer = "light added by VFX"
    BloomSourceLayer = "bloom source"
    BloomLayer = "bloom"

  PostPass = object
    program: GLuint
    locations: Table[string, GLint]

  RenderTarget = object
    framebuffer: GLuint
    texture: GLuint
    size: IVec2

  PostSettings* = object
    enabled*: bool
    occlusion*: bool
    bloom*: bool
    fxaa*: bool
    occlusionRadius*: float32     ## World units the AO looks around a pixel.
    occlusionIntensity*: float32
    occlusionBias*: float32       ## Cosine ignored, hides flat-surface noise.
    occlusionTint*: Vec3          ## Color occlusion fades toward.
    occlusionSharpness*: float32  ## How hard the blur stops at depth edges.
    occlusionNormalDetail*: float32 ## Mapped surface relief the AO reacts to.
    bloomThreshold*: float32      ## Scene brightness that starts to glow.
    bloomVfx*: float32            ## How much of the VFX light glows.
    bloomStrength*: float32
    vignette*: float32
    vignetteStart*: float32       ## Distance from the center it begins.
    vignetteEnd*: float32         ## Distance where it reaches full strength.
    saturation*: float32
    contrast*: float32

  PostFx* = object
    settings*: PostSettings
    size: IVec2
    sceneFramebuffer: GLuint
    sceneColor: GLuint
    sceneDepth: GLuint            ## Depth-stencil, sampled for occlusion.
    materialNormals: RenderTarget ## View-space RGB; alpha marks mapped surfaces.
    occlusion: array[2, RenderTarget]
    beforeVfx: RenderTarget       ## Half-res copy of the scene before VFX.
    bloom: array[BloomLevels, RenderTarget]
    vertexArray: GLuint
    occlusionPass, blurPass, multiplyPass: PostPass
    prefilterPass, downPass, upPass, finalPass: PostPass
    near, far: float32
    when PostLayerControls:
      layer*: PostLayer
      layerPass: PostPass
      inverseProjection: Mat4

const
  PostShaderTarget =
    when defined(emscripten):
      glsl3WebGL
    else:
      glsl4Desktop
  FullscreenVertex = toShader(postVertex, PostShaderTarget, shaderVertex)
  OcclusionFragment = toShader(postOcclusion, PostShaderTarget, shaderFragment)
  BlurFragment = toShader(postBlur, PostShaderTarget, shaderFragment)
  MultiplyFragment = toShader(postMultiply, PostShaderTarget, shaderFragment)
  PrefilterFragment = toShader(postPrefilter, PostShaderTarget, shaderFragment)
  DownFragment = toShader(postDown, PostShaderTarget, shaderFragment)
  UpFragment = toShader(postUp, PostShaderTarget, shaderFragment)
  FinalFragment = toShader(postFinal, PostShaderTarget, shaderFragment)

when PostLayerControls:
  const LayerFragment = toShader(postLayer, PostShaderTarget, shaderFragment)

proc envFlag(name: string, default = true): bool =
  let value = getEnv(name)
  if value.len == 0: default else: value notin ["0", "false", "off", "no"]

proc envFloat(name: string, default: float32): float32 =
  try: parseFloat(getEnv(name, $default)).float32
  except ValueError: default

proc defaultPostSettings*(): PostSettings =
  PostSettings(
    enabled: envFlag("CAC_POSTFX"),
    occlusion: envFlag("CAC_SSAO"),
    bloom: envFlag("CAC_BLOOM"),
    fxaa: envFlag("CAC_FXAA"),
    occlusionRadius: envFloat("CAC_SSAO_RADIUS", 1.501),
    occlusionIntensity: envFloat("CAC_SSAO_INTENSITY", 3.523),
    occlusionBias: envFloat("CAC_SSAO_BIAS", 0.08),
    occlusionTint: vec3(0.10, 0.10, 0.16),
    occlusionSharpness: 40,
    occlusionNormalDetail: 0.45,
    bloomThreshold: 0.922,
    bloomVfx: 1.0,
    bloomStrength: 0.75,
    vignette: 0.32,
    vignetteStart: 0.35,
    vignetteEnd: 1.05,
    saturation: 1.06,
    contrast: 0.12
  )

proc compileStage(kind: GLenum, source, label: string): GLuint =
  result = glCreateShader(kind)
  let sources = allocCStringArray([source])
  defer:
    deallocCStringArray(sources)
  glShaderSource(result, 1, sources, nil)
  glCompileShader(result)
  var status: GLint
  glGetShaderiv(result, GL_COMPILE_STATUS, status.addr)
  if status == 0:
    var length: GLint
    glGetShaderiv(result, GL_INFO_LOG_LENGTH, length.addr)
    var log = newString(length)
    glGetShaderInfoLog(result, length, nil, log.cstring)
    raise newException(CatchableError,
      "CaC post " & label & " shader failed:\n" & log)

proc compilePass(fragment, label: string): PostPass =
  let
    vertexShader = compileStage(GL_VERTEX_SHADER, FullscreenVertex, label)
    fragmentShader = compileStage(GL_FRAGMENT_SHADER, fragment, label)
  result.program = glCreateProgram()
  glAttachShader(result.program, vertexShader)
  glAttachShader(result.program, fragmentShader)
  glLinkProgram(result.program)
  glDeleteShader(vertexShader)
  glDeleteShader(fragmentShader)
  var status: GLint
  glGetProgramiv(result.program, GL_LINK_STATUS, status.addr)
  if status == 0:
    var length: GLint
    glGetProgramiv(result.program, GL_INFO_LOG_LENGTH, length.addr)
    var log = newString(length)
    glGetProgramInfoLog(result.program, length, nil, log.cstring)
    raise newException(CatchableError,
      "CaC post " & label & " program failed:\n" & log)

proc location(pass: var PostPass, name: string): GLint =
  if name notin pass.locations:
    pass.locations[name] = glGetUniformLocation(pass.program, name.cstring)
  pass.locations[name]

proc setFloat(pass: var PostPass, name: string, value: float32) =
  glUniform1f(pass.location(name), value)

proc setVec2(pass: var PostPass, name: string, value: Vec2) =
  glUniform2f(pass.location(name), value.x, value.y)

proc setVec3(pass: var PostPass, name: string, value: Vec3) =
  glUniform3f(pass.location(name), value.x, value.y, value.z)

proc setTexture(pass: var PostPass, name: string, unit: int, texture: GLuint) =
  glActiveTexture(GLenum(GL_TEXTURE0.int + unit))
  glBindTexture(GL_TEXTURE_2D, texture)
  glUniform1i(pass.location(name), unit.GLint)

proc newTexture(size: IVec2, internal: GLint, format, kind: GLenum,
    filter: GLint): GLuint =
  glGenTextures(1, result.addr)
  glBindTexture(GL_TEXTURE_2D, result)
  glTexImage2D(GL_TEXTURE_2D, 0, internal, size.x.GLsizei, size.y.GLsizei, 0,
    format, kind, nil)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, filter)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, filter)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE.GLint)

proc release(target: var RenderTarget) =
  if target.framebuffer != 0:
    glDeleteFramebuffers(1, target.framebuffer.addr)
    glDeleteTextures(1, target.texture.addr)
  target = RenderTarget()

proc initTarget(target: var RenderTarget, size: IVec2) =
  target.release()
  target.size = ivec2(max(size.x, 1), max(size.y, 1))
  target.texture = newTexture(target.size, GL_RGBA8.GLint, GL_RGBA,
    GL_UNSIGNED_BYTE, GL_LINEAR.GLint)
  glGenFramebuffers(1, target.framebuffer.addr)
  glBindFramebuffer(GL_FRAMEBUFFER, target.framebuffer)
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
    target.texture, 0)

proc bindTarget(target: RenderTarget) =
  glBindFramebuffer(GL_FRAMEBUFFER, target.framebuffer)
  glViewport(0, 0, target.size.x.GLsizei, target.size.y.GLsizei)

proc texel(target: RenderTarget): Vec2 =
  vec2(1.0'f32 / target.size.x.float32, 1.0'f32 / target.size.y.float32)

proc ensureSize(post: var PostFx, size: IVec2) =
  if size == post.size:
    return
  post.size = size
  post.materialNormals.release()
  if post.sceneFramebuffer != 0:
    glDeleteFramebuffers(1, post.sceneFramebuffer.addr)
    glDeleteTextures(1, post.sceneColor.addr)
    glDeleteTextures(1, post.sceneDepth.addr)
  post.sceneColor = newTexture(size, GL_RGBA8.GLint, GL_RGBA,
    GL_UNSIGNED_BYTE, GL_LINEAR.GLint)
  post.sceneDepth = newTexture(size, GL_DEPTH24_STENCIL8.GLint,
    GL_DEPTH_STENCIL, GL_UNSIGNED_INT_24_8, GL_NEAREST.GLint)
  glGenFramebuffers(1, post.sceneFramebuffer.addr)
  glBindFramebuffer(GL_FRAMEBUFFER, post.sceneFramebuffer)
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
    post.sceneColor, 0)
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT,
    GL_TEXTURE_2D, post.sceneDepth, 0)
  if glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE:
    raise newException(CatchableError, "CaC post scene target is incomplete")
  post.materialNormals.initTarget(size)
  glBindTexture(GL_TEXTURE_2D, post.materialNormals.texture)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST.GLint)
  # The normal replay shares the finished depth, so nearer cards and heroes
  # reject the floor's normals. No extra depth copy or float extension needed.
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT,
    GL_TEXTURE_2D, post.sceneDepth, 0)
  if glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE:
    raise newException(CatchableError, "CaC material normal target is incomplete")
  let half = ivec2(max(size.x div 2, 1), max(size.y div 2, 1))
  for target in post.occlusion.mitems:
    target.initTarget(half)
  post.beforeVfx.initTarget(half)
  var levelSize = half
  for target in post.bloom.mitems:
    target.initTarget(levelSize)
    levelSize = ivec2(max(levelSize.x div 2, 1), max(levelSize.y div 2, 1))
  glBindFramebuffer(GL_FRAMEBUFFER, 0)

proc initPostFx*(): PostFx =
  result.settings = defaultPostSettings()
  result.near = 0.1
  result.far = 100
  glGenVertexArrays(1, result.vertexArray.addr)
  result.occlusionPass = compilePass(OcclusionFragment, "occlusion")
  result.blurPass = compilePass(BlurFragment, "occlusion blur")
  result.multiplyPass = compilePass(MultiplyFragment, "occlusion multiply")
  result.prefilterPass = compilePass(PrefilterFragment, "bloom prefilter")
  result.downPass = compilePass(DownFragment, "bloom down")
  result.upPass = compilePass(UpFragment, "bloom up")
  result.finalPass = compilePass(FinalFragment, "final")
  when PostLayerControls:
    result.layerPass = compilePass(LayerFragment, "layer view")
    let key =
      try: parseInt(getEnv("CAC_POST_LAYER", "1"))
      except ValueError: 1
    result.layer = PostLayer(((key + 9) mod 10 + 10) mod 10)

proc showing(post: PostFx, layer: PostLayer): bool =
  when PostLayerControls: post.layer == layer
  else: false

proc drawFullscreen(post: PostFx) =
  glBindVertexArray(post.vertexArray)
  glDrawArrays(GL_TRIANGLES, 0, 3)

proc prepareFullscreen() =
  glDisable(GL_DEPTH_TEST)
  glDepthMask(GL_FALSE)
  glDisable(GL_STENCIL_TEST)
  glDisable(GL_CULL_FACE)
  glDisable(GL_BLEND)

proc restoreSceneTarget(post: PostFx) =
  glBindVertexArray(0)
  glUseProgram(0)
  glActiveTexture(GL_TEXTURE0)
  glDisable(GL_BLEND)
  glDepthMask(GL_TRUE)
  glBindFramebuffer(GL_FRAMEBUFFER, post.sceneFramebuffer)
  glViewport(0, 0, post.size.x.GLsizei, post.size.y.GLsizei)

proc beginScene*(post: var PostFx, size: IVec2, near, far: float32) =
  ## Routes the 3D scene's draws to the offscreen target. near and far must
  ## match the camera projection so the occlusion blur reads real distances.
  if not post.settings.enabled:
    return
  post.ensureSize(ivec2(max(size.x, 1), max(size.y, 1)))
  post.near = near
  post.far = far
  post.materialNormals.bindTarget()
  glClearColor(0, 0, 0, 0)
  glClear(GL_COLOR_BUFFER_BIT)
  glBindFramebuffer(GL_FRAMEBUFFER, post.sceneFramebuffer)
  glViewport(0, 0, post.size.x.GLsizei, post.size.y.GLsizei)

proc beginMaterialNormals*(post: PostFx): bool =
  ## Call after opaque geometry, before SSAO. Re-render only normal-mapped
  ## objects with depth EQUAL and no depth writes; color/stencil stay intact.
  if not post.settings.enabled or
      (not post.settings.occlusion and not post.showing(NormalLayer)):
    return false
  post.materialNormals.bindTarget()
  glDisable(GL_STENCIL_TEST)
  return true

proc endMaterialNormals*(post: PostFx) =
  glDepthFunc(GL_LESS)
  post.restoreSceneTarget()

proc applyOcclusion*(post: var PostFx, projection: Mat4) =
  ## Darkens creases and contact points in everything drawn so far, then
  ## snapshots the scene so `present` can tell which light the VFX add.
  if not post.settings.enabled:
    return
  let settings = post.settings
  prepareFullscreen()
  when PostLayerControls:
    post.inverseProjection = projection.inverse
  if settings.occlusion:
    post.occlusion[0].bindTarget()
    glUseProgram(post.occlusionPass.program)
    post.occlusionPass.setTexture("depthTexture", 0, post.sceneDepth)
    post.occlusionPass.setTexture("normalTexture", 1, post.materialNormals.texture)
    var inverseProjection = projection.inverse
    glUniformMatrix4fv(post.occlusionPass.location("inverseProjection"), 1,
      GL_FALSE, cast[ptr float32](inverseProjection.addr))
    post.occlusionPass.setVec2("projectionScale",
      vec2(projection[0, 0], projection[1, 1]))
    post.occlusionPass.setVec2("texel",
      vec2(1.0'f32 / post.size.x.float32, 1.0'f32 / post.size.y.float32))
    post.occlusionPass.setFloat("radius", settings.occlusionRadius)
    post.occlusionPass.setFloat("intensity", settings.occlusionIntensity)
    post.occlusionPass.setFloat("bias", settings.occlusionBias)
    post.occlusionPass.setFloat("normalDetail", settings.occlusionNormalDetail)
    post.drawFullscreen()

    glUseProgram(post.blurPass.program)
    post.blurPass.setTexture("depthTexture", 1, post.sceneDepth)
    post.blurPass.setFloat("sharpness", settings.occlusionSharpness)
    post.blurPass.setFloat("near", post.near)
    post.blurPass.setFloat("far", post.far)
    # The unblurred layer view keeps the raw result in occlusion[0].
    let blurs =
      if post.showing(RawOcclusionLayer): 0
      else: 2
    for (source, destination, axis) in
        [(0, 1, vec2(1, 0)), (1, 0, vec2(0, 1))][0 ..< blurs]:
      post.occlusion[destination].bindTarget()
      post.blurPass.setTexture("occlusionTexture", 0,
        post.occlusion[source].texture)
      post.blurPass.setVec2("direction", axis * post.occlusion[source].texel)
      post.drawFullscreen()

    glBindFramebuffer(GL_FRAMEBUFFER, post.sceneFramebuffer)
    glViewport(0, 0, post.size.x.GLsizei, post.size.y.GLsizei)
    glEnable(GL_BLEND)
    glBlendFuncSeparate(GL_DST_COLOR, GL_ZERO, GL_ZERO, GL_ONE)
    glUseProgram(post.multiplyPass.program)
    post.multiplyPass.setTexture("occlusionTexture", 0,
      post.occlusion[0].texture)
    post.multiplyPass.setVec3("tint", settings.occlusionTint)
    post.drawFullscreen()
    glDisable(GL_BLEND)

  if settings.bloom:
    glBindFramebuffer(GL_READ_FRAMEBUFFER, post.sceneFramebuffer)
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, post.beforeVfx.framebuffer)
    glBlitFramebuffer(0, 0, post.size.x, post.size.y,
      0, 0, post.beforeVfx.size.x, post.beforeVfx.size.y,
      GL_COLOR_BUFFER_BIT, GL_LINEAR.GLenum)
  post.restoreSceneTarget()

when PostLayerControls:
  proc layerAvailable*(post: PostFx): bool =
    ## False when the effect that fills the shown layer is switched off.
    case post.layer
    of RawOcclusionLayer, OcclusionLayer: post.settings.occlusion
    of BeforeVfxLayer, VfxLayer, BloomSourceLayer, BloomLayer:
      post.settings.bloom
    else: true

  proc drawLayer(post: var PostFx) =
    ## Replaces the final image on the bound window with post.layer.
    var
      color = post.sceneColor
      other = post.sceneColor
      mode = 0
      scale = 1.0'f32
    case post.layer
    of FinalLayer, SceneLayer: discard
    of DepthLayer: mode = 1
    of NormalLayer: mode = 2
    of RawOcclusionLayer, OcclusionLayer: color = post.occlusion[0].texture
    of BeforeVfxLayer: color = post.beforeVfx.texture
    of VfxLayer:
      mode = 3
      other = post.beforeVfx.texture
    of BloomSourceLayer: color = post.bloom[0].texture
    of BloomLayer:
      color = post.bloom[0].texture
      scale = post.settings.bloomStrength
    if not post.layerAvailable():
      scale = 0
    let pass = post.layerPass.addr
    glUseProgram(pass.program)
    pass[].setTexture("colorTexture", 0, color)
    pass[].setTexture("otherTexture", 1, other)
    pass[].setTexture("depthTexture", 2, post.sceneDepth)
    pass[].setTexture("normalTexture", 3, post.materialNormals.texture)
    glUniformMatrix4fv(pass[].location("inverseProjection"), 1, GL_FALSE,
      cast[ptr float32](post.inverseProjection.addr))
    pass[].setVec2("texel",
      vec2(1.0'f32 / post.size.x.float32, 1.0'f32 / post.size.y.float32))
    glUniform1i(pass[].location("mode"), mode.GLint)
    pass[].setFloat("scale", scale)
    pass[].setFloat("near", post.near)
    pass[].setFloat("far", post.far)
    post.drawFullscreen()

proc present*(post: var PostFx, windowSize: IVec2,
    outputFramebuffer: GLuint = 0) =
  ## Composites onto the window or a hidden capture target, ready for the HUD.
  if not post.settings.enabled:
    return
  let settings = post.settings
  prepareFullscreen()
  if settings.bloom:
    post.bloom[0].bindTarget()
    glUseProgram(post.prefilterPass.program)
    post.prefilterPass.setTexture("sceneTexture", 0, post.sceneColor)
    post.prefilterPass.setTexture("beforeTexture", 1, post.beforeVfx.texture)
    post.prefilterPass.setVec2("texel",
      vec2(1.0'f32 / post.size.x.float32, 1.0'f32 / post.size.y.float32))
    post.prefilterPass.setFloat("threshold", settings.bloomThreshold)
    post.prefilterPass.setFloat("vfxWeight", settings.bloomVfx)
    post.prefilterPass.setFloat("useVfx", 1)
    post.drawFullscreen()

    # The bloom source layer view keeps the prefiltered light in bloom[0].
    let levels =
      if post.showing(BloomSourceLayer): 1
      else: BloomLevels
    glUseProgram(post.downPass.program)
    for level in 1 ..< levels:
      post.bloom[level].bindTarget()
      post.downPass.setTexture("sourceTexture", 0, post.bloom[level - 1].texture)
      post.downPass.setVec2("texel", post.bloom[level - 1].texel)
      post.drawFullscreen()

    # Each smaller level spreads its light over the next larger one.
    glEnable(GL_BLEND)
    glBlendFunc(GL_ONE, GL_ONE)
    glUseProgram(post.upPass.program)
    for level in countdown(levels - 1, 1):
      post.bloom[level - 1].bindTarget()
      post.upPass.setTexture("sourceTexture", 0, post.bloom[level].texture)
      post.upPass.setVec2("texel", post.bloom[level].texel)
      post.drawFullscreen()
    glDisable(GL_BLEND)

  glBindFramebuffer(GL_FRAMEBUFFER, outputFramebuffer)
  glViewport(0, 0, windowSize.x.GLsizei, windowSize.y.GLsizei)
  glUseProgram(post.finalPass.program)
  post.finalPass.setTexture("sceneTexture", 0, post.sceneColor)
  post.finalPass.setTexture("bloomTexture", 1, post.bloom[0].texture)
  post.finalPass.setVec2("texel",
    vec2(1.0'f32 / post.size.x.float32, 1.0'f32 / post.size.y.float32))
  post.finalPass.setFloat("useFxaa", if settings.fxaa: 1 else: 0)
  post.finalPass.setFloat("bloomStrength",
    if settings.bloom: settings.bloomStrength else: 0)
  post.finalPass.setFloat("vignette", settings.vignette)
  post.finalPass.setFloat("vignetteStart", settings.vignetteStart)
  post.finalPass.setFloat("vignetteEnd", settings.vignetteEnd)
  post.finalPass.setFloat("saturation", settings.saturation)
  post.finalPass.setFloat("contrast", settings.contrast)
  when PostLayerControls:
    if post.layer == FinalLayer: post.drawFullscreen()
    else: post.drawLayer()
  else:
    post.drawFullscreen()
  glBindVertexArray(0)
  glUseProgram(0)
  glActiveTexture(GL_TEXTURE0)
  glDepthMask(GL_TRUE)
