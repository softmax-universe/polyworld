## Immediate GPU toon rendering within the engine's current render pass.

import
  std/[sets, tables],
  chroma, pixie, vmath, gltf,
  common, meshes,
  ../../[frustums, shadowmeshes, shadows, tooncommon]

type
  ShadowSource = object
    primitive: gltf.Primitive
    version: uint64
    alpha: AlphaMode

  ShadowGeometry = object
    sources: seq[ShadowSource]
    primitives: seq[gltf.Primitive]

  ToonBlend = object
    node: Node
    primitive: gltf.Primitive
    pose: ptr ToonMeshPose

  ToonContext* = ref object of ToonSettings
    shader, depthShader, backgroundShader: ShaderProgram
    when defined(useDirectX) or defined(useVulkan): solidDepth: ShaderProgram
    backgroundVertices: VertexBuffer
    rampTexture: GpuImage
    jointMatrices: seq[Mat4]
    blended: seq[ToonBlend]
    shadowGeometry: Table[pointer, ShadowGeometry]

proc setRamp*(ctx: ToonContext, image: Image) =
  ## Replaces the shading ramp while preserving linear filtering.
  ctx.rampTexture.destroy()
  ctx.rampTexture = newTexture(image)
  ctx.rampTexture.setPassSampling(linear = true)

proc newToonContext*(): ToonContext =
  ## Builds Shady-generated programs for the engine's active graphics device.
  result = ToonContext(
    transform: mat4(),
    lightDirection: ToonLightDirection,
    tint: color(1, 1, 1, 1),
    rimColor: color(1, 1, 1, 0),
    shader: newProgram(ToonVertSrc, ToonFragSrc, ModelLayout),
    depthShader: newProgram(ToonDepthVertSrc, ToonDepthFragSrc, ModelLayout),
    backgroundShader: newProgram(ToonBackgroundVertSrc,
      ToonBackgroundFragSrc, VertexLayout(stride: sizeof(Vec3),
      attributes: @[VertexAttribute(name: "vertexPosition", format: Float3)])),
    backgroundVertices: newBuffer([
      vec3(-1, -1, 0), vec3(3, -1, 0), vec3(-1, 3, 0)
    ])
  )
  when defined(useDirectX) or defined(useVulkan):
    result.solidDepth = newProgram(ToonDepthVertSrc, "", ModelLayout)
  result.setPalette(ToonPalettes[0])
  result.setRamp(rampImage())

proc drawBackground*(ctx: ToonContext) =
  ## Fills the current target without changing its stored scene depth.
  let shader = ctx.backgroundShader
  shader.setUniform("toonSkyColor", ctx.skyColor.colorVector)
  shader.setUniform("toonHorizonColor", ctx.horizonColor.colorVector)
  shader.setUniform("toonGroundColor", ctx.groundColor.colorVector)
  shader.setUniform("toonHorizonHeight", ctx.horizonHeight)
  common.draw(shader, ctx.backgroundVertices, 3)

proc uploadPose(program: ShaderProgram, joints: openArray[Mat4]) =
  ## Packs the skin palette using Shady's reflected native uniform layout.
  program.setUniform("toonUseSkinning", joints.len > 0)
  if joints.len > 128:
    raise newException(GltfError, "Toon supports at most 128 skin joints.")
  if joints.len > 0:
    when defined(useDirectX) or defined(useVulkan):
      program.setUniform("toonJointMatrices", joints)
    else:
      var palette: array[128, Mat4]
      for i, joint in joints: palette[i] = joint
      program.setUniform("toonJointMatrices", palette)

proc modelUniforms(ctx: ToonContext, program: ShaderProgram,
    root, owner: Node, pose: ptr ToonMeshPose) =
  ## Shares the exact posed model and skin matrices across color and depth.
  program.setUniform("toonPackedParts", pose != nil and pose.packedParts)
  let transform = if pose == nil: owner.mat else: pose.transform
  program.setUniform("toonModel", transform)
  program.setUniform("toonNormalMatrix",
    if pose == nil: owner.mat.normalMatrix else: pose.normal)
  if pose == nil:
    root.skinMatricesInto(owner, ctx.jointMatrices)
    program.uploadPose(ctx.jointMatrices)
  else:
    program.uploadPose(pose.joints)

proc drawPrimitive(ctx: ToonContext, root, owner: Node,
    primitive: gltf.Primitive, pose: ptr ToonMeshPose = nil) =
  ## Draws one opaque, cutout, or transparent material with retained buffers.
  let
    shader = ctx.shader
    material = primitive.material
    textures = modelMeshCache.textures(material)
    geometry = modelMeshCache.geometry(primitive)
  ctx.modelUniforms(shader, root, owner, pose)
  shader.setUniform("toonUnlit", material.unlit or
    (pose != nil and pose.unlit) or owner.name in ctx.unlitNodes)
  shader.setUniform("toonBaseColorFactor", material.baseColorFactor.colorVector)
  shader.setUniform("toonEmissiveFactor", vec3(material.emissiveFactor.r,
    material.emissiveFactor.g, material.emissiveFactor.b))
  shader.setUniform("toonAlphaCutoff",
    if material.alphaMode == MaskAlphaMode: material.alphaCutoff else: -1.0'f)
  shader.bindTexture("toonBaseColorTexture", textures.baseColor)
  shader.bindTexture("toonEmissiveTexture", textures.emissive)
  shader.bindTexture("toonRamp", ctx.rampTexture)
  var blend = Opaque
  if material.alphaMode == BlendAlphaMode:
    when defined(useMetal4) or defined(useDirectX) or defined(useVulkan):
      blend = AlphaBlend
    else:
      blend = StraightAlpha
  shader.drawGeometry(geometry, DrawState(
    depthTest: true,
    depthWrite: material.alphaMode != BlendAlphaMode,
    cull: if material.doubleSided: CullNone else: CullBack,
    blend: blend
  ))

proc drawToonMesh(ctx: ToonContext, root, node: Node,
    pose: ptr ToonMeshPose = nil) =
  ## Defers transparent primitives until opaque geometry has written depth.
  for primitive in node.mesh.primitives:
    if primitive.material.alphaMode == BlendAlphaMode:
      ctx.blended.add ToonBlend(node: node, primitive: primitive, pose: pose)
    else:
      ctx.drawPrimitive(root, node, primitive, pose)

proc drawToonNodes(ctx: ToonContext, root, node: Node) =
  ## Visits visible nodes without transferring frame ownership to glTF.
  if not node.visible:
    return
  if node.mesh != nil:
    ctx.drawToonMesh(root, node)
  for child in node.nodes:
    ctx.drawToonNodes(root, child)

proc draw*(ctx: ToonContext, root: Node, pose: ptr ToonPose = nil) =
  ## Draws posed toon geometry directly into the engine's active target.
  if pose != nil and pose.boundsValid and
    not pose.bounds.inFrustum(ctx.proj * ctx.view):
      return
  if pose == nil:
    root.updateTransforms(ctx.transform)
  let shader = ctx.shader
  shader.setUniform("toonView", ctx.view)
  shader.setUniform("toonProj", ctx.proj)
  shader.setUniform("toonLightDirection", ctx.lightDirection)
  shader.setUniform("toonCameraPosition", ctx.cameraPosition)
  shader.setUniform("toonHighlightColor", ctx.highlightColor.colorVector)
  shader.setUniform("toonShadowColor", ctx.shadowColor.colorVector)
  shader.setUniform("toonRimColor", ctx.rimColor.colorVector)
  shader.setUniform("toonTint", ctx.tint.colorVector)
  shader.setUniform("toonGlaze", ctx.glaze.colorVector)
  shader.setUniform("toonLightingMode", ctx.lighting.ord.int32)
  shader.setUniform("toonPerPixelLighting", ctx.perPixelLighting)
  shader.setUniform("toonNeutralMaterial", ctx.neutralMaterial)
  shader.setUniform("toonShadowMvp0", sunShadowMvp(0))
  shader.setUniform("toonShadowMvp1", sunShadowMvp(1))
  shader.setUniform("toonShadowStep", sunShadowBlend)
  shader.setUniform("toonShadowsOn", if sunShadowsActive(): 1.0'f else: 0.0'f)
  shader.setUniform("toonShadowStrength", sunShadowStrength * lightLevel)
  shader.setUniform("toonShadowBias", sunShadowBias)
  shader.setUniform("toonShadowTexel", SunShadowTexel)
  shader.setUniform("toonShadowSoftness", sunShadowSoftness)
  shader.setUniform("toonShadingStrength", sunShadingStrength)
  shader.setUniform("toonLightLevel", lightLevel)
  shader.bindTexture("toonShadowMap0", modelShadowTexture(sunShadowTextures[0]))
  shader.bindTexture("toonShadowMap1", modelShadowTexture(sunShadowTextures[1]))
  preserveDrawState:
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

proc drawSunDepthPrimitive(ctx: ToonContext, root, owner: Node,
    primitive: gltf.Primitive, pose: ptr ToonMeshPose = nil) =
  ## Draws the same skinned geometry and alpha cutout into the sun target.
  let
    geometry = modelMeshCache.geometry(primitive)
    material = primitive.material
  when defined(useDirectX) or defined(useVulkan):
    let packed = pose != nil and pose.packedParts
    if (if packed: not geometry.packedCutout else: material.alphaMode != MaskAlphaMode):
      ctx.modelUniforms(ctx.solidDepth, root, owner, pose)
      ctx.solidDepth.drawGeometry(geometry, DrawState(depthTest: true, depthWrite: true))
      return
  let
    shader = ctx.depthShader
    textures = modelMeshCache.textures(material)
  ctx.modelUniforms(shader, root, owner, pose)
  shader.setUniform("toonBaseColorFactor", material.baseColorFactor.colorVector)
  shader.setUniform("toonAlphaCutoff",
    if material.alphaMode == MaskAlphaMode: material.alphaCutoff else: -1.0'f)
  shader.bindTexture("toonBaseColorTexture", textures.baseColor)
  shader.drawGeometry(geometry,
    DrawState(depthTest: true, depthWrite: true))

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
      modelMeshCache.release(primitive)
      modelMeshCache.release(primitive.material)
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

proc drawSunDepth*(ctx: ToonContext, root: Node,
    pose: ptr ToonPose = nil) =
  ## Renders opaque and cutout skinning into the currently active sun pass.
  if pose != nil and pose.boundsValid and
    not pose.bounds.inFrustum(sunDepthPassMvp()):
      return
  if pose == nil:
    root.updateTransforms(ctx.transform)
  ctx.depthShader.setUniform("toonDepthLightMvp", sunDepthPassMvp())
  when defined(useDirectX) or defined(useVulkan):
    ctx.solidDepth.setUniform("toonDepthLightMvp", sunDepthPassMvp())
  preserveDrawState:
    if pose == nil:
      ctx.drawDepthNodes(root, root)
    else:
      for i in 0 ..< pose.meshCount:
        let mesh = addr pose.meshes[i]
        ctx.drawDepthMesh(root, mesh.node, mesh)
