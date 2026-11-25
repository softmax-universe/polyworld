import opengl

var
  sunShadowTextures*: array[2, GLuint]
  sunFramebuffers: array[2, GLuint]
  depthProgram, cutoutDepthProgram: GLuint
  depthMvpLocation: GLint
  cutoutMvpLocation, cutoutTexturesLocation, cutoutCutoffLocation: GLint
  unshadowedTexture: GLuint

const SunShaderTarget =
  when defined(emscripten):
    glsl3WebGL
  else:
    glsl4Desktop

proc compileStage(kind: GLenum, source, label: string): GLuint =
  ## Compiles one OpenGL shader stage or terminates with its diagnostic.
  result = glCreateShader(kind)
  var sourceArray = allocCStringArray([source])
  defer: deallocCStringArray(sourceArray)
  glShaderSource(result, 1.GLsizei, sourceArray, nil)
  glCompileShader(result)
  var ok: GLint
  glGetShaderiv(result, GL_COMPILE_STATUS, ok.addr)
  if ok == 0:
    var length: GLint
    glGetShaderiv(result, GL_INFO_LOG_LENGTH, length.addr)
    var log = newString(length)
    glGetShaderInfoLog(result, length, nil, log.cstring)
    quit(label & " shader failed:\n" & log & "\nsource:\n" & source)

proc compileDepthProgram(vertexSource, fragmentSource: string): GLuint =
  ## Links one depth program or terminates with its diagnostic.
  let
    vertexShader = compileStage(GL_VERTEX_SHADER, vertexSource, "sundepth.vert")
    fragmentShader = compileStage(
      GL_FRAGMENT_SHADER, fragmentSource, "sundepth.frag")
  result = glCreateProgram()
  glAttachShader(result, vertexShader)
  glAttachShader(result, fragmentShader)
  glLinkProgram(result)
  # The linked executable owns its code; release the compilation objects.
  glDetachShader(result, vertexShader)
  glDetachShader(result, fragmentShader)
  glDeleteShader(vertexShader)
  glDeleteShader(fragmentShader)
  var ok: GLint
  glGetProgramiv(result, GL_LINK_STATUS, ok.addr)
  if ok == 0:
    var length: GLint
    glGetProgramiv(result, GL_INFO_LOG_LENGTH, length.addr)
    var log = newString(length)
    glGetProgramInfoLog(result, length, nil, log.cstring)
    quit("sun depth program failed:\n" & log)

proc initSunShadows*(
    lightRadius = 100.0'f, lightDistance = 170.0'f
) =
  ## Compiles the depth programs and creates the two shadow framebuffers.
  ## Requires a current GL context; safe to call more than once. The radius
  ## must cover the whole scene from any sun angle (map half-diagonal plus
  ## the tallest features).
  if sunFramebuffers[0] != 0:
    return
  if getEnv("SUN_SHADOWS") == "0":
    sunShadowsEnabled = false
  sunLightRadius = lightRadius
  sunLightDistance = lightDistance

  depthProgram = compileDepthProgram(
    toShader(sunDepthVert, SunShaderTarget, shaderVertex),
    toShader(sunDepthFrag, SunShaderTarget, shaderFragment)
  )
  depthMvpLocation = glGetUniformLocation(depthProgram, "sunDepthMvp")
  cutoutDepthProgram = compileDepthProgram(
    toShader(sunCutoutDepthVert, SunShaderTarget, shaderVertex),
    toShader(sunCutoutDepthFrag, SunShaderTarget, shaderFragment)
  )
  cutoutMvpLocation = glGetUniformLocation(cutoutDepthProgram, "sunDepthMvp")
  cutoutTexturesLocation = glGetUniformLocation(
    cutoutDepthProgram, "cutoutTextures")
  cutoutCutoffLocation = glGetUniformLocation(
    cutoutDepthProgram, "cutoutCutoff")

  for step in 0 .. 1:
    # Linear filtering plus the comparison mode turns every sampler2DShadow
    # tap into a bilinearly filtered depth test (hardware PCF).
    glGenTextures(1, sunShadowTextures[step].addr)
    glBindTexture(GL_TEXTURE_2D, sunShadowTextures[step])
    glTexImage2D(
      GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT24.GLint,
      SunShadowMapSize, SunShadowMapSize, 0,
      GL_DEPTH_COMPONENT, GL_UNSIGNED_INT, nil
    )
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE.GLint)
    glTexParameteri(
      GL_TEXTURE_2D, GL_TEXTURE_COMPARE_MODE, GL_COMPARE_REF_TO_TEXTURE.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_COMPARE_FUNC, GL_LEQUAL.GLint)
    glBindTexture(GL_TEXTURE_2D, 0)

    glGenFramebuffers(1, sunFramebuffers[step].addr)
    glBindFramebuffer(GL_FRAMEBUFFER, sunFramebuffers[step])
    glFramebufferTexture2D(
      GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D,
      sunShadowTextures[step], 0)
    var drawTargets = [GL_NONE]
    glDrawBuffers(1, cast[ptr GLenum](drawTargets.addr))
    glReadBuffer(GL_NONE)
    doAssert glCheckFramebufferStatus(GL_FRAMEBUFFER) ==
      GL_FRAMEBUFFER_COMPLETE
    # Start the map at far depth so everything counts as lit until the
    # first real depth pass runs.
    glClear(GL_DEPTH_BUFFER_BIT)
  glBindFramebuffer(GL_FRAMEBUFFER, 0)
  updateSunMatrix()

proc sunShadowsActive*(): bool =
  ## Returns whether the shadow maps exist and shadows are switched on.
  sunShadowsEnabled and sunFramebuffers[0] != 0

proc sunDepthProgramId*(): GLuint =
  ## The plain depth program, for mesh modules building depth vertex arrays.
  depthProgram

proc sunCutoutProgramId*(): GLuint =
  ## The alpha-cutout depth program, same purpose.
  cutoutDepthProgram

proc beginSunDepthPass*(step: int) =
  ## Binds one step's shadow framebuffer and clears it. Prefer the
  ## sunDepthPasses template, which brackets the active steps.
  glBindFramebuffer(GL_FRAMEBUFFER, sunFramebuffers[step])
  when not defined(emscripten):
    glDisable(GL_MULTISAMPLE)
  glViewport(0, 0, SunShadowMapSize, SunShadowMapSize)
  glClear(GL_DEPTH_BUFFER_BIT)
  glEnable(GL_DEPTH_TEST)
  glDisable(GL_CULL_FACE)
  glDisable(GL_BLEND)
  activeDepthMvp = if step == 0: sunLightMvp0 else: sunLightMvp1

proc bindSunDepth*(transform: Mat4) =
  ## Selects the plain depth program with the given light-space transform.
  var matrix = transform
  glUseProgram(depthProgram)
  glUniformMatrix4fv(depthMvpLocation, 1, GL_FALSE, cast[ptr float32](matrix.addr))

proc bindSunCutoutDepth*(transform: Mat4, alphaCutoff: float32) =
  ## Selects the cutout depth program; the caller binds its texture array to
  ## unit 0 before drawing.
  var matrix = transform
  glUseProgram(cutoutDepthProgram)
  glUniformMatrix4fv(
    cutoutMvpLocation, 1, GL_FALSE, cast[ptr float32](matrix.addr))
  glUniform1i(cutoutTexturesLocation, 0)
  glUniform1f(cutoutCutoffLocation, alphaCutoff)

proc endSunDepthPass*(windowSize: IVec2) =
  ## Unbinds the shadow framebuffer and restores the window viewport.
  glBindVertexArray(0)
  glUseProgram(0)
  glBindFramebuffer(GL_FRAMEBUFFER, 0)
  glViewport(0, 0, windowSize.x.GLsizei, windowSize.y.GLsizei)

template sunDepthPasses*(windowSize: IVec2, body: untyped) =
  ## Draws one map without a cross-fade, otherwise both neighboring maps.
  ## The injected sunPassIndex is 0 for the first map and 1 for the second.
  ## Restores the caller's targets and MSAA setting even if a draw fails.
  if sunShadowsActive():
    var readFramebuffer, drawFramebuffer: GLint
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, readFramebuffer.addr)
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, drawFramebuffer.addr)
    when not defined(emscripten):
      let multisampleEnabled = glIsEnabled(GL_MULTISAMPLE)
    try:
      let lastShadowStep = (sunShadowBlend > 0).ord
      for sunPassIndex {.inject.} in 0 .. lastShadowStep:
        beginSunDepthPass(sunPassIndex)
        body
    finally:
      endSunDepthPass(windowSize)
      glBindFramebuffer(GL_READ_FRAMEBUFFER, readFramebuffer.GLuint)
      glBindFramebuffer(GL_DRAW_FRAMEBUFFER, drawFramebuffer.GLuint)
      when not defined(emscripten):
        if multisampleEnabled == GL_TRUE:
          glEnable(GL_MULTISAMPLE)
        else:
          glDisable(GL_MULTISAMPLE)

proc sunShadowMvp*(step: int): Mat4 =
  ## Returns the receiver transform for one shadow texture.
  if step == 0: sunLightMvp0 else: sunLightMvp1

proc sunUploadModel*(transform: Mat4) =
  ## Uploads the plain shadow transform for backend-neutral terrain drawing.
  bindSunDepth(transform)

proc sunUploadCutoutModel*(transform: Mat4, alphaCutoff: float32) =
  ## Uploads the cutout shadow transform and alpha threshold.
  bindSunCutoutDepth(transform, alphaCutoff)

proc sunBindCutoutTexture*(texture: GLuint) =
  ## Binds the cutout caster texture array to its shadow program.
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D_ARRAY, texture)

proc initUnshadowedShadows*() =
  ## Supplies complete comparison textures for scenes without shadow maps.
  if unshadowedTexture != 0:
    return
  var depth = high(uint32)
  glGenTextures(1, unshadowedTexture.addr)
  glBindTexture(GL_TEXTURE_2D, unshadowedTexture)
  glTexImage2D(
    GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT24.GLint, 1, 1, 0,
    GL_DEPTH_COMPONENT, GL_UNSIGNED_INT, depth.addr
  )
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE.GLint)
  glTexParameteri(
    GL_TEXTURE_2D, GL_TEXTURE_COMPARE_MODE, GL_COMPARE_REF_TO_TEXTURE.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_COMPARE_FUNC, GL_LEQUAL.GLint)
  glBindTexture(GL_TEXTURE_2D, 0)
  sunShadowTextures = [unshadowedTexture, unshadowedTexture]

proc closeUnshadowedShadows*() =
  ## Releases comparison textures created for an unshadowed scene.
  if unshadowedTexture == 0:
    return
  for texture in sunShadowTextures.mitems:
    if texture == unshadowedTexture:
      texture = 0
  glDeleteTextures(1, unshadowedTexture.addr)
  unshadowedTexture = 0

proc closeSunShadows*() =
  ## Releases shadow resources while the graphics context is current.
  closeUnshadowedShadows()
  glDeleteFramebuffers(2, sunFramebuffers[0].addr)
  glDeleteTextures(2, sunShadowTextures[0].addr)
  sunFramebuffers = default(typeof(sunFramebuffers))
  sunShadowTextures = default(typeof(sunShadowTextures))
  if depthProgram != 0:
    glDeleteProgram(depthProgram)
    depthProgram = 0
  if cutoutDepthProgram != 0:
    glDeleteProgram(cutoutDepthProgram)
    cutoutDepthProgram = 0
