## OpenGL rendering of CaC material sprites and particles.

import
  std/[math, os],
  opengl, pixie, shady, vmath,
  ../../../core/core, ../../[vfxdata, vfxshaders]

export vfxdata

type
  VfxRenderer* = object
    program, vertexArray, vertexBuffer: GLuint
    lightningTexture, oozeTexture, oozeDropletTexture: GLuint
    lightningAspect: float32
    vertices, materialVertices: seq[float32]

proc compileStage(kind: GLenum, source: string): GLuint =
  result = glCreateShader(kind)
  let sources = allocCStringArray([source])
  defer: deallocCStringArray(sources)
  glShaderSource(result, 1, sources, nil)
  glCompileShader(result)
  var status: GLint
  glGetShaderiv(result, GL_COMPILE_STATUS, status.addr)
  if status == 0:
    var length: GLint
    glGetShaderiv(result, GL_INFO_LOG_LENGTH, length.addr)
    var log = newString(length)
    glGetShaderInfoLog(result, length, nil, log.cstring)
    raise newException(CatchableError, "VFX shader failed: " & log)

proc initVfxRenderer*(textureRoot: string): VfxRenderer =
  const target = when defined(emscripten): glsl3WebGL else: glsl4Desktop
  let
    vertex = compileStage(GL_VERTEX_SHADER,
      toShader(vfxVertex, target, shaderVertex))
    fragment = compileStage(GL_FRAGMENT_SHADER,
      toShader(vfxFragment, target, shaderFragment))
  result.program = glCreateProgram()
  glAttachShader(result.program, vertex)
  glAttachShader(result.program, fragment)
  glLinkProgram(result.program)
  glDeleteShader(vertex)
  glDeleteShader(fragment)
  var status: GLint
  glGetProgramiv(result.program, GL_LINK_STATUS, status.addr)
  if status == 0:
    var length: GLint
    glGetProgramiv(result.program, GL_INFO_LOG_LENGTH, length.addr)
    var log = newString(length)
    glGetProgramInfoLog(result.program, length, nil, log.cstring)
    raise newException(CatchableError, "VFX shader link failed: " & log)
  glGenVertexArrays(1, result.vertexArray.addr)
  glBindVertexArray(result.vertexArray)
  glGenBuffers(1, result.vertexBuffer.addr)
  glBindBuffer(GL_ARRAY_BUFFER, result.vertexBuffer)
  for attribute in [
    (name: "position", count: 3, offset: 0),
    (name: "uv", count: 2, offset: 3),
    (name: "ink", count: 4, offset: 5),
    (name: "style", count: 1, offset: 9),
    (name: "dimensions", count: 2, offset: 10)
  ]:
    let location = glGetAttribLocation(result.program, attribute.name.cstring)
    doAssert location >= 0
    glEnableVertexAttribArray(location.GLuint)
    glVertexAttribPointer(location.GLuint, attribute.count.GLint, cGL_FLOAT,
      GL_FALSE, (12 * sizeof(float32)).GLsizei,
      cast[pointer](attribute.offset * sizeof(float32)))
  glBindVertexArray(0)

  proc loadTexture(name: string, handle: var GLuint): Image =
    result = readImage(textureRoot / name)
    glGenTextures(1, handle.addr)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, handle)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE.GLint)
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA.GLint, result.width.GLsizei,
      result.height.GLsizei, 0, GL_RGBA, GL_UNSIGNED_BYTE, result.data[0].addr)
    glGenerateMipmap(GL_TEXTURE_2D)
  let lightning = loadTexture("lightning-strike.png", result.lightningTexture)
  result.lightningAspect = lightning.width.float32 / lightning.height.float32
  discard loadTexture("ooze-splat.png", result.oozeTexture)
  discard loadTexture("ooze-droplet.png", result.oozeDropletTexture)

include ../../vfxgeometry

proc draw*(renderer: var VfxRenderer, viewProjection: Mat4,
    additive = true, depthTest = true) =
  if renderer.vertices.len == 0 and renderer.materialVertices.len == 0: return
  glBindBuffer(GL_ARRAY_BUFFER, renderer.vertexBuffer)
  if depthTest: glEnable(GL_DEPTH_TEST)
  else: glDisable(GL_DEPTH_TEST)
  glDepthMask(GL_FALSE)
  glDisable(GL_CULL_FACE)
  glEnable(GL_BLEND)
  glUseProgram(renderer.program)
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, renderer.lightningTexture)
  glUniform1i(glGetUniformLocation(renderer.program, "vfxLightningSampler"), 0)
  var previousOozeUnit, previousDropletUnit: GLint
  glActiveTexture(GL_TEXTURE1)
  glGetIntegerv(GL_TEXTURE_BINDING_2D, previousOozeUnit.addr)
  glBindTexture(GL_TEXTURE_2D, renderer.oozeTexture)
  glUniform1i(glGetUniformLocation(renderer.program, "vfxOozeSampler"), 1)
  glActiveTexture(GL_TEXTURE2)
  glGetIntegerv(GL_TEXTURE_BINDING_2D, previousDropletUnit.addr)
  glBindTexture(GL_TEXTURE_2D, renderer.oozeDropletTexture)
  glUniform1i(glGetUniformLocation(renderer.program, "vfxOozeDropletSampler"), 2)
  var matrix = viewProjection
  glUniformMatrix4fv(glGetUniformLocation(renderer.program, "vfxViewProjection"),
    1, GL_FALSE, cast[ptr float32](matrix.addr))
  glBindVertexArray(renderer.vertexArray)
  # Steel, leather, and jelly retain their shadows and alpha; light is laid
  # over those surfaces in a second pass, using the existing additive blend.
  if renderer.materialVertices.len > 0:
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
    glBufferData(GL_ARRAY_BUFFER, renderer.materialVertices.len * sizeof(float32),
      renderer.materialVertices[0].addr, GL_DYNAMIC_DRAW)
    glDrawArrays(GL_TRIANGLES, 0, (renderer.materialVertices.len div 12).GLsizei)
  if renderer.vertices.len > 0:
    glBlendFunc(GL_SRC_ALPHA, if additive: GL_ONE else: GL_ONE_MINUS_SRC_ALPHA)
    glBufferData(GL_ARRAY_BUFFER, renderer.vertices.len * sizeof(float32),
      renderer.vertices[0].addr, GL_DYNAMIC_DRAW)
    glDrawArrays(GL_TRIANGLES, 0, (renderer.vertices.len div 12).GLsizei)
  glBindVertexArray(0)
  # The scene keeps its shadow maps on these units between frames.
  glActiveTexture(GL_TEXTURE1)
  glBindTexture(GL_TEXTURE_2D, previousOozeUnit.GLuint)
  glActiveTexture(GL_TEXTURE2)
  glBindTexture(GL_TEXTURE_2D, previousDropletUnit.GLuint)
  glActiveTexture(GL_TEXTURE0)
  glDepthMask(GL_TRUE)

proc drawCharacterFlash*(renderer: var VfxRenderer, stencilRef: int,
    strength: float32) =
  ## Stencil retains the visible character silhouette, including skinning and
  ## cutout materials. A red overlay stays bright even on blue/dark clothing.
  if strength <= 0: return
  var savedVertices = move(renderer.vertices)
  var savedMaterials = move(renderer.materialVertices)
  renderer.addQuad([vec3(-1, 1, 0), vec3(-1, -1, 0),
    vec3(1, -1, 0), vec3(1, 1, 0)],
    [vec2(0), vec2(0), vec2(0), vec2(0)],
    vec4(1, 0.025, 0.045, strength * 0.88'f), 0)
  glEnable(GL_STENCIL_TEST)
  glStencilMask(0)
  glStencilFunc(GL_EQUAL, stencilRef.GLint, 0xff)
  glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP)
  renderer.draw(mat4(), additive = false, depthTest = false)
  glDisable(GL_STENCIL_TEST)
  glStencilMask(0xff)
  renderer.vertices = move(savedVertices)
  renderer.materialVertices = move(savedMaterials)

proc dispose*(renderer: var VfxRenderer) =
  ## Releases the effect pipeline, sprite textures, and upload buffer.
  glDeleteProgram(renderer.program)
  glDeleteVertexArrays(1, renderer.vertexArray.addr)
  glDeleteBuffers(1, renderer.vertexBuffer.addr)
  glDeleteTextures(1, renderer.lightningTexture.addr)
  glDeleteTextures(1, renderer.oozeTexture.addr)
  glDeleteTextures(1, renderer.oozeDropletTexture.addr)
  renderer = VfxRenderer()
