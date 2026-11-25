import opengl, shady, vmath
import ../../tableshaders

const ShaderTarget =
  when defined(emscripten): glsl3WebGL
  else: glsl4Desktop

type
  SolidRenderer* = object
    program: GLuint
    vertexArray: GLuint
    vertexBuffer: GLuint
    vertices*: seq[float32]

proc compileStage(
    kind: GLenum,
    source,
    label: string
): GLuint =
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
      CatchableError,
      label & " shader failed:\n" & log & "\n" & source
    )

proc compileSolidProgram(): GLuint =
  let
    vertexShader = compileStage(
      GL_VERTEX_SHADER,
      toShader(solidVertex, ShaderTarget, shaderVertex),
      "CaC solid vertex"
    )
    fragmentShader = compileStage(
      GL_FRAGMENT_SHADER,
      toShader(solidFragment, ShaderTarget, shaderFragment),
      "CaC solid fragment"
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
      CatchableError,
      "CaC solid program failed:\n" & log
    )

proc initSolidRenderer*(): SolidRenderer =
  result.program = compileSolidProgram()
  glGenVertexArrays(1, result.vertexArray.addr)
  glBindVertexArray(result.vertexArray)
  glGenBuffers(1, result.vertexBuffer.addr)
  glBindBuffer(GL_ARRAY_BUFFER, result.vertexBuffer)
  const stride = (10 * sizeof(float32)).GLsizei
  for attribute in [
    (name: "position", count: 3, offset: 0),
    (name: "normal", count: 3, offset: 3 * sizeof(float32)),
    (name: "color", count: 4, offset: 6 * sizeof(float32))
  ]:
    let location = glGetAttribLocation(
      result.program,
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

proc draw*(
    renderer: var SolidRenderer,
    viewProjection: Mat4
) =
  if renderer.vertices.len == 0:
    return
  glBindBuffer(GL_ARRAY_BUFFER, renderer.vertexBuffer)
  glBufferData(
    GL_ARRAY_BUFFER,
    renderer.vertices.len * sizeof(float32),
    renderer.vertices[0].addr,
    GL_DYNAMIC_DRAW
  )
  glEnable(GL_DEPTH_TEST)
  glDepthMask(GL_TRUE)
  glDisable(GL_BLEND)
  glDisable(GL_CULL_FACE)
  glUseProgram(renderer.program)
  solidViewProjection = viewProjection
  solidLightDirection = normalize(vec3(-0.5, 1.0, 0.65))
  glUniformMatrix4fv(
    glGetUniformLocation(renderer.program, "solidViewProjection"),
    1,
    GL_FALSE,
    cast[ptr float32](solidViewProjection.addr)
  )
  glUniform3f(
    glGetUniformLocation(renderer.program, "solidLightDirection"),
    solidLightDirection.x,
    solidLightDirection.y,
    solidLightDirection.z
  )
  glBindVertexArray(renderer.vertexArray)
  glDrawArrays(
    GL_TRIANGLES,
    0,
    (renderer.vertices.len div 10).GLsizei
  )
  glBindVertexArray(0)
