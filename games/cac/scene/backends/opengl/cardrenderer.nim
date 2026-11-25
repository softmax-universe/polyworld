## Card surfaces: silky draws each face, from source images and fonts in the
## UI atlas (silkyfaces.nim), into a texture of its own the first time that
## face is needed. The table draws a card as one quad on its face's texture;
## the HUD shows the same texture. Card backs and badges come from the atlas.

import std/tables
import chroma, opengl, pixie, shady, silky, silky/drawers/ogl, vmath
import ../../../core/core, ../../../ui/[cardfaces, silkyfaces]
import ../../cardshaders
export silkyfaces.FaceState, silkyfaces.addFaceAssets

type
  CardTexture = GLuint
  CardRenderer* = object
    program, vertexArray, vertexBuffer: GLuint
    vertices: seq[float32]
    batches: seq[Batch]

  Batch = object
    ## Consecutive vertices drawn from one texture.
    texture: GLuint
    size: Vec2  ## The texture's size, in texels.
    first, count: int

  FaceTexture = object
    texture: GLuint
    lastFrame: int

  HudFace = object
    texture: GLuint
    origin, size: Vec2
    tint: ColorRGBX

const
  CardBackKey* = "card/back"
  FaceTextureTop = CardFaceHeight.float32 - 0.5'f
  FaceTextureBottom = 0.5'f
  FloatsPerVertex = 9
  FaceTextureBudget = 64
    ## Face textures kept between frames (about 2.7 MB each with mipmaps).
    ## A frame that shows more keeps them all.

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
    raise newException(CatchableError, "Card shader failed: " & log)

proc linkProgram(vertexSource, fragmentSource: string): GLuint =
  let
    vertex = compileStage(GL_VERTEX_SHADER, vertexSource)
    fragment = compileStage(GL_FRAGMENT_SHADER, fragmentSource)
  result = glCreateProgram()
  glAttachShader(result, vertex)
  glAttachShader(result, fragment)
  glLinkProgram(result)
  glDeleteShader(vertex)
  glDeleteShader(fragment)
  var status: GLint
  glGetProgramiv(result, GL_LINK_STATUS, status.addr)
  if status == 0:
    var length: GLint
    glGetProgramiv(result, GL_INFO_LOG_LENGTH, length.addr)
    var log = newString(length)
    glGetProgramInfoLog(result, length, nil, log.cstring)
    raise newException(CatchableError, "Card shader link failed: " & log)

proc bindAttributes(program: GLuint,
    attributes: openArray[(string, int)]) =
  ## Float attributes, packed one after another in each vertex.
  var stride = 0
  for (_, count) in attributes:
    stride += count
  var offset = 0
  for (name, count) in attributes:
    let location = glGetAttribLocation(program, name.cstring)
    doAssert location >= 0
    glEnableVertexAttribArray(location.GLuint)
    glVertexAttribPointer(location.GLuint, count.GLint, cGL_FLOAT, GL_FALSE,
      (stride * sizeof(float32)).GLsizei,
      cast[pointer](offset * sizeof(float32)))
    offset += count

const ShaderTarget = when defined(emscripten): glsl3WebGL else: glsl4Desktop

proc initCardRenderer*(): CardRenderer =
  result.program = linkProgram(
    toShader(cardVertex, ShaderTarget, shaderVertex),
    toShader(cardFragment, ShaderTarget, shaderFragment))
  glGenVertexArrays(1, result.vertexArray.addr)
  glBindVertexArray(result.vertexArray)
  glGenBuffers(1, result.vertexBuffer.addr)
  glBindBuffer(GL_ARRAY_BUFFER, result.vertexBuffer)
  result.program.bindAttributes([("position", 3), ("uv", 2), ("tint", 4)])
  glBindVertexArray(0)

var
  faceTextures: Table[FaceState, FaceTexture]
  faceFramebuffer: GLuint
  frame = 0
  hudFaces: seq[HudFace]
  hudProgram, hudVertexArray, hudVertexBuffer: GLuint

proc newFaceTexture(): GLuint =
  glGenTextures(1, result.addr)
  glBindTexture(GL_TEXTURE_2D, result)
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.GLint, CardFaceWidth.GLsizei,
    CardFaceHeight.GLsizei, 0, GL_RGBA, GL_UNSIGNED_BYTE, nil)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER,
    GL_LINEAR_MIPMAP_LINEAR.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE.GLint)
  glGenerateMipmap(GL_TEXTURE_2D)

proc renderFace(sk: Silky, state: FaceState, texture: GLuint) =
  ## Silky draws the face into `texture`, between the quads it has queued
  ## for the HUD, which are set aside meanwhile. Needs silky's UI frame.
  var
    framebuffer: GLint
    viewport: array[4, GLint]
    clearColor: array[4, GLfloat]
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, framebuffer.addr)
  glGetIntegerv(GL_VIEWPORT, viewport[0].addr)
  glGetFloatv(GL_COLOR_CLEAR_VALUE, clearColor[0].addr)
  let blend = glIsEnabled(GL_BLEND)
  defer:
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer.GLuint)
    glViewport(viewport[0], viewport[1], viewport[2], viewport[3])
    glClearColor(clearColor[0], clearColor[1], clearColor[2], clearColor[3])
    if blend: glEnable(GL_BLEND) else: glDisable(GL_BLEND)
  sk.isolatedDrawing(rect(0, 0, CardFaceWidth.float32,
      CardFaceHeight.float32)):
    sk.paintFace(state, vec2(0, 0))
    if faceFramebuffer == 0:
      glGenFramebuffers(1, faceFramebuffer.addr)
    glBindFramebuffer(GL_FRAMEBUFFER, faceFramebuffer)
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
      texture, 0)
    glViewport(0, 0, CardFaceWidth.GLsizei, CardFaceHeight.GLsizei)
    glClearColor(0, 0, 0, 0)
    glClear(GL_COLOR_BUFFER_BIT)
    let vertices = sk.drawer.layers[0]
    if vertices.len > 0:
      sk.drawer.endFrame(sk.image, vec2(CardFaceWidth.float32,
        CardFaceHeight.float32), vertices[0].unsafeAddr, vertices.len)
    glBindTexture(GL_TEXTURE_2D, texture)
    glGenerateMipmap(GL_TEXTURE_2D)

proc atlasTexture(sk: Silky): CardTexture =
  ## Borrows the atlas used by the current Silky drawer.
  sk.atlasTextureId()

include ../../cardgeometry

proc draw*(renderer: var CardRenderer, sk: Silky, viewProjection: Mat4) =
  if renderer.vertices.len == 0: return
  glBindBuffer(GL_ARRAY_BUFFER, renderer.vertexBuffer)
  glBufferData(GL_ARRAY_BUFFER, renderer.vertices.len * sizeof(float32),
    renderer.vertices[0].addr, GL_DYNAMIC_DRAW)
  glEnable(GL_DEPTH_TEST)
  glDepthMask(GL_TRUE)
  glDisable(GL_CULL_FACE)
  glEnable(GL_BLEND)
  glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA)
  glUseProgram(renderer.program)
  glActiveTexture(GL_TEXTURE0)
  cardViewProjection = viewProjection
  glUniformMatrix4fv(glGetUniformLocation(renderer.program, "cardViewProjection"),
    1, GL_FALSE, cast[ptr float32](cardViewProjection.addr))
  glUniform1i(glGetUniformLocation(renderer.program, "cardAtlasSampler"), 0)
  let sizeLocation = glGetUniformLocation(renderer.program, "cardAtlasSize")
  glBindVertexArray(renderer.vertexArray)
  for batch in renderer.batches:
    glBindTexture(GL_TEXTURE_2D, batch.texture)
    glUniform2f(sizeLocation, batch.size.x, batch.size.y)
    glDrawArrays(GL_TRIANGLES, batch.first.GLint, batch.count.GLsizei)
  glBindVertexArray(0)

proc drawHudFaces*(sk: Silky) =
  ## Draws the faces the HUD asked for this frame, over what silky drew.
  ## Call after `endUi`.
  if hudFaces.len == 0:
    return
  if hudProgram == 0:
    hudProgram = linkProgram(
      toShader(hudVertex, ShaderTarget, shaderVertex),
      toShader(hudFragment, ShaderTarget, shaderFragment))
    glGenVertexArrays(1, hudVertexArray.addr)
    glBindVertexArray(hudVertexArray)
    glGenBuffers(1, hudVertexBuffer.addr)
    glBindBuffer(GL_ARRAY_BUFFER, hudVertexBuffer)
    hudProgram.bindAttributes([("position", 2), ("uv", 2)])
    glBindVertexArray(0)
  let scale = sk.uiScale
  glViewport(0, 0, sk.framebufferSize.x, sk.framebufferSize.y)
  glDisable(GL_DEPTH_TEST)
  glEnable(GL_BLEND)
  glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA)
  glUseProgram(hudProgram)
  glUniform2f(glGetUniformLocation(hudProgram, "hudViewportSize"),
    sk.framebufferSize.x.float32, sk.framebufferSize.y.float32)
  glUniform1i(glGetUniformLocation(hudProgram, "hudSampler"), 0)
  let tintLocation = glGetUniformLocation(hudProgram, "hudTint")
  glActiveTexture(GL_TEXTURE0)
  glBindVertexArray(hudVertexArray)
  glBindBuffer(GL_ARRAY_BUFFER, hudVertexBuffer)
  for face in hudFaces:
    let
      a = face.origin * scale
      b = (face.origin + face.size) * scale
      # Silky drew the face's top at the texture's last row.
      vertices = [a.x, a.y, 0'f32, 1, a.x, b.y, 0, 0, b.x, b.y, 1, 0,
        a.x, a.y, 0, 1, b.x, b.y, 1, 0, b.x, a.y, 1, 1]
    glBufferData(GL_ARRAY_BUFFER, vertices.len * sizeof(float32),
      vertices[0].unsafeAddr, GL_STREAM_DRAW)
    glUniform4f(tintLocation, face.tint.r.float32 / 255,
      face.tint.g.float32 / 255, face.tint.b.float32 / 255,
      face.tint.a.float32 / 255)
    glBindTexture(GL_TEXTURE_2D, face.texture)
    glDrawArrays(GL_TRIANGLES, 0, 6)
  glBindVertexArray(0)
  glUseProgram(0)
  glDisable(GL_BLEND)
  hudFaces.setLen(0)
