import
  opengl, pixie, shady, vmath, windy,
  polyworld/backends/opengl/renderer,
  fixtures/renderconformance

proc compileStage(kind: GLenum, source: string): GLuint =
  ## Compiles a conformance shader and reports the native compiler diagnostic.
  result = glCreateShader(kind)
  let sources = allocCStringArray([source])
  defer: deallocCStringArray(sources)
  glShaderSource(result, 1, sources, nil)
  glCompileShader(result)
  var status, length: GLint
  glGetShaderiv(result, GL_COMPILE_STATUS, status.addr)
  if status == 0:
    glGetShaderiv(result, GL_INFO_LOG_LENGTH, length.addr)
    var message = newString(length)
    glGetShaderInfoLog(result, length, nil, message.cstring)
    glDeleteShader(result)
    raise newException(ValueError, "Conformance shader failed: " & message)

proc newProgram(fragmentSource: string): GLuint =
  ## Links the shared vertex fixture to one authored fragment shader.
  let
    vert = compileStage(
      GL_VERTEX_SHADER, toShader(vertex, glsl4Desktop, shaderVertex)
    )
    frag = compileStage(GL_FRAGMENT_SHADER, fragmentSource)
  defer:
    glDeleteShader(vert)
    glDeleteShader(frag)
  result = glCreateProgram()
  glAttachShader(result, vert)
  glAttachShader(result, frag)
  glBindAttribLocation(result, 0, "position")
  glLinkProgram(result)
  var status, length: GLint
  glGetProgramiv(result, GL_LINK_STATUS, status.addr)
  if status == 0:
    glGetProgramiv(result, GL_INFO_LOG_LENGTH, length.addr)
    var message = newString(length)
    glGetProgramInfoLog(result, length, nil, message.cstring)
    glDeleteProgram(result)
    raise newException(ValueError, "Conformance link failed: " & message)

proc draw(vertices: openArray[float32], buffer: GLuint) =
  ## Streams the common geometry into the test's single vertex buffer.
  glBindBuffer(GL_ARRAY_BUFFER, buffer)
  glBufferData(
    GL_ARRAY_BUFFER, (vertices.len * sizeof(float32)).GLsizeiptr,
    vertices[0].unsafeAddr, GL_STREAM_DRAW
  )
  glVertexAttribPointer(0, 2, cGL_FLOAT, false, 8, nil)
  glDrawArrays(GL_TRIANGLES, 0, (vertices.len div 2).GLsizei)

proc main() =
  ## Runs the same triangle and ordered-texture fixtures as Metal and native.
  let window = newWindow(
    "OpenGL core conformance", ivec2(FixtureSize), visible = false
  )
  initRenderer(window)
  var target = newFrameTarget(FixtureSize, FixtureSize)
  let
    solid = newProgram(toShader(fragment, glsl4Desktop, shaderFragment))
    sampled = newProgram(
      toShader(textureFragment, glsl4Desktop, shaderFragment)
    )
  var vao, buffer, texture: GLuint
  glGenVertexArrays(1, vao.addr)
  glGenBuffers(1, buffer.addr)
  glGenTextures(1, texture.addr)
  defer:
    glDeleteTextures(1, texture.addr)
    glDeleteBuffers(1, buffer.addr)
    glDeleteVertexArrays(1, vao.addr)
    glDeleteProgram(solid)
    glDeleteProgram(sampled)
    destroyFrameTarget(target)
    shutdownRenderer()
    window.close()
  glBindVertexArray(vao)
  glEnableVertexAttribArray(0)
  pushFrameTarget(target)
  glEnable(GL_DEPTH_TEST)
  glDepthFunc(GL_LEQUAL)
  glUseProgram(solid)
  for tint in [vec4(1, 0, 0, 1), vec4(0, 1, 0, 1)]:
    clearFrame(color(0, 0, 0, 1))
    glUniform4f(glGetUniformLocation(solid, "tint"),
      tint.x, tint.y, tint.z, tint.w)
    draw(TriangleVertices, buffer)
    readFrameImage(FixtureSize, FixtureSize).verifyTriangle(
      rgbx((tint.x * 255).uint8, (tint.y * 255).uint8, 0, 255)
    )
  clearFrame(color(0, 0, 0, 1))
  glDisable(GL_DEPTH_TEST)
  glUseProgram(sampled)
  glUniform1i(glGetUniformLocation(sampled, "sourceTexture"), 0)
  glUniform2f(glGetUniformLocation(sampled, "sampleUv"), 0.5, 0.5)
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, texture)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST.GLint)
  var pixel = [255'u8, 0, 0, 255]
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.GLint, 1, 1, 0,
    GL_RGBA, GL_UNSIGNED_BYTE, pixel[0].addr)
  draw(LeftVertices, buffer)
  pixel = [0'u8, 255, 0, 255]
  glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 1, 1,
    GL_RGBA, GL_UNSIGNED_BYTE, pixel[0].addr)
  draw(RightVertices, buffer)
  readFrameImage(FixtureSize, FixtureSize).verifySplit(
    rgbx(255, 0, 0, 255), rgbx(0, 255, 0, 255)
  )
  doAssert glGetError() == GL_NO_ERROR
  popFrameTarget()
  echo "OpenGL shared triangle and ordered-texture fixtures passed"

main()
