## Bodies seen through scenery with a screen-door dither.
##
## Walls draw whole. Whatever part of a body sits behind them shows through
## on a fixed Bayer 4x4 pattern, so a fighter in a corridor stays readable
## without cutting holes in the level.
##
## How it works, for a game that draws straight to the window:
##
## 1. `beginXrayBodies` binds an offscreen colour and depth target and
##    clears it. The game draws its bodies again, with any look it likes
##    (a side colour, say). Their own depth test keeps the nearest surface,
##    so an arm behind a torso stays behind it.
## 2. `finishXrayBodies` lays that target over the window with the depth
##    test inverted: a texel lands only where the body is behind what the
##    window already holds, and only on the pattern's pixels. Visible bodies
##    sit at their own depth and fail the test, so they are never covered.
##
## The pattern is anchored to window pixels, not to the world, so it
## doesn't crawl as the camera pans. Nothing writes depth, so particles and
## gizmos drawn later still sort against the walls.
##
## `xrayBodySettings` reads PREFIX=0 (off), PREFIX_COVERAGE and PREFIX_CELL
## (points per cell).

import
  std/[os, strutils],
  opengl, shady, vmath

type
  XrayBodyError* = object of CatchableError

  XrayBodySettings* = object
    enabled*: bool
    coverage*: float32
      ## Share of the pattern's pixels that show the body, 0 .. 1. Half is
      ## a checkerboard.
    cell*: float32
      ## Points per pattern cell; `finishXrayBodies` multiplies it by the
      ## window's content scale, so a cell is the same size on every screen.
    clearance*: float32
      ## World units a body must sit behind scenery before it shows, so a
      ## visible body never speckles over itself.

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
    locations: array[6, GLint]

const
  ShaderTarget =
    when defined(emscripten):
      glsl3WebGL
    else:
      glsl4Desktop

var
  bodyColor: Uniform[Sampler2d]
  bodyDepth: Uniform[Sampler2d]
  coverage: Uniform[float32]
  cell: Uniform[float32]
  depthTerms: Uniform[Vec4]
  clearance: Uniform[float32]

proc fullscreenVertex(gl_Position: var Vec4) =
  ## Covers the target with one triangle generated from the vertex index.
  let corner = vec2(
    float32((gl_VertexID mod 2) * 2),
    float32((gl_VertexID div 2) * 2)
  )
  gl_Position = vec4(
    corner.x * 2.0'f - 1.0'f,
    corner.y * 2.0'f - 1.0'f,
    0.0'f,
    1.0'f
  )

proc compositeFragment(
    gl_FragCoord: Vec4,
    gl_FragDepth: var float32,
    fragColor: var Vec4
) =
  ## Draws hidden body texels through the fixed screen-door pattern.
  let
    pattern = ivec2(floor(gl_FragCoord.xy / cell) mod 4.0'f)
    lowX = pattern.x mod 2
    lowY = pattern.y mod 2
    highX = pattern.x div 2
    highY = pattern.y div 2
    # Expand the two recursive Bayer levels without a shader array.
    bayer = abs(lowX - lowY) * 8 + lowY * 4 +
      abs(highX - highY) * 2 + highY
  if (float32(bayer) + 0.5'f) / 16.0'f >= coverage:
    discardFragment()
  let
    texel = ivec2(gl_FragCoord.xy)
    body = texelFetch(bodyColor, texel, 0)
  if body.a <= 0.0'f:
    discardFragment()
  # Pull toward the eye in view space for either projection type.
  let ndc = texelFetch(bodyDepth, texel, 0).r * 2.0'f - 1.0'f
  var z = (depthTerms.y - ndc * depthTerms.w) /
    (ndc * depthTerms.z - depthTerms.x)
  z += clearance
  let nearer = (depthTerms.x * z + depthTerms.y) /
    (depthTerms.z * z + depthTerms.w)
  gl_FragDepth = clamp(nearer * 0.5'f + 0.5'f, 0.0'f, 1.0'f)
  fragColor = vec4(body.rgb, 1.0'f)

proc defaultXrayBodySettings*(): XrayBodySettings =
  ## A checkerboard in three-point cells.
  XrayBodySettings(enabled: true, coverage: 0.5, cell: 3, clearance: 0.2)

proc envFlag(name: string, default: bool): bool =
  let value = getEnv(name)
  if value.len == 0: default else: value notin ["0", "false", "off", "no"]

proc envFloat(name: string, default: float32): float32 =
  try: parseFloat(getEnv(name, $default)).float32
  except ValueError: default

proc xrayBodySettings*(
    prefix: string,
    defaults = defaultXrayBodySettings()
): XrayBodySettings =
  ## Applies PREFIX=0 (off), PREFIX_COVERAGE and PREFIX_CELL from the
  ## environment over the defaults.
  result = defaults
  result.enabled = envFlag(prefix, defaults.enabled)
  result.coverage = clamp(
    envFloat(prefix & "_COVERAGE", defaults.coverage), 0, 1)
  result.cell = max(1'f32, envFloat(prefix & "_CELL", defaults.cell))

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
      "depthTerms", "clearance"]:
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
    xray: var XrayBodies, projection: Mat4, contentScale = 1'f32
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
    max(1'f32, round(xray.settings.cell * max(contentScale, 1'f32))))
  glUniform4f(xray.locations[4], projection[2, 2], projection[3, 2],
    projection[2, 3], projection[3, 3])
  glUniform1f(xray.locations[5], xray.settings.clearance)
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
