## LvD-only final current-sight clip. Preserve the explored ground image,
## then restore it over every hidden ground pixel after props/effects/shadows.
## Shared shaders/defaults and authoritative state are untouched.
import opengl, shady, vmath

const ShaderTarget =
  when defined(emscripten):
    glsl3WebGL
  else:
    glsl4Desktop

type StrictFog* = object
  program, vao, framebuffer, color, depth, sight: GLuint
  size: IVec2
  target: GLint
  capturing: bool
  inverse: Mat4
  side: int

proc strictFogVertex(gl_Position: var Vec4, uv: var Vec2) =
  ## Covers the viewport with one triangle and matching texture coordinates.
  let point = vec2(
    float32((gl_VertexID mod 2) * 2),
    float32((gl_VertexID div 2) * 2)
  )
  uv = point
  gl_Position = vec4(point * 2.0'f - 1.0'f, vec2(0.0'f, 1.0'f))

proc strictFogFragment(
    uv: Vec2,
    color: var Vec4,
    groundColor, groundDepth, currentSight: Uniform[Sampler2D],
    inverseView: Uniform[Mat4],
    mapSide: Uniform[float32]
) =
  ## Restores ground outside current sight after later scene passes.
  let
    depth = texture(groundDepth, uv).r
    point = inverseView * vec4(uv * 2.0'f - 1.0'f,
      vec2(depth * 2.0'f - 1.0'f, 1.0'f))
    cell = floor(point.xz / point.w + mapSide * 0.5'f)
    inside = cell.x >= 0.0'f and cell.y >= 0.0'f and
      cell.x < mapSide and cell.y < mapSide
  if depth < 1.0'f and inside and
    texelFetch(currentSight, ivec2(cell), 0).r > 0.5'f:
      discardFragment()
  color = texture(groundColor, uv)

proc compile(kind: GLenum, text: string): GLuint =
  ## Compiles one Shady-generated stage for the current graphics target.
  result = glCreateShader(kind)
  var sources = allocCStringArray([text])
  glShaderSource(result, 1, sources, nil)
  deallocCStringArray(sources)
  glCompileShader(result)
  var ok: GLint
  glGetShaderiv(result, GL_COMPILE_STATUS, ok.addr)
  if ok == 0:
    var length: GLint
    glGetShaderiv(result, GL_INFO_LOG_LENGTH, length.addr)
    var log = newString(length)
    glGetShaderInfoLog(result, length, nil, log.cstring)
    doAssert false, "Strict fog shader compilation failed:\n" & log & text

proc initStrictFog*(): StrictFog =
  ## Creates the Shady program and framebuffer resources for strict fog.
  let
    vertex = compile(GL_VERTEX_SHADER,
      toShader(strictFogVertex, ShaderTarget, shaderVertex))
    fragment = compile(GL_FRAGMENT_SHADER,
      toShader(strictFogFragment, ShaderTarget, shaderFragment))
  result.program = glCreateProgram()
  glAttachShader(result.program, vertex)
  glAttachShader(result.program, fragment)
  glLinkProgram(result.program)
  glDeleteShader(vertex)
  glDeleteShader(fragment)
  var ok: GLint
  glGetProgramiv(result.program, GL_LINK_STATUS, ok.addr)
  doAssert ok != 0
  glGenVertexArrays(1, result.vao.addr)
  glGenFramebuffers(1, result.framebuffer.addr)
  glGenTextures(1, result.color.addr)
  glGenTextures(1, result.depth.addr)
  glGenTextures(1, result.sight.addr)

proc beginStrictGround*(fog: var StrictFog, size: IVec2) =
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, fog.target.addr)
  if fog.size != size:
    fog.size = size
    for tex in [fog.color, fog.depth]:
      glBindTexture(GL_TEXTURE_2D, tex)
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST.GLint)
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST.GLint)
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE.GLint)
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE.GLint)
      if tex == fog.color:
        glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8.GLint,size.x,size.y,0,GL_RGBA,GL_UNSIGNED_BYTE,nil)
      else:
        glTexImage2D(GL_TEXTURE_2D,0,GL_DEPTH_COMPONENT24.GLint,size.x,size.y,0,GL_DEPTH_COMPONENT,GL_UNSIGNED_INT,nil)
    glBindFramebuffer(GL_FRAMEBUFFER, fog.framebuffer)
    glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,fog.color,0)
    glFramebufferTexture2D(GL_FRAMEBUFFER,GL_DEPTH_ATTACHMENT,GL_TEXTURE_2D,fog.depth,0)
    doAssert glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE
  glBindFramebuffer(GL_FRAMEBUFFER, fog.framebuffer)
  glViewport(0, 0, size.x, size.y)
  fog.capturing = true

proc captureStrictGround*(fog: var StrictFog, size: IVec2, inverseView: Mat4,
    values: openArray[uint8], side: int) =
  fog.inverse = inverseView
  fog.side = side
  if not fog.capturing:
    fog.beginStrictGround(size)
    glBindFramebuffer(GL_READ_FRAMEBUFFER, fog.target.GLuint)
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, fog.framebuffer)
    glBlitFramebuffer(0,0,size.x,size.y,0,0,size.x,size.y,
      GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT,GL_NEAREST.GLenum)
  fog.capturing = false
  glBindFramebuffer(GL_FRAMEBUFFER, fog.target.GLuint)
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, fog.sight)
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST.GLint)
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST.GLint)
  var alignment: GLint
  glGetIntegerv(GL_UNPACK_ALIGNMENT, alignment.addr)
  glPixelStorei(GL_UNPACK_ALIGNMENT,1)
  glTexImage2D(GL_TEXTURE_2D,0,GL_R8.GLint,side.GLsizei,side.GLsizei,0,GL_RED,GL_UNSIGNED_BYTE,unsafeAddr values[0])
  glPixelStorei(GL_UNPACK_ALIGNMENT,alignment)

proc restoreHiddenGround*(fog: var StrictFog) =
  glBindFramebuffer(GL_FRAMEBUFFER,fog.target.GLuint)
  glViewport(0,0,fog.size.x,fog.size.y)
  glDisable(GL_DEPTH_TEST)
  glDisable(GL_BLEND)
  glDisable(GL_CULL_FACE)
  glDepthMask(GL_FALSE)
  glUseProgram(fog.program)
  for i, name in ["groundColor", "groundDepth", "currentSight"]:
    glActiveTexture(GLenum(GL_TEXTURE0.uint32 + i.uint32))
    glBindTexture(GL_TEXTURE_2D, [fog.color,fog.depth,fog.sight][i])
    glUniform1i(glGetUniformLocation(fog.program,name.cstring),i.GLint)
  glUniformMatrix4fv(glGetUniformLocation(fog.program,"inverseView"),1,GL_FALSE,cast[ptr float32](fog.inverse.addr))
  glUniform1f(glGetUniformLocation(fog.program,"mapSide"),fog.side.float32)
  glBindVertexArray(fog.vao)
  glDrawArrays(GL_TRIANGLES,0,3)
  glBindVertexArray(0)
  glUseProgram(0)
  glDepthMask(GL_TRUE)
  glActiveTexture(GL_TEXTURE0)

proc closeStrictFog*(fog: var StrictFog) =
  glDeleteProgram(fog.program)
  glDeleteVertexArrays(1,fog.vao.addr)
  glDeleteFramebuffers(1,fog.framebuffer.addr)
  glDeleteTextures(1,fog.color.addr)
  glDeleteTextures(1,fog.depth.addr)
  glDeleteTextures(1,fog.sight.addr)
  fog = StrictFog()
