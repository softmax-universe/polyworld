## Character PBR draws encoded directly into the engine's GPU frame.

import
  std/math, shady,
  chroma, pixie, vmath, windy, gltf,
  gltf/backends/shaders as shaderSources,
  common, meshes,
  ../../shadows

type
  CharacterRenderer* = ref object
    window: Window
    shader: ShaderProgram
    environment: GpuImage
    jointMatrices: seq[Mat4]
    blended: seq[tuple[owner: Node, primitive: gltf.Primitive]]

proc studioFaceDirection(face, x, y, size: int): Vec3 =
  ## Returns a normalized direction for a cubemap texel.
  let
    u = ((x.float32 + 0.5'f) / size.float32) * 2.0'f - 1.0'f
    v = ((y.float32 + 0.5'f) / size.float32) * 2.0'f - 1.0'f
  case face
  of 0:
    normalize(vec3(1.0'f, -v, -u))
  of 1:
    normalize(vec3(-1.0'f, -v, u))
  of 2:
    normalize(vec3(u, 1.0'f, v))
  of 3:
    normalize(vec3(u, -1.0'f, -v))
  of 4:
    normalize(vec3(u, -v, 1.0'f))
  of 5:
    normalize(vec3(-u, -v, -1.0'f))
  else:
    vec3(0, 1, 0)

proc studioColor(dir: Vec3): ColorRGBX =
  ## Returns a tiny neutral studio-light sample color.
  let
    hemi = clamp(dir.y * 0.5'f + 0.5'f, 0.0'f, 1.0'f)
    keyDir = normalize(vec3(0.35'f, 0.85'f, 0.25'f))
    fillDir = normalize(vec3(-0.45'f, 0.65'f, -0.35'f))
    key = pow(max(dot(dir, keyDir), 0.0'f), 24.0'f)
    fill = pow(max(dot(dir, fillDir), 0.0'f), 8.0'f)
    cool = vec3(0.18'f, 0.19'f, 0.21'f)
    neutral = vec3(0.58'f, 0.6'f, 0.63'f)
    sky = vec3(0.92'f, 0.94'f, 0.97'f)
  var color = mix(cool, neutral, hemi)
  color = mix(color, sky, hemi * hemi)
  color += vec3(0.28'f, 0.27'f, 0.25'f) * key
  color += vec3(0.10'f, 0.11'f, 0.12'f) * fill
  rgbx(
    clamp((color.x * 255.0'f).int, 0, 255).uint8,
    clamp((color.y * 255.0'f).int, 0, 255).uint8,
    clamp((color.z * 255.0'f).int, 0, 255).uint8,
    255
  )

proc newCharacterRenderer*(window: Window): CharacterRenderer =
  ## Borrows the engine device and creates the immediate character pipeline.
  initNative(window)
  result = CharacterRenderer(window: window,
    shader: newProgram(nativeStage(shaderSources.gltfPbrVert, shaderVertex),
      nativeStage(shaderSources.gltfPbrFrag, shaderFragment), ModelLayout))
  var faces: array[6, Image]
  for face in 0 ..< faces.len:
    faces[face] = newImage(8, 8)
    for y in 0 ..< 8:
      for x in 0 ..< 8:
        faces[face].data[y * 8 + x] =
          studioColor(studioFaceDirection(face, x, y, 8))
  result.environment = newCubeTexture(faces)

proc beginFrame*(renderer: CharacterRenderer, window: Window, size: IVec2) =
  ## Ensures character previews have a frame while preserving an active one.
  renderer.window = window
  if not frameActive():
    common.beginFrame(size.x.int, size.y.int, color(0, 0, 0, 1))

proc clearScreen*(renderer: CharacterRenderer, color: Color) =
  ## Clears the currently selected target, including portrait offscreen targets.
  renderer.beginFrame(renderer.window, renderer.window.size)
  common.clear(color)

proc clearScreen*(renderer: CharacterRenderer, color: ColorRGBX) =
  ## Accepts byte colors at the same public boundary as the OpenGL renderer.
  renderer.clearScreen(color.color)

proc endFrame*(renderer: CharacterRenderer) =
  ## Leaves command submission and presentation to the engine frame owner.
  discard renderer

proc setTextureTransform(program: ShaderProgram, prefix: string,
    transform: TextureTransform) =
  ## Applies authored glTF UV sets, offsets, scale, and rotation.
  program.setUniform(prefix & "TexCoord", transform.texCoord.int32)
  program.setUniform(prefix & "UvOffset", transform.offset)
  program.setUniform(prefix & "UvScale", transform.scale)
  program.setUniform(prefix & "UvRotation", transform.rotation)

proc drawPrimitive(renderer: CharacterRenderer, ctx: PbrContext,
    root, owner: Node, primitive: gltf.Primitive) =
  ## Supplies all shared PBR material inputs before one immediate draw.
  let
    shader = renderer.shader
    material = primitive.material
    textures = modelMeshCache.textures(material)
  shader.setUniform("model", owner.mat)
  shader.setUniform("normalMatrix", owner.mat.normalMatrix)
  root.skinMatricesInto(owner, renderer.jointMatrices)
  shader.setUniform("useSkinning", renderer.jointMatrices.len > 0)
  if renderer.jointMatrices.len > 128:
    raise newException(GltfError, "Character PBR supports at most 128 joints.")
  if renderer.jointMatrices.len > 0:
    var palette: array[128, Mat4]
    for i, joint in renderer.jointMatrices:
      palette[i] = joint
    shader.setUniform("jointMatrices", palette)
  shader.setUniform("baseColorFactor", material.baseColorFactor.colorVector)
  let emission = vec3(material.emissiveFactor.r, material.emissiveFactor.g,
    material.emissiveFactor.b) *
    (if material.hasEmissiveStrength: material.emissiveStrength else: 1.0'f)
  shader.setUniform("emissiveFactor", emission)
  shader.setUniform("metallicFactor", material.metallicFactor)
  shader.setUniform("roughnessFactor", material.roughnessFactor)
  shader.setUniform("transmissionFactor", material.transmissionFactor)
  shader.setUniform("normalScale", material.normalScale)
  shader.setUniform("occlusionStrength", material.occlusionStrength)
  shader.setUniform("useNormalTexture", material.hasNormalTexture)
  shader.setUniform("unlitMaterial", material.unlit.int32)
  shader.setUniform("opaqueMaterial", (material.alphaMode == OpaqueAlphaMode).int32)
  shader.setUniform("alphaCutoff",
    if material.alphaMode == MaskAlphaMode: material.alphaCutoff else: -1.0'f)
  shader.setTextureTransform("baseColor", material.baseColorTransform)
  shader.setTextureTransform("metallicRoughness", material.metallicRoughnessTransform)
  shader.setTextureTransform("normal", material.normalTransform)
  shader.setTextureTransform("occlusion", material.occlusionTransform)
  shader.setTextureTransform("emissive", material.emissiveTransform)
  shader.bindTexture("baseColorTexture", textures.baseColor)
  shader.bindTexture("metallicRoughnessTexture", textures.metallicRoughness)
  shader.bindTexture("normalTexture", textures.normal)
  shader.bindTexture("occlusionTexture", textures.occlusion)
  shader.bindTexture("emissiveTexture",
    if material.emissive == nil: whiteModelTexture() else: textures.emissive)
  let blended = material.alphaMode == BlendAlphaMode or
    material.transmissionFactor > 0 or ctx.tint.a < 1
  shader.drawGeometry(modelMeshCache.geometry(primitive), DrawState(
    depthTest: true,
    depthWrite: not blended,
    cull: if material.doubleSided: CullNone else: CullBack,
    blend: if blended: AlphaBlend else: Opaque
  ))

proc drawNodes(renderer: CharacterRenderer, ctx: PbrContext, root, node: Node) =
  ## Retains transparent materials until the model's opaque pass is complete.
  if not node.visible:
    return
  if node.mesh != nil:
    for primitive in node.mesh.primitives:
      if primitive.material.alphaMode == BlendAlphaMode or
        primitive.material.transmissionFactor > 0 or ctx.tint.a < 1:
        renderer.blended.add (node, primitive)
      else:
        renderer.drawPrimitive(ctx, root, node, primitive)
  for child in node.nodes:
    renderer.drawNodes(ctx, root, child)

proc drawPbr*(renderer: CharacterRenderer, ctx: PbrContext, root: Node) =
  ## Draws an independently posed model before another instance can re-pose it.
  root.updateTransforms(ctx.transform)
  let shader = renderer.shader
  shader.setUniform("view", ctx.view)
  shader.setUniform("proj", ctx.proj)
  shader.setUniform("tint", ctx.tint.colorVector)
  shader.setUniform("cameraPosition", ctx.cameraPosition)
  shader.setUniform("sunLightDirection", ctx.sunLightDirection)
  shader.setUniform("sunLightColor", ctx.sunLightColor.colorVector)
  shader.setUniform("rimLightDirection", ctx.rimLightDirection)
  shader.setUniform("rimLightColor", ctx.rimLightColor.colorVector)
  shader.setUniform("ambientLightColor", ctx.ambientLightColor.colorVector)
  shader.setUniform("fogColor", ctx.fogColor.colorVector)
  shader.setUniform("fogStart", ctx.fogStart)
  shader.setUniform("fogEnd", ctx.fogEnd)
  shader.setUniform("fogDensity", ctx.fogDensity)
  shader.setUniform("fogStrength", ctx.fogStrength)
  shader.setUniform("debugViewMode", ctx.debugView.int32)
  shader.setUniform("useShadow", ctx.useShadows and sunShadowsActive())
  shader.setUniform("lightSpace", sunShadowMvp(0))
  shader.setUniform("shadowBias", sunShadowBias)
  shader.setUniform("shadowMapTexelSize", vec2(SunShadowTexel))
  shader.setUniform("environmentMapStrength", ctx.environmentMapStrength)
  shader.setUniform("environmentMipCount", 3.0'f)
  shader.bindTexture("environmentMap", renderer.environment)
  shader.bindTexture("shadowMap", modelShadowTexture(sunShadowTextures[0]))
  preserveDrawState:
    renderer.blended.setLen(0)
    renderer.drawNodes(ctx, root, root)
    for entry in renderer.blended:
      renderer.drawPrimitive(ctx, root, entry.owner, entry.primitive)
    renderer.blended.setLen(0)
