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
  ## Compiles one shape shader stage with a useful diagnostic.
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
      ShapeError,
      label & " shader failed:\n" & log & "\n" & source
    )

proc compileProgram(): GLuint =
  ## Compiles and links the shape shader program.
  let
    vertexShader = compileShaderStage(
      GL_VERTEX_SHADER,
      toShader(shapeVertex, ShaderTarget, shaderVertex),
      "shape vertex"
    )
    fragmentShader = compileShaderStage(
      GL_FRAGMENT_SHADER,
      toShader(shapeFragment, ShaderTarget, shaderFragment),
      "shape fragment"
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
      ShapeError,
      "shape program failed:\n" & log
    )

proc makeWhiteTexture(): GLuint =
  ## Builds a 1x1 white texel used when no atlas is bound.
  glGenTextures(1, result.addr)
  glBindTexture(GL_TEXTURE_2D, result)
  var pixel = [255'u8, 255, 255, 255]
  glTexImage2D(
    GL_TEXTURE_2D,
    0,
    GL_RGBA.GLint,
    1,
    1,
    0,
    GL_RGBA,
    GL_UNSIGNED_BYTE,
    pixel[0].addr
  )
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE.GLint)
  glBindTexture(GL_TEXTURE_2D, 0)

proc initShapeRenderer*(): ShapeRenderer =
  ## Creates one dynamic mesh buffer for world-space shapes.
  result.gpu.program = compileProgram()
  result.gpu.whiteTexture = makeWhiteTexture()
  glGenVertexArrays(1, result.gpu.vertexArray.addr)
  glBindVertexArray(result.gpu.vertexArray)
  glGenBuffers(1, result.gpu.vertexBuffer.addr)
  glBindBuffer(GL_ARRAY_BUFFER, result.gpu.vertexBuffer)
  const stride = (VertexFloats * sizeof(float32)).GLsizei
  for attribute in [
    (name: "worldPosition", count: 3, offset: 0),
    (name: "texturePosition", count: 2, offset: 3 * sizeof(float32)),
    (name: "vertexColor", count: 4, offset: 5 * sizeof(float32))
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

proc closeShapeRenderer*(renderer: var ShapeRenderer) =
    ## Releases owned GPU resources while the renderer's context is current.
    ## The externally supplied texture is borrowed and remains alive.
    ## Safe to repeat. Initialize a new renderer before drawing again.
    glDeleteProgram(renderer.gpu.program)
    glDeleteVertexArrays(1, renderer.gpu.vertexArray.addr)
    glDeleteBuffers(1, renderer.gpu.vertexBuffer.addr)
    glDeleteTextures(1, renderer.gpu.whiteTexture.addr)
    renderer = ShapeRenderer()

proc draw*(
    renderer: var ShapeRenderer,
    viewProjection: Mat4,
    opaque = false
) =
  ## Draws the shape batch, writing depth for opaque surfaces.
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
  glDepthMask(if opaque: GL_TRUE else: GL_FALSE)
  glDisable(GL_CULL_FACE)
  if opaque:
    glDisable(GL_BLEND)
  else:
    glEnable(GL_BLEND)
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  glUseProgram(renderer.gpu.program)
  shapeViewProjection = viewProjection
  glUniformMatrix4fv(
    glGetUniformLocation(renderer.gpu.program, "shapeViewProjection"),
    1,
    GL_FALSE,
    cast[ptr float32](shapeViewProjection.addr)
  )
  glActiveTexture(GL_TEXTURE0)
  if renderer.texture != 0:
    glBindTexture(GL_TEXTURE_2D, renderer.texture)
  else:
    glBindTexture(GL_TEXTURE_2D, renderer.gpu.whiteTexture)
  glUniform1i(glGetUniformLocation(renderer.gpu.program, "shapeSampler"), 0)
  glBindVertexArray(renderer.gpu.vertexArray)
  glDrawArrays(
    GL_TRIANGLES,
    0,
    (renderer.vertices.len div VertexFloats).GLsizei
  )
  glBindVertexArray(0)
  glBindTexture(GL_TEXTURE_2D, 0)
  glDepthMask(GL_TRUE)
