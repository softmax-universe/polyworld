## OpenGL terrain rendering and native resource management.

import
  std/[os, random, strformat, strutils, tables],
  chroma, gltf, opengl, pixie, pixie/internal, shady, vmath,
  ../../[assets, common, pathing, profiles, shadows, terrainblends, terrainmaps,
    terrainreliefs, terrainsurfaces, textures, toon]

type
  TerrainVertexArray = GLuint
  TerrainBuffer = GLuint
  TerrainCount = GLsizei

include ../../shared/terrainshaders
include ../../shared/terrainstate

type EnvLocations = object
  highlight, shadow, light, level: GLint
  ambient, bounds, ambientOn: GLint

type ShadowLocations = object
  mvp0, mvp1, map0, map1, step: GLint
  on, strength, bias, texel, softness, shading: GLint

var
  terrainProgram: GLuint
  terrainEnv, waterEnv, propEnv, treeEnv: EnvLocations
  mvpLocation, borderWidthLocation: GLint
  heightScaleLocation, edgesEnabledLocation: GLint
  texScaleLocation, blendDepthLocation, heightBlendLocation: GLint
  terrainTexturesLocation, visibilityTexLocation: GLint
  unboostedMaterialLocation: GLint
  groundMaskLocation, groundMaskEnabledLocation, groundLayersLocation: GLint
  groundRingLocation, groundRingShapeLocation: GLint
  visibilityOffsetLocation, visibilityScaleLocation: GLint
  generatedLocation, heightBlendEnabledLocation: GLint
  splatsEnabledLocation, splatAmountLocation: GLint
  splatColorsLocation, splatHeightsLocation: GLint
  splatDataLocation, blendDataLocation: GLint
  splatDataSizeLocation, blendDataSizeLocation: GLint
  waterProgram: GLuint
  waterMvpLocation, waterCameraLocation, waterNormalsLocation: GLint
  waterOffsetLocation, waterOpacityLocation: GLint
  waterHighlightOpacityLocation: GLint
  waterVisibilityTexLocation: GLint
  waterVisibilityOffsetLocation, waterVisibilityScaleLocation: GLint
  propProgram: GLuint
  propMvpLocation, propModelLocation, propVisibilityTexLocation: GLint
  propVisibilityOffsetLocation, propVisibilityScaleLocation: GLint
  propTintLocation: GLint
  treeProgram, texturedPropProgram, texturedInstantProgram: GLuint
  texturedInstantMvpLocation, texturedInstantVisibilityTexLocation: GLint
  texturedInstantModelLocation: GLint
  texturedInstantVisibilityOffsetLocation: GLint
  texturedInstantVisibilityScaleLocation: GLint
  texturedInstantTexturesLocation, texturedInstantAlphaCutoffLocation: GLint
  texturedInstantTintLocation: GLint
  texturedInstantEnv: EnvLocations
  texturedInstantShadow: ShadowLocations
  texturedPropMvpLocation, texturedPropVisibilityTexLocation: GLint
  texturedPropModelLocation: GLint
  texturedPropVisibilityOffsetLocation: GLint
  texturedPropVisibilityScaleLocation: GLint
  texturedPropTexturesLocation, texturedPropAlphaCutoffLocation: GLint
  texturedPropEnv: EnvLocations
  texturedPropShadow: ShadowLocations
  treeMvpLocation, treeVisibilityTexLocation: GLint
  treeVisibilityOffsetLocation, treeVisibilityScaleLocation: GLint
  treeTexturesLocation, treeAlphaCutoffLocation: GLint
  terrainShadow, propShadow, treeShadow: ShadowLocations
  terrainDepthVertexArray, propDepthVertexArray: GLuint
  treeDepthVertexArray: GLuint

const OpenGlShaderTarget =
  when defined(emscripten):
    glsl3WebGL
  else:
    glsl4Desktop


include ../../shared/terrainhooks
include ../../shared/terrainmeshes

proc compileStage(kind: GLenum, source, label: string): GLuint =
  ## Compiles one OpenGL shader stage or terminates with its diagnostic.
  result = glCreateShader(kind)
  var sourceArray = allocCStringArray([source])
  defer: deallocCStringArray(sourceArray)
  glShaderSource(result, 1.GLsizei, sourceArray, nil)
  glCompileShader(result)
  var ok: GLint
  glGetShaderiv(result, GL_COMPILE_STATUS, ok.addr)
  if ok == 0:
    var length: GLint
    glGetShaderiv(result, GL_INFO_LOG_LENGTH, length.addr)
    var log = newString(length)
    glGetShaderInfoLog(result, length, nil, log.cstring)
    quit(label & " shader failed:\n" & log & "\nsource:\n" & source)

proc compileProgram(vertexSource, fragmentSource: string): GLuint =
  ## Links the terrain shader program or terminates with its diagnostic.
  let
    vertexShader = compileStage(GL_VERTEX_SHADER, vertexSource, "terrain.vert")
    fragmentShader = compileStage(
      GL_FRAGMENT_SHADER,
      fragmentSource,
      "terrain.frag"
    )
  result = glCreateProgram()
  glAttachShader(result, vertexShader)
  glAttachShader(result, fragmentShader)
  glLinkProgram(result)
  # The linked executable owns its code; release the compilation objects.
  glDetachShader(result, vertexShader)
  glDetachShader(result, fragmentShader)
  glDeleteShader(vertexShader)
  glDeleteShader(fragmentShader)
  var ok: GLint
  glGetProgramiv(result, GL_LINK_STATUS, ok.addr)
  if ok == 0:
    var length: GLint
    glGetProgramiv(result, GL_INFO_LOG_LENGTH, length.addr)
    var log = newString(length)
    glGetProgramInfoLog(result, length, nil, log.cstring)
    quit("terrain program failed:\n" & log)

proc envLocations(program: GLuint): EnvLocations =
  result.highlight = glGetUniformLocation(program, "envHighlight")
  result.shadow = glGetUniformLocation(program, "envShadow")
  result.light = glGetUniformLocation(program, "envLightDirection")
  result.level = glGetUniformLocation(program, "envLightLevel")
  result.ambient = glGetUniformLocation(program, "ambientMap")
  result.bounds = glGetUniformLocation(program, "ambientBounds")
  result.ambientOn = glGetUniformLocation(program, "ambientEnabled")

proc setEnvUniforms(loc: EnvLocations) =
  ## Uploads the environment palette to the program currently in use.
  let
    h = environmentHighlight
    s = environmentShadow
    l = -environmentLight
  glUniform3f(loc.highlight, h.r, h.g, h.b)
  glUniform3f(loc.shadow, s.r, s.g, s.b)
  glUniform3f(loc.light, l.x, l.y, l.z)
  glUniform1f(loc.level, lightLevel)
  glUniform1f(loc.ambientOn, if ambientTexture != 0: 1 else: 0)
  glUniform4f(loc.bounds, ambientOrigin.x, ambientOrigin.y,
    ambientSpan.x, ambientSpan.y)
  glActiveTexture(GL_TEXTURE9)
  if ambientTexture == 0:
    # Disabled samplers still require a complete texture on macOS OpenGL.
    if ambientFallbackTexture == 0:
      glGenTextures(1, ambientFallbackTexture.addr)
      glBindTexture(GL_TEXTURE_2D, ambientFallbackTexture)
      var pixel = [255'u8, 255, 255, 255]
      glTexImage2D(
        GL_TEXTURE_2D, 0, GL_RGBA8.GLint, 1, 1, 0,
        GL_RGBA, GL_UNSIGNED_BYTE, pixel[0].addr
      )
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST.GLint)
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST.GLint)
    glBindTexture(GL_TEXTURE_2D, ambientFallbackTexture)
  else:
    glBindTexture(GL_TEXTURE_2D, ambientTexture)
  glUniform1i(loc.ambient, 9)
  glActiveTexture(GL_TEXTURE0)

proc shadowLocations(program: GLuint): ShadowLocations =
  result.mvp0 = glGetUniformLocation(program, "shadowMvp0")
  result.mvp1 = glGetUniformLocation(program, "shadowMvp1")
  result.map0 = glGetUniformLocation(program, "shadowMapPcf0")
  result.map1 = glGetUniformLocation(program, "shadowMapPcf1")
  result.step = glGetUniformLocation(program, "shadowStep")
  result.on = glGetUniformLocation(program, "shadowsOn")
  result.strength = glGetUniformLocation(program, "shadowStrength")
  result.bias = glGetUniformLocation(program, "shadowBias")
  result.texel = glGetUniformLocation(program, "shadowTexel")
  result.softness = glGetUniformLocation(program, "shadowSoftness")
  result.shading = glGetUniformLocation(program, "shadingStrength")

proc setShadowUniforms(loc: ShadowLocations) =
  ## Uploads the sun shadow state (polyworld/shadows) to the program
  ## currently in use, binding the two step maps on texture units 2 and 3.
  var
    lightMatrix0 = sunShadowMvp(0)
    lightMatrix1 = sunShadowMvp(1)
  glUniformMatrix4fv(
    loc.mvp0, 1, GL_FALSE, cast[ptr float32](lightMatrix0.addr))
  glUniformMatrix4fv(
    loc.mvp1, 1, GL_FALSE, cast[ptr float32](lightMatrix1.addr))
  glUniform1f(loc.step, sunShadowBlend)
  glUniform1f(loc.on, if sunShadowsActive(): 1.0 else: 0.0)
  glUniform1f(loc.strength, sunShadowStrength * lightLevel)
  glUniform1f(loc.bias, sunShadowBias)
  glUniform1f(loc.texel, SunShadowTexel)
  glUniform1f(loc.softness, sunShadowSoftness)
  glUniform1f(loc.shading, sunShadingStrength)
  glActiveTexture(GL_TEXTURE2)
  glBindTexture(GL_TEXTURE_2D, sunShadowTextures[0])
  glUniform1i(loc.map0, 2)
  glActiveTexture(GL_TEXTURE3)
  glBindTexture(GL_TEXTURE_2D, sunShadowTextures[1])
  glUniform1i(loc.map1, 3)
  glActiveTexture(GL_TEXTURE0)

proc uploadPropModel(model: PropModel) =
  ## Uploads one independently drawable prop model on first use.
  if model.vertexArray != 0:
    return
  doAssert propProgram != 0, "initTerrain must run before drawing props"
  glGenVertexArrays(1, model.vertexArray.addr)
  glBindVertexArray(model.vertexArray)
  glGenBuffers(1, model.vertexBuffer.addr)
  glBindBuffer(GL_ARRAY_BUFFER, model.vertexBuffer)
  glBufferData(
    GL_ARRAY_BUFFER,
    model.vertices.len * sizeof(float32),
    model.vertices[0].addr,
    GL_STATIC_DRAW
  )
  const stride = (9 * sizeof(float32)).GLsizei
  for attribute in [
    (name: "vertPos", count: 3, offset: 0),
    (name: "vertColor", count: 3, offset: 3 * sizeof(float32)),
    (name: "normal", count: 3, offset: 6 * sizeof(float32))
  ]:
    let location = glGetAttribLocation(
      propProgram,
      attribute.name.cstring
    )
    doAssert location >= 0
    glEnableVertexAttribArray(location.GLuint)
    glVertexAttribPointer(
      location.GLuint,
      attribute.count.GLint,
      cGL_FLOAT,
      GL_FALSE,
      stride,
      cast[pointer](attribute.offset)
    )
  model.vertexCount = (model.vertices.len div 9).GLsizei
  # A position-only view of the same buffer for the sun depth pass.
  glGenVertexArrays(1, model.depthVertexArray.addr)
  glBindVertexArray(model.depthVertexArray)
  glBindBuffer(GL_ARRAY_BUFFER, model.vertexBuffer)
  block:
    let location = glGetAttribLocation(sunDepthProgramId(), "vertPos")
    doAssert location >= 0
    glEnableVertexAttribArray(location.GLuint)
    glVertexAttribPointer(location.GLuint, 3, cGL_FLOAT, GL_FALSE, stride, nil)
  glBindVertexArray(0)

proc uploadTexturedPropModel(model: PropModel) =
  ## Uploads one textured prop for immediate drawing on first use: a
  ## model-space buffer in the tree layout, with a lit view and a
  ## position-plus-uv view for the cutout depth pass.
  if model.texturedVertexArray != 0:
    return
  doAssert texturedInstantProgram != 0,
    "initTerrain must run before drawing props"
  let mesh = texturedPropMesh(model)
  const stride = (12 * sizeof(float32)).GLsizei
  glGenBuffers(1, model.texturedVertexBuffer.addr)
  glBindBuffer(GL_ARRAY_BUFFER, model.texturedVertexBuffer)
  glBufferData(
    GL_ARRAY_BUFFER,
    mesh.len * sizeof(float32),
    mesh[0].addr,
    GL_STATIC_DRAW
  )
  glGenVertexArrays(1, model.texturedVertexArray.addr)
  glBindVertexArray(model.texturedVertexArray)
  for attribute in [
    (name: "vertPos", count: 3, offset: 0),
    (name: "vertUv", count: 3, offset: 3 * sizeof(float32)),
    (name: "normal", count: 3, offset: 6 * sizeof(float32)),
    (name: "vertTint", count: 3, offset: 9 * sizeof(float32))
  ]:
    let location = glGetAttribLocation(
      texturedInstantProgram, attribute.name.cstring)
    doAssert location >= 0
    glEnableVertexAttribArray(location.GLuint)
    glVertexAttribPointer(
      location.GLuint, attribute.count.GLint, cGL_FLOAT, GL_FALSE, stride,
      cast[pointer](attribute.offset))
  glGenVertexArrays(1, model.texturedDepthVertexArray.addr)
  glBindVertexArray(model.texturedDepthVertexArray)
  glBindBuffer(GL_ARRAY_BUFFER, model.texturedVertexBuffer)
  for attribute in [
    (name: "vertPos", count: 3, offset: 0),
    (name: "vertUv", count: 3, offset: 3 * sizeof(float32))
  ]:
    let location = glGetAttribLocation(
      sunCutoutProgramId(), attribute.name.cstring)
    doAssert location >= 0
    glEnableVertexAttribArray(location.GLuint)
    glVertexAttribPointer(
      location.GLuint, attribute.count.GLint, cGL_FLOAT, GL_FALSE, stride,
      cast[pointer](attribute.offset))
  glBindVertexArray(0)
  model.vertexCount = (model.vertices.len div 9).GLsizei

proc drawTexturedProp(
    model: PropModel,
    position: Vec3,
    rotation,
    propScale: float32,
    viewProjection: Mat4,
    tint: Vec4
) =
  ## Draws one textured prop immediately with the cutout texture program.
  model.uploadTexturedPropModel()
  var
    model3d = translate(position) * rotateY(rotation) *
      scale(vec3(propScale, propScale, propScale))
    transform = viewProjection * model3d
  glDisable(GL_BLEND)
  glDepthMask(GL_TRUE)
  glDisable(GL_CULL_FACE)
  glEnable(GL_DEPTH_TEST)
  glUseProgram(texturedInstantProgram)
  setEnvUniforms(texturedInstantEnv)
  setShadowUniforms(texturedInstantShadow)
  glUniformMatrix4fv(
    texturedInstantModelLocation, 1, GL_FALSE,
    cast[ptr float32](model3d.addr))
  glUniformMatrix4fv(
    texturedInstantMvpLocation, 1, GL_FALSE,
    cast[ptr float32](transform.addr))
  glUniform1f(
    texturedInstantVisibilityOffsetLocation,
    visibilitySize.float32 / 2
  )
  glUniform1f(
    texturedInstantVisibilityScaleLocation, 1.0'f / visibilitySize.float32)
  glUniform1f(texturedInstantAlphaCutoffLocation, TreeAlphaCutoff)
  glUniform4f(texturedInstantTintLocation, tint.x, tint.y, tint.z, tint.w)
  glActiveTexture(GL_TEXTURE1)
  glBindTexture(GL_TEXTURE_2D, visibilityTexture)
  glUniform1i(texturedInstantVisibilityTexLocation, 1)
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D_ARRAY, model.textureArray)
  glUniform1i(texturedInstantTexturesLocation, 0)
  glBindVertexArray(model.texturedVertexArray)
  glDrawArrays(GL_TRIANGLES, 0, model.vertexCount)
  glBindVertexArray(0)
  glUseProgram(0)

proc setPropTint(tint: Vec4) =
  ## Uploads the standalone or batched prop color multiply.
  if propTintLocation >= 0:
    glUniform4f(propTintLocation, tint.x, tint.y, tint.z, tint.w)

proc drawProp*(
    pack: PropPack,
    name: string,
    position: Vec3,
    rotation,
    propScale: float32,
    viewProjection: Mat4,
    tint = vec4(1, 1, 1, 1)
) =
  ## Draws one named prop immediately into the current framebuffer.
  if not pack.hasProp(name):
    return
  let model = pack.models[pack.names[name]]
  if model.textureArray != 0:
    drawTexturedProp(
      model, position, rotation, propScale, viewProjection, tint)
    return
  model.uploadPropModel()
  var
    model3d = translate(position) * rotateY(rotation) *
      scale(vec3(propScale, propScale, propScale))
    transform = viewProjection * model3d
  if tint.w < 1.0'f32:
    glEnable(GL_BLEND)
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
    glDepthMask(GL_FALSE)
  else:
    glDisable(GL_BLEND)
    glDepthMask(GL_TRUE)
  glDisable(GL_CULL_FACE)
  glEnable(GL_DEPTH_TEST)
  glUseProgram(propProgram)
  setEnvUniforms(propEnv)
  setShadowUniforms(propShadow)
  glUniformMatrix4fv(
    propModelLocation, 1, GL_FALSE, cast[ptr float32](model3d.addr))
  glUniformMatrix4fv(
    propMvpLocation,
    1,
    GL_FALSE,
    cast[ptr float32](transform.addr)
  )
  setPropTint(tint)
  glUniform1f(propVisibilityOffsetLocation, visibilitySize.float32 / 2)
  glUniform1f(propVisibilityScaleLocation, 1.0'f / visibilitySize.float32)
  glActiveTexture(GL_TEXTURE1)
  glBindTexture(GL_TEXTURE_2D, visibilityTexture)
  glUniform1i(propVisibilityTexLocation, 1)
  glActiveTexture(GL_TEXTURE0)
  glBindVertexArray(model.vertexArray)
  glDrawArrays(GL_TRIANGLES, 0, model.vertexCount)
  glBindVertexArray(0)
  glUseProgram(0)
  glDepthMask(GL_TRUE)
  glDisable(GL_BLEND)

## Terrain parameters

proc uploadTerrainData(texture: var Texture, values: seq[float32]): Vec2 =
  ## Uploads flat RGBA records into a portable nearest-filtered float texture.
  if values.len == 0 or values.len mod 4 != 0:
    raise newException(QuadTerrainError, "Terrain data needs complete RGBA records.")
  let count = values.len div 4
  var maximum: GLint
  glGetIntegerv(GL_MAX_TEXTURE_SIZE, maximum.addr)
  let
    width = min(min(1024, maximum.int), count)
    height = (count + width - 1) div width
  if count > 16_777_215 or height > maximum.int:
    raise newException(QuadTerrainError, "Terrain data exceeds GPU capacity.")
  var data = newSeq[float32](width * height * 4)
  copyMem(data[0].addr, unsafeAddr values[0], values.len * sizeof(float32))
  if texture == 0:
    glGenTextures(1, texture.addr)
  glBindTexture(GL_TEXTURE_2D, texture)
  glTexImage2D(
    GL_TEXTURE_2D, 0, GL_RGBA32F.GLint, width.GLsizei, height.GLsizei,
    0, GL_RGBA, cGL_FLOAT, data[0].addr
  )
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE.GLint)
  glBindTexture(GL_TEXTURE_2D, 0)
  vec2(width.float32, height.float32)

proc bindTerrainData() =
  ## Binds generated material controls and brush records for either draw path.
  glUniform1f(unboostedMaterialLocation, terrainUnboostedMaterial)
  glUniform1f(generatedLocation, if generatedTerrain: 1 else: 0)
  glUniform1f(heightBlendEnabledLocation, if terrainHeightBlending: 1 else: 0)
  glUniform1f(splatsEnabledLocation, if terrainSplats: 1 else: 0)
  glUniform1f(splatAmountLocation, clamp(terrainSplatAmount, 0.0'f, 1.0'f))
  glUniform2f(splatDataSizeLocation, splatDimensions.x, splatDimensions.y)
  glUniform2f(blendDataSizeLocation, blendDimensions.x, blendDimensions.y)
  for (unit, target, texture, location) in [
    (5, GL_TEXTURE_2D_ARRAY, splatColorArray, splatColorsLocation),
    (6, GL_TEXTURE_2D_ARRAY, splatHeightArray, splatHeightsLocation),
    (7, GL_TEXTURE_2D, splatDataTexture, splatDataLocation),
    (8, GL_TEXTURE_2D, blendDataTexture, blendDataLocation)
  ]:
    glActiveTexture((GL_TEXTURE0.int + unit).GLenum)
    glBindTexture(target, texture)
    glUniform1i(location, unit.GLint)

proc uploadTerrainVisibility*(
    values: openArray[uint8], size: int
) =
  ## Uploads one visibility value per world tile for terrain fog rendering.
  if visibilityTexture == 0:
    return
  if size <= 0 or values.len != size * size:
    raise newException(
      QuadTerrainError,
      "terrain visibility must contain one value per world tile"
    )
  glBindTexture(GL_TEXTURE_2D, visibilityTexture)
  if visibilitySize != size:
    glTexImage2D(
      GL_TEXTURE_2D,
      0,
      GL_R8.GLint,
      size.GLsizei,
      size.GLsizei,
      0,
      GL_RED,
      GL_UNSIGNED_BYTE,
      nil
    )
    visibilitySize = size
  # Fog has one byte per tile; map widths need not be multiples of four.
  # Preserve the caller's pixel-store state for subsequent image uploads.
  var unpackAlignment: GLint
  glGetIntegerv(GL_UNPACK_ALIGNMENT, unpackAlignment.addr)
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
  glTexSubImage2D(
    GL_TEXTURE_2D,
    0,
    0,
    0,
    size.GLsizei,
    size.GLsizei,
    GL_RED,
    GL_UNSIGNED_BYTE,
    unsafeAddr values[0]
  )
  glPixelStorei(GL_UNPACK_ALIGNMENT, unpackAlignment)
  glBindTexture(GL_TEXTURE_2D, 0)

proc uploadAmbientOcclusion*(
  values: openArray[uint8], size: int, origin, span: Vec2
) =
  ## Uploads sky visibility at heights 0, 1, 3 and 7, packed in RGBA channels.
  if size <= 0 or values.len != size * size * 4 or span.x <= 0 or span.y <= 0:
    raise newException(QuadTerrainError, "Invalid ambient occlusion field.")
  if ambientTexture == 0:
    glGenTextures(1, ambientTexture.addr)
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, ambientTexture)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE.GLint)
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.GLint, size.GLsizei, size.GLsizei,
    0, GL_RGBA, GL_UNSIGNED_BYTE, unsafeAddr values[0])
  glBindTexture(GL_TEXTURE_2D, 0)
  ambientOrigin = origin
  ambientSpan = span

proc clearAmbientOcclusion*() =
  ## Releases the optional map and restores unoccluded ambient lighting.
  if ambientTexture != 0:
    glDeleteTextures(1, ambientTexture.addr)
    ambientTexture = 0
  if ambientFallbackTexture != 0:
    glDeleteTextures(1, ambientFallbackTexture.addr)
    ambientFallbackTexture = 0

proc uploadGroundMask*(values: openArray[uint8], size: int) =
  ## Uploads a square two-channel coverage mask (stone, dirt) the terrain
  ## shader samples by tile position, and switches the ground path on.
  if values.len != size * size * 2:
    raise newException(
      QuadTerrainError,
      "ground mask must hold two bytes per texel"
    )
  if groundMaskTexture == 0:
    glGenTextures(1, groundMaskTexture.addr)
    glBindTexture(GL_TEXTURE_2D, groundMaskTexture)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR.GLint)
    glTexParameteri(
      GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE.GLint)
    glTexParameteri(
      GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE.GLint)
  glBindTexture(GL_TEXTURE_2D, groundMaskTexture)
  glTexImage2D(
    GL_TEXTURE_2D,
    0,
    GL_RG8.GLint,
    size.GLsizei,
    size.GLsizei,
    0,
    GL_RG,
    GL_UNSIGNED_BYTE,
    unsafeAddr values[0]
  )
  glBindTexture(GL_TEXTURE_2D, 0)
  groundMaskActive = true

proc bindGroundMask() =
  ## Sets the ground mask uniforms for one terrain draw. Units 2 and 3 are
  ## the sun shadow maps.
  glUniform1f(
    groundMaskEnabledLocation, if groundMaskActive: 1.0 else: 0.0)
  glUniform4f(
    groundLayersLocation,
    groundLayerIndices.x, groundLayerIndices.y, groundLayerIndices.z,
    groundLayerIndices.w)
  glUniform4f(
    groundRingLocation,
    groundRingValues.x, groundRingValues.y, groundRingValues.z,
    groundRingValues.w)
  glUniform3f(
    groundRingShapeLocation,
    groundRingShapeValues.x, groundRingShapeValues.y,
    groundRingShapeValues.z)
  if groundMaskTexture == 0:
    glGenTextures(1, groundMaskTexture.addr)
    glBindTexture(GL_TEXTURE_2D, groundMaskTexture)
    var pixel = [0'u8, 0]
    glTexImage2D(
      GL_TEXTURE_2D, 0, GL_RG8.GLint, 1, 1, 0,
      GL_RG, GL_UNSIGNED_BYTE, pixel[0].addr
    )
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE.GLint)
  glActiveTexture(GL_TEXTURE4)
  glBindTexture(GL_TEXTURE_2D, groundMaskTexture)
  glUniform1i(groundMaskLocation, 4)

proc initTexturedVertexArrays(batch: var TexturedBatch) =
  ## Creates the vertex arrays for one textured batch: the tinted lit draw
  ## and the position-plus-uv view for the cutout depth pass.
  const stride = (12 * sizeof(float32)).GLsizei
  glGenBuffers(1, batch.vertexBuffer.addr)
  glGenVertexArrays(1, batch.vertexArray.addr)
  glBindVertexArray(batch.vertexArray)
  glBindBuffer(GL_ARRAY_BUFFER, batch.vertexBuffer)
  for attribute in [
    (name: "vertPos", count: 3, offset: 0),
    (name: "vertUv", count: 3, offset: 3 * sizeof(float32)),
    (name: "normal", count: 3, offset: 6 * sizeof(float32)),
    (name: "vertTint", count: 3, offset: 9 * sizeof(float32))
  ]:
    let location = glGetAttribLocation(
      texturedPropProgram, attribute.name.cstring)
    doAssert location >= 0
    glEnableVertexAttribArray(location.GLuint)
    glVertexAttribPointer(
      location.GLuint, attribute.count.GLint, cGL_FLOAT, GL_FALSE, stride,
      cast[pointer](attribute.offset))
  glGenVertexArrays(1, batch.depthVertexArray.addr)
  glBindVertexArray(batch.depthVertexArray)
  glBindBuffer(GL_ARRAY_BUFFER, batch.vertexBuffer)
  for attribute in [
    (name: "vertPos", count: 3, offset: 0),
    (name: "vertUv", count: 3, offset: 3 * sizeof(float32))
  ]:
    let location = glGetAttribLocation(
      sunCutoutProgramId(), attribute.name.cstring)
    doAssert location >= 0
    glEnableVertexAttribArray(location.GLuint)
    glVertexAttribPointer(
      location.GLuint, attribute.count.GLint, cGL_FLOAT, GL_FALSE, stride,
      cast[pointer](attribute.offset))
  glBindVertexArray(0)

proc releaseTexturedBatch(batch: var TexturedBatch) =
  ## Releases an empty group's GPU resources without deleting shared textures.
  if batch.vertexBuffer != 0:
    glDeleteBuffers(1, batch.vertexBuffer.addr)
  if batch.vertexArray != 0:
    glDeleteVertexArrays(1, batch.vertexArray.addr)
  if batch.depthVertexArray != 0:
    glDeleteVertexArrays(1, batch.depthVertexArray.addr)
  batch = TexturedBatch()

proc drawTerrainRange*(
    viewProjection: Mat4,
    firstVertex, vertexCount: int,
    showEdges = false
) =
  ## Draws part of the baked terrain. Layers are emitted in order, so any run
  ## of layers is one contiguous vertex range: a game that stacks its levels
  ## top to bottom can hide everything above the player with a single offset,
  ## which is what makes a cutaway view cost nothing.
  if vertexCount <= 0:
    return
  glDisable(GL_CULL_FACE)
  glEnable(GL_DEPTH_TEST)
  glUseProgram(terrainProgram)
  setEnvUniforms(terrainEnv)
  setShadowUniforms(terrainShadow)
  mvp = viewProjection
  glUniformMatrix4fv(mvpLocation, 1, GL_FALSE, cast[ptr float32](mvp.addr))
  glUniform1f(borderWidthLocation, borderWidth)
  glUniform1f(heightScaleLocation, amplitude)
  glUniform1f(edgesEnabledLocation, if showEdges: 1.0 else: 0.0)
  glUniform1f(texScaleLocation, terrainTextureScale)
  glUniform1f(blendDepthLocation, terrainBlendDepth)
  glUniform1f(heightBlendLocation, terrainHeightBlend)
  glUniform1f(visibilityOffsetLocation, visibilitySize.float32 / 2)
  glUniform1f(visibilityScaleLocation, 1.0'f / visibilitySize.float32)
  glActiveTexture(GL_TEXTURE1)
  glBindTexture(GL_TEXTURE_2D, visibilityTexture)
  glUniform1i(visibilityTexLocation, 1)
  bindGroundMask()
  bindTerrainData()
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D_ARRAY, terrainTextureArray)
  glUniform1i(terrainTexturesLocation, 0)
  glBindVertexArray(vertexArray)
  glDrawArrays(GL_TRIANGLES, firstVertex.GLint, vertexCount.GLsizei)
  glBindVertexArray(0)
  glUseProgram(0)

proc drawTexturedMesh(
    vertexArray, textureArray: GLuint, vertexCount: int, mvp: Mat4
) =
  ## Draws one tree-layout mesh with the cutout texture program.
  var matrix = mvp
  glUseProgram(treeProgram)
  setEnvUniforms(treeEnv)
  setShadowUniforms(treeShadow)
  glUniformMatrix4fv(
    treeMvpLocation,
    1,
    GL_FALSE,
    cast[ptr float32](matrix.addr)
  )
  glUniform1f(treeVisibilityOffsetLocation, visibilitySize.float32 / 2)
  glUniform1f(
    treeVisibilityScaleLocation,
    1.0'f / visibilitySize.float32
  )
  glUniform1f(treeAlphaCutoffLocation, TreeAlphaCutoff)
  glActiveTexture(GL_TEXTURE1)
  glBindTexture(GL_TEXTURE_2D, visibilityTexture)
  glUniform1i(treeVisibilityTexLocation, 1)
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D_ARRAY, textureArray)
  glUniform1i(treeTexturesLocation, 0)
  glBindVertexArray(vertexArray)
  glDrawArrays(GL_TRIANGLES, 0, vertexCount.GLsizei)
  glBindVertexArray(0)

proc drawTexturedBatch(batch: TexturedBatch, mvp: Mat4) =
  ## Draws one textured prop batch with its per-instance tints.
  var
    matrix = mvp
    model3d = mat4()
  glUseProgram(texturedPropProgram)
  setEnvUniforms(texturedPropEnv)
  setShadowUniforms(texturedPropShadow)
  glUniformMatrix4fv(
    texturedPropModelLocation, 1, GL_FALSE,
    cast[ptr float32](model3d.addr))
  glUniformMatrix4fv(
    texturedPropMvpLocation,
    1,
    GL_FALSE,
    cast[ptr float32](matrix.addr)
  )
  glUniform1f(texturedPropVisibilityOffsetLocation, visibilitySize.float32 / 2)
  glUniform1f(
    texturedPropVisibilityScaleLocation,
    1.0'f / visibilitySize.float32
  )
  glUniform1f(texturedPropAlphaCutoffLocation, TreeAlphaCutoff)
  glActiveTexture(GL_TEXTURE1)
  glBindTexture(GL_TEXTURE_2D, visibilityTexture)
  glUniform1i(texturedPropVisibilityTexLocation, 1)
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D_ARRAY, batch.textureArray)
  glUniform1i(texturedPropTexturesLocation, 0)
  glBindVertexArray(batch.vertexArray)
  glDrawArrays(GL_TRIANGLES, 0, (batch.mesh.len div 12).GLsizei)
  glBindVertexArray(0)

proc drawTerrain*(viewProjection: Mat4, showEdges = false,
    drawGround = true, drawProps = true) {.measure.} =
  ## Opaque terrain and prop passes. Disables back-face culling itself (the
  ## gltf PBR renderer's beginFrame leaves culling on and the terrain mesh
  ## is not consistently wound) and enables the depth test.
  glDisable(GL_CULL_FACE)
  glEnable(GL_DEPTH_TEST)
  glUseProgram(terrainProgram)
  setEnvUniforms(terrainEnv)
  setShadowUniforms(terrainShadow)
  mvp = viewProjection
  glUniformMatrix4fv(mvpLocation, 1, GL_FALSE, cast[ptr float32](mvp.addr))
  glUniform1f(borderWidthLocation, borderWidth)
  glUniform1f(heightScaleLocation, amplitude)
  glUniform1f(edgesEnabledLocation, if showEdges: 1.0 else: 0.0)
  glUniform1f(texScaleLocation, terrainTextureScale)
  glUniform1f(blendDepthLocation, terrainBlendDepth)
  glUniform1f(heightBlendLocation, terrainHeightBlend)
  glUniform1f(visibilityOffsetLocation, visibilitySize.float32 / 2)
  glUniform1f(visibilityScaleLocation, 1.0'f / visibilitySize.float32)
  glActiveTexture(GL_TEXTURE1)
  glBindTexture(GL_TEXTURE_2D, visibilityTexture)
  glUniform1i(visibilityTexLocation, 1)
  bindGroundMask()
  bindTerrainData()
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D_ARRAY, terrainTextureArray)
  glUniform1i(terrainTexturesLocation, 0)
  glBindVertexArray(vertexArray)
  if drawGround:
    glDrawArrays(GL_TRIANGLES, 0, meshVertexCount.GLsizei)
  glBindVertexArray(0)

  if not drawProps:
    glUseProgram(0)
    return

  if propMesh.len > 0:
    var model3d = mat4()
    glUseProgram(propProgram)
    setEnvUniforms(propEnv)
    setShadowUniforms(propShadow)
    setPropTint(vec4(1, 1, 1, 1))
    glUniformMatrix4fv(
      propModelLocation, 1, GL_FALSE, cast[ptr float32](model3d.addr))
    glUniformMatrix4fv(
      propMvpLocation,
      1,
      GL_FALSE,
      cast[ptr float32](mvp.addr)
    )
    glUniform1f(propVisibilityOffsetLocation, visibilitySize.float32 / 2)
    glUniform1f(
      propVisibilityScaleLocation,
      1.0'f / visibilitySize.float32
    )
    glActiveTexture(GL_TEXTURE1)
    glBindTexture(GL_TEXTURE_2D, visibilityTexture)
    glUniform1i(propVisibilityTexLocation, 1)
    glBindVertexArray(propVertexArray)
    glDrawArrays(GL_TRIANGLES, 0, (propMesh.len div 9).GLsizei)
    glBindVertexArray(0)
    glActiveTexture(GL_TEXTURE0)

  if treeMesh.len > 0:
    drawTexturedMesh(
      treeVertexArray, treeTextureArray, treeMesh.len div TreeVertexSize, mvp)
  for batch in texturedBatches.mitems:
    if batch.mesh.len > 0:
      drawTexturedBatch(batch, mvp)
  glUseProgram(0)

proc waterShaderProgram*(): GLuint =
  ## The compiled water program, for setting an override shader's own uniforms.
  waterProgram

proc drawWater*(
    viewProjection: Mat4,
    cameraEye: Vec3,
    offset = vec2(0),
    opacity = 0.55'f,
    highlightOpacity = 0.45'f,
    firstVertex = 0,
    vertexCount = -1
) =
  ## Draws water with a world-space offset and base plus highlight opacity.
  ## Call after all opaque drawing. The default range is all water; waterLayerRanges
  ## gives one layer's.
  let count = if vertexCount < 0: waterMesh.len div 6 - firstVertex else: vertexCount
  if count <= 0:
    return
  glDisable(GL_CULL_FACE)
  glUseProgram(waterProgram)
  setEnvUniforms(waterEnv)
  mvp = viewProjection
  glUniformMatrix4fv(waterMvpLocation, 1, GL_FALSE, cast[ptr float32](mvp.addr))
  glUniform3f(waterCameraLocation, cameraEye.x, cameraEye.y, cameraEye.z)
  glUniform2f(waterOffsetLocation, offset.x, offset.y)
  glUniform1f(waterOpacityLocation, opacity)
  glUniform1f(waterHighlightOpacityLocation, highlightOpacity)
  glUniform1f(waterVisibilityOffsetLocation, visibilitySize.float32 / 2)
  glUniform1f(
    waterVisibilityScaleLocation,
    1.0'f / visibilitySize.float32
  )
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D_ARRAY, waterNormalTextureArray)
  glUniform1i(waterNormalsLocation, 0)
  glActiveTexture(GL_TEXTURE1)
  glBindTexture(GL_TEXTURE_2D, visibilityTexture)
  glUniform1i(waterVisibilityTexLocation, 1)
  glEnable(GL_BLEND)
  glBlendFunc(if waterPremultipliedAlpha: GL_ONE else: GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  glDepthMask(GL_FALSE)
  glBindVertexArray(waterVertexArray)
  glDrawArrays(GL_TRIANGLES, firstVertex.GLint, count.GLsizei)
  glBindVertexArray(0)
  glDepthMask(GL_TRUE)
  glDisable(GL_BLEND)
  glActiveTexture(GL_TEXTURE0)
  glUseProgram(0)

proc drawTerrainSunDepth*(firstVertex = 0, vertexCount = -1) {.measure.} =
  ## Renders every baked caster — terrain, props, trees — into the sun's
  ## depth map. Call between beginSunDepthPass and endSunDepthPass, with the
  ## same vertex range the main pass will draw (a cutaway view should not
  ## receive shadows from hidden floors). The default range is everything.
  let terrainCount =
    if vertexCount < 0: meshVertexCount - firstVertex else: vertexCount
  if terrainCount > 0:
    bindSunDepth(sunDepthPassMvp())
    glBindVertexArray(terrainDepthVertexArray)
    glDrawArrays(GL_TRIANGLES, firstVertex.GLint, terrainCount.GLsizei)
  if propMesh.len > 0:
    bindSunDepth(sunDepthPassMvp())
    glBindVertexArray(propDepthVertexArray)
    glDrawArrays(GL_TRIANGLES, 0, (propMesh.len div 9).GLsizei)
  if treeMesh.len > 0:
    bindSunCutoutDepth(sunDepthPassMvp(), TreeAlphaCutoff)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D_ARRAY, treeTextureArray)
    glBindVertexArray(treeDepthVertexArray)
    glDrawArrays(GL_TRIANGLES, 0, (treeMesh.len div TreeVertexSize).GLsizei)
  for batch in texturedBatches.mitems:
    if batch.mesh.len == 0:
      continue
    bindSunCutoutDepth(sunDepthPassMvp(), TreeAlphaCutoff)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D_ARRAY, batch.textureArray)
    glBindVertexArray(batch.depthVertexArray)
    glDrawArrays(GL_TRIANGLES, 0, (batch.mesh.len div 12).GLsizei)
  glBindVertexArray(0)

proc drawPropSunDepth*(
    pack: PropPack,
    name: string,
    position: Vec3,
    rotation,
    propScale: float32
) =
  ## Renders one standalone prop into the sun's depth map; the depth-pass
  ## twin of drawProp for props drawn per frame instead of baked.
  if not pack.hasProp(name):
    return
  let
    model = pack.models[pack.names[name]]
    transform = sunDepthPassMvp() * translate(position) *
      rotateY(rotation) * scale(vec3(propScale, propScale, propScale))
  if model.textureArray != 0:
    model.uploadTexturedPropModel()
    bindSunCutoutDepth(transform, TreeAlphaCutoff)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D_ARRAY, model.textureArray)
    glBindVertexArray(model.texturedDepthVertexArray)
    glDrawArrays(GL_TRIANGLES, 0, model.vertexCount)
    glBindVertexArray(0)
    return
  model.uploadPropModel()
  bindSunDepth(transform)
  glBindVertexArray(model.depthVertexArray)
  glDrawArrays(GL_TRIANGLES, 0, model.vertexCount)
  glBindVertexArray(0)
proc releasePropModel(model: PropModel) =
  ## Releases all OpenGL geometry owned by one independently drawable prop.
  glDeleteBuffers(1, model.vertexBuffer.addr)
  glDeleteBuffers(1, model.texturedVertexBuffer.addr)
  glDeleteVertexArrays(1, model.vertexArray.addr)
  glDeleteVertexArrays(1, model.depthVertexArray.addr)
  glDeleteVertexArrays(1, model.texturedVertexArray.addr)
  glDeleteVertexArrays(1, model.texturedDepthVertexArray.addr)
  model.vertexBuffer = 0
  model.texturedVertexBuffer = 0
  model.vertexArray = 0
  model.depthVertexArray = 0
  model.texturedVertexArray = 0
  model.texturedDepthVertexArray = 0

proc uploadTexturedBatch(batch: var TexturedBatch) =
  ## Uploads one changed textured batch while retaining its vertex layout.
  if batch.vertexBuffer == 0:
    initTexturedVertexArrays(batch)
  glBindBuffer(GL_ARRAY_BUFFER, batch.vertexBuffer)
  glBufferData(
    GL_ARRAY_BUFFER,
    batch.mesh.len * sizeof(float32),
    batch.mesh[0].addr,
    GL_STATIC_DRAW
  )

proc updateTerrainMeshRange(offset, count: int) =
  ## Uploads changed edge flags in one contiguous range of ground vertices.
  glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer)
  glBufferSubData(
    GL_ARRAY_BUFFER,
    offset * sizeof(float32),
    count * sizeof(float32),
    mesh[offset].addr
  )

proc uploadTerrainMesh() =
  ## Uploads the baked vertex data into its OpenGL buffer.
  if mesh.len == 0:
    return
  glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer)
  glBufferData(
    GL_ARRAY_BUFFER,
    mesh.len * sizeof(float32),
    mesh[0].addr,
    GL_DYNAMIC_DRAW
  )

proc uploadWaterMesh() =
  ## Uploads the baked vertex data into its OpenGL buffer.
  if waterMesh.len == 0:
    return
  glBindBuffer(GL_ARRAY_BUFFER, waterVertexBuffer)
  glBufferData(
    GL_ARRAY_BUFFER,
    waterMesh.len * sizeof(float32),
    waterMesh[0].addr,
    GL_DYNAMIC_DRAW
  )

proc uploadTreeMesh() =
  ## Uploads the baked vertex data into its OpenGL buffer.
  if treeMesh.len == 0:
    return
  glBindBuffer(GL_ARRAY_BUFFER, treeVertexBuffer)
  glBufferData(
    GL_ARRAY_BUFFER,
    treeMesh.len * sizeof(float32),
    treeMesh[0].addr,
    GL_STATIC_DRAW
  )

proc uploadPropMesh() =
  ## Uploads the baked vertex data into its OpenGL buffer.
  if propMesh.len == 0:
    return
  glBindBuffer(GL_ARRAY_BUFFER, propVertexBuffer)
  glBufferData(
    GL_ARRAY_BUFFER,
    propMesh.len * sizeof(float32),
    propMesh[0].addr,
    GL_STATIC_DRAW
  )

proc initTerrainPrograms() =
  ## Compiles Shady programs and caches their OpenGL uniform locations.
  terrainProgram = compileProgram(
    toShader(terrainVert, OpenGlShaderTarget, shaderVertex),
    toShader(terrainFrag, OpenGlShaderTarget, shaderFragment)
  )
  mvpLocation = glGetUniformLocation(terrainProgram, "mvp")
  terrainEnv = envLocations(terrainProgram)
  terrainShadow = shadowLocations(terrainProgram)
  borderWidthLocation = glGetUniformLocation(
    terrainProgram,
    "borderWidthUniform"
  )
  heightScaleLocation = glGetUniformLocation(terrainProgram, "heightScale")
  edgesEnabledLocation = glGetUniformLocation(terrainProgram, "edgesEnabled")
  texScaleLocation = glGetUniformLocation(terrainProgram, "texScale")
  blendDepthLocation = glGetUniformLocation(terrainProgram, "blendDepth")
  heightBlendLocation = glGetUniformLocation(terrainProgram, "heightBlend")
  generatedLocation = glGetUniformLocation(terrainProgram, "generatedEnabled")
  heightBlendEnabledLocation = glGetUniformLocation(
    terrainProgram, "heightBlendEnabled"
  )
  splatsEnabledLocation = glGetUniformLocation(terrainProgram, "splatsEnabled")
  splatAmountLocation = glGetUniformLocation(terrainProgram, "splatAmount")
  splatColorsLocation = glGetUniformLocation(terrainProgram, "splatColors")
  splatHeightsLocation = glGetUniformLocation(terrainProgram, "splatHeights")
  splatDataLocation = glGetUniformLocation(terrainProgram, "splatData")
  blendDataLocation = glGetUniformLocation(terrainProgram, "blendData")
  splatDataSizeLocation = glGetUniformLocation(terrainProgram, "splatDataSize")
  blendDataSizeLocation = glGetUniformLocation(terrainProgram, "blendDataSize")
  terrainTexturesLocation = glGetUniformLocation(
    terrainProgram,
    "terrainTextures"
  )
  unboostedMaterialLocation = glGetUniformLocation(
    terrainProgram, "unboostedMaterial"
  )
  visibilityTexLocation = glGetUniformLocation(
    terrainProgram,
    "visibilityTex"
  )
  groundMaskLocation = glGetUniformLocation(terrainProgram, "groundMask")
  groundMaskEnabledLocation = glGetUniformLocation(
    terrainProgram,
    "groundMaskEnabled"
  )
  groundLayersLocation = glGetUniformLocation(terrainProgram, "groundLayers")
  groundRingLocation = glGetUniformLocation(terrainProgram, "groundRing")
  groundRingShapeLocation = glGetUniformLocation(
    terrainProgram,
    "groundRingShape"
  )
  visibilityOffsetLocation = glGetUniformLocation(
    terrainProgram,
    "visibilityOffset"
  )
  visibilityScaleLocation = glGetUniformLocation(
    terrainProgram,
    "visibilityScale"
  )
  waterProgram =
    if waterShaderOverride.vertex.len > 0:
      compileProgram(waterShaderOverride.vertex, waterShaderOverride.fragment)
    else:
      compileProgram(
        toShader(waterVert, OpenGlShaderTarget, shaderVertex),
        toShader(waterFrag, OpenGlShaderTarget, shaderFragment)
      )
  waterMvpLocation = glGetUniformLocation(waterProgram, "mvp")
  waterEnv = envLocations(waterProgram)
  waterCameraLocation = glGetUniformLocation(waterProgram, "cameraPos")
  waterNormalsLocation = glGetUniformLocation(waterProgram, "waterNormals")
  waterOffsetLocation = glGetUniformLocation(waterProgram, "waterOffset")
  waterOpacityLocation = glGetUniformLocation(waterProgram, "waterOpacity")
  waterHighlightOpacityLocation = glGetUniformLocation(
    waterProgram,
    "waterHighlightOpacity"
  )
  waterVisibilityTexLocation = glGetUniformLocation(
    waterProgram,
    "visibilityTex"
  )
  waterVisibilityOffsetLocation = glGetUniformLocation(
    waterProgram,
    "visibilityOffset"
  )
  waterVisibilityScaleLocation = glGetUniformLocation(
    waterProgram,
    "visibilityScale"
  )

  propProgram = compileProgram(
    toShader(propVert, OpenGlShaderTarget, shaderVertex),
    toShader(propFrag, OpenGlShaderTarget, shaderFragment)
  )
  propMvpLocation = glGetUniformLocation(propProgram, "mvp")
  propModelLocation = glGetUniformLocation(propProgram, "propModel")
  propTintLocation = glGetUniformLocation(propProgram, "propTint")
  propEnv = envLocations(propProgram)
  propShadow = shadowLocations(propProgram)
  propVisibilityTexLocation = glGetUniformLocation(
    propProgram,
    "visibilityTex"
  )
  propVisibilityOffsetLocation = glGetUniformLocation(
    propProgram,
    "visibilityOffset"
  )
  propVisibilityScaleLocation = glGetUniformLocation(
    propProgram,
    "visibilityScale"
  )

  treeProgram = compileProgram(
    toShader(treeVert, OpenGlShaderTarget, shaderVertex),
    toShader(treeFrag, OpenGlShaderTarget, shaderFragment)
  )
  treeMvpLocation = glGetUniformLocation(treeProgram, "mvp")
  treeEnv = envLocations(treeProgram)
  treeShadow = shadowLocations(treeProgram)
  treeVisibilityTexLocation = glGetUniformLocation(
    treeProgram,
    "visibilityTex"
  )
  treeVisibilityOffsetLocation = glGetUniformLocation(
    treeProgram,
    "visibilityOffset"
  )
  treeVisibilityScaleLocation = glGetUniformLocation(
    treeProgram,
    "visibilityScale"
  )
  texturedPropProgram = compileProgram(
    toShader(texturedPropVert, OpenGlShaderTarget, shaderVertex),
    toShader(texturedPropFrag, OpenGlShaderTarget, shaderFragment)
  )
  texturedPropMvpLocation = glGetUniformLocation(texturedPropProgram, "mvp")
  texturedPropModelLocation = glGetUniformLocation(
    texturedPropProgram, "propModel")
  texturedPropEnv = envLocations(texturedPropProgram)
  texturedPropShadow = shadowLocations(texturedPropProgram)
  texturedPropVisibilityTexLocation = glGetUniformLocation(
    texturedPropProgram, "visibilityTex")
  texturedPropVisibilityOffsetLocation = glGetUniformLocation(
    texturedPropProgram, "visibilityOffset")
  texturedPropVisibilityScaleLocation = glGetUniformLocation(
    texturedPropProgram, "visibilityScale")
  texturedPropTexturesLocation = glGetUniformLocation(
    texturedPropProgram, "treeTextures")
  texturedPropAlphaCutoffLocation = glGetUniformLocation(
    texturedPropProgram, "treeAlphaCutoff")
  texturedInstantProgram = compileProgram(
    toShader(texturedPropVert, OpenGlShaderTarget, shaderVertex),
    toShader(texturedInstantFrag, OpenGlShaderTarget, shaderFragment)
  )
  texturedInstantMvpLocation = glGetUniformLocation(
    texturedInstantProgram, "mvp")
  texturedInstantModelLocation = glGetUniformLocation(
    texturedInstantProgram, "propModel")
  texturedInstantEnv = envLocations(texturedInstantProgram)
  texturedInstantShadow = shadowLocations(texturedInstantProgram)
  texturedInstantVisibilityTexLocation = glGetUniformLocation(
    texturedInstantProgram, "visibilityTex")
  texturedInstantVisibilityOffsetLocation = glGetUniformLocation(
    texturedInstantProgram, "visibilityOffset")
  texturedInstantVisibilityScaleLocation = glGetUniformLocation(
    texturedInstantProgram, "visibilityScale")
  texturedInstantTexturesLocation = glGetUniformLocation(
    texturedInstantProgram, "treeTextures")
  texturedInstantAlphaCutoffLocation = glGetUniformLocation(
    texturedInstantProgram, "treeAlphaCutoff")
  texturedInstantTintLocation = glGetUniformLocation(
    texturedInstantProgram, "propTint")
  treeTexturesLocation = glGetUniformLocation(treeProgram, "treeTextures")
  treeAlphaCutoffLocation = glGetUniformLocation(
    treeProgram,
    "treeAlphaCutoff"
  )


proc initTerrainBuffers() =
  ## Creates OpenGL buffers and vertex arrays for each terrain mesh layout.
  glGenVertexArrays(1, vertexArray.addr)
  glBindVertexArray(vertexArray)
  glGenBuffers(1, vertexBuffer.addr)
  glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer)
  block:
    const stride = (TerrainVertexSize * sizeof(float32)).GLsizei
    let positionLocation = glGetAttribLocation(terrainProgram, "vertPos")
    doAssert positionLocation >= 0
    glEnableVertexAttribArray(positionLocation.GLuint)
    glVertexAttribPointer(
      positionLocation.GLuint,
      3,
      cGL_FLOAT,
      GL_FALSE,
      stride,
      nil
    )
    let edgeMaskLocation = glGetAttribLocation(terrainProgram, "edgeMask")
    doAssert edgeMaskLocation >= 0
    glEnableVertexAttribArray(edgeMaskLocation.GLuint)
    glVertexAttribPointer(
      edgeMaskLocation.GLuint, 1, cGL_FLOAT, GL_FALSE, stride,
      cast[pointer](3 * sizeof(float32))
    )
    let normalLocation = glGetAttribLocation(terrainProgram, "normal")
    doAssert normalLocation >= 0
    glEnableVertexAttribArray(normalLocation.GLuint)
    glVertexAttribPointer(
      normalLocation.GLuint, 3, cGL_FLOAT, GL_FALSE, stride,
      cast[pointer](4 * sizeof(float32))
    )
    let tileColorLocation = glGetAttribLocation(terrainProgram, "tileColor")
    doAssert tileColorLocation >= 0
    glEnableVertexAttribArray(tileColorLocation.GLuint)
    glVertexAttribPointer(
      tileColorLocation.GLuint, 3, cGL_FLOAT, GL_FALSE, stride,
      cast[pointer](7 * sizeof(float32))
    )
    let materialsLocation = glGetAttribLocation(terrainProgram, "materials")
    doAssert materialsLocation >= 0
    glEnableVertexAttribArray(materialsLocation.GLuint)
    glVertexAttribPointer(
      materialsLocation.GLuint, 4, cGL_FLOAT, GL_FALSE, stride,
      cast[pointer](10 * sizeof(float32))
    )
    let cornerWeightLocation = glGetAttribLocation(
      terrainProgram,
      "cornerWeight"
    )
    doAssert cornerWeightLocation >= 0
    glEnableVertexAttribArray(cornerWeightLocation.GLuint)
    glVertexAttribPointer(
      cornerWeightLocation.GLuint, 4, cGL_FLOAT, GL_FALSE, stride,
      cast[pointer](14 * sizeof(float32))
    )
    let splatRangeLocation = glGetAttribLocation(terrainProgram, "splatRange")
    doAssert splatRangeLocation >= 0
    glEnableVertexAttribArray(splatRangeLocation.GLuint)
    glVertexAttribPointer(
      splatRangeLocation.GLuint, 3, cGL_FLOAT, GL_FALSE, stride,
      cast[pointer](18 * sizeof(float32))
    )

  glGenVertexArrays(1, propVertexArray.addr)
  glBindVertexArray(propVertexArray)
  glGenBuffers(1, propVertexBuffer.addr)
  glBindBuffer(GL_ARRAY_BUFFER, propVertexBuffer)
  block:
    const stride = (9 * sizeof(float32)).GLsizei
    let positionLocation = glGetAttribLocation(propProgram, "vertPos")
    doAssert positionLocation >= 0
    glEnableVertexAttribArray(positionLocation.GLuint)
    glVertexAttribPointer(
      positionLocation.GLuint,
      3,
      cGL_FLOAT,
      GL_FALSE,
      stride,
      nil
    )
    let colorLocation = glGetAttribLocation(propProgram, "vertColor")
    doAssert colorLocation >= 0
    glEnableVertexAttribArray(colorLocation.GLuint)
    glVertexAttribPointer(
      colorLocation.GLuint, 3, cGL_FLOAT, GL_FALSE, stride,
      cast[pointer](3 * sizeof(float32))
    )
    let normalLocation = glGetAttribLocation(propProgram, "normal")
    doAssert normalLocation >= 0
    glEnableVertexAttribArray(normalLocation.GLuint)
    glVertexAttribPointer(
      normalLocation.GLuint, 3, cGL_FLOAT, GL_FALSE, stride,
      cast[pointer](6 * sizeof(float32))
    )

  glGenVertexArrays(1, treeVertexArray.addr)
  glBindVertexArray(treeVertexArray)
  glGenBuffers(1, treeVertexBuffer.addr)
  glBindBuffer(GL_ARRAY_BUFFER, treeVertexBuffer)
  block:
    const stride = (TreeVertexSize * sizeof(float32)).GLsizei
    let positionLocation = glGetAttribLocation(treeProgram, "vertPos")
    doAssert positionLocation >= 0
    glEnableVertexAttribArray(positionLocation.GLuint)
    glVertexAttribPointer(
      positionLocation.GLuint,
      3,
      cGL_FLOAT,
      GL_FALSE,
      stride,
      nil
    )
    let uvLocation = glGetAttribLocation(treeProgram, "vertUv")
    doAssert uvLocation >= 0
    glEnableVertexAttribArray(uvLocation.GLuint)
    glVertexAttribPointer(
      uvLocation.GLuint, 3, cGL_FLOAT, GL_FALSE, stride,
      cast[pointer](3 * sizeof(float32))
    )
    let normalLocation = glGetAttribLocation(treeProgram, "normal")
    doAssert normalLocation >= 0
    glEnableVertexAttribArray(normalLocation.GLuint)
    glVertexAttribPointer(
      normalLocation.GLuint, 3, cGL_FLOAT, GL_FALSE, stride,
      cast[pointer](6 * sizeof(float32))
    )
    let brightnessLocation = glGetAttribLocation(treeProgram, "vertBrightness")
    doAssert brightnessLocation >= 0
    glEnableVertexAttribArray(brightnessLocation.GLuint)
    glVertexAttribPointer(
      brightnessLocation.GLuint, 1, cGL_FLOAT, GL_FALSE, stride,
      cast[pointer](9 * sizeof(float32))
    )

  glGenVertexArrays(1, waterVertexArray.addr)
  glBindVertexArray(waterVertexArray)
  glGenBuffers(1, waterVertexBuffer.addr)
  glBindBuffer(GL_ARRAY_BUFFER, waterVertexBuffer)
  block:
    const stride = (6 * sizeof(float32)).GLsizei
    let positionLocation = glGetAttribLocation(waterProgram, "vertPos")
    doAssert positionLocation >= 0
    glEnableVertexAttribArray(positionLocation.GLuint)
    glVertexAttribPointer(
      positionLocation.GLuint,
      3,
      cGL_FLOAT,
      GL_FALSE,
      stride,
      nil
    )
    let normalLocation = glGetAttribLocation(waterProgram, "normal")
    # An override shader may ignore the normal, and GLSL drops unused attributes.
    if normalLocation >= 0:
      glEnableVertexAttribArray(normalLocation.GLuint)
      glVertexAttribPointer(
        normalLocation.GLuint, 3, cGL_FLOAT, GL_FALSE, stride,
        cast[pointer](3 * sizeof(float32))
      )

  # Sun depth pass vertex arrays: the same vertex buffers, but only the
  # position attribute (plus uv and layer for the tree cutout).
  glGenVertexArrays(1, terrainDepthVertexArray.addr)
  glBindVertexArray(terrainDepthVertexArray)
  glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer)
  block:
    const stride = (TerrainVertexSize * sizeof(float32)).GLsizei
    let positionLocation = glGetAttribLocation(
      sunDepthProgramId(), "vertPos")
    doAssert positionLocation >= 0
    glEnableVertexAttribArray(positionLocation.GLuint)
    glVertexAttribPointer(
      positionLocation.GLuint, 3, cGL_FLOAT, GL_FALSE, stride, nil)
  glGenVertexArrays(1, propDepthVertexArray.addr)
  glBindVertexArray(propDepthVertexArray)
  glBindBuffer(GL_ARRAY_BUFFER, propVertexBuffer)
  block:
    const stride = (9 * sizeof(float32)).GLsizei
    let positionLocation = glGetAttribLocation(
      sunDepthProgramId(), "vertPos")
    doAssert positionLocation >= 0
    glEnableVertexAttribArray(positionLocation.GLuint)
    glVertexAttribPointer(
      positionLocation.GLuint, 3, cGL_FLOAT, GL_FALSE, stride, nil)
  glGenVertexArrays(1, treeDepthVertexArray.addr)
  glBindVertexArray(treeDepthVertexArray)
  glBindBuffer(GL_ARRAY_BUFFER, treeVertexBuffer)
  block:
    const stride = (TreeVertexSize * sizeof(float32)).GLsizei
    let positionLocation = glGetAttribLocation(
      sunCutoutProgramId(), "vertPos")
    doAssert positionLocation >= 0
    glEnableVertexAttribArray(positionLocation.GLuint)
    glVertexAttribPointer(
      positionLocation.GLuint, 3, cGL_FLOAT, GL_FALSE, stride, nil)
    let uvLocation = glGetAttribLocation(sunCutoutProgramId(), "vertUv")
    doAssert uvLocation >= 0
    glEnableVertexAttribArray(uvLocation.GLuint)
    glVertexAttribPointer(
      uvLocation.GLuint, 3, cGL_FLOAT, GL_FALSE, stride,
      cast[pointer](3 * sizeof(float32))
    )
  glBindVertexArray(0)


proc initTerrainVisibility() =
  ## Allocates the initial tile visibility map.
  visibilitySize = GridTiles
  glGenTextures(1, visibilityTexture.addr)
  glBindTexture(GL_TEXTURE_2D, visibilityTexture)
  glTexImage2D(
    GL_TEXTURE_2D,
    0,
    GL_R8.GLint,
    GridTiles,
    GridTiles,
    0,
    GL_RED,
    GL_UNSIGNED_BYTE,
    nil
  )
  glTexParameteri(
    GL_TEXTURE_2D,
    GL_TEXTURE_MIN_FILTER,
    GL_LINEAR.GLint
  )
  glTexParameteri(
    GL_TEXTURE_2D,
    GL_TEXTURE_MAG_FILTER,
    GL_LINEAR.GLint
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
  glBindTexture(GL_TEXTURE_2D, 0)
