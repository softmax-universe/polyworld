## OpenGL toon rendering over glTF buffers.

import
  std/[sets, tables],
  opengl, vmath, chroma, pixie, gltf,
  ../../[frustums, shadowmeshes, shadows, tooncommon]

type
  ToonUniforms = object
    model, normalMatrix, view, proj: GLint
    useSkinning, jointMatrices, packedParts: GLint
    lightDirection, cameraPosition: GLint
    baseColorTexture, baseColorFactor: GLint
    emissiveTexture, emissiveFactor: GLint
    alphaCutoff, ramp: GLint
    highlightColor, shadowColor, rimColor, unlit, tint, glaze: GLint
    lightingMode, perPixelLighting, neutralMaterial: GLint
    shadowMvp0, shadowMvp1, shadowMap0, shadowMap1, shadowStep: GLint
    shadowsOn, shadowStrength: GLint
    shadowBias, shadowTexel, shadowSoftness, shadingStrength, lightLevel: GLint

  ToonDepthUniforms = object
    model, lightMvp, useSkinning, jointMatrices, packedParts: GLint
    baseColorTexture, baseColorFactor, alphaCutoff: GLint

  BackgroundUniforms = object
    sky, horizon, ground, horizonHeight: GLint

  ShadowSource = object
    primitive: Primitive
    version: uint64
    alpha: AlphaMode

  ShadowGeometry = object
    sources: seq[ShadowSource]
    primitives: seq[Primitive]

  ToonBlend = object
    node: Node
    primitive: Primitive
    pose: ptr ToonMeshPose

  ToonContext* = ref object of ToonSettings
    shader: GLuint
    uniforms: ToonUniforms
    depthShader: GLuint
    depthUniforms: ToonDepthUniforms
    backgroundShader: GLuint
    backgroundUniforms: BackgroundUniforms
    backgroundVao, backgroundVbo: GLuint
    rampTexture: GLuint
    jointMatrices: seq[Mat4]
    blended: seq[ToonBlend]
    shadowGeometry: Table[pointer, ShadowGeometry]

var blackTexture: GLuint

proc ensureBlackTexture(): GLuint =
  ## A 1x1 black texel for materials that have no emissive map.
  if blackTexture == 0:
    glGenTextures(1, blackTexture.addr)
    glBindTexture(GL_TEXTURE_2D, blackTexture)
    var pixel = [0'u8, 0, 0, 255]
    glTexImage2D(
      GL_TEXTURE_2D, 0, GL_RGBA.GLint, 1, 1, 0,
      GL_RGBA, GL_UNSIGNED_BYTE, pixel[0].addr
    )
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST.GLint)
    glBindTexture(GL_TEXTURE_2D, 0)
  blackTexture

proc uploadRamp(ctx: ToonContext, image: Image) =
  if ctx.rampTexture == 0:
    glGenTextures(1, ctx.rampTexture.addr)
  glBindTexture(GL_TEXTURE_2D, ctx.rampTexture)
  glTexImage2D(
    GL_TEXTURE_2D, 0, GL_RGBA.GLint, image.width.GLint, image.height.GLint,
    0, GL_RGBA, GL_UNSIGNED_BYTE, image.data[0].addr
  )
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE.GLint)

proc setRamp*(ctx: ToonContext, image: Image) =
  ## Replaces the ramp with any width x 1 image (red channel is read).
  ctx.uploadRamp(image)

proc newToonContext*(): ToonContext =
  result = ToonContext(
    transform: mat4(),
    lightDirection: ToonLightDirection,
    tint: color(1, 1, 1, 1),
    rimColor: color(1, 1, 1, 0),
  )
  result.setPalette(ToonPalettes[0])
  result.shader = compileShaderFiles(ToonVertSrc, ToonFragSrc)
  template loc(field: untyped, name: string) =
    result.uniforms.field = glGetUniformLocation(result.shader, name)
  loc(model, "toonModel")
  loc(normalMatrix, "toonNormalMatrix")
  loc(view, "toonView")
  loc(proj, "toonProj")
  loc(useSkinning, "toonUseSkinning")
  loc(packedParts, "toonPackedParts")
  loc(jointMatrices, "toonJointMatrices")
  loc(lightDirection, "toonLightDirection")
  loc(cameraPosition, "toonCameraPosition")
  loc(baseColorTexture, "toonBaseColorTexture")
  loc(baseColorFactor, "toonBaseColorFactor")
  loc(emissiveTexture, "toonEmissiveTexture")
  loc(emissiveFactor, "toonEmissiveFactor")
  loc(alphaCutoff, "toonAlphaCutoff")
  loc(ramp, "toonRamp")
  loc(highlightColor, "toonHighlightColor")
  loc(shadowColor, "toonShadowColor")
  loc(rimColor, "toonRimColor")
  loc(unlit, "toonUnlit")
  loc(tint, "toonTint")
  loc(glaze, "toonGlaze")
  loc(lightingMode, "toonLightingMode")
  loc(perPixelLighting, "toonPerPixelLighting")
  loc(neutralMaterial, "toonNeutralMaterial")
  loc(shadowMvp0, "toonShadowMvp0")
  loc(shadowMvp1, "toonShadowMvp1")
  loc(shadowMap0, "toonShadowMap0")
  loc(shadowMap1, "toonShadowMap1")
  loc(shadowStep, "toonShadowStep")
  loc(shadowsOn, "toonShadowsOn")
  loc(shadowStrength, "toonShadowStrength")
  loc(shadowBias, "toonShadowBias")
  loc(shadowTexel, "toonShadowTexel")
  loc(shadowSoftness, "toonShadowSoftness")
  loc(shadingStrength, "toonShadingStrength")
  loc(lightLevel, "toonLightLevel")
  result.uploadRamp(rampImage())

  result.depthShader = compileShaderFiles(ToonDepthVertSrc, ToonDepthFragSrc)
  template dloc(field: untyped, name: string) =
    result.depthUniforms.field =
      glGetUniformLocation(result.depthShader, name)
  dloc(model, "toonModel")
  dloc(lightMvp, "toonDepthLightMvp")
  dloc(useSkinning, "toonUseSkinning")
  dloc(packedParts, "toonPackedParts")
  dloc(jointMatrices, "toonJointMatrices")
  dloc(baseColorTexture, "toonBaseColorTexture")
  dloc(baseColorFactor, "toonBaseColorFactor")
  dloc(alphaCutoff, "toonAlphaCutoff")

  result.backgroundShader =
    compileShaderFiles(ToonBackgroundVertSrc, ToonBackgroundFragSrc)
  template bloc(field: untyped, name: string) =
    result.backgroundUniforms.field =
      glGetUniformLocation(result.backgroundShader, name)
  bloc(sky, "toonSkyColor")
  bloc(horizon, "toonHorizonColor")
  bloc(ground, "toonGroundColor")
  bloc(horizonHeight, "toonHorizonHeight")
  # One triangle covering clip space; the vertex shader reads only xy.
  var corners = [
    vec3(-1, -1, 0), vec3(3, -1, 0), vec3(-1, 3, 0)
  ]
  glGenVertexArrays(1, result.backgroundVao.addr)
  glBindVertexArray(result.backgroundVao)
  glGenBuffers(1, result.backgroundVbo.addr)
  glBindBuffer(GL_ARRAY_BUFFER, result.backgroundVbo)
  glBufferData(
    GL_ARRAY_BUFFER, corners.len * sizeof(Vec3), corners[0].addr,
    GL_STATIC_DRAW)
  glEnableVertexAttribArray(0)
  glVertexAttribPointer(0, 3, cGL_FLOAT, GL_FALSE, 0, nil)
  glBindVertexArray(0)

proc drawBackground*(ctx: ToonContext) =
  ## Fills the screen with the palette gradient. Draw it first; it writes
  ## no depth, so the scene lands on top.
  glUseProgram(ctx.backgroundShader)
  let u = ctx.backgroundUniforms
  glUniform4f(u.sky, ctx.skyColor.r, ctx.skyColor.g, ctx.skyColor.b, 1)
  glUniform4f(
    u.horizon, ctx.horizonColor.r, ctx.horizonColor.g, ctx.horizonColor.b, 1)
  glUniform4f(
    u.ground, ctx.groundColor.r, ctx.groundColor.g, ctx.groundColor.b, 1)
  glUniform1f(u.horizonHeight, ctx.horizonHeight)
  glDisable(GL_DEPTH_TEST)
  glDepthMask(GL_FALSE)
  glDisable(GL_BLEND)
  glDisable(GL_CULL_FACE)
  glBindVertexArray(ctx.backgroundVao)
  glDrawArrays(GL_TRIANGLES, 0, 3)
  glBindVertexArray(0)
  glDepthMask(GL_TRUE)
  glEnable(GL_DEPTH_TEST)
  glEnable(GL_CULL_FACE)
  glUseProgram(0)

proc uploadPose(
  useSkinning, jointMatrices: GLint,
  joints: openArray[Mat4]
) =
  ## Sends a prepared palette to the currently active drawing program.
  glUniform1i(useSkinning, (joints.len > 0).ord.GLint)
  if joints.len > 0:
    glUniformMatrix4fv(
      jointMatrices, joints.len.GLsizei, GL_FALSE,
      cast[ptr float32](unsafeAddr joints[0])
    )

proc drawPrimitive(
  ctx: ToonContext, root, owner: Node, primitive: Primitive,
  pose: ptr ToonMeshPose = nil
) =
  let u = ctx.uniforms
  glUniform1i(u.packedParts, (pose != nil and pose.packedParts).ord.GLint)
  var
    modelMat = if pose == nil: owner.mat else: pose.transform
    normalMat = if pose == nil: owner.mat.normalMatrix else: pose.normal
  glUniformMatrix4fv(u.model, 1, GL_FALSE, cast[ptr float32](modelMat.addr))
  glUniformMatrix3fv(
    u.normalMatrix, 1, GL_FALSE, cast[ptr float32](normalMat.addr))

  if pose == nil:
    root.skinMatricesInto(owner, ctx.jointMatrices)
    uploadPose(u.useSkinning, u.jointMatrices, ctx.jointMatrices)
  else:
    uploadPose(u.useSkinning, u.jointMatrices, pose.joints)
  glUniform1i(
    u.unlit,
    (primitive.material.unlit or
      (pose != nil and pose.unlit) or
      owner.name in ctx.unlitNodes).ord.GLint
  )

  primitive.uploadToGpu()
  glBindVertexArray(primitive.data.vertexArrayId)

  let material = primitive.material
  glActiveTexture(GL_TEXTURE0)
  glUniform1i(u.baseColorTexture, 0)
  glBindTexture(GL_TEXTURE_2D, material.data.baseColorId)
  glUniform4f(
    u.baseColorFactor, material.baseColorFactor.r, material.baseColorFactor.g,
    material.baseColorFactor.b, material.baseColorFactor.a)
  glActiveTexture(GL_TEXTURE1)
  glUniform1i(u.emissiveTexture, 1)
  let emissiveId =
    if material.data.emissiveId != 0:
      material.data.emissiveId
    else:
      ensureBlackTexture()
  glBindTexture(GL_TEXTURE_2D, emissiveId)
  glUniform3f(
    u.emissiveFactor, material.emissiveFactor.r, material.emissiveFactor.g,
    material.emissiveFactor.b)
  glActiveTexture(GL_TEXTURE2)
  glUniform1i(u.ramp, 2)
  glBindTexture(GL_TEXTURE_2D, ctx.rampTexture)

  case material.alphaMode
  of MaskAlphaMode:
    glUniform1f(u.alphaCutoff, material.alphaCutoff)
    glDisable(GL_BLEND)
    glDepthMask(GL_TRUE)
  of BlendAlphaMode:
    glUniform1f(u.alphaCutoff, -1)
    glEnable(GL_BLEND)
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
    glDepthMask(GL_FALSE)
  of OpaqueAlphaMode:
    glUniform1f(u.alphaCutoff, -1)
    glDisable(GL_BLEND)
    glDepthMask(GL_TRUE)
  if material.doubleSided:
    glDisable(GL_CULL_FACE)
  else:
    glEnable(GL_CULL_FACE)

  if primitive.indices16.len > 0:
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, primitive.data.indicesId)
    glDrawElements(
      GL_TRIANGLES, primitive.indices16.len.GLint, GL_UNSIGNED_SHORT, nil)
  elif primitive.indices32.len > 0:
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, primitive.data.indicesId)
    glDrawElements(
      GL_TRIANGLES, primitive.indices32.len.GLint, GL_UNSIGNED_INT, nil)
  else:
    glDrawArrays(GL_TRIANGLES, 0, primitive.points.len.cint)

proc drawToonMesh(
  ctx: ToonContext, root, node: Node, pose: ptr ToonMeshPose = nil
) =
  ## Retains transparent draws in the context's reusable queue.
  for primitive in node.mesh.primitives:
    if primitive.material.alphaMode == BlendAlphaMode:
      ctx.blended.add ToonBlend(node: node, primitive: primitive, pose: pose)
    else:
      ctx.drawPrimitive(root, node, primitive, pose)

proc drawToonNodes(ctx: ToonContext, root, node: Node) =
  ## Walks visible nodes without allocating a recursive closure.
  if not node.visible:
    return
  if node.mesh != nil:
    ctx.drawToonMesh(root, node)
  for child in node.nodes:
    ctx.drawToonNodes(root, child)

proc draw*(
  ctx: ToonContext,
  root: Node,
  pose: ptr ToonPose = nil
) =
  ## Draws every visible mesh under root with toon shading. Blended
  ## materials go last so they see the opaque depth.
  if pose != nil and pose.boundsValid and
    not pose.bounds.inFrustum(ctx.proj * ctx.view):
      return
  if pose == nil:
    root.updateTransforms(ctx.transform)
  glUseProgram(ctx.shader)
  let u = ctx.uniforms
  var
    viewMat = ctx.view
    projMat = ctx.proj
  glUniformMatrix4fv(u.view, 1, GL_FALSE, cast[ptr float32](viewMat.addr))
  glUniformMatrix4fv(u.proj, 1, GL_FALSE, cast[ptr float32](projMat.addr))
  glUniform3f(
    u.lightDirection, ctx.lightDirection.x, ctx.lightDirection.y,
    ctx.lightDirection.z)
  glUniform3f(
    u.cameraPosition, ctx.cameraPosition.x, ctx.cameraPosition.y,
    ctx.cameraPosition.z)
  glUniform4f(
    u.highlightColor, ctx.highlightColor.r, ctx.highlightColor.g,
    ctx.highlightColor.b, ctx.highlightColor.a)
  glUniform4f(
    u.shadowColor, ctx.shadowColor.r, ctx.shadowColor.g,
    ctx.shadowColor.b, ctx.shadowColor.a)
  glUniform4f(
    u.rimColor, ctx.rimColor.r, ctx.rimColor.g, ctx.rimColor.b,
    ctx.rimColor.a)
  glUniform4f(u.tint, ctx.tint.r, ctx.tint.g, ctx.tint.b, ctx.tint.a)
  glUniform4f(u.glaze, ctx.glaze.r, ctx.glaze.g, ctx.glaze.b, ctx.glaze.a)
  glUniform1i(u.lightingMode, ctx.lighting.ord.GLint)
  glUniform1i(u.perPixelLighting, ctx.perPixelLighting.ord.GLint)
  glUniform1i(u.neutralMaterial, ctx.neutralMaterial.ord.GLint)

  # Sun shadow map state (polyworld/shadows): characters darken where the
  # sun cannot see them and flatten with the shared shading strength.
  var
    lightMatrix0 = sunLightMvp0
    lightMatrix1 = sunLightMvp1
  glUniformMatrix4fv(
    u.shadowMvp0, 1, GL_FALSE, cast[ptr float32](lightMatrix0.addr))
  glUniformMatrix4fv(
    u.shadowMvp1, 1, GL_FALSE, cast[ptr float32](lightMatrix1.addr))
  glUniform1f(u.shadowStep, sunShadowBlend)
  glUniform1f(u.shadowsOn, if sunShadowsActive(): 1.0 else: 0.0)
  glUniform1f(u.shadowStrength, sunShadowStrength * lightLevel)
  glUniform1f(u.shadowBias, sunShadowBias)
  glUniform1f(u.shadowTexel, SunShadowTexel)
  glUniform1f(u.shadowSoftness, sunShadowSoftness)
  glUniform1f(u.shadingStrength, sunShadingStrength)
  glUniform1f(u.lightLevel, lightLevel)
  glActiveTexture(GL_TEXTURE3)
  glBindTexture(GL_TEXTURE_2D, sunShadowTextures[0])
  glUniform1i(u.shadowMap0, 3)
  glActiveTexture(GL_TEXTURE4)
  glBindTexture(GL_TEXTURE_2D, sunShadowTextures[1])
  glUniform1i(u.shadowMap1, 4)
  glActiveTexture(GL_TEXTURE0)

  glEnable(GL_DEPTH_TEST)
  glDepthFunc(GL_LEQUAL)
  glFrontFace(GL_CCW)

  ctx.blended.setLen(0)
  if pose == nil:
    ctx.drawToonNodes(root, root)
  else:
    for i in 0 ..< pose.meshCount:
      let mesh = addr pose.meshes[i]
      ctx.drawToonMesh(root, mesh.node, mesh)
  for entry in ctx.blended:
    ctx.drawPrimitive(root, entry.node, entry.primitive, entry.pose)
  ctx.blended.setLen(0)

  glDisable(GL_BLEND)
  glDepthMask(GL_TRUE)
  glEnable(GL_CULL_FACE)
  glBindVertexArray(0)
  glUseProgram(0)

proc drawSunDepthPrimitive(
  ctx: ToonContext, root, owner: Node, primitive: Primitive,
  pose: ptr ToonMeshPose = nil
) =
  let u = ctx.depthUniforms
  glUniform1i(u.packedParts, (pose != nil and pose.packedParts).ord.GLint)
  var modelMat = if pose == nil: owner.mat else: pose.transform
  glUniformMatrix4fv(u.model, 1, GL_FALSE, cast[ptr float32](modelMat.addr))
  if pose == nil:
    root.skinMatricesInto(owner, ctx.jointMatrices)
    uploadPose(u.useSkinning, u.jointMatrices, ctx.jointMatrices)
  else:
    uploadPose(u.useSkinning, u.jointMatrices, pose.joints)

  primitive.uploadToGpu()
  glBindVertexArray(primitive.data.vertexArrayId)

  let material = primitive.material
  glActiveTexture(GL_TEXTURE0)
  glUniform1i(u.baseColorTexture, 0)
  glBindTexture(GL_TEXTURE_2D, material.data.baseColorId)
  glUniform4f(
    u.baseColorFactor, material.baseColorFactor.r, material.baseColorFactor.g,
    material.baseColorFactor.b, material.baseColorFactor.a)
  if material.alphaMode == MaskAlphaMode:
    glUniform1f(u.alphaCutoff, material.alphaCutoff)
  else:
    glUniform1f(u.alphaCutoff, -1)

  if primitive.indices16.len > 0:
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, primitive.data.indicesId)
    glDrawElements(
      GL_TRIANGLES, primitive.indices16.len.GLint, GL_UNSIGNED_SHORT, nil)
  elif primitive.indices32.len > 0:
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, primitive.data.indicesId)
    glDrawElements(
      GL_TRIANGLES, primitive.indices32.len.GLint, GL_UNSIGNED_INT, nil)
  else:
    glDrawArrays(GL_TRIANGLES, 0, primitive.points.len.cint)

proc prepareShadowGeometry(ctx: ToonContext, mesh: Mesh) =
  ## Retains batched shadow buffers until source geometry or cutouts change.
  let key = cast[pointer](mesh)
  let geometry = addr ctx.shadowGeometry.mgetOrPut(key, ShadowGeometry())
  var changed = geometry.sources.len != mesh.primitives.len
  if not changed:
    for i, primitive in mesh.primitives:
      let source = geometry.sources[i]
      if source.primitive != primitive or
        source.version != primitive.geometryVersion or
        source.alpha != primitive.material.alphaMode:
          changed = true
          break
  if not changed:
    return
  for primitive in geometry.primitives:
    var owned = true
    for source in geometry.sources:
      if primitive == source.primitive:
        owned = false
        break
    if owned:
      primitive.clearFromGpu()
  geometry.sources.setLen(mesh.primitives.len)
  for i, primitive in mesh.primitives:
    geometry.sources[i] = ShadowSource(
      primitive: primitive,
      version: primitive.geometryVersion,
      alpha: primitive.material.alphaMode
    )
  geometry.primitives = mesh.shadowPrimitives()

proc drawDepthMesh(
  ctx: ToonContext, root, node: Node, pose: ptr ToonMeshPose = nil
) =
  ## Borrows cached shadow primitives without copying their sequence.
  ctx.prepareShadowGeometry(node.mesh)
  let geometry = addr ctx.shadowGeometry[cast[pointer](node.mesh)]
  for primitive in geometry.primitives:
    ctx.drawSunDepthPrimitive(root, node, primitive, pose)

proc drawDepthNodes(ctx: ToonContext, root, node: Node) =
  ## Walks visible shadow casters without allocating a recursive closure.
  if not node.visible:
    return
  if node.mesh != nil:
    ctx.drawDepthMesh(root, node)
  for child in node.nodes:
    ctx.drawDepthNodes(root, child)

proc drawSunDepth*(
  ctx: ToonContext,
  root: Node,
  pose: ptr ToonPose = nil
) =
  ## Renders every visible opaque mesh under root into the sun's depth map
  ## (polyworld/shadows), skinning included, so characters cast shadows.
  ## Call between beginSunDepthPass and endSunDepthPass with ctx.transform
  ## already posed; blended materials never cast.
  if pose != nil and pose.boundsValid and
    not pose.bounds.inFrustum(sunDepthPassMvp()):
      return
  if pose == nil:
    root.updateTransforms(ctx.transform)
  glUseProgram(ctx.depthShader)
  var lightMatrix = sunDepthPassMvp()
  glUniformMatrix4fv(
    ctx.depthUniforms.lightMvp, 1, GL_FALSE,
    cast[ptr float32](lightMatrix.addr))
  glDisable(GL_CULL_FACE)
  glEnable(GL_DEPTH_TEST)
  glDepthMask(GL_TRUE)

  if pose == nil:
    ctx.drawDepthNodes(root, root)
  else:
    for i in 0 ..< pose.meshCount:
      let mesh = addr pose.meshes[i]
      ctx.drawDepthMesh(root, mesh.node, mesh)
  glBindVertexArray(0)
