import std/os
import opengl, pixie
import polyworld/nightskies
import ../../../paths, ../../[courtyardgeometry, courtyardmaterials, courtyardshaders, ring]
export courtyardmaterials

type
  CourtyardRenderer* = object
    material*: CourtyardMaterial
    lamps*: array[2, Vec3] ## Positions for a two-lamp stage; Z follows cameraSide.
    program, vao, vbo: GLuint
    normalMap: GLuint
    skyProgram: GLuint
    skyViewLocation, skyEyeLocation, skyTimeLocation, skyBrightnessLocation: GLint
    shadows: array[2, GLuint]
    lightMatrices: array[2, Mat4]
    commonCount, backdropCount, centerCount: int
    playerCount: int
    arenaRadius, balconyLampRadius, balconyLampHalfAngle: float32
    viewLocation, lightLocation, eyeLocation, timeLocation, sideLocation,
      shadowLocation, normalLocation,
      normalStrengthLocation, normalsOnlyLocation, normalViewLocation,
      slopeBroadLocation, scaleBroadLocation, lampLocation,
      playerCountLocation, arenaRadiusLocation, lampRadiusLocation,
      lampAngleLocation, stageYawLocation: GLint
    lampLocations: array[2, GLint]

const
  ShadowSize = 2048

proc compile(kind: GLenum, source: string): GLuint =
  result = glCreateShader(kind)
  let sources = allocCStringArray([source])
  defer: deallocCStringArray(sources)
  glShaderSource(result, 1, sources, nil)
  glCompileShader(result)
  var ok: GLint
  glGetShaderiv(result, GL_COMPILE_STATUS, ok.addr)
  if ok == 0:
    var size: GLint
    glGetShaderiv(result, GL_INFO_LOG_LENGTH, size.addr)
    var log = newString(size)
    glGetShaderInfoLog(result, size, nil, log.cstring)
    raise newException(CatchableError, "Courtyard shader: " & log)

proc program(vertex, fragment: string): GLuint =
  let v = compile(GL_VERTEX_SHADER, vertex)
  let f = compile(GL_FRAGMENT_SHADER, fragment)
  defer:
    glDeleteShader(v)
    glDeleteShader(f)
  result = glCreateProgram()
  glAttachShader(result, v)
  glAttachShader(result, f)
  # The scene and depth programs share one fixed vertex-array layout.
  for (location, name) in [
      (0, "position"), (1, "normal"), (2, "color"),
      (3, "material"), (4, "uv")]:
    glBindAttribLocation(result, location.GLuint, name.cstring)
  glLinkProgram(result)
  var ok: GLint
  glGetProgramiv(result, GL_LINK_STATUS, ok.addr)
  if ok == 0:
    var size: GLint
    glGetProgramiv(result, GL_INFO_LOG_LENGTH, size.addr)
    var log = newString(size)
    glGetProgramInfoLog(result, size, nil, log.cstring)
    raise newException(CatchableError, "Courtyard shader link: " & log)

proc matrix(location: GLint, value: Mat4) =
  var data = value
  glUniformMatrix4fv(location, 1, GL_FALSE, cast[ptr float32](data.addr))

proc loadNormalTexture(path: string): GLuint =
  let image = readImage(path)
  glGenTextures(1, result.addr)
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, result)
  # RGBA8, not SRGB: all normal channels are linear vector components.
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.GLint,
    image.width.GLsizei, image.height.GLsizei, 0,
    GL_RGBA, GL_UNSIGNED_BYTE, image.data[0].addr)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT.GLint)
  glGenerateMipmap(GL_TEXTURE_2D)
  glBindTexture(GL_TEXTURE_2D, 0)

proc initCourtyardRenderer*(mesh: CourtyardMesh, playerCount = 2,
    arenaRadius = 0.0'f32, balconyLampRadius = 0.0'f32,
    balconyLampHalfAngle = 0.0'f32): CourtyardRenderer =
  ## A shared material/sky pipeline for the arena and its selection terrace.
  result.playerCount = playerCount
  result.arenaRadius = arenaRadius
  result.balconyLampRadius = balconyLampRadius
  result.balconyLampHalfAngle = balconyLampHalfAngle
  result.lamps = [vec3(-6.75, 1.25, -6.32), vec3(6.75, 1.25, -6.32)]
  result.commonCount = mesh.commonCount
  result.backdropCount = mesh.backdropCount
  result.centerCount = mesh.centerCount
  result.program = program(CourtyardVertexSource, CourtyardFragmentSource)
  let textureRoot = artworkRoot() / "battlefield/textures"
  result.normalMap = loadNormalTexture(textureRoot / "stone-slab-normal.png")
  result.material = defaultCourtyardMaterial()
  result.skyProgram = program(NightSkyVertexSource, NightSkyFragmentSource)
  result.skyViewLocation = glGetUniformLocation(result.skyProgram, "inverseViewProjection")
  result.skyEyeLocation = glGetUniformLocation(result.skyProgram, "cameraEye")
  result.skyTimeLocation = glGetUniformLocation(result.skyProgram, "time")
  result.skyBrightnessLocation = glGetUniformLocation(result.skyProgram, "skyBrightness")
  glGenVertexArrays(1, result.vao.addr)
  glBindVertexArray(result.vao)
  glGenBuffers(1, result.vbo.addr)
  glBindBuffer(GL_ARRAY_BUFFER, result.vbo)
  var data = newSeqOfCap[float32](mesh.vertices.len * 12)
  for v in mesh.vertices:
    data.add [v.position.x, v.position.y, v.position.z,
      v.normal.x, v.normal.y, v.normal.z, v.color.x, v.color.y, v.color.z,
      v.material, v.uv.x, v.uv.y]
  glBufferData(GL_ARRAY_BUFFER, data.len * sizeof(float32), data[0].addr,
    GL_STATIC_DRAW)
  for attribute in [(0, 3, 0), (1, 3, 3), (2, 3, 6), (3, 1, 9), (4, 2, 10)]:
    glEnableVertexAttribArray(attribute[0].GLuint)
    glVertexAttribPointer(attribute[0].GLuint, attribute[1].GLint,
      cGL_FLOAT, GL_FALSE, (12 * sizeof(float32)).GLsizei,
      cast[pointer](attribute[2] * sizeof(float32)))
  for (name, destination) in [
      ("viewProjection", result.viewLocation.addr),
      ("lightMatrix", result.lightLocation.addr),
      ("cameraEye", result.eyeLocation.addr),
      ("time", result.timeLocation.addr),
      ("cameraSide", result.sideLocation.addr),
      ("shadowMap", result.shadowLocation.addr),
      ("stoneNormalMap", result.normalLocation.addr),
      ("normalStrength", result.normalStrengthLocation.addr),
      ("lampIntensity", result.lampLocation.addr),
      ("playerCount", result.playerCountLocation.addr),
      ("arenaRadius", result.arenaRadiusLocation.addr),
      ("balconyLampRadius", result.lampRadiusLocation.addr),
      ("balconyLampHalfAngle", result.lampAngleLocation.addr),
      ("slopeBroad", result.slopeBroadLocation.addr),
      ("scaleBroad", result.scaleBroadLocation.addr),
      ("normalsOnly", result.normalsOnlyLocation.addr),
      ("normalView", result.normalViewLocation.addr),
      ("stageYaw", result.stageYawLocation.addr),
      ("firstLamp", result.lampLocations[0].addr),
      ("secondLamp", result.lampLocations[1].addr)]:
    destination[] = glGetUniformLocation(result.program, name.cstring)

  # Bake the static sun shadows for both camera directions once. No scene
  # geometry is rebuilt or uploaded on a normal frame, including cloth.
  let depthProgram = program(
    CourtyardDepthVertexSource, CourtyardDepthFragmentSource
  )
  let lightLocation = glGetUniformLocation(depthProgram, "lightMatrix")
  var viewport: array[4, GLint]
  var oldFramebuffer: GLint
  glGetIntegerv(GL_VIEWPORT, viewport[0].addr)
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, oldFramebuffer.addr)
  glEnable(GL_DEPTH_TEST)
  glDepthMask(GL_TRUE)
  glDisable(GL_BLEND)
  glDisable(GL_CULL_FACE)
  glUseProgram(depthProgram)
  glViewport(0, 0, ShadowSize, ShadowSize)
  for seat in 0 .. 1:
    let side = if seat == 0: 1.0'f32 else: -1.0'f32
    let light = normalize(vec3(-0.48'f32 * side, 0.85, 0.35'f32 * side))
    let
      extent = max(18.0'f32, result.arenaRadius + 3.0'f32)
      distance = if arenaRadius > 0: extent * 2 else: 35.0'f32
      farPlane = if arenaRadius > 0: max(70.0'f32, extent * 4) else: 70.0'f32
    result.lightMatrices[seat] = ortho(-extent, extent, -extent,
      extent, 1.0'f32, farPlane) *
      lookAt(light * distance, vec3(0), vec3(0, 1, 0))
    glGenTextures(1, result.shadows[seat].addr)
    glBindTexture(GL_TEXTURE_2D, result.shadows[seat])
    glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT24.GLint,
      ShadowSize, ShadowSize, 0, GL_DEPTH_COMPONENT, GL_UNSIGNED_INT, nil)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_COMPARE_MODE,
      GL_COMPARE_REF_TO_TEXTURE.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_COMPARE_FUNC, GL_LEQUAL.GLint)
    var framebuffer: GLuint
    glGenFramebuffers(1, framebuffer.addr)
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT,
      GL_TEXTURE_2D, result.shadows[seat], 0)
    var targets = [GL_NONE]
    glDrawBuffers(1, cast[ptr GLenum](targets.addr))
    glReadBuffer(GL_NONE)
    if glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE:
      raise newException(CatchableError, "Courtyard shadow framebuffer is incomplete")
    glClear(GL_DEPTH_BUFFER_BIT)
    matrix(lightLocation, result.lightMatrices[seat])
    glDrawArrays(GL_TRIANGLES, 0, result.commonCount.GLsizei)
    glDrawArrays(GL_TRIANGLES,
      (result.commonCount + seat * result.backdropCount).GLint,
      result.backdropCount.GLsizei)
    glDeleteFramebuffers(1, framebuffer.addr)
  glBindFramebuffer(GL_FRAMEBUFFER, oldFramebuffer.GLuint)
  glViewport(viewport[0], viewport[1], viewport[2], viewport[3])
  glBindTexture(GL_TEXTURE_2D, 0)
  glBindVertexArray(0)
  glDeleteProgram(depthProgram)

proc dispose*(renderer: var CourtyardRenderer) =
  ## Releases the battlefield resources before another layout replaces it.
  glDeleteProgram(renderer.program)
  glDeleteProgram(renderer.skyProgram)
  glDeleteVertexArrays(1, renderer.vao.addr)
  glDeleteBuffers(1, renderer.vbo.addr)
  glDeleteTextures(1, renderer.normalMap.addr)
  glDeleteTextures(2, renderer.shadows[0].addr)
  renderer = CourtyardRenderer()

proc initCourtyardRenderer*(playerCount = 2): CourtyardRenderer =
  if playerCount > 2:
    let layout = buildMultiplayerLayout(playerCount)
    result = initCourtyardRenderer(buildMultiplayerCourtyardMesh(layout),
      playerCount, layout.outerRadius, layout.lampRadius, layout.lampHalfAngle)
  else:
    result = initCourtyardRenderer(buildCourtyardMesh(), playerCount)

proc drawSky*(renderer: CourtyardRenderer, viewProjection: Mat4,
    cameraEye: Vec3, time: float32, brightness = 1.0'f32) =
  # The sky never writes depth: SSAO sees the clear depth of 1.0, and all
  # opaque objects and VFX can occlude it without treating it as a wall.
  glEnable(GL_DEPTH_TEST)
  glDepthFunc(GL_LEQUAL)
  glDepthMask(GL_FALSE)
  glDisable(GL_STENCIL_TEST)
  glDisable(GL_BLEND)
  glDisable(GL_CULL_FACE)
  glUseProgram(renderer.skyProgram)
  matrix(renderer.skyViewLocation, viewProjection.inverse)
  glUniform3f(renderer.skyEyeLocation, cameraEye.x, cameraEye.y, cameraEye.z)
  glUniform1f(renderer.skyTimeLocation, time)
  glUniform1f(renderer.skyBrightnessLocation, brightness)
  glBindVertexArray(renderer.vao)
  glDrawArrays(GL_TRIANGLES, 0, 3)
  glBindVertexArray(0)
  glEnable(GL_DEPTH_TEST)
  glDepthMask(GL_TRUE)
  glDepthFunc(GL_LESS)

proc draw*(renderer: CourtyardRenderer, viewProjection: Mat4,
    cameraEye: Vec3, time, cameraSide: float32,
    normalsOnly = false, normalView = mat4(), stageYaw = 0'f32) =
  ## stageYaw turns the multiplayer balconies (see stageRotation) while
  ## the center island stays put. Lighting and baked shadows live in the
  ## balconies' own frame, so their lamps and key light turn with them.
  let seat = if cameraSide > 0: 0 else: 1
  glEnable(GL_DEPTH_TEST)
  glDepthMask(if normalsOnly: GL_FALSE else: GL_TRUE)
  glDepthFunc(if normalsOnly: GL_EQUAL else: GL_LESS)
  glDisable(GL_BLEND)
  glDisable(GL_CULL_FACE)
  glUseProgram(renderer.program)
  matrix(renderer.viewLocation, viewProjection)
  matrix(renderer.lightLocation, renderer.lightMatrices[seat])
  glUniform3f(renderer.eyeLocation, cameraEye.x, cameraEye.y, cameraEye.z)
  glUniform1f(renderer.timeLocation, time)
  glUniform1f(renderer.sideLocation, cameraSide)
  glUniform1f(renderer.normalStrengthLocation,
    renderer.material.normalStrength)
  glUniform1f(renderer.lampLocation, renderer.material.lampIntensity)
  for i, lamp in renderer.lamps:
    glUniform3f(renderer.lampLocations[i], lamp.x, lamp.y, lamp.z * cameraSide)
  glUniform1i(renderer.playerCountLocation, renderer.playerCount.GLint)
  glUniform1f(renderer.arenaRadiusLocation, renderer.arenaRadius)
  glUniform1f(renderer.lampRadiusLocation, renderer.balconyLampRadius)
  glUniform1f(renderer.lampAngleLocation, renderer.balconyLampHalfAngle)
  glUniform1f(renderer.slopeBroadLocation, renderer.material.slopeBroad)
  glUniform1f(renderer.scaleBroadLocation, renderer.material.scaleBroad)
  glUniform1i(renderer.normalsOnlyLocation, if normalsOnly: 1 else: 0)
  matrix(renderer.normalViewLocation, normalView)
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, renderer.shadows[seat])
  glUniform1i(renderer.shadowLocation, 0)
  glActiveTexture(GL_TEXTURE1)
  glBindTexture(GL_TEXTURE_2D, renderer.normalMap)
  glUniform1i(renderer.normalLocation, 1)
  glBindVertexArray(renderer.vao)
  # The center island, in the world frame: its lamp light comes from the
  # turned balconies.
  glUniform1f(renderer.stageYawLocation, stageYaw)
  glDrawArrays(GL_TRIANGLES, 0, renderer.centerCount.GLsizei)
  # Everything else, drawn through the stage turn in its own frame.
  let
    stage = stageRotation(stageYaw)
    stageEye = (stage.inverse * vec4(cameraEye.x, cameraEye.y,
      cameraEye.z, 1)).xyz
  matrix(renderer.viewLocation, viewProjection * stage)
  matrix(renderer.normalViewLocation, normalView * stage)
  glUniform3f(renderer.eyeLocation, stageEye.x, stageEye.y, stageEye.z)
  glUniform1f(renderer.stageYawLocation, 0)
  glDrawArrays(GL_TRIANGLES, renderer.centerCount.GLint,
    (renderer.commonCount - renderer.centerCount).GLsizei)
  glDrawArrays(GL_TRIANGLES,
    (renderer.commonCount + seat * renderer.backdropCount).GLint,
    renderer.backdropCount.GLsizei)
  glBindVertexArray(0)
  for unit in [GL_TEXTURE3, GL_TEXTURE2, GL_TEXTURE1, GL_TEXTURE0]:
    glActiveTexture(unit)
    glBindTexture(GL_TEXTURE_2D, 0)
  glDepthMask(GL_TRUE)
  glDepthFunc(GL_LESS)
