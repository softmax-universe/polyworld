## OpenGL distortion rendering with a resolved copy of the finished scene.

import
  std/strutils,
  opengl, shady, vmath,
  ../shaders/distortions

export distortions

type
  DistortionRenderer* = object
    program, vertexArray, vertexBuffer: GLuint
    copyFramebuffer, copyTexture: GLuint
    size: IVec2
    ready, unavailable, copyChecked: bool
    floats: seq[float32]
    viewMatrix, sceneSampler, viewportSize, clock, shiftScale: GLint

  SavedState = object
    viewport: array[4, GLint]
    depthTest, cullFace, blend: GLboolean
    depthMask: GLboolean
    blendFuncs: array[4, GLint]
    program, vertexArray, activeTexture, texture0: GLint
    readFramebuffer, drawFramebuffer, arrayBuffer: GLint

const
  ShaderTarget =
    when defined(emscripten):
      glsl3WebGL
    else:
      glsl4Desktop

proc compileStage(kind: GLenum, source: string): GLuint =
  ## Compiles one distortion shader stage with driver diagnostics.
  result = glCreateShader(kind)
  let text = allocCStringArray([source])
  defer: deallocCStringArray(text)
  glShaderSource(result, 1, text, nil)
  glCompileShader(result)
  var status: GLint
  glGetShaderiv(result, GL_COMPILE_STATUS, status.addr)
  if status == 0:
    var length: GLint
    glGetShaderiv(result, GL_INFO_LOG_LENGTH, length.addr)
    var log = newString(max(1, length))
    glGetShaderInfoLog(result, length, nil, log.cstring)
    raise newException(DistortionError, "Distortion shader failed:\n" & log)

proc setup(renderer: var DistortionRenderer) =
  ## Builds the program and buffers on first use, with a GL context current.
  let
    vertex = compileStage(
      GL_VERTEX_SHADER,
      toShader(distortionVertex, ShaderTarget, shaderVertex)
    )
    fragment = compileStage(
      GL_FRAGMENT_SHADER,
      toShader(distortionFragment, ShaderTarget, shaderFragment)
    )
  renderer.program = glCreateProgram()
  glAttachShader(renderer.program, vertex)
  glAttachShader(renderer.program, fragment)
  glLinkProgram(renderer.program)
  glDeleteShader(vertex)
  glDeleteShader(fragment)
  var linked: GLint
  glGetProgramiv(renderer.program, GL_LINK_STATUS, linked.addr)
  if linked == 0:
    raise newException(DistortionError, "Distortion program did not link")
  renderer.viewMatrix = glGetUniformLocation(renderer.program, "viewMatrix")
  renderer.sceneSampler = glGetUniformLocation(renderer.program, "scene")
  renderer.viewportSize = glGetUniformLocation(renderer.program, "viewportSize")
  renderer.clock = glGetUniformLocation(renderer.program, "clock")
  renderer.shiftScale = glGetUniformLocation(renderer.program, "shiftScale")
  glGenVertexArrays(1, renderer.vertexArray.addr)
  glBindVertexArray(renderer.vertexArray)
  glGenBuffers(1, renderer.vertexBuffer.addr)
  glBindBuffer(GL_ARRAY_BUFFER, renderer.vertexBuffer)
  const stride = (VertexFloats * sizeof(float32)).GLsizei
  for (name, count, offset) in [("position", 3, 0), ("corner", 2, 3), ("params", 4, 5)]:
    let location = glGetAttribLocation(renderer.program, name.cstring)
    if location < 0: continue
    glEnableVertexAttribArray(location.GLuint)
    glVertexAttribPointer(location.GLuint, count.GLint, cGL_FLOAT, GL_FALSE, stride,
      cast[pointer](offset * sizeof(float32)))
  glBindVertexArray(0)
  glGenFramebuffers(1, renderer.copyFramebuffer.addr)
  glGenTextures(1, renderer.copyTexture.addr)
  renderer.ready = true

proc ensureSize(renderer: var DistortionRenderer, size: IVec2) =
  ## Matches the scene copy to the window.
  if size == renderer.size: return
  renderer.size = size
  renderer.copyChecked = false
  glBindTexture(GL_TEXTURE_2D, renderer.copyTexture)
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.GLint, size.x, size.y, 0,
    GL_RGBA, GL_UNSIGNED_BYTE, nil)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE.GLint)
  glBindFramebuffer(GL_FRAMEBUFFER, renderer.copyFramebuffer)
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
    renderer.copyTexture, 0)

proc saveState(): SavedState =
  ## Captures every OpenGL binding and setting this pass changes.
  glGetIntegerv(GL_VIEWPORT, result.viewport[0].addr)
  result.depthTest = glIsEnabled(GL_DEPTH_TEST)
  result.cullFace = glIsEnabled(GL_CULL_FACE)
  result.blend = glIsEnabled(GL_BLEND)
  glGetBooleanv(GL_DEPTH_WRITEMASK, result.depthMask.addr)
  glGetIntegerv(GL_BLEND_SRC_RGB, result.blendFuncs[0].addr)
  glGetIntegerv(GL_BLEND_DST_RGB, result.blendFuncs[1].addr)
  glGetIntegerv(GL_BLEND_SRC_ALPHA, result.blendFuncs[2].addr)
  glGetIntegerv(GL_BLEND_DST_ALPHA, result.blendFuncs[3].addr)
  glGetIntegerv(GL_CURRENT_PROGRAM, result.program.addr)
  glGetIntegerv(GL_VERTEX_ARRAY_BINDING, result.vertexArray.addr)
  glGetIntegerv(GL_ARRAY_BUFFER_BINDING, result.arrayBuffer.addr)
  glGetIntegerv(GL_ACTIVE_TEXTURE, result.activeTexture.addr)
  glActiveTexture(GL_TEXTURE0)
  glGetIntegerv(GL_TEXTURE_BINDING_2D, result.texture0.addr)
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, result.readFramebuffer.addr)
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, result.drawFramebuffer.addr)

proc setEnabled(capability: GLenum, enabled: GLboolean) =
  ## Restores a saved capability flag.
  if enabled: glEnable(capability) else: glDisable(capability)

proc restore(state: SavedState) =
  ## Restores the caller's framebuffer, bindings and draw state.
  glViewport(state.viewport[0], state.viewport[1],
    state.viewport[2].GLsizei, state.viewport[3].GLsizei)
  setEnabled(GL_DEPTH_TEST, state.depthTest)
  setEnabled(GL_CULL_FACE, state.cullFace)
  setEnabled(GL_BLEND, state.blend)
  glDepthMask(state.depthMask)
  glBlendFuncSeparate(state.blendFuncs[0].GLenum, state.blendFuncs[1].GLenum,
    state.blendFuncs[2].GLenum, state.blendFuncs[3].GLenum)
  glUseProgram(state.program.GLuint)
  glBindVertexArray(state.vertexArray.GLuint)
  glBindBuffer(GL_ARRAY_BUFFER, state.arrayBuffer.GLuint)
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, state.texture0.GLuint)
  glActiveTexture(state.activeTexture.GLenum)
  glBindFramebuffer(GL_READ_FRAMEBUFFER, state.readFramebuffer.GLuint)
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, state.drawFramebuffer.GLuint)

proc drawDistortions*(
    renderer: var DistortionRenderer,
    distortions: openArray[Distortion],
    viewMatrix: Mat4,
    eye, right, up: Vec3,
    size: IVec2,
    clock: float32,
    source: GLuint = 0
) =
  ## Bends what the `source` framebuffer (the window by default) shows under
  ## each distortion. `size` is its size in pixels, `right` and `up` the
  ## camera's axes, and `clock` seconds for the heat ripples. Leaves GL state
  ## as it found it.
  if distortions.len == 0 or renderer.unavailable or size.x <= 0 or size.y <= 0:
    return
  let saved = saveState()
  defer: saved.restore()
  if not renderer.ready: renderer.setup()
  renderer.ensureSize(size)
  # Copy the finished scene, resolving multisampling, to sample it shifted.
  if not renderer.copyChecked:
    while glGetError() != GL_NO_ERROR: discard
  glBindFramebuffer(GL_READ_FRAMEBUFFER, source)
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, renderer.copyFramebuffer)
  glBlitFramebuffer(0, 0, size.x, size.y, 0, 0, size.x, size.y,
    GL_COLOR_BUFFER_BIT, GL_NEAREST.GLenum)
  if not renderer.copyChecked:
    renderer.copyChecked = true
    let error = glGetError()
    if error != GL_NO_ERROR:
      renderer.unavailable = true
      echo "Distortion is off: the window's colors can't be copied (GL error 0x",
        toHex(error.int, 4), ")"
      return
  buildDistortionVertices(renderer.floats, distortions, viewMatrix,
    eye, right, up, size)
  if renderer.floats.len == 0: return
  glBindFramebuffer(GL_FRAMEBUFFER, source)
  glViewport(0, 0, size.x, size.y)
  glEnable(GL_DEPTH_TEST)
  glDepthMask(GL_FALSE)
  glDisable(GL_CULL_FACE)
  glEnable(GL_BLEND)
  glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ZERO, GL_ONE)
  glUseProgram(renderer.program)
  var matrix = viewMatrix
  glUniformMatrix4fv(renderer.viewMatrix, 1, GL_FALSE, cast[ptr float32](matrix.addr))
  glUniform2f(renderer.viewportSize, size.x.float32, size.y.float32)
  glUniform1f(renderer.clock, clock)
  glUniform2f(renderer.shiftScale, 1, 1)
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, renderer.copyTexture)
  glUniform1i(renderer.sceneSampler, 0)
  glBindVertexArray(renderer.vertexArray)
  glBindBuffer(GL_ARRAY_BUFFER, renderer.vertexBuffer)
  glBufferData(GL_ARRAY_BUFFER, renderer.floats.len * sizeof(float32),
    renderer.floats[0].addr, GL_STREAM_DRAW)
  glDrawArrays(GL_TRIANGLES, 0, GLsizei(renderer.floats.len div VertexFloats))

proc close*(renderer: var DistortionRenderer) =
  ## Releases the program, buffers and scene copy.
  if renderer.ready:
    glDeleteProgram(renderer.program)
    glDeleteVertexArrays(1, renderer.vertexArray.addr)
    glDeleteBuffers(1, renderer.vertexBuffer.addr)
    glDeleteFramebuffers(1, renderer.copyFramebuffer.addr)
    glDeleteTextures(1, renderer.copyTexture.addr)
  renderer = DistortionRenderer()
