## OpenGL renderer for procedural visual effects.

import
  std/strutils,
  opengl, shady, vmath,
  ../../[fxmeshdata, fxmeshshaders]

const ShaderTarget =
  when defined(emscripten): glsl3WebGL
  else: glsl4Desktop

type
  FxRenderer* = object
    program: GLuint
    locations: array[FxUniform, GLint]
    vertexArray: GLuint
    vertexBuffer: GLuint
    indexBuffer: GLuint
    patternTextures: array[FxTexture, GLuint]
    indexCount*: int
    vertexCount*: int

proc makePatternTexture(kind: FxTexture): GLuint =
  ## Builds one repeating mipmapped grayscale pattern texture.
  var pixels = buildFxPattern(kind)
  glGenTextures(1, result.addr)
  glBindTexture(GL_TEXTURE_2D, result)
  glTexImage2D(
    GL_TEXTURE_2D,
    0,
    GL_RGBA8.GLint,
    FxTextureSize,
    FxTextureSize,
    0,
    GL_RGBA,
    GL_UNSIGNED_BYTE,
    pixels[0].addr
  )
  glGenerateMipmap(GL_TEXTURE_2D)
  glTexParameteri(
    GL_TEXTURE_2D,
    GL_TEXTURE_MIN_FILTER,
    GL_LINEAR_MIPMAP_LINEAR.GLint
  )
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT)
  glBindTexture(GL_TEXTURE_2D, 0)

## Renderer

proc compileStage(
  kind: GLenum,
  source, label: string
): GLuint {.raises: [FxMeshError].} =
  ## Compiles a shader stage or raises an fx-specific error.
  result = glCreateShader(kind)
  var sources = allocCStringArray([source])
  defer: deallocCStringArray(sources)
  glShaderSource(result, 1, sources, nil)
  glCompileShader(result)
  var ok: GLint
  glGetShaderiv(result, GL_COMPILE_STATUS, ok.addr)
  if ok == 0:
    var logLength: GLint
    glGetShaderiv(result, GL_INFO_LOG_LENGTH, logLength.addr)
    var log = newString(max(logLength.int, 1))
    glGetShaderInfoLog(result, logLength, nil, log.cstring)
    glDeleteShader(result)
    let message = label & " failed:\n" & log.strip(chars = {'\0'}) &
      "\nExpanded source:\n" & source
    echo message
    raise newException(FxMeshError, message)

proc initFxRenderer*(): FxRenderer {.raises: [FxMeshError].} =
  ## Compiles the single fx program and creates every GPU resource.
  let
    vertexShader = compileStage(
      GL_VERTEX_SHADER,
      toShader(fxVertex, ShaderTarget, shaderVertex),
      "Shady fx vertex"
    )
    fragmentShader = compileStage(
      GL_FRAGMENT_SHADER,
      toShader(fxFragment, ShaderTarget, shaderFragment),
      "Shady fx fragment"
    )
  result.program = glCreateProgram()
  glAttachShader(result.program, vertexShader)
  glAttachShader(result.program, fragmentShader)
  glLinkProgram(result.program)
  glDeleteShader(vertexShader)
  glDeleteShader(fragmentShader)
  var ok: GLint
  glGetProgramiv(result.program, GL_LINK_STATUS, ok.addr)
  if ok == 0:
    var logLength: GLint
    glGetProgramiv(result.program, GL_INFO_LOG_LENGTH, logLength.addr)
    var log = newString(max(logLength.int, 1))
    glGetProgramInfoLog(result.program, logLength, nil, log.cstring)
    glDeleteProgram(result.program)
    raise newException(FxMeshError, "fx program failed to link:\n" & log)
  for uniform in FxUniform:
    result.locations[uniform] = glGetUniformLocation(
      result.program,
      FxUniformNames[uniform].cstring
    )

  glGenVertexArrays(1, result.vertexArray.addr)
  glGenBuffers(1, result.vertexBuffer.addr)
  glGenBuffers(1, result.indexBuffer.addr)
  glBindVertexArray(result.vertexArray)
  glBindBuffer(GL_ARRAY_BUFFER, result.vertexBuffer)
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, result.indexBuffer)
  let stride = GLsizei(12 * sizeof(float32))
  let
    positionLocation = glGetAttribLocation(result.program, "vertPos")
    normalLocation = glGetAttribLocation(result.program, "vertNormal")
    uvLocation = glGetAttribLocation(result.program, "vertUv")
    dataLocation = glGetAttribLocation(result.program, "vertData")
  glEnableVertexAttribArray(positionLocation.GLuint)
  glVertexAttribPointer(
    positionLocation.GLuint, 3, cGL_FLOAT, GL_FALSE, stride, nil
  )
  glEnableVertexAttribArray(normalLocation.GLuint)
  glVertexAttribPointer(
    normalLocation.GLuint,
    3,
    cGL_FLOAT,
    GL_FALSE,
    stride,
    cast[pointer](3 * sizeof(float32))
  )
  glEnableVertexAttribArray(uvLocation.GLuint)
  glVertexAttribPointer(
    uvLocation.GLuint,
    2,
    cGL_FLOAT,
    GL_FALSE,
    stride,
    cast[pointer](6 * sizeof(float32))
  )
  glEnableVertexAttribArray(dataLocation.GLuint)
  glVertexAttribPointer(
    dataLocation.GLuint,
    4,
    cGL_FLOAT,
    GL_FALSE,
    stride,
    cast[pointer](8 * sizeof(float32))
  )
  glBindVertexArray(0)

  for kind in FxTexture:
    result.patternTextures[kind] = makePatternTexture(kind)

proc uploadFxMesh*(
    renderer: var FxRenderer,
    mesh: tuple[vertices: seq[float32], indices: seq[uint32]]
) =
  ## Uploads packed geometry, including map-projected effect meshes.
  renderer.vertexCount = mesh.vertices.len div 12
  renderer.indexCount = mesh.indices.len
  glBindVertexArray(renderer.vertexArray)
  glBindBuffer(GL_ARRAY_BUFFER, renderer.vertexBuffer)
  glBufferData(
    GL_ARRAY_BUFFER,
    mesh.vertices.len * sizeof(float32),
    if mesh.vertices.len > 0: cast[pointer](mesh.vertices[0].addr) else: nil,
    GL_STATIC_DRAW
  )
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, renderer.indexBuffer)
  glBufferData(
    GL_ELEMENT_ARRAY_BUFFER,
    mesh.indices.len * sizeof(uint32),
    if mesh.indices.len > 0: cast[pointer](mesh.indices[0].addr) else: nil,
    GL_STATIC_DRAW
  )
  glBindVertexArray(0)

proc uploadFxMesh*(renderer: var FxRenderer, s: FxSettings) =
  ## Rebuilds the current shape and uploads it to the GPU buffers.
  renderer.uploadFxMesh(buildFxMesh(s))

proc closeFxRenderer*(renderer: var FxRenderer) =
  ## Releases the fx program, buffers, and pattern textures.
  if renderer.program != 0:
    glDeleteProgram(renderer.program)
  if renderer.vertexArray != 0:
    glDeleteVertexArrays(1, renderer.vertexArray.addr)
  if renderer.vertexBuffer != 0:
    glDeleteBuffers(1, renderer.vertexBuffer.addr)
  if renderer.indexBuffer != 0:
    glDeleteBuffers(1, renderer.indexBuffer.addr)
  for kind in FxTexture:
    if renderer.patternTextures[kind] != 0:
      glDeleteTextures(1, renderer.patternTextures[kind].addr)
  renderer = FxRenderer()

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
  ## Draws one uploaded fx mesh. Does not clear the framebuffer.
  if renderer.program == 0 or renderer.indexCount == 0:
    return
  template location(uniform: FxUniform): GLint =
    renderer.locations[uniform]
  var
    viewMatrix = viewProjection
    modelMatrix = model * scale(vec3(sizeScale))
  glEnable(GL_DEPTH_TEST)
  glDepthMask(GL_FALSE)
  glDisable(GL_CULL_FACE)
  glEnable(GL_BLEND)
  case settings.blendMode
  of AlphaBlend:
    glBlendFuncSeparate(
      GL_SRC_ALPHA,
      GL_ONE_MINUS_SRC_ALPHA,
      GL_ONE,
      GL_ONE_MINUS_SRC_ALPHA
    )
  of AdditiveBlend:
    glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE, GL_ZERO, GL_ONE)
  glUseProgram(renderer.program)
  let edgeFade = fxEdgeFade(settings)
  glUniform4f(location(EdgeFadeUniform),
    edgeFade.x, edgeFade.y, edgeFade.z, edgeFade.w)
  let edgeShape = fxEdgeShape(settings)
  glUniform2f(location(EdgeShapeUniform), edgeShape.x, edgeShape.y)
  glUniformMatrix4fv(
    location(ViewProjectionUniform),
    1,
    GL_FALSE,
    cast[ptr float32](viewMatrix.addr)
  )
  glUniformMatrix4fv(
    location(ModelUniform),
    1,
    GL_FALSE,
    cast[ptr float32](modelMatrix.addr)
  )
  glUniform1f(location(TimeUniform), time)
  glUniform1f(location(LifeUniform), life)
  glUniform1f(location(AlphaUniform), fxAlpha(settings, life))
  glUniform1f(location(DissolveUniform), fxDissolve(settings, life))
  glUniform1f(location(DissolveEdgeUniform), settings.dissolveEdge)
  glUniform1f(location(SpinSpeedUniform), settings.spinSpeed)
  glUniform1f(location(TwistAngleUniform), settings.twistAngle)
  glUniform1f(location(WaveAmpUniform), settings.waveAmp)
  glUniform1f(location(WaveFreqUniform), settings.waveFreq)
  glUniform1f(location(WaveSpeedUniform), settings.waveSpeed)
  glUniform1f(location(RippleAmpUniform), settings.rippleAmp)
  glUniform1f(location(RippleFreqUniform), settings.rippleFreq)
  glUniform1f(location(RippleSpeedUniform), settings.rippleSpeed)
  glUniform1f(location(InflateUniform), settings.inflate)
  glUniform1f(location(PulseAmpUniform), settings.pulseAmp)
  glUniform1f(location(PulseSpeedUniform), settings.pulseSpeed)
  glUniform1f(location(ExpandStartUniform), settings.expandStart)
  glUniform1f(location(ExpandEndUniform), settings.expandEnd)
  glUniform1f(location(ExpandPowerUniform), settings.expandPower)
  glUniform1i(location(SweepSourceUniform), settings.sweepSource.ord.GLint)
  glUniform1f(location(SweepBandUniform), settings.sweepBand)
  glUniform1f(location(SweepSoftUniform), settings.sweepSoft)
  glUniform2f(location(UvScaleUniform), settings.uvScale.x, settings.uvScale.y)
  glUniform2f(location(ScrollUniform), settings.scroll.x, settings.scroll.y)
  glUniform1f(location(NoiseScaleUniform), settings.noiseScale)
  glUniform1i(
    location(GradientSourceUniform),
    settings.gradientSource.ord.GLint
  )
  glUniform4f(
    location(StartColorUniform),
    settings.startColor.x,
    settings.startColor.y,
    settings.startColor.z,
    settings.startColor.w
  )
  glUniform4f(
    location(EndColorUniform),
    settings.endColor.x,
    settings.endColor.y,
    settings.endColor.z,
    settings.endColor.w
  )
  glUniform4f(
    location(EdgeColorUniform),
    settings.edgeColor.x,
    settings.edgeColor.y,
    settings.edgeColor.z,
    settings.edgeColor.w
  )
  glUniform1i(location(PatternUniform), 0)
  glUniform1i(location(NoiseUniform), 1)
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, renderer.patternTextures[settings.texture])
  glActiveTexture(GL_TEXTURE1)
  glBindTexture(GL_TEXTURE_2D, renderer.patternTextures[NoiseTexture])
  glActiveTexture(GL_TEXTURE0)
  when not defined(emscripten):
    if wireframe:
      glPolygonMode(GL_FRONT_AND_BACK, GL_LINE)
  glBindVertexArray(renderer.vertexArray)
  glDrawElements(
    GL_TRIANGLES,
    renderer.indexCount.GLsizei,
    GL_UNSIGNED_INT,
    nil
  )
  glBindVertexArray(0)
  when not defined(emscripten):
    if wireframe:
      glPolygonMode(GL_FRONT_AND_BACK, GL_FILL)
  glUseProgram(0)
  glDepthMask(GL_TRUE)
  glDisable(GL_DEPTH_TEST)
  glDisable(GL_BLEND)
