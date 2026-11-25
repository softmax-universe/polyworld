const ShaderTarget =
  when defined(emscripten):
    glsl3WebGL
  else:
    glsl4Desktop

proc compileShaderStage(
    kind: GLenum,
    source,
    label: string
): GLuint =
  ## Compiles one bar shader stage with a useful diagnostic.
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
    raise newException(
      WorldBarError,
      label & " shader failed:\n" & log & "\n" & source
    )

proc compileProgram(): GLuint =
  ## Compiles and links the shared world-bar shader program.
  let
    vertexShader = compileShaderStage(
      GL_VERTEX_SHADER,
      toShader(barVertex, ShaderTarget, shaderVertex),
      "world bar vertex"
    )
    fragmentShader = compileShaderStage(
      GL_FRAGMENT_SHADER,
      toShader(barFragment, ShaderTarget, shaderFragment),
      "world bar fragment"
    )
  result = glCreateProgram()
  glAttachShader(result, vertexShader)
  glAttachShader(result, fragmentShader)
  glLinkProgram(result)
  glDeleteShader(vertexShader)
  glDeleteShader(fragmentShader)
  var status: GLint
  glGetProgramiv(result, GL_LINK_STATUS, status.addr)
  if status == 0:
    var length: GLint
    glGetProgramiv(result, GL_INFO_LOG_LENGTH, length.addr)
    var log = newString(length)
    glGetProgramInfoLog(result, length, nil, log.cstring)
    raise newException(
      WorldBarError,
      "world bar program failed:\n" & log
    )

proc initWorldBarRenderer*(): WorldBarRenderer =
  ## Creates one dynamic mesh buffer for all world-space resource bars.
  result.gpu.program = compileProgram()
  glGenTextures(1, result.gpu.whiteTexture.addr)
  glBindTexture(GL_TEXTURE_2D, result.gpu.whiteTexture)
  var white = [255'u8, 255'u8, 255'u8, 255'u8]
  glTexImage2D(
    GL_TEXTURE_2D, 0, GL_RGBA.GLint, 1, 1, 0,
    GL_RGBA, GL_UNSIGNED_BYTE, white[0].addr
  )
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR.GLint)
  glGenVertexArrays(1, result.gpu.vertexArray.addr)
  glBindVertexArray(result.gpu.vertexArray)
  glGenBuffers(1, result.gpu.vertexBuffer.addr)
  glBindBuffer(GL_ARRAY_BUFFER, result.gpu.vertexBuffer)
  const stride = (VertexFloats * sizeof(float32)).GLsizei
  for attribute in [
    (name: "worldCenter", count: 3, offset: 0),
    (name: "billboardOffset", count: 2, offset: 3 * sizeof(float32)),
    (name: "vertexColor", count: 4, offset: 5 * sizeof(float32)),
    (name: "vertexUv", count: 2, offset: 9 * sizeof(float32)),
    (name: "vertexTextureMode", count: 1, offset: 11 * sizeof(float32))
  ]:
    let location = glGetAttribLocation(
      result.gpu.program,
      attribute.name.cstring
    )
    doAssert location >= 0
    glEnableVertexAttribArray(location.GLuint)
    glVertexAttribPointer(
      location.GLuint,
      attribute.count.GLint,
      cGL_FLOAT,
      GL_FALSE,
      stride,
      cast[pointer](attribute.offset)
    )
  glBindVertexArray(0)

proc closeWorldBarRenderer*(renderer: var WorldBarRenderer) =
  ## Releases this renderer's GPU resources while its context is current.
  ## Safe to repeat. Initialize a new renderer before drawing again.
  glDeleteProgram(renderer.gpu.program)
  glDeleteVertexArrays(1, renderer.gpu.vertexArray.addr)
  glDeleteBuffers(1, renderer.gpu.vertexBuffer.addr)
  glDeleteTextures(1, renderer.gpu.whiteTexture.addr)
  renderer = WorldBarRenderer()

proc draw*(
    renderer: var WorldBarRenderer,
    viewProjection: Mat4,
    cameraRight,
    cameraUp: Vec3,
    textureId = default(WorldBarTexture)
) =
  ## Uploads and draws the world-space billboard batch with scene depth.
  if renderer.vertices.len == 0:
    return
  glBindBuffer(GL_ARRAY_BUFFER, renderer.gpu.vertexBuffer)
  glBufferData(
    GL_ARRAY_BUFFER,
    renderer.vertices.len * sizeof(float32),
    renderer.vertices[0].addr,
    GL_DYNAMIC_DRAW
  )
  glEnable(GL_DEPTH_TEST)
  glDepthMask(GL_FALSE)
  glDisable(GL_CULL_FACE)
  glEnable(GL_BLEND)
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  glUseProgram(renderer.gpu.program)
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(
    GL_TEXTURE_2D,
    if textureId == 0: renderer.gpu.whiteTexture else: textureId
  )
  glUniform1i(glGetUniformLocation(renderer.gpu.program, "barTexture"), 0)
  barViewProjection = viewProjection
  barCameraRight = cameraRight
  barCameraUp = cameraUp
  glUniformMatrix4fv(
    glGetUniformLocation(renderer.gpu.program, "barViewProjection"),
    1,
    GL_FALSE,
    cast[ptr float32](barViewProjection.addr)
  )
  glUniform3f(
    glGetUniformLocation(renderer.gpu.program, "barCameraRight"),
    cameraRight.x,
    cameraRight.y,
    cameraRight.z
  )
  glUniform3f(
    glGetUniformLocation(renderer.gpu.program, "barCameraUp"),
    cameraUp.x,
    cameraUp.y,
    cameraUp.z
  )
  glBindVertexArray(renderer.gpu.vertexArray)
  glDrawArrays(
    GL_TRIANGLES,
    0,
    (renderer.vertices.len div VertexFloats).GLsizei
  )
  glBindVertexArray(0)
  glUseProgram(0)
  glDepthMask(GL_TRUE)
  glDisable(GL_BLEND)
