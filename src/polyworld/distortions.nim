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
  opengl, vmath

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

  VertexSource = """
uniform mat4 viewMatrix;
in vec3 position;
in vec2 corner;
in vec4 params;
out vec2 local;
out vec4 shape;
void main() {
  local = corner;
  shape = params;
  gl_Position = viewMatrix * vec4(position, 1.0);
}
"""

  FragmentSource = """
uniform sampler2D scene;
uniform vec2 viewportSize;
uniform float clock;
in vec2 local;
in vec4 shape;
out vec4 color;
void main() {
  float d = length(local);
  if (d >= 1.0) discard;
  vec2 outward = d > 0.0001 ? local / d : vec2(0.0);
  int kind = int(shape.x + 0.5);
  float progress = clamp(shape.y, 0.0, 1.0);
  float pixels = shape.z;
  float seed = shape.w;
  vec2 shift = vec2(0.0);
  float mask = 0.0;
  if (kind == 0) {
    // A ring racing outward, pushing the picture away from the center.
    float ring = exp(-pow((d - progress) / 0.13, 2.0));
    float fade = 1.0 - progress;
    shift = outward * ring * fade;
    mask = clamp(ring * fade * 2.0, 0.0, 1.0);
  } else if (kind == 1) {
    // Rising ripples, strongest in the middle, swelling in then fading out.
    float fade = (1.0 - d) * (1.0 - progress) * min(1.0, progress * 6.0);
    vec2 p = local * 3.5 + vec2(seed, seed * 1.7);
    float rise = clock * 3.0;
    shift = vec2(sin(p.y * 4.0 - rise + sin(p.x * 3.1 + seed)),
      cos(p.x * 4.7 + rise * 0.8 + p.y * 1.3)) * fade * 0.5;
    mask = clamp(fade * 3.0, 0.0, 1.0);
  } else {
    // A bubble: magnifies its middle and bends hard at its rim.
    float rim = pow(d, 8.0);
    shift = -outward * (d * (1.0 - d) * 0.6 + rim * 0.8);
    mask = 1.0 - smoothstep(0.92, 1.0, d);
  }
  vec2 uv = gl_FragCoord.xy / viewportSize + shift * pixels / viewportSize;
  color = vec4(texture(scene, uv).rgb, mask);
}
"""

proc shaderHeader(): string =
  when defined(emscripten):
    "#version 300 es\nprecision highp float;\n"
  else:
    "#version 410 core\n"

proc compileStage(kind: GLenum, source: string): GLuint =
  result = glCreateShader(kind)
  let text = allocCStringArray([shaderHeader() & source])
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
    vertex = compileStage(GL_VERTEX_SHADER, VertexSource)
    fragment = compileStage(GL_FRAGMENT_SHADER, FragmentSource)
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
