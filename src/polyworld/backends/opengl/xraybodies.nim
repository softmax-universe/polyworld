## OpenGL implementation of the screen-door X-ray body pass.

import
  opengl, shady, vmath,
  ../shaders/xraybodies

export xraybodies

type
  XrayBodies* = object
    settings*: XrayBodySettings
    framebuffer: GLuint
    colorTexture: GLuint
    depthTexture: GLuint
    program: GLuint
    vertexArray: GLuint
    size: IVec2
    target: GLint          ## The framebuffer bound before `beginXrayBodies`.
    viewport: array[4, GLint]
    open: bool             ## Between a successful begin and its finish.
    locations: array[7, GLint]

const
  ShaderTarget =
    when defined(emscripten):
      glsl3WebGL
    else:
      glsl4Desktop

proc compileStage(kind: GLenum, source, label: string): GLuint =
  ## Compiles one stage, raising with the driver's log on failure.
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
    raise newException(XrayBodyError,
      "x-ray body " & label & " shader failed:\n" & log)

proc compileProgram(): GLuint =
  ## Links the screen-door composite shader stages.
  let
    vertexShader = compileStage(
      GL_VERTEX_SHADER,
      toShader(fullscreenVertex, ShaderTarget, shaderVertex),
      "vertex"
    )
    fragmentShader = compileStage(
      GL_FRAGMENT_SHADER,
      toShader(compositeFragment, ShaderTarget, shaderFragment),
      "fragment"
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
    raise newException(XrayBodyError, "x-ray body program failed:\n" & log)

proc initXrayBodies*(
    settings = defaultXrayBodySettings()
): XrayBodies =
  ## Compiles the composite. The target is made on the first frame.
  result.settings = settings
  result.program = compileProgram()
  for i, name in ["bodyColor", "bodyDepth", "coverage", "cell",
      "depthTerms", "clearance", "patternYTransform"]:
    result.locations[i] = glGetUniformLocation(result.program, name.cstring)
  glGenVertexArrays(1, result.vertexArray.addr)
  glGenFramebuffers(1, result.framebuffer.addr)
  glGenTextures(1, result.colorTexture.addr)
  glGenTextures(1, result.depthTexture.addr)

proc closeXrayBodies*(xray: var XrayBodies) =
  ## Releases every GL object the pass owns.
  glDeleteTextures(1, xray.colorTexture.addr)
  glDeleteTextures(1, xray.depthTexture.addr)
  glDeleteFramebuffers(1, xray.framebuffer.addr)
  glDeleteVertexArrays(1, xray.vertexArray.addr)
  glDeleteProgram(xray.program)
  xray = XrayBodies()

proc ensureSize(xray: var XrayBodies, size: IVec2) =
  ## Matches the offscreen target to the window, one texel per pixel.
  if size == xray.size:
    return
  xray.size = size
  for (texture, internal, format, kind) in [
      (xray.colorTexture, GL_RGBA8.GLint, GL_RGBA, GL_UNSIGNED_BYTE),
      (xray.depthTexture, GL_DEPTH_COMPONENT24.GLint, GL_DEPTH_COMPONENT,
        GL_UNSIGNED_INT)]:
    glBindTexture(GL_TEXTURE_2D, texture)
    glTexImage2D(GL_TEXTURE_2D, 0, internal, size.x.GLsizei, size.y.GLsizei,
      0, format, kind, nil)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE.GLint)
  glBindTexture(GL_TEXTURE_2D, 0)
  glBindFramebuffer(GL_FRAMEBUFFER, xray.framebuffer)
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
    xray.colorTexture, 0)
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D,
    xray.depthTexture, 0)
  if glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE:
    xray.settings.enabled = false
    echo "X-ray bodies are off: the offscreen target is incomplete"

proc beginXrayBodies*(xray: var XrayBodies, size: IVec2): bool =
  ## Binds and clears the body target; draw the bodies next, then call
  ## `finishXrayBodies`. Returns false (and binds nothing) when the pass is
  ## off, so the bodies needn't be drawn.
  xray.open = false
  if not xray.settings.enabled or size.x <= 0 or size.y <= 0:
    return false
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, xray.target.addr)
  glGetIntegerv(GL_VIEWPORT, xray.viewport[0].addr)
  xray.ensureSize(size)
  if not xray.settings.enabled:
    glBindFramebuffer(GL_FRAMEBUFFER, xray.target.GLuint)
    return false
  glBindFramebuffer(GL_FRAMEBUFFER, xray.framebuffer)
  glViewport(0, 0, size.x.GLsizei, size.y.GLsizei)
  glDepthMask(GL_TRUE)
  glClearColor(0, 0, 0, 0)
  glClearDepth(1)
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
  xray.open = true
  true

proc finishXrayBodies*(
    xray: var XrayBodies, projection: Mat4, contentScale = 1'f
) =
  ## Lays the hidden parts of the bodies over the framebuffer that was bound
  ## at `beginXrayBodies`, on the dither pattern. `projection` is the one
  ## the bodies were drawn with; `contentScale` is the window's pixels per
  ## point. Leaves depth writes on and the test LEQUAL.
  if not xray.open:
    return
  xray.open = false
  glBindFramebuffer(GL_FRAMEBUFFER, xray.target.GLuint)
  glViewport(xray.viewport[0], xray.viewport[1],
    xray.viewport[2].GLsizei, xray.viewport[3].GLsizei)
  glEnable(GL_DEPTH_TEST)
  glDepthFunc(GL_GREATER)
  glDepthMask(GL_FALSE)
  glDisable(GL_BLEND)
  glDisable(GL_CULL_FACE)
  glUseProgram(xray.program)
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, xray.colorTexture)
  glUniform1i(xray.locations[0], 0)
  glActiveTexture(GL_TEXTURE1)
  glBindTexture(GL_TEXTURE_2D, xray.depthTexture)
  glUniform1i(xray.locations[1], 1)
  glUniform1f(xray.locations[2], xray.settings.coverage)
  glUniform1f(xray.locations[3],
    max(1'f, round(xray.settings.cell * max(contentScale, 1'f))))
  glUniform4f(xray.locations[4], projection[2, 2], projection[3, 2],
    projection[2, 3], projection[3, 3])
  glUniform1f(xray.locations[5], xray.settings.clearance)
  glUniform2f(xray.locations[6], 1, 0)
  glBindVertexArray(xray.vertexArray)
  glDrawArrays(GL_TRIANGLES, 0, 3)
  glBindVertexArray(0)
  glUseProgram(0)
  glBindTexture(GL_TEXTURE_2D, 0)
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, 0)
  glDepthFunc(GL_LEQUAL)
  glDepthMask(GL_TRUE)
  glEnable(GL_CULL_FACE)
