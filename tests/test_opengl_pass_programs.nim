import
  std/tables,
  opengl, pixie, shady, vmath, windy,
  polyworld/backends/opengl/[passprograms, passresources],
  polyworld/shadermetadata

const ShaderTarget =
  when defined(emscripten): glsl3WebGL
  else: glsl4Desktop

var
  tint: Uniform[Vec4]
  tex: Uniform[Sampler2D]
  transform: Uniform[Mat4]
  palette: Uniform[array[2, Vec4]]
  bones: Uniform[array[4, Mat4]]

proc vertex(position: Vec2, uv: var Vec2, gl_Position: var Vec4) =
  ## Transforms the indexed triangle and supplies its texture coordinates.
  uv = position * 0.5'f + 0.5'f
  gl_Position = transform * vec4(position.x, position.y, 0.0'f, 1.0'f)

proc fragment(uv: Vec2, fragColor: var Vec4) =
  ## Makes both active matrix-array elements observable in the output.
  let
    first = bones[0] * vec4(1)
    second = bones[1] * vec4(1)
  fragColor = texture(tex, uv) * tint *
    vec4(first.x, second.y, palette[1].z, 1.0'f)

proc matrix(value: float32): Mat4 =
  ## Creates an exactly representable diagonal matrix for uniform probes.
  result = mat4()
  for i in 0 ..< 4:
    result[i, i] = value

proc assertBones(program: ShaderProgram, first, second: Mat4) =
  ## Checks the driver's actual array values after staged writes are drawn.
  for i, expected in [first, second]:
    var actual: Mat4
    let location = glGetUniformLocation(program.handle,
      ("bones[" & $i & "]").cstring)
    doAssert location >= 0
    glGetUniformfv(program.handle, location, cast[ptr GLfloat](actual.addr))
    doAssert actual == expected, "Unexpected bone " & $i

proc assertPixel(expected: array[4, uint8]) =
  ## Checks the rendered color with one unit of framebuffer rounding slack.
  var actual: array[4, uint8]
  glReadPixels(8, 8, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, actual[0].addr)
  for i in 0 ..< 4:
    doAssert abs(actual[i].int - expected[i].int) <= 1, $actual

proc main() =
  ## Runs an offscreen fixture without showing or activating a window.
  let window = newWindow("Pass program probe", ivec2(16, 16),
    visible = false, vsync = false, msaa = msaaDisabled)
  defer: window.close()
  window.makeContextCurrent()
  loadExtensions()
  let image = newImage(1, 1)
  image.data[0] = rgbx(255, 255, 255, 255)
  let texture = newTexture(image, linear = false)
  defer: texture.destroy()
  let program = newProgram(toShader(vertex, ShaderTarget, shaderVertex),
    toShader(fragment, ShaderTarget, shaderFragment), VertexLayout(
    stride: sizeof(Vec2), attributes: @[
      VertexAttribute(name: "position", format: Float2, offset: 0)]))
  defer: program.destroy()
  let vertices = newBuffer([vec2(-1, -1), vec2(3, -1), vec2(-1, 3)])
  defer: vertices.destroy()
  var callerVao: GLuint
  glGenVertexArrays(1, callerVao.addr)
  defer: glDeleteVertexArrays(1, callerVao.addr)
  glBindVertexArray(callerVao)
  let callerIndices = newIndexBuffer([0'u32, 1, 2])
  defer: callerIndices.destroy()
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, callerIndices.handle)
  glBindBuffer(GL_COPY_WRITE_BUFFER, vertices.handle)
  let indices = newIndexBuffer([0'u16, 1, 2])
  defer: indices.destroy()
  indices.updateBuffer([0'u16, 1, 2])
  for (binding, expected) in [
    (GL_VERTEX_ARRAY_BINDING, callerVao),
    (GL_ELEMENT_ARRAY_BUFFER_BINDING, callerIndices.handle),
    (GL_COPY_WRITE_BUFFER_BINDING, vertices.handle)
  ]:
    var actual: GLint
    glGetIntegerv(binding, actual.addr)
    doAssert actual.GLuint == expected
  doAssert indices.target == GL_ELEMENT_ARRAY_BUFFER
  doAssert vertices.target == GL_ARRAY_BUFFER
  let
    paletteField = program.reflection.fieldIndex("palette")
    bonesField = program.reflection.fieldIndex("bones")
  doAssert paletteField >= 0 and bonesField >= 0
  doAssert program.reflection.fields[paletteField].kind == "float4"
  doAssert program.reflection.fields[paletteField].count == 2
  doAssert program.reflection.fields[paletteField].offset == -1
  doAssert program.reflection.fields[bonesField].kind == "float4x4"
  doAssert program.reflection.fields[bonesField].count >= 2
  doAssert program.fieldLocations[paletteField] >= 0
  doAssert program.reflection.textures[0].name == "tex"
  doAssert program.reflection.inputs[0].name == "position"
  var framebuffer, target: GLuint
  glGenFramebuffers(1, framebuffer.addr)
  defer: glDeleteFramebuffers(1, framebuffer.addr)
  glGenTextures(1, target.addr)
  defer: glDeleteTextures(1, target.addr)
  glBindTexture(GL_TEXTURE_2D, target)
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.GLint, 16, 16, 0,
    GL_RGBA, GL_UNSIGNED_BYTE, nil)
  glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
    GL_TEXTURE_2D, target, 0)
  doAssert glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE
  glViewport(0, 0, 16, 16)
  glEnable(GL_BLEND)
  glBlendFunc(GL_ZERO, GL_ONE)
  glDepthMask(false)
  glUseProgram(0)
  program.setUniform("transform", mat4())
  program.setUniform("tint", vec4(1))
  program.setUniform("palette[0]", [vec4(1), vec4(1)])
  program.bindTexture("tex", texture)
  program.setUniform("bones[1]", matrix(0.25))
  var current: GLint
  glGetIntegerv(GL_CURRENT_PROGRAM, current.addr)
  doAssert current == 0
  draw(program, vertices, 3, DrawState(), indices, index32 = false)
  program.assertBones(matrix(0), matrix(0.25))
  assertPixel([0'u8, 64, 255, 255])
  glGetIntegerv(GL_CURRENT_PROGRAM, current.addr)
  doAssert current == 0 and glIsEnabled(GL_BLEND)
  glGetIntegerv(GL_BLEND_SRC_RGB, current.addr)
  doAssert current.GLenum == GL_ZERO

  program.setUniform("bones", [matrix(0.25), matrix(0.25), mat4(), mat4()])
  program.setUniform("bones[1]", matrix(0.75))
  draw(program, vertices, 3, DrawState(), indices, index32 = false)
  program.assertBones(matrix(0.25), matrix(0.75))
  assertPixel([64'u8, 191, 255, 255])

  program.setUniform("bones[1]", matrix(0.75))
  program.setUniform("bones", [matrix(0.5), matrix(0.25), mat4(), mat4()])
  draw(program, vertices, 3, DrawState(), indices, index32 = false)
  program.assertBones(matrix(0.5), matrix(0.25))
  assertPixel([128'u8, 64, 255, 255])

  program.setUniform("bones", [matrix(0.25), matrix(0.25), mat4(), mat4()])
  program.setUniform("bones[1]", matrix(0.75))
  program.setUniform("bones[0]", matrix(0.5))
  draw(program, vertices, 3, DrawState(), indices, index32 = false)
  program.assertBones(matrix(0.5), matrix(0.75))
  assertPixel([128'u8, 191, 255, 255])
  indices.updateBuffer([0'u32, 1, 2])
  draw(program, vertices, 3, DrawState(), indices, index32 = true)
  assertPixel([128'u8, 191, 255, 255])
  doAssert program.values[program.fieldLocations[bonesField]].count == 4
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, target)
  glActiveTexture(GL_TEXTURE1)
  glBindVertexArray(callerVao)
  beginSceneDraws()
  preserveDrawState:
    draw(program, vertices, 3, indices = indices)
    program.setUniform("bones[1]", matrix(0.25))
    draw(program, vertices, 3, indices = indices)
  endSceneDraws()
  assertPixel([128'u8, 64, 255, 255])
  var binding: GLint
  glGetIntegerv(GL_VERTEX_ARRAY_BINDING, binding.addr)
  doAssert binding.GLuint == callerVao
  glGetIntegerv(GL_ACTIVE_TEXTURE, binding.addr)
  doAssert binding.GLenum == GL_TEXTURE1
  glActiveTexture(GL_TEXTURE0)
  glGetIntegerv(GL_TEXTURE_BINDING_2D, binding.addr)
  doAssert binding.GLuint == target

  glEnable(GL_BLEND)
  beginGameFrameDraws()
  preserveDrawState:
    discard
  endGameFrameDraws()
  doAssert glIsEnabled(GL_BLEND)

  # A game pass consumes its node state even after foreign code changes GL.
  # The same node must be reapplied on the far side of a UI handoff.
  let marked = DrawState(depthTest: true, depthWrite: true, cull: CullBack,
    blend: Additive, stencilWrite: true, stencilCompare: Always, stencilReference: 3)
  beginGameFrameDraws()
  for batch in 0..1:
    glFrontFace(GL_CW)
    glDisable(GL_DEPTH_TEST)
    glDisable(GL_STENCIL_TEST)
    glDepthMask(GL_FALSE)
    glStencilMask(0)
    preserveDrawState:
      draw(program, vertices, 3, marked, indices)
      doAssert glIsEnabled(GL_DEPTH_TEST) and glIsEnabled(GL_STENCIL_TEST)
      glGetIntegerv(GL_STENCIL_WRITEMASK, binding.addr)
      doAssert binding == 0xff
      glGetIntegerv(GL_FRONT_FACE, binding.addr)
      doAssert binding.GLenum == GL_CCW
      var next = marked
      next.depthWrite = false
      next.stencilWrite = false
      next.blend = PremultipliedAlpha
      draw(program, vertices, 3, next, indices)
      doAssert glIsEnabled(GL_DEPTH_TEST) and not glIsEnabled(GL_STENCIL_TEST)
      withClearWriteMasks(true, true):
        glGetIntegerv(GL_DEPTH_WRITEMASK, binding.addr)
        doAssert binding == 1
      glGetIntegerv(GL_DEPTH_WRITEMASK, binding.addr)
      doAssert binding == 0
      glGetIntegerv(GL_STENCIL_WRITEMASK, binding.addr)
      doAssert binding == 0
      glGetIntegerv(GL_BLEND_DST_RGB, binding.addr)
      doAssert binding.GLenum == GL_ONE_MINUS_SRC_ALPHA
    endSceneDraws()
    doAssert not glIsEnabled(GL_DEPTH_TEST) and not glIsEnabled(GL_CULL_FACE)
    doAssert not glIsEnabled(GL_BLEND) and not glIsEnabled(GL_STENCIL_TEST)
    glGetIntegerv(GL_VERTEX_ARRAY_BINDING, binding.addr)
    doAssert binding.GLuint == callerVao
  endGameFrameDraws()
  glDepthMask(GL_FALSE)
  glStencilMaskSeparate(GL_FRONT, 0x34)
  glStencilMaskSeparate(GL_BACK, 0x56)
  draw(program, vertices, 3, marked, indices)
  for (field, expected) in [(GL_DEPTH_WRITEMASK, 0.GLint),
      (GL_STENCIL_WRITEMASK, 0x34.GLint), (GL_STENCIL_BACK_WRITEMASK, 0x56.GLint)]:
    glGetIntegerv(field, binding.addr)
    doAssert binding == expected
  doAssert glGetError() == GL_NO_ERROR
  echo "PASS shared OpenGL uniforms, array writes, texture and draw state"

main()
