## Screen-space distortion: explosion shockwaves, heat haze and shield bubbles
## that bend what is behind them, like the distortion pass in Recoil (Spring)
## games.
##
## It works on what the window already shows. One blit copies the finished
## scene, multisampled or not, into a texture. Each distortion is then a quad
## facing the camera that re-draws that copy shifted a few pixels:
##
## - `ShockwaveDistortion`: a ring that races from the center to the edge and
##   pushes the picture outward as it passes, fading as it grows.
## - `HeatDistortion`: rippling haze that rises and drifts, fading out.
## - `ShieldDistortion`: a bubble that magnifies the middle and bends hard at
##   its rim.
##
## Call `drawDistortions` after the world and its particles and before the HUD.
## Quads are depth tested without writing depth, pulled toward the camera by
## their radius, so hills and walls hide distortions behind them.

import
  std/strutils,
  opengl, shady, vmath

type
  DistortionKind* = enum
    ShockwaveDistortion, HeatDistortion, ShieldDistortion

  Distortion* = object
    kind*: DistortionKind
    center*: Vec3     ## World position.
    radius*: float32  ## World units out to the edge of the effect.
    strength*: float32
      ## Peak shift as a share of the effect's radius on screen: 0.05 is gentle.
    age*, life*: float32  ## Seconds; the distortion is gone once age reaches life.
    seed*: float32    ## Varies heat ripples between sources.

  DistortionRenderer* = object
    program, vertexArray, vertexBuffer: GLuint
    copyFramebuffer, copyTexture: GLuint
    size: IVec2
    ready, unavailable, copyChecked: bool
    floats: seq[float32]
    viewMatrix, sceneSampler, viewportSize, clock: GLint

  SavedState = object
    viewport: array[4, GLint]
    depthTest, cullFace, blend: GLboolean
    depthMask: GLboolean
    blendFuncs: array[4, GLint]
    program, vertexArray, activeTexture, texture0: GLint
    readFramebuffer, drawFramebuffer, arrayBuffer: GLint

const
  VertexFloats = 9 ## Position 3, corner 2, kind, progress, shift pixels, seed.
  ShaderTarget =
    when defined(emscripten):
      glsl3WebGL
    else:
      glsl4Desktop

var
  viewMatrix: Uniform[Mat4]
  scene: Uniform[Sampler2d]
  viewportSize: Uniform[Vec2]
  clock: Uniform[float32]

proc distortionVertex(
    position: Vec3,
    corner: Vec2,
    params: Vec4,
    local: var Vec2,
    shape: var Vec4,
    gl_Position: var Vec4
) =
  ## Projects the distortion quad while preserving its local coordinates.
  local = corner
  shape = params
  gl_Position = viewMatrix * vec4(position, 1.0'f)

proc distortionFragment(
    gl_FragCoord: Vec4,
    local: Vec2,
    shape: Vec4,
    color: var Vec4
) =
  ## Samples the finished scene through a shockwave, haze, or shield.
  let d = length(local)
  if d >= 1.0'f:
    discardFragment()
  let
    outward =
      if d > 0.0001'f:
        local / d
      else:
        vec2(0.0'f)
    kind = int(shape.x + 0.5'f)
    progress = clamp(shape.y, 0.0'f, 1.0'f)
    pixels = shape.z
    seed = shape.w
  var
    shift = vec2(0.0'f)
    mask = 0.0'f
  if kind == 0:
    # A ring races outward and pushes the picture away from its center.
    let
      ring = exp(-pow((d - progress) / 0.13'f, 2.0'f))
      fade = 1.0'f - progress
    shift = outward * ring * fade
    mask = clamp(ring * fade * 2.0'f, 0.0'f, 1.0'f)
  elif kind == 1:
    # Rising ripples swell in and then fade, strongest in the middle.
    let
      fade = (1.0'f - d) * (1.0'f - progress) *
        min(1.0'f, progress * 6.0'f)
      p = local * 3.5'f + vec2(seed, seed * 1.7'f)
      rise = clock * 3.0'f
    shift = vec2(
      sin(p.y * 4.0'f - rise + sin(p.x * 3.1'f + seed)),
      cos(p.x * 4.7'f + rise * 0.8'f + p.y * 1.3'f)
    ) * fade * 0.5'f
    mask = clamp(fade * 3.0'f, 0.0'f, 1.0'f)
  else:
    # A bubble magnifies its middle and bends harder at its rim.
    let rim = pow(d, 8.0'f)
    shift = -outward * (d * (1.0'f - d) * 0.6'f + rim * 0.8'f)
    mask = 1.0'f - smoothstep(0.92'f, 1.0'f, d)
  let uv = gl_FragCoord.xy / viewportSize + shift * pixels / viewportSize
  color = vec4(texture(scene, uv).rgb, mask)

proc compileStage(kind: GLenum, source: string): GLuint =
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
    raise newException(ValueError, "Distortion shader failed:\n" & log)

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
    raise newException(ValueError, "Distortion program did not link")
  renderer.viewMatrix = glGetUniformLocation(renderer.program, "viewMatrix")
  renderer.sceneSampler = glGetUniformLocation(renderer.program, "scene")
  renderer.viewportSize = glGetUniformLocation(renderer.program, "viewportSize")
  renderer.clock = glGetUniformLocation(renderer.program, "clock")
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
  if enabled: glEnable(capability) else: glDisable(capability)

proc restore(state: SavedState) =
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

proc age*(distortions: var seq[Distortion], seconds: float32) =
  ## Advances every distortion and drops the finished ones.
  var kept = 0
  for item in distortions.mitems:
    item.age += seconds
    if item.age < item.life:
      distortions[kept] = item
      inc kept
  distortions.setLen(kept)

proc project(point: Vec3, viewMatrix: Mat4, size: IVec2): Vec2 =
  let clip = viewMatrix * vec4(point, 1)
  if clip.w <= 0: return vec2(-1e6)
  vec2((clip.x / clip.w + 1) * 0.5 * size.x.float32, (clip.y / clip.w + 1) * 0.5 * size.y.float32)

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
  # One quad per distortion, pulled toward the camera so the ground does not cut it.
  renderer.floats.setLen(0)
  for item in distortions:
    if item.life <= 0 or item.radius <= 0: continue
    let
      toEye = eye - item.center
      lift = if length(toEye) > 1e-6: normalize(toEye) * min(item.radius, length(toEye) * 0.5) else: vec3(0)
      center = item.center + lift
      onScreen = length(project(item.center + right * item.radius, viewMatrix, size) -
        project(item.center, viewMatrix, size))
      pixels = item.strength * onScreen
      params = [item.kind.ord.float32, item.age / item.life, pixels, item.seed]
      sideways = right * item.radius
      upward = up * item.radius
    for (u, v) in [(-1'f32, -1'f32), (1'f32, -1'f32), (1'f32, 1'f32),
        (-1'f32, -1'f32), (1'f32, 1'f32), (-1'f32, 1'f32)]:
      let at = center + sideways * u + upward * v
      renderer.floats.add [at.x, at.y, at.z, u, v]
      renderer.floats.add params
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
