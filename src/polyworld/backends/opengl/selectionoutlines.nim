## OpenGL selection masks and outline compositing.

import
  opengl, shady, vmath,
  ../shaders/selectionoutlines

export selectionoutlines

const ShaderTarget =
  when defined(emscripten): glsl3WebGL
  else: glsl4Desktop

type
  SelectionOutline* = object
    framebuffer: GLuint
    destinationFramebuffer: GLint
    colorTexture: GLuint
    depthTexture: GLuint
    program: GLuint
    vertexArray: GLuint
    vertexBuffer: GLuint
    size: IVec2
    visibility: OutlineVisibility

proc compileShaderStage(
    kind: GLenum,
    source,
    label: string
): GLuint =
  ## Compiles one selection shader stage with a useful diagnostic.
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
      SelectionOutlineError,
      label & " shader failed:\n" & log & "\n" & source
    )

proc compileProgram(visibility: OutlineVisibility): GLuint =
  ## Compiles and links the shared selection edge shader program.
  let
    fragmentSource =
      if visibility == OccludedOutline:
        toShader(occlusionFragment, ShaderTarget, shaderFragment)
      else:
        toShader(selectionFragment, ShaderTarget, shaderFragment)
    vertexShader = compileShaderStage(
      GL_VERTEX_SHADER,
      toShader(selectionVertex, ShaderTarget, shaderVertex),
      "selection vertex"
    )
    fragmentShader = compileShaderStage(
      GL_FRAGMENT_SHADER,
      fragmentSource,
      "selection fragment"
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
      SelectionOutlineError,
      "selection program failed:\n" & log
    )

proc initSelectionOutline*(
    visibility = AlwaysOutline
): SelectionOutline =
  ## Creates the selection edge shader and full-screen triangle.
  result.visibility = visibility
  result.program = compileProgram(visibility)
  let vertices = [
    -1.0'f, -1.0'f,
    3.0'f, -1.0'f,
    -1.0'f, 3.0'f
  ]
  glGenVertexArrays(1, result.vertexArray.addr)
  glBindVertexArray(result.vertexArray)
  glGenBuffers(1, result.vertexBuffer.addr)
  glBindBuffer(GL_ARRAY_BUFFER, result.vertexBuffer)
  glBufferData(
    GL_ARRAY_BUFFER,
    sizeof(vertices),
    unsafeAddr vertices[0],
    GL_STATIC_DRAW
  )
  let location = glGetAttribLocation(result.program, "vertexPosition")
  doAssert location >= 0
  glEnableVertexAttribArray(location.GLuint)
  glVertexAttribPointer(
    location.GLuint,
    2,
    cGL_FLOAT,
    GL_FALSE,
    (2 * sizeof(float32)).GLsizei,
    nil
  )
  glBindVertexArray(0)
  glGenFramebuffers(1, result.framebuffer.addr)
  glGenTextures(1, result.colorTexture.addr)
  glGenTextures(1, result.depthTexture.addr)

proc ensureSize(outline: var SelectionOutline, size: IVec2) =
  ## Resizes the silhouette framebuffer to match the current window.
  let safeSize = ivec2(max(size.x, 1), max(size.y, 1))
  if outline.size == safeSize:
    return
  outline.size = safeSize
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, outline.colorTexture)
  glTexImage2D(
    GL_TEXTURE_2D,
    0,
    GL_RGBA8.GLint,
    safeSize.x,
    safeSize.y,
    0,
    GL_RGBA,
    GL_UNSIGNED_BYTE,
    nil
  )
  glTexParameteri(
    GL_TEXTURE_2D,
    GL_TEXTURE_MIN_FILTER,
    GL_NEAREST.GLint
  )
  glTexParameteri(
    GL_TEXTURE_2D,
    GL_TEXTURE_MAG_FILTER,
    GL_NEAREST.GLint
  )
  glTexParameteri(
    GL_TEXTURE_2D,
    GL_TEXTURE_WRAP_S,
    GL_CLAMP_TO_EDGE.GLint
  )
  glTexParameteri(
    GL_TEXTURE_2D,
    GL_TEXTURE_WRAP_T,
    GL_CLAMP_TO_EDGE.GLint
  )
  glBindTexture(GL_TEXTURE_2D, outline.depthTexture)
  glTexImage2D(
    GL_TEXTURE_2D,
    0,
    GL_DEPTH_COMPONENT24.GLint,
    safeSize.x,
    safeSize.y,
    0,
    GL_DEPTH_COMPONENT,
    GL_UNSIGNED_INT,
    nil
  )
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE.GLint)
  glBindFramebuffer(GL_FRAMEBUFFER, outline.framebuffer)
  glFramebufferTexture2D(
    GL_FRAMEBUFFER,
    GL_COLOR_ATTACHMENT0,
    GL_TEXTURE_2D,
    outline.colorTexture,
    0
  )
  glFramebufferTexture2D(
    GL_FRAMEBUFFER,
    GL_DEPTH_ATTACHMENT,
    GL_TEXTURE_2D,
    outline.depthTexture,
    0
  )
  doAssert glCheckFramebufferStatus(GL_FRAMEBUFFER) ==
    GL_FRAMEBUFFER_COMPLETE
  glBindFramebuffer(GL_FRAMEBUFFER, 0)
  glBindTexture(GL_TEXTURE_2D, 0)

proc beginMask*(outline: var SelectionOutline, size: IVec2) =
  ## Clears and binds the selected-object silhouette target.
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, outline.destinationFramebuffer.addr)
  outline.ensureSize(size)
  glBindFramebuffer(GL_FRAMEBUFFER, outline.framebuffer)
  glViewport(0, 0, outline.size.x, outline.size.y)
  glDepthMask(GL_TRUE)
  glDisable(GL_BLEND)
  glEnable(GL_DEPTH_TEST)
  glDepthFunc(GL_LEQUAL)
  glClearColor(0, 0, 0, 0)
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)

proc drawOutline*(
    outline: SelectionOutline,
    color = SelectionOutlineColor
) =
  ## Draws silhouette edges into the scene target that preceded the mask.
  glBindFramebuffer(GL_FRAMEBUFFER, outline.destinationFramebuffer.GLuint)
  glViewport(0, 0, outline.size.x, outline.size.y)
  glDepthMask(GL_FALSE)
  if outline.visibility == OccludedOutline:
    glEnable(GL_DEPTH_TEST)
    glDepthFunc(GL_GREATER)
  else:
    glDisable(GL_DEPTH_TEST)
  glDisable(GL_CULL_FACE)
  glEnable(GL_BLEND)
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  glUseProgram(outline.program)
  glUniform2f(
    glGetUniformLocation(outline.program, "selectionYTransform"), 1, 0
  )
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, outline.colorTexture)
  glUniform1i(
    glGetUniformLocation(outline.program, "selectionTexture"),
    0
  )
  if outline.visibility == OccludedOutline:
    glActiveTexture(GL_TEXTURE1)
    glBindTexture(GL_TEXTURE_2D, outline.depthTexture)
    glUniform1i(
      glGetUniformLocation(outline.program, "selectionDepth"),
      1
    )
  glUniform2f(
    glGetUniformLocation(outline.program, "selectionResolution"),
    outline.size.x.float32,
    outline.size.y.float32
  )
  glUniform3f(
    glGetUniformLocation(outline.program, "selectionColor"),
    color.x,
    color.y,
    color.z
  )
  glBindVertexArray(outline.vertexArray)
  glDrawArrays(GL_TRIANGLES, 0, 3)
  glBindVertexArray(0)
  glUseProgram(0)
  glDisable(GL_BLEND)
  glDepthFunc(GL_LEQUAL)
  glDepthMask(GL_TRUE)
  glActiveTexture(GL_TEXTURE0)

proc closeSelectionOutline*(outline: var SelectionOutline) =
  ## Releases the outline's shader, mesh, and framebuffer attachments.
  glDeleteTextures(1, outline.colorTexture.addr)
  glDeleteTextures(1, outline.depthTexture.addr)
  glDeleteFramebuffers(1, outline.framebuffer.addr)
  glDeleteBuffers(1, outline.vertexBuffer.addr)
  glDeleteVertexArrays(1, outline.vertexArray.addr)
  glDeleteProgram(outline.program)
  outline = SelectionOutline()
