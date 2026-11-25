## Screen-space ambient occlusion for clients that draw straight to the
## window.
##
## Ported from CaC's post pass (games/cac/scene/post.nim): the same
## 16-tap spiral around a depth-reconstructed normal, at half resolution,
## the same depth-aware blur and the same tinted multiply. Three changes fit
## it to a game that keeps drawing into the window's multisampled buffer:
##
## - One blit copies the opaque scene's depth out of the window, so nothing
##   is rerouted offscreen and MSAA stays as it is.
## - The sample radius and the blur's depth edges follow the projection's
##   clip w, so one set of world-unit settings works for perspective and
##   orthographic cameras alike.
## - It darkens the window in place. Call `applyScreenOcclusion` after the
##   opaque pass and before particles, gizmos and the HUD; those stay bright.
##
## Calling `captureGround` between the scenery and the characters marks what
## is drawn after it as bodies: they still cast contact shadows onto the
## ground, but keep only `bodyOcclusion` of their own darkening, so their
## colors stay readable.
##
## Normals come from depth alone: CaC's material-normal replay is left out.
## `screenOcclusionSettings` reads PREFIX=0 (off), PREFIX_RADIUS,
## PREFIX_INTENSITY and PREFIX_BIAS, like CaC's CAC_SSAO variables.

import
  std/[os, strutils, tables],
  opengl, shady, vmath

const
  OcclusionTaps = 16
  ShaderTarget =
    when defined(emscripten):
      glsl3WebGL
    else:
      glsl4Desktop

type
  ScreenOcclusionError* = object of CatchableError

  ScreenOcclusionSettings* = object
    enabled*: bool
    radius*: float32    ## World units the occlusion looks around a pixel.
    intensity*: float32
    bias*: float32      ## Cosine ignored, hides flat-surface noise.
    tint*: Vec3         ## Color full occlusion fades toward.
    sharpness*: float32
      ## How hard the blur stops at depth gaps, measured against the view's
      ## half height at that depth.
    bodyOcclusion*: float32
      ## Share of its darkening a pixel drawn after `captureGround` keeps.

  OcclusionPass = object
    program: GLuint
    locations: Table[string, GLint]

  OcclusionTarget = object
    framebuffer: GLuint
    texture: GLuint
    size: IVec2

  DepthCopy = object
    ## A single-sample copy of the window's depth.
    framebuffer: GLuint
    texture: GLuint

  ScreenOcclusion* = object
    settings*: ScreenOcclusionSettings
    size: IVec2
    depth: DepthCopy           ## The whole opaque scene.
    ground: DepthCopy          ## The scene before its bodies.
    groundCaptured: bool       ## `ground` holds this frame's copy.
    occlusion: array[2, OcclusionTarget]
    vertexArray: GLuint
    occlusionPass, blurPass, multiplyPass: OcclusionPass
    copyChecked: bool          ## The depth copy has been tried at this size.
    unavailable: bool          ## The window's depth can't be copied; stays off.

  SavedState = object
    viewport: array[4, GLint]
    depthTest, cullFace, blend, stencilTest: bool
    depthMask: GLboolean
    blendFuncs: array[4, GLint]
    program, vertexArray, activeTexture: GLint
    textures: array[3, GLint]
    readFramebuffer, drawFramebuffer: GLint


var
  depthTexture, groundTexture, occlusionTexture: Uniform[Sampler2D]
  inverseProjection: Uniform[Mat4]
  texel, projectionScale, clipW: Uniform[Vec2]
  radius, intensity, bias: Uniform[float32]
  direction, halfSize, depthTexel: Uniform[Vec2]
  depthTerms: Uniform[Vec4]
  edgeScale, bodyOcclusion: Uniform[float32]
  tint: Uniform[Vec3]

proc fullscreenVertex(gl_Position: var Vec4, uv: var Vec2) =
  ## Covers the framebuffer with a single triangle and normalized coordinates.
  var corner = vec2(0.0'f)
  if gl_VertexID == 1:
    corner.x = 2.0'f
  elif gl_VertexID == 2:
    corner.y = 2.0'f
  uv = corner
  gl_Position = vec4(corner * 2.0'f - 1.0'f, vec2(0.0'f, 1.0'f))

proc viewPosition(p: Vec2): Vec3 =
  ## Reconstructs positions at nearest depth texel centers to avoid row tilts.
  let
    center = (floor(p / texel) + 0.5'f) * texel
    depth = texture(depthTexture, center).x
    position = inverseProjection *
      vec4(center * 2.0'f - 1.0'f, vec2(depth * 2.0'f - 1.0'f, 1.0'f))
  result = position.xyz / position.w

proc viewNormal(p: Vec2, center: Vec3): Vec3 =
  ## Chooses depth-nearest neighbors to keep silhouette normals clean.
  let
    right = viewPosition(p + vec2(texel.x, 0.0'f)) - center
    left = center - viewPosition(p - vec2(texel.x, 0.0'f))
    up = viewPosition(p + vec2(0.0'f, texel.y)) - center
    down = center - viewPosition(p - vec2(0.0'f, texel.y))
    dx =
      if abs(right.z) < abs(left.z): right
      else: left
    dy =
      if abs(up.z) < abs(down.z): up
      else: down
  result = normalize(cross(dx, dy))

proc occlusionHash(p: Vec2): float32 =
  ## Rotates the sample spiral independently for each framebuffer pixel.
  result = fract(52.9829189'f * fract(dot(p, vec2(0.06711056'f, 0.00583715'f))))

proc occlusionFragment(gl_FragCoord: Vec4, fragColor: var Vec4) =
  ## Samples a world-sized spiral around a depth-reconstructed surface normal.
  # Pick one full-resolution texel so each half-resolution row rounds alike.
  let
    base = (floor(gl_FragCoord.xy) * 2.0'f + 0.5'f) * texel
    depth = texture(depthTexture, base).x
  if depth >= 1.0'f:
    fragColor = vec4(1.0'f)
    return
  let
    center = viewPosition(base)
    normal = viewNormal(base, center)
    # Clip w is -z for perspective cameras and 1 for orthographic cameras.
    w = max(clipW.x * center.z + clipW.y, 0.1'f)
    uvRadius = 0.5'f * projectionScale * radius / w
    spin = occlusionHash(gl_FragCoord.xy) * 6.2831853'f
  var occlusion = 0.0'f
  for i in 0 ..< OcclusionTaps:
    let
      t = (float32(i) + 0.5'f) / float32(OcclusionTaps)
      angle = float32(i) * 2.3999632'f + spin
      offset = vec2(cos(angle), sin(angle)) * t * uvRadius
      delta = viewPosition(base + offset) - center
      distance2 = dot(delta, delta)
      falloff = max(0.0'f, 1.0'f - distance2 / (radius * radius))
      cosine = dot(delta, normal) * inversesqrt(distance2 + 0.0001'f)
    occlusion += falloff * max(0.0'f, cosine - bias)
  let ao = clamp(1.0'f - intensity * occlusion / float32(OcclusionTaps), 0.0'f, 1.0'f)
  fragColor = vec4(ao, ao, ao, 1.0'f)

proc viewDepth(p: Vec2): float32 =
  ## Reads positive view depth at the full-resolution texel used for occlusion.
  let
    texelCenter = (floor(p * halfSize) * 2.0'f + 0.5'f) * depthTexel
    ndc = texture(depthTexture, texelCenter).x * 2.0'f - 1.0'f
  result = -(depthTerms.x * ndc + depthTerms.y) /
    (depthTerms.z * ndc + depthTerms.w)

proc blurFragment(uv: Vec2, fragColor: var Vec4) =
  ## Smooths occlusion while preserving depth edges for either camera kind.
  let
    centerDepth = viewDepth(uv)
    scale = edgeScale / max(clipW.y - clipW.x * centerDepth, 0.0001'f)
  var
    total = 0.0'f
    weights = 0.0'f
  for i in -4 .. 4:
    let
      p = uv + direction * float32(i)
      difference = abs(viewDepth(p) - centerDepth) * scale
      weight = exp(-float32(i * i) / 12.0'f) * max(0.0'f, 1.0'f - difference)
    total += texture(occlusionTexture, p).x * weight
    weights += weight
  let ao = total / max(weights, 0.0001'f)
  fragColor = vec4(ao, ao, ao, 1.0'f)

proc multiplyFragment(uv: Vec2, gl_FragCoord: Vec4, fragColor: var Vec4) =
  ## Tints occluded surfaces while retaining configurable body brightness.
  var ao = texture(occlusionTexture, uv).x
  if ao > 0.996'f:
    discardFragment()
  # Without a ground copy both samplers read the same scene depth texture.
  let pixel = ivec2(gl_FragCoord.x.int32, gl_FragCoord.y.int32)
  if texelFetch(depthTexture, pixel, 0).x <
    texelFetch(groundTexture, pixel, 0).x:
      ao = mix(1.0'f, ao, bodyOcclusion)
  fragColor = vec4(mix(tint, vec3(1.0'f), ao), 1.0'f)

const
  FullscreenVertex = toShader(fullscreenVertex, ShaderTarget, shaderVertex)
  OcclusionFragment = toShader(occlusionFragment, ShaderTarget, shaderFragment)
  BlurFragment = toShader(blurFragment, ShaderTarget, shaderFragment)
  MultiplyFragment = toShader(multiplyFragment, ShaderTarget, shaderFragment)

proc defaultScreenOcclusionSettings*(): ScreenOcclusionSettings =
  ## CaC's tuned values. Its blur sharpness of 40 per unit of relative depth
  ## becomes 15.4 here: its 42 degree camera has a projection scale of 2.6.
  ScreenOcclusionSettings(
    enabled: true,
    radius: 1.501,
    intensity: 3.523,
    bias: 0.08,
    tint: vec3(0.10, 0.10, 0.16),
    sharpness: 15.4,
    bodyOcclusion: 0.25
  )

proc envFlag(name: string, default: bool): bool =
  let value = getEnv(name)
  if value.len == 0: default else: value notin ["0", "false", "off", "no"]

proc envFloat(name: string, default: float32): float32 =
  try: parseFloat(getEnv(name, $default)).float32
  except ValueError: default

proc screenOcclusionSettings*(
    prefix: string,
    defaults = defaultScreenOcclusionSettings()
): ScreenOcclusionSettings =
  ## Applies PREFIX=0 (off), PREFIX_RADIUS, PREFIX_INTENSITY and PREFIX_BIAS
  ## from the environment over the defaults.
  result = defaults
  result.enabled = envFlag(prefix, defaults.enabled)
  result.radius = envFloat(prefix & "_RADIUS", defaults.radius)
  result.intensity = envFloat(prefix & "_INTENSITY", defaults.intensity)
  result.bias = envFloat(prefix & "_BIAS", defaults.bias)

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
    raise newException(ScreenOcclusionError,
      "screen occlusion " & label & " shader failed:\n" & log)

proc compilePass(fragment, label: string): OcclusionPass =
  ## Links a full-screen triangle program.
  let
    vertexShader = compileStage(GL_VERTEX_SHADER, FullscreenVertex, label)
    fragmentShader = compileStage(GL_FRAGMENT_SHADER, fragment, label)
  result.program = glCreateProgram()
  glAttachShader(result.program, vertexShader)
  glAttachShader(result.program, fragmentShader)
  glLinkProgram(result.program)
  glDeleteShader(vertexShader)
  glDeleteShader(fragmentShader)
  var status: GLint
  glGetProgramiv(result.program, GL_LINK_STATUS, status.addr)
  if status == 0:
    var length: GLint
    glGetProgramiv(result.program, GL_INFO_LOG_LENGTH, length.addr)
    var log = newString(length)
    glGetProgramInfoLog(result.program, length, nil, log.cstring)
    raise newException(ScreenOcclusionError,
      "screen occlusion " & label & " program failed:\n" & log)

proc location(pass: var OcclusionPass, name: string): GLint =
  if name notin pass.locations:
    pass.locations[name] = glGetUniformLocation(pass.program, name.cstring)
  pass.locations[name]

proc setFloat(pass: var OcclusionPass, name: string, value: float32) =
  glUniform1f(pass.location(name), value)

proc setVec2(pass: var OcclusionPass, name: string, value: Vec2) =
  glUniform2f(pass.location(name), value.x, value.y)

proc setVec3(pass: var OcclusionPass, name: string, value: Vec3) =
  glUniform3f(pass.location(name), value.x, value.y, value.z)

proc setVec4(pass: var OcclusionPass, name: string, value: Vec4) =
  glUniform4f(pass.location(name), value.x, value.y, value.z, value.w)

proc setTexture(
    pass: var OcclusionPass, name: string, unit: int, texture: GLuint
) =
  glActiveTexture(GLenum(GL_TEXTURE0.int + unit))
  glBindTexture(GL_TEXTURE_2D, texture)
  glUniform1i(pass.location(name), unit.GLint)

proc newTexture(size: IVec2, internal: GLint, format, kind: GLenum,
    filter: GLint): GLuint =
  glGenTextures(1, result.addr)
  glBindTexture(GL_TEXTURE_2D, result)
  glTexImage2D(GL_TEXTURE_2D, 0, internal, size.x.GLsizei, size.y.GLsizei, 0,
    format, kind, nil)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, filter)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, filter)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE.GLint)

proc release(target: var OcclusionTarget) =
  if target.framebuffer != 0:
    glDeleteFramebuffers(1, target.framebuffer.addr)
    glDeleteTextures(1, target.texture.addr)
  target = OcclusionTarget()

proc initTarget(target: var OcclusionTarget, size: IVec2) =
  target.release()
  target.size = ivec2(max(size.x, 1), max(size.y, 1))
  target.texture = newTexture(target.size, GL_RGBA8.GLint, GL_RGBA,
    GL_UNSIGNED_BYTE, GL_LINEAR.GLint)
  glGenFramebuffers(1, target.framebuffer.addr)
  glBindFramebuffer(GL_FRAMEBUFFER, target.framebuffer)
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
    target.texture, 0)

proc bindTarget(target: OcclusionTarget) =
  glBindFramebuffer(GL_FRAMEBUFFER, target.framebuffer)
  glViewport(0, 0, target.size.x.GLsizei, target.size.y.GLsizei)

proc texelSize(target: OcclusionTarget): Vec2 =
  vec2(1.0'f32 / target.size.x.float32, 1.0'f32 / target.size.y.float32)

proc release(copy: var DepthCopy) =
  if copy.framebuffer != 0:
    glDeleteFramebuffers(1, copy.framebuffer.addr)
    glDeleteTextures(1, copy.texture.addr)
  copy = DepthCopy()

proc initDepthCopy(copy: var DepthCopy, size: IVec2): bool =
  ## Returns false when the driver can't render to this depth format.
  copy.release()
  # The window's buffer is 24-bit depth with 8-bit stencil; a depth blit
  # needs the same format on both ends.
  copy.texture = newTexture(size, GL_DEPTH24_STENCIL8.GLint,
    GL_DEPTH_STENCIL, GL_UNSIGNED_INT_24_8, GL_NEAREST.GLint)
  glGenFramebuffers(1, copy.framebuffer.addr)
  glBindFramebuffer(GL_FRAMEBUFFER, copy.framebuffer)
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT,
    GL_TEXTURE_2D, copy.texture, 0)
  var none = GL_NONE
  glDrawBuffers(1, none.addr)
  glReadBuffer(GL_NONE)
  glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE

proc ensureSize(occlusion: var ScreenOcclusion, size: IVec2) =
  ## Matches the depth copies to the window and the AO targets to half of it.
  if size == occlusion.size:
    return
  occlusion.size = size
  occlusion.copyChecked = false
  occlusion.groundCaptured = false
  if not occlusion.depth.initDepthCopy(size) or
      not occlusion.ground.initDepthCopy(size):
    occlusion.unavailable = true
    echo "Screen occlusion is off: no single-sample depth target"
    return
  let half = ivec2(max(size.x div 2, 1), max(size.y div 2, 1))
  for target in occlusion.occlusion.mitems:
    target.initTarget(half)

proc initScreenOcclusion*(
    settings = defaultScreenOcclusionSettings()
): ScreenOcclusion =
  ## Compiles the passes. Targets are made on the first frame, at its size.
  result.settings = settings
  glGenVertexArrays(1, result.vertexArray.addr)
  result.occlusionPass = compilePass(OcclusionFragment, "sample")
  result.blurPass = compilePass(BlurFragment, "blur")
  result.multiplyPass = compilePass(MultiplyFragment, "multiply")

proc closeScreenOcclusion*(occlusion: var ScreenOcclusion) =
  ## Releases every GL object the pass owns.
  occlusion.depth.release()
  occlusion.ground.release()
  for target in occlusion.occlusion.mitems:
    target.release()
  for pass in [occlusion.occlusionPass, occlusion.blurPass,
      occlusion.multiplyPass]:
    if pass.program != 0:
      glDeleteProgram(pass.program)
  if occlusion.vertexArray != 0:
    glDeleteVertexArrays(1, occlusion.vertexArray.addr)
  occlusion = ScreenOcclusion(settings: occlusion.settings)

proc saveState(): SavedState =
  ## Records the state the pass changes, so the frame resumes untouched.
  glGetIntegerv(GL_VIEWPORT, result.viewport[0].addr)
  result.depthTest = glIsEnabled(GL_DEPTH_TEST)
  result.cullFace = glIsEnabled(GL_CULL_FACE)
  result.blend = glIsEnabled(GL_BLEND)
  result.stencilTest = glIsEnabled(GL_STENCIL_TEST)
  glGetBooleanv(GL_DEPTH_WRITEMASK, result.depthMask.addr)
  glGetIntegerv(GL_BLEND_SRC_RGB, result.blendFuncs[0].addr)
  glGetIntegerv(GL_BLEND_DST_RGB, result.blendFuncs[1].addr)
  glGetIntegerv(GL_BLEND_SRC_ALPHA, result.blendFuncs[2].addr)
  glGetIntegerv(GL_BLEND_DST_ALPHA, result.blendFuncs[3].addr)
  glGetIntegerv(GL_CURRENT_PROGRAM, result.program.addr)
  glGetIntegerv(GL_VERTEX_ARRAY_BINDING, result.vertexArray.addr)
  glGetIntegerv(GL_ACTIVE_TEXTURE, result.activeTexture.addr)
  for unit in 0 ..< result.textures.len:
    glActiveTexture(GLenum(GL_TEXTURE0.int + unit))
    glGetIntegerv(GL_TEXTURE_BINDING_2D, result.textures[unit].addr)
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, result.readFramebuffer.addr)
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, result.drawFramebuffer.addr)

proc setEnabled(capability: GLenum, enabled: bool) =
  if enabled: glEnable(capability) else: glDisable(capability)

proc restore(state: SavedState) =
  glViewport(state.viewport[0], state.viewport[1],
    state.viewport[2].GLsizei, state.viewport[3].GLsizei)
  setEnabled(GL_DEPTH_TEST, state.depthTest)
  setEnabled(GL_CULL_FACE, state.cullFace)
  setEnabled(GL_BLEND, state.blend)
  setEnabled(GL_STENCIL_TEST, state.stencilTest)
  glDepthMask(state.depthMask)
  glBlendFuncSeparate(state.blendFuncs[0].GLenum, state.blendFuncs[1].GLenum,
    state.blendFuncs[2].GLenum, state.blendFuncs[3].GLenum)
  glUseProgram(state.program.GLuint)
  glBindVertexArray(state.vertexArray.GLuint)
  for unit in 0 ..< state.textures.len:
    glActiveTexture(GLenum(GL_TEXTURE0.int + unit))
    glBindTexture(GL_TEXTURE_2D, state.textures[unit].GLuint)
  glActiveTexture(state.activeTexture.GLenum)
  glBindFramebuffer(GL_READ_FRAMEBUFFER, state.readFramebuffer.GLuint)
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, state.drawFramebuffer.GLuint)

proc drawFullscreen(occlusion: ScreenOcclusion) =
  glBindVertexArray(occlusion.vertexArray)
  glDrawArrays(GL_TRIANGLES, 0, 3)

proc copyDepth(
    occlusion: var ScreenOcclusion, source: GLuint, copy: DepthCopy
): bool =
  ## Resolves the window's depth into a single-sample copy. The first copy
  ## at each size checks for errors and turns the pass off if the formats
  ## disagree, rather than shading from garbage.
  if not occlusion.copyChecked:
    while glGetError() != GL_NO_ERROR:
      discard
  glBindFramebuffer(GL_READ_FRAMEBUFFER, source)
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, copy.framebuffer)
  glBlitFramebuffer(0, 0, occlusion.size.x, occlusion.size.y,
    0, 0, occlusion.size.x, occlusion.size.y,
    GL_DEPTH_BUFFER_BIT, GL_NEAREST.GLenum)
  if not occlusion.copyChecked:
    occlusion.copyChecked = true
    let error = glGetError()
    if error != GL_NO_ERROR:
      occlusion.unavailable = true
      echo "Screen occlusion is off: the window's depth can't be copied ",
        "(GL error 0x", toHex(error.int, 4), ")"
      return false
  true

proc captureGround*(
    occlusion: var ScreenOcclusion, size: IVec2, source: GLuint = 0
) =
  ## Optional: call after the scenery, before the characters. What draws
  ## between this and `applyScreenOcclusion` counts as bodies.
  if not occlusion.settings.enabled or occlusion.unavailable or
      size.x <= 0 or size.y <= 0:
    return
  let saved = saveState()
  occlusion.ensureSize(size)
  if not occlusion.unavailable:
    occlusion.groundCaptured = occlusion.copyDepth(source, occlusion.ground)
  saved.restore()

proc applyScreenOcclusion*(
    occlusion: var ScreenOcclusion,
    size: IVec2,
    projection: Mat4,
    source: GLuint = 0
) =
  ## Darkens creases and contact points in everything the `source`
  ## framebuffer (the window by default) holds so far. `size` is its size in
  ## pixels and `projection` the camera's. Leaves GL state as it found it.
  let settings = occlusion.settings
  defer:
    occlusion.groundCaptured = false
  if not settings.enabled or occlusion.unavailable or
      size.x <= 0 or size.y <= 0:
    return
  let saved = saveState()
  occlusion.ensureSize(size)
  if occlusion.unavailable or not occlusion.copyDepth(source, occlusion.depth):
    saved.restore()
    return
  glDisable(GL_DEPTH_TEST)
  glDepthMask(GL_FALSE)
  glDisable(GL_STENCIL_TEST)
  glDisable(GL_CULL_FACE)
  glDisable(GL_BLEND)
  let
    inverseProjection = projection.inverse
    clipW = vec2(projection[2, 3], projection[3, 3])
    depthTexel = vec2(1.0'f32 / size.x.float32, 1.0'f32 / size.y.float32)

  occlusion.occlusion[0].bindTarget()
  glUseProgram(occlusion.occlusionPass.program)
  occlusion.occlusionPass.setTexture("depthTexture", 0,
    occlusion.depth.texture)
  var matrix = inverseProjection
  glUniformMatrix4fv(occlusion.occlusionPass.location("inverseProjection"),
    1, GL_FALSE, cast[ptr float32](matrix.addr))
  occlusion.occlusionPass.setVec2("projectionScale",
    vec2(projection[0, 0], projection[1, 1]))
  occlusion.occlusionPass.setVec2("clipW", clipW)
  occlusion.occlusionPass.setVec2("texel", depthTexel)
  occlusion.occlusionPass.setFloat("radius", settings.radius)
  occlusion.occlusionPass.setFloat("intensity", settings.intensity)
  occlusion.occlusionPass.setFloat("bias", settings.bias)
  occlusion.drawFullscreen()

  glUseProgram(occlusion.blurPass.program)
  occlusion.blurPass.setTexture("depthTexture", 1, occlusion.depth.texture)
  occlusion.blurPass.setVec2("halfSize",
    vec2(occlusion.occlusion[0].size.x.float32,
      occlusion.occlusion[0].size.y.float32))
  occlusion.blurPass.setVec2("depthTexel", depthTexel)
  # View z = (a * ndc + b) / (c * ndc + d), read off the inverse projection.
  occlusion.blurPass.setVec4("depthTerms", vec4(
    inverseProjection[2, 2], inverseProjection[3, 2],
    inverseProjection[2, 3], inverseProjection[3, 3]))
  occlusion.blurPass.setVec2("clipW", clipW)
  occlusion.blurPass.setFloat("edgeScale",
    settings.sharpness * projection[1, 1])
  for (input, output, axis) in [(0, 1, vec2(1, 0)), (1, 0, vec2(0, 1))]:
    occlusion.occlusion[output].bindTarget()
    occlusion.blurPass.setTexture("occlusionTexture", 0,
      occlusion.occlusion[input].texture)
    occlusion.blurPass.setVec2("direction",
      axis * occlusion.occlusion[input].texelSize)
    occlusion.drawFullscreen()

  glBindFramebuffer(GL_FRAMEBUFFER, source)
  glViewport(0, 0, size.x.GLsizei, size.y.GLsizei)
  glEnable(GL_BLEND)
  glBlendFuncSeparate(GL_DST_COLOR, GL_ZERO, GL_ZERO, GL_ONE)
  glUseProgram(occlusion.multiplyPass.program)
  occlusion.multiplyPass.setTexture("occlusionTexture", 0,
    occlusion.occlusion[0].texture)
  occlusion.multiplyPass.setTexture("depthTexture", 1,
    occlusion.depth.texture)
  occlusion.multiplyPass.setTexture("groundTexture", 2,
    if occlusion.groundCaptured: occlusion.ground.texture
    else: occlusion.depth.texture)
  occlusion.multiplyPass.setVec3("tint", settings.tint)
  occlusion.multiplyPass.setFloat("bodyOcclusion", settings.bodyOcclusion)
  occlusion.drawFullscreen()
  saved.restore()
