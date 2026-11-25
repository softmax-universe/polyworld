proc compileParticleStage(
    kind: GLenum,
    source,
    label: string
): GLuint =
  ## Compiles one particle shader stage or raises its full diagnostic.
  result = glCreateShader(kind)
  var sources = allocCStringArray([source])
  defer: deallocCStringArray(sources)
  glShaderSource(result, 1, sources, nil)
  glCompileShader(result)
  var ok: GLint
  glGetShaderiv(result, GL_COMPILE_STATUS, ok.addr)
  if ok != 0:
    return
  var length: GLint
  glGetShaderiv(result, GL_INFO_LOG_LENGTH, length.addr)
  var log = newString(max(length.int, 1))
  glGetShaderInfoLog(result, length, nil, log.cstring)
  glDeleteShader(result)
  let message = label & " failed:\n" & log.strip(chars = {'\0'}) &
    "\nExpanded source:\n" & source
  echo message
  raise newException(ParticleError, message)

proc compileParticleProgram(): ParticleProgram =
  ## Compiles and links the shared semantic particle shader pair.
  let
    vertex = compileParticleStage(
      GL_VERTEX_SHADER,
      ParticleVertexSource,
      "particle vertex shader"
    )
    fragment = compileParticleStage(
      GL_FRAGMENT_SHADER,
      ParticleFragmentSource,
      "particle fragment shader"
    )
  result.id = glCreateProgram()
  glAttachShader(result.id, vertex)
  glAttachShader(result.id, fragment)
  glLinkProgram(result.id)
  glDeleteShader(vertex)
  glDeleteShader(fragment)
  var ok: GLint
  glGetProgramiv(result.id, GL_LINK_STATUS, ok.addr)
  if ok == 0:
    var length: GLint
    glGetProgramiv(result.id, GL_INFO_LOG_LENGTH, length.addr)
    var log = newString(max(length.int, 1))
    glGetProgramInfoLog(result.id, length, nil, log.cstring)
    glDeleteProgram(result.id)
    raise newException(
      ParticleError,
      "particle shaders failed to link:\n" & log.strip(chars = {'\0'})
    )
  for uniform in ParticleUniform:
    result.locations[uniform] = glGetUniformLocation(
      result.id,
      ParticleUniformNames[uniform.ord].cstring
    )

proc initParticleSystem*(): ParticleSystem =
  ## Creates the shared shaders and empty instanced-quad vertex array.
  result.gpu.program = compileParticleProgram()
  result.nextSeed = 1
  glGenVertexArrays(1, result.gpu.vertexArray.addr)
  var previous: GLint
  glGetIntegerv(GL_TEXTURE_BINDING_2D, previous.addr)
  glGenTextures(1, result.gpu.sightTexture.addr)
  glBindTexture(GL_TEXTURE_2D, result.gpu.sightTexture)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE.GLint)
  # Keep the sampler complete even for callers that don't use sight clipping.
  var white = [255'u8, 255, 255, 255]
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.GLint, 1, 1, 0,
    GL_RGBA, GL_UNSIGNED_BYTE, white[0].addr)
  glBindTexture(GL_TEXTURE_2D, previous.GLuint)

proc uploadParticleEffect(
    system: ParticleSystem,
    effect: ParticleEffect,
    viewProjection: var Mat4,
    cameraRight,
    cameraUp,
    cameraForward: Vec3
) =
  ## Uploads one effect and the current camera basis to the shader.
  template location(uniform: ParticleUniform): GLint =
    system.gpu.program.locations[uniform]
  glUniformMatrix4fv(
    location(ViewProjectionUniform),
    1,
    GL_FALSE,
    cast[ptr float32](viewProjection.addr)
  )
  glUniform3f(
    location(CameraRightUniform),
    cameraRight.x,
    cameraRight.y,
    cameraRight.z
  )
  glUniform3f(
    location(CameraUpUniform),
    cameraUp.x,
    cameraUp.y,
    cameraUp.z
  )
  glUniform3f(
    location(CameraForwardUniform),
    cameraForward.x,
    cameraForward.y,
    cameraForward.z
  )
  glUniform1f(location(TimeUniform), system.time)
  glUniform1f(location(StartTimeUniform), effect.startTime)
  glUniform1f(location(TravelTimeUniform), effect.travelTime)
  glUniform1f(
    location(SeedUniform),
    (effect.seed mod 65_521'u32).float32
  )
  glUniform1i(location(EffectKindUniform), effect.kind.ord.GLint)
  glUniform3f(
    location(OriginUniform),
    effect.origin.x,
    effect.origin.y,
    effect.origin.z
  )
  glUniform3f(
    location(TargetUniform),
    effect.target.x,
    effect.target.y,
    effect.target.z
  )

proc drawParticles*(
    system: ParticleSystem,
    viewProjection: Mat4,
    cameraRight,
    cameraUp,
    cameraForward: Vec3,
    visibility: openArray[uint8] = [],
    visibilityWidth = 0,
    visibilityOrigin = vec2(0),
    visibilityPadding = 0,
    viewer = -1'i32,
    clipToSight = false
) =
  ## Draws every visible active effect with instanced, depth-tested billboards.
  if system.gpu.program.id == 0 or system.effects.len == 0:
    return
  # Opt-in exact fragment clipping preserves the default path policy for other
  # games, without suppressing a whole incoming shot at a sight boundary.
  let clip = clipToSight and visibility.len > 0
  if clip and (visibilityWidth <= 0 or visibility.len != visibilityWidth * visibilityWidth):
    return
  var oldActive, oldTexture, oldAlignment: GLint
  glGetIntegerv(GL_ACTIVE_TEXTURE, oldActive.addr)
  glActiveTexture(GL_TEXTURE0)
  glGetIntegerv(GL_TEXTURE_BINDING_2D, oldTexture.addr)
  glBindTexture(GL_TEXTURE_2D, system.gpu.sightTexture)
  if clip:
    glGetIntegerv(GL_UNPACK_ALIGNMENT, oldAlignment.addr)
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
    glTexImage2D(GL_TEXTURE_2D, 0, GL_R8.GLint, visibilityWidth.GLsizei,
      visibilityWidth.GLsizei, 0, GL_RED, GL_UNSIGNED_BYTE, visibility[0].unsafeAddr)
    glPixelStorei(GL_UNPACK_ALIGNMENT, oldAlignment)
  var matrix = viewProjection
  glEnable(GL_DEPTH_TEST)
  glDepthMask(GL_FALSE)
  glEnable(GL_BLEND)
  glDisable(GL_CULL_FACE)
  glUseProgram(system.gpu.program.id)
  let clipLocation = system.gpu.program.locations[ClipSightUniform]
  glUniform1i(system.gpu.program.locations[SightUniform], 0)
  glUniform1i(clipLocation, 0)
  if clip:
    glUniform2f(system.gpu.program.locations[SightOriginUniform],
      visibilityOrigin.x, visibilityOrigin.y)
    glUniform1f(system.gpu.program.locations[SightWidthUniform],
      visibilityWidth.float32)
  glBindVertexArray(system.gpu.vertexArray)
  for effect in system.effects:
    if effect.startTime > system.time:
      continue
    let owned = viewer >= 0 and effect.owner == viewer
    glUniform1i(clipLocation, (clip and not owned).GLint)
    if not clip and not owned:
      if not particlePathVisible(
        effect.origin,
        effect.target,
        visibility,
        visibilityWidth,
        visibilityOrigin,
        visibilityPadding
      ):
        continue
    if effect.kind in
        {ArrowWake, LeafBolt, LeafBurst, BloomSeed, BloomPetals, RootLeaves,
         IceShard, FrostBurst, IceShatter, BlizzardShards, SnowSquall}:
      glBlendFuncSeparate(
        GL_SRC_ALPHA,
        GL_ONE_MINUS_SRC_ALPHA,
        GL_ONE,
        GL_ONE_MINUS_SRC_ALPHA
      )
    else:
      glBlendFuncSeparate(
        GL_SRC_ALPHA,
        GL_ONE,
        GL_ZERO,
        GL_ONE
      )
    system.uploadParticleEffect(
      effect,
      matrix,
      cameraRight,
      cameraUp,
      cameraForward
    )
    glDrawArraysInstanced(
      GL_TRIANGLE_STRIP,
      0,
      4,
      effect.kind.effectParticleCount.GLsizei
    )
  glBindVertexArray(0)
  glUseProgram(0)
  glDepthMask(GL_TRUE)
  glDisable(GL_BLEND)
  glBindTexture(GL_TEXTURE_2D, oldTexture.GLuint)
  glActiveTexture(oldActive.GLenum)

proc closeParticles*(system: var ParticleSystem) =
  ## Releases particle GPU resources and clears presentation state.
  if system.gpu.program.id != 0:
    glDeleteProgram(system.gpu.program.id)
  if system.gpu.vertexArray != 0:
    glDeleteVertexArrays(1, system.gpu.vertexArray.addr)
  if system.gpu.sightTexture != 0:
    glDeleteTextures(1, system.gpu.sightTexture.addr)
  system = ParticleSystem()
