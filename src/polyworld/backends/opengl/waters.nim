## OpenGL water captures, textures and draws.

import opengl

const
  ShaderTarget =
    when defined(emscripten): glsl3WebGL
    else: glsl4Desktop
  ReflectionUnit = 10
  SceneDepthUnit = 11
  SceneColorUnit = 12
  ShoreFieldUnit = 13
  FoamNoiseUnit = 14

type ShoreField = object
  ## One water layer's distance to its shore, as a texture over a world rectangle.
  texture: GLuint
  origin, size: Vec2 ## world x, z of the field's corner, and its x, z extent

var
  reflectionFbo, reflectionColor, reflectionDepth, blankTexture: GLuint
  reflectionSize: IVec2
  sceneCopyFbo, depthCopy, colorCopy, foamNoiseTexture: GLuint
  sceneCopySize: IVec2
  shoreFields: seq[ShoreField] ## per terrain layer; built lazily by drawWaterBody
  skyProgram, skyVertexArray, skyVertexBuffer: GLuint
  reflectionActive: bool
  savedReadFramebuffer, savedDrawFramebuffer: GLint
  savedViewport: array[4, GLint]

proc compileStage(kind: GLenum, source: string): GLuint =
  ## Compiles one shader stage, raising with its log on failure.
  result = glCreateShader(kind)
  var text = allocCStringArray([source])
  glShaderSource(result, 1, text, nil)
  deallocCStringArray(text)
  glCompileShader(result)
  var ok: GLint
  glGetShaderiv(result, GL_COMPILE_STATUS, ok.addr)
  if ok == 0:
    var log = newString(4096)
    var length: GLsizei
    glGetShaderInfoLog(result, 4096, length.addr, log.cstring)
    log.setLen(length)
    glDeleteShader(result)
    raise newException(PolyworldWaterError, "water sky shader: " & log)

proc installWaters*() =
  ## Replaces the engine's water shader; call before initTerrain, which compiles it.
  waterPremultipliedAlpha = true
  waterShaderOverride = (
    toShader(watersVert, ShaderTarget, shaderVertex),
    toShader(watersFrag, ShaderTarget, shaderFragment))

proc endReflection*() =
  ## Restores the render targets and viewport saved by beginReflection.
  if reflectionActive:
    glBindFramebuffer(GL_READ_FRAMEBUFFER, savedReadFramebuffer.GLuint)
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, savedDrawFramebuffer.GLuint)
    glViewport(savedViewport[0], savedViewport[1], savedViewport[2],
      savedViewport[3])
    reflectionActive = false

proc destroyWaters*() =
  ## Releases every water resource and permits another initialization.
  endReflection()
  for field in shoreFields:
    if field.texture != 0:
      var texture = field.texture
      glDeleteTextures(1, texture.addr)
  shoreFields.setLen(0)
  for texture in [reflectionColor, blankTexture, depthCopy, colorCopy,
      foamNoiseTexture]:
    if texture != 0:
      var handle = texture
      glDeleteTextures(1, handle.addr)
  for framebuffer in [reflectionFbo, sceneCopyFbo]:
    if framebuffer != 0:
      var handle = framebuffer
      glDeleteFramebuffers(1, handle.addr)
  if reflectionDepth != 0:
    glDeleteRenderbuffers(1, reflectionDepth.addr)
  if skyProgram != 0:
    glDeleteProgram(skyProgram)
  if skyVertexBuffer != 0:
    glDeleteBuffers(1, skyVertexBuffer.addr)
  if skyVertexArray != 0:
    glDeleteVertexArrays(1, skyVertexArray.addr)
  reflectionFbo = 0
  reflectionColor = 0
  reflectionDepth = 0
  blankTexture = 0
  sceneCopyFbo = 0
  depthCopy = 0
  colorCopy = 0
  foamNoiseTexture = 0
  skyProgram = 0
  skyVertexBuffer = 0
  skyVertexArray = 0
  reflectionSize = ivec2(0, 0)
  sceneCopySize = ivec2(0, 0)

proc initWaters*() =
  ## Creates the water's textures, framebuffers and sky; call after initTerrain.
  destroyWaters()
  let program = waterShaderProgram()
  glUseProgram(program)
  glUniform1i(glGetUniformLocation(program, "reflectionTex"), ReflectionUnit)
  glUniform1i(glGetUniformLocation(program, "sceneDepthTex"), SceneDepthUnit)
  glUniform1i(glGetUniformLocation(program, "sceneColorTex"), SceneColorUnit)
  glUniform1i(glGetUniformLocation(program, "shoreField"), ShoreFieldUnit)
  glUniform1i(glGetUniformLocation(program, "foamNoiseTex"), FoamNoiseUnit)
  glUseProgram(0)
  glGenFramebuffers(1, sceneCopyFbo.addr)
  glGenTextures(1, depthCopy.addr)
  glGenTextures(1, colorCopy.addr)
  glGenFramebuffers(1, reflectionFbo.addr)
  glGenTextures(1, reflectionColor.addr)
  glGenRenderbuffers(1, reflectionDepth.addr)
  var noise = tileableNoise()
  glGenTextures(1, foamNoiseTexture.addr)
  glBindTexture(GL_TEXTURE_2D, foamNoiseTexture)
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
  glTexImage2D(GL_TEXTURE_2D, 0, GL_R8.GLint, 256, 256, 0, GL_RED, GL_UNSIGNED_BYTE,
    noise[0].addr)
  glPixelStorei(GL_UNPACK_ALIGNMENT, 4)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR.GLint)
  glGenerateMipmap(GL_TEXTURE_2D)
  # Bound for views without their own reflection pass, which reflect nothing.
  var white = [255'u8, 255, 255, 255]
  glGenTextures(1, blankTexture.addr)
  glBindTexture(GL_TEXTURE_2D, blankTexture)
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.GLint, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE,
    white[0].addr)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST.GLint)
  glBindTexture(GL_TEXTURE_2D, 0)
  let
    vertex = compileStage(GL_VERTEX_SHADER,
      toShader(waterSkyVert, ShaderTarget, shaderVertex))
    fragment = compileStage(GL_FRAGMENT_SHADER,
      toShader(waterSkyFrag, ShaderTarget, shaderFragment))
  skyProgram = glCreateProgram()
  glAttachShader(skyProgram, vertex)
  glAttachShader(skyProgram, fragment)
  glLinkProgram(skyProgram)
  glDetachShader(skyProgram, vertex)
  glDetachShader(skyProgram, fragment)
  glDeleteShader(vertex)
  glDeleteShader(fragment)
  var linked: GLint
  glGetProgramiv(skyProgram, GL_LINK_STATUS, linked.addr)
  if linked == 0:
    var
      log = newString(4096)
      length: GLsizei
    glGetProgramInfoLog(skyProgram, log.len.GLsizei, length.addr, log.cstring)
    log.setLen(length)
    destroyWaters()
    raise newException(PolyworldWaterError, "water sky program: " & log)
  var triangle = [-1'f32, -1, 3, -1, -1, 3]
  glGenVertexArrays(1, skyVertexArray.addr)
  glBindVertexArray(skyVertexArray)
  glGenBuffers(1, skyVertexBuffer.addr)
  glBindBuffer(GL_ARRAY_BUFFER, skyVertexBuffer)
  glBufferData(GL_ARRAY_BUFFER, sizeof(triangle), triangle[0].addr, GL_STATIC_DRAW)
  let position = glGetAttribLocation(skyProgram, "vertPos")
  glEnableVertexAttribArray(position.GLuint)
  glVertexAttribPointer(position.GLuint, 2, cGL_FLOAT, GL_FALSE, 0, nil)
  glBindVertexArray(0)

proc drawWaterSky*(viewProjection: Mat4, eye: Vec3, zenith, horizon, ground: Color) =
  ## Fills the current viewport with a sky for reflections: the background's colours by
  ## view direction (horizon at eye level), writing no depth. Draw it first.
  var inverse = viewProjection.inverse
  glUseProgram(skyProgram)
  glUniformMatrix4fv(glGetUniformLocation(skyProgram, "skyInverseViewProjection"), 1,
    GL_FALSE, cast[ptr float32](inverse.addr))
  glUniform3f(glGetUniformLocation(skyProgram, "skyEye"), eye.x, eye.y, eye.z)
  glUniform3f(glGetUniformLocation(skyProgram, "skyZenith"), zenith.r, zenith.g, zenith.b)
  glUniform3f(glGetUniformLocation(skyProgram, "skyHorizon"), horizon.r, horizon.g,
    horizon.b)
  glUniform3f(glGetUniformLocation(skyProgram, "skyGround"), ground.r, ground.g, ground.b)
  glDisable(GL_DEPTH_TEST)
  glDepthMask(GL_FALSE)
  glDisable(GL_BLEND)
  glDisable(GL_CULL_FACE)
  glBindVertexArray(skyVertexArray)
  glDrawArrays(GL_TRIANGLES, 0, 3)
  glBindVertexArray(0)
  glDepthMask(GL_TRUE)
  glEnable(GL_DEPTH_TEST)
  glUseProgram(0)

proc beginReflection*(size: IVec2) {.measure.} =
  ## Starts rendering a reflection into its texture, at the window's size.
  if reflectionActive:
    raise newException(PolyworldWaterError, "water reflection is already active")
  if size.x <= 0 or size.y <= 0:
    raise newException(PolyworldWaterError, "water reflection size must be positive")
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, savedReadFramebuffer.addr)
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, savedDrawFramebuffer.addr)
  glGetIntegerv(GL_VIEWPORT, savedViewport[0].addr)
  reflectionActive = true
  if size != reflectionSize:
    reflectionSize = size
    glBindTexture(GL_TEXTURE_2D, reflectionColor)
    # Half floats keep bright light above white; WebGL 2 cannot render to them without
    # an extension, so the browser keeps 8 bits.
    when defined(emscripten):
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.GLint, size.x, size.y, 0, GL_RGBA,
        GL_UNSIGNED_BYTE, nil)
    else:
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F.GLint, size.x, size.y, 0, GL_RGBA,
        cGL_FLOAT, nil)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE.GLint)
    glBindTexture(GL_TEXTURE_2D, 0)
    glBindRenderbuffer(GL_RENDERBUFFER, reflectionDepth)
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, size.x, size.y)
    glBindRenderbuffer(GL_RENDERBUFFER, 0)
    glBindFramebuffer(GL_FRAMEBUFFER, reflectionFbo)
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
      reflectionColor, 0)
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER,
      reflectionDepth)
    if glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE:
      raise newException(PolyworldWaterError, "water reflection framebuffer is incomplete")
  glBindFramebuffer(GL_FRAMEBUFFER, reflectionFbo)
  glViewport(0, 0, size.x, size.y)
  glClear(GL_DEPTH_BUFFER_BIT)

proc buildShoreField(layerIndex: int): ShoreField =
  ## Uploads one layer's shared shore distance samples.
  var data = buildShoreFieldData(layerIndex)
  result.origin = data.origin
  result.size = data.size
  if data.distances.len == 0:
    return
  let
    w = data.width
    h = data.height
  glGenTextures(1, result.texture.addr)
  glBindTexture(GL_TEXTURE_2D, result.texture)
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
  glTexImage2D(GL_TEXTURE_2D, 0, GL_R16F.GLint, w.GLsizei, h.GLsizei, 0, GL_RED,
    cGL_FLOAT, data.distances[0].addr)
  glPixelStorei(GL_UNPACK_ALIGNMENT, 4)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE.GLint)
  glBindTexture(GL_TEXTURE_2D, 0)

proc buildShoreFields*() =
  ## (Re)builds every water layer's shore distance field from the current terrain.
  ## drawWaterBody builds them on first use; call this after the terrain or its
  ## relief changes.
  for field in shoreFields:
    if field.texture != 0:
      var texture = field.texture
      glDeleteTextures(1, texture.addr)
  shoreFields.setLen(layers.len)
  for i in 0 ..< layers.len:
    shoreFields[i] =
      if layers[i].water and i < waterLayerSurfaces.len: buildShoreField(i)
      else: ShoreField()

proc captureScene*(size: IVec2) {.measure.} =
  ## Copies the current scene's colour and 24-bit depth into the water textures.
  ## Preserves the caller's targets, including an offscreen screenshot buffer.
  var readFramebuffer, drawFramebuffer: GLint
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, readFramebuffer.addr)
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, drawFramebuffer.addr)
  defer:
    glBindFramebuffer(GL_READ_FRAMEBUFFER, readFramebuffer.GLuint)
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, drawFramebuffer.GLuint)
  if size != sceneCopySize:
    sceneCopySize = size
    glBindTexture(GL_TEXTURE_2D, depthCopy)
    glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH24_STENCIL8.GLint, size.x, size.y, 0,
      GL_DEPTH_STENCIL, GL_UNSIGNED_INT_24_8, nil)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE.GLint)
    glBindTexture(GL_TEXTURE_2D, colorCopy)
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.GLint, size.x, size.y, 0, GL_RGBA,
      GL_UNSIGNED_BYTE, nil)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE.GLint)
    glBindTexture(GL_TEXTURE_2D, 0)
    glBindFramebuffer(GL_FRAMEBUFFER, sceneCopyFbo)
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
      colorCopy, 0)
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_TEXTURE_2D,
      depthCopy, 0)
    if glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE:
      raise newException(PolyworldWaterError, "water scene-copy framebuffer is incomplete")
  glBindFramebuffer(GL_READ_FRAMEBUFFER, drawFramebuffer.GLuint)
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, sceneCopyFbo)
  glBlitFramebuffer(0, 0, size.x, size.y, 0, 0, size.x, size.y,
    GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT, GL_NEAREST.GLenum)

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
  glUseProgram(program)
  var inverse = viewProjection.inverse
  glUniformMatrix4fv(glGetUniformLocation(program, "inverseViewProjection"), 1, GL_FALSE,
    cast[ptr float32](inverse.addr))
  glUniform4f(glGetUniformLocation(program, "depthViewport"),
    rect.x / windowSize.x, rect.y / windowSize.y,
    rect.z / windowSize.x, rect.w / windowSize.y)
  template uniform(name: string, value: float32) =
    glUniform1f(glGetUniformLocation(program, name), value)
  template uniform(name: string, value: Vec3) =
    glUniform3f(glGetUniformLocation(program, name), value.x, value.y, value.z)
  uniform("captureFlipY", 0)
  uniform("waterColor", params.color)
  uniform("sunColor", vec3(sunLight.r, sunLight.g, sunLight.b))
  uniform("waterSunToward", sunToward)
  uniform("waterLift", params.lift)
  # A view without its reflection pass reflects nothing at any angle.
  uniform("reflectiveness", if reflected: params.reflectiveness else: 0)
  uniform("fresnelStrength", if reflected: params.fresnelStrength else: 0)
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
  glUniform4f(glGetUniformLocation(program, "shoreFieldBounds"), field.origin.x,
    field.origin.y, max(field.size.x, 0.001), max(field.size.y, 0.001))
  # Wrapped every 10,000 s to keep float32 precision; the jump is rare and brief.
  uniform("rippleClock", float32((epochTime() - startTime) mod 10_000))
  glUseProgram(0)
  for (unit, texture) in [
    (ReflectionUnit, if reflected: reflectionColor else: blankTexture),
    (SceneDepthUnit, depthCopy), (SceneColorUnit, colorCopy),
    (ShoreFieldUnit, shoreFields[body.layer].texture),
    (FoamNoiseUnit, foamNoiseTexture)
  ]:
    glActiveTexture(GLenum(GL_TEXTURE0.int + unit))
    glBindTexture(GL_TEXTURE_2D, texture)
  glActiveTexture(GL_TEXTURE0)
  drawWater(viewProjection, eye, firstVertex = vertices.a, vertexCount = vertices.len)
