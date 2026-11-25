## Metal terrain, scenery, and water rendering from shared Shady programs.

import
  std/[os, random, strformat, strutils, tables],
  chroma, gltf, pixie, pixie/internal, shady, vmath,
  ../../[assets, common, pathing, profiles, shadows, terrainblends,
    terrainmaps, terrainreliefs, terrainsurfaces, textures, toon]
import ./common as metalcommon

type
  TerrainVertexArray = MetalBuffer
  TerrainBuffer = MetalBuffer
  TerrainCount = int

include ../../shared/terrainshaders
include ../../shared/terrainstate

var
  terrainProgram, waterProgram, propProgram, treeProgram: MetalProgram
  texturedPropProgram, texturedInstantProgram: MetalProgram

include ../../shared/terrainhooks
include ../../shared/terrainmeshes

proc terrainLayout(): VertexLayout =
  ## Describes the packed terrain vertex fields shared with mesh generation.
  VertexLayout(stride: TerrainVertexSize * sizeof(float32), attributes: @[
    VertexAttribute(name: "vertPos", format: Float3, offset: 0),
    VertexAttribute(name: "edgeMask", format: Float1, offset: 12),
    VertexAttribute(name: "normal", format: Float3, offset: 16),
    VertexAttribute(name: "tileColor", format: Float3, offset: 28),
    VertexAttribute(name: "materials", format: Float4, offset: 40),
    VertexAttribute(name: "cornerWeight", format: Float4, offset: 56),
    VertexAttribute(name: "splatRange", format: Float3, offset: 72)
  ])

proc propLayout(): VertexLayout =
  ## Describes colored prop vertices in their shared packed representation.
  VertexLayout(stride: 9 * sizeof(float32), attributes: @[
    VertexAttribute(name: "vertPos", format: Float3, offset: 0),
    VertexAttribute(name: "vertColor", format: Float3, offset: 12),
    VertexAttribute(name: "normal", format: Float3, offset: 24)
  ])

proc treeLayout(): VertexLayout =
  ## Describes textured foliage vertices with independent brightness.
  VertexLayout(stride: TreeVertexSize * sizeof(float32), attributes: @[
    VertexAttribute(name: "vertPos", format: Float3, offset: 0),
    VertexAttribute(name: "vertUv", format: Float3, offset: 12),
    VertexAttribute(name: "normal", format: Float3, offset: 24),
    VertexAttribute(name: "vertBrightness", format: Float1, offset: 36)
  ])

proc texturedLayout(): VertexLayout =
  ## Describes textured prop vertices with their baked material colors.
  VertexLayout(stride: 12 * sizeof(float32), attributes: @[
    VertexAttribute(name: "vertPos", format: Float3, offset: 0),
    VertexAttribute(name: "vertUv", format: Float3, offset: 12),
    VertexAttribute(name: "normal", format: Float3, offset: 24),
    VertexAttribute(name: "vertTint", format: Float3, offset: 36)
  ])

proc waterLayout(): VertexLayout =
  ## Describes the water positions and normals used by override shaders too.
  VertexLayout(stride: 6 * sizeof(float32), attributes: @[
    VertexAttribute(name: "vertPos", format: Float3, offset: 0),
    VertexAttribute(name: "normal", format: Float3, offset: 12)
  ])

proc depthLayout(stride: int, cutout = false): VertexLayout =
  ## Selects position and optional texture coordinates from an existing mesh.
  result = VertexLayout(stride: stride * sizeof(float32), attributes: @[
    VertexAttribute(name: "vertPos", format: Float3, offset: 0)
  ])
  if cutout:
    result.attributes.add VertexAttribute(
      name: "vertUv", format: Float3, offset: 12
    )

proc replaceBuffer(buffer: var MetalBuffer, values: seq[float32]) =
  ## Uploads a packed mesh, retaining its allocation across ordinary rebakes.
  if values.len == 0:
    return
  if buffer == nil:
    buffer = newBuffer(values)
  else:
    updateBuffer(buffer, values)

proc initTerrainPrograms() =
  ## Compiles all terrain stages directly from their shared Shady procedures.
  terrainProgram = newProgram(
    toShader(terrainVert, metalMSL, shaderVertex),
    toShader(terrainFrag, metalMSL, shaderFragment), terrainLayout()
  )
  waterProgram =
    if waterShaderOverride.vertex.len > 0:
      newProgram(waterShaderOverride.vertex,
        waterShaderOverride.fragment, waterLayout())
    else:
      newProgram(
        toShader(waterVert, metalMSL, shaderVertex),
        toShader(waterFrag, metalMSL, shaderFragment), waterLayout()
      )
  propProgram = newProgram(
    toShader(propVert, metalMSL, shaderVertex),
    toShader(propFrag, metalMSL, shaderFragment), propLayout()
  )
  treeProgram = newProgram(
    toShader(treeVert, metalMSL, shaderVertex),
    toShader(treeFrag, metalMSL, shaderFragment), treeLayout()
  )
  texturedPropProgram = newProgram(
    toShader(texturedPropVert, metalMSL, shaderVertex),
    toShader(texturedPropFrag, metalMSL, shaderFragment), texturedLayout()
  )
  texturedInstantProgram = newProgram(
    toShader(texturedPropVert, metalMSL, shaderVertex),
    toShader(texturedInstantFrag, metalMSL, shaderFragment), texturedLayout()
  )

proc initTerrainBuffers() =
  ## Defers Metal allocations until the shared geometry is first uploaded.
  destroy(vertexBuffer)
  destroy(waterVertexBuffer)
  destroy(treeVertexBuffer)
  destroy(propVertexBuffer)
  vertexBuffer = nil
  waterVertexBuffer = nil
  treeVertexBuffer = nil
  propVertexBuffer = nil

proc initTerrainVisibility() =
  ## Initializes the tile visibility texture before the shared visible fill.
  visibilitySize = GridTiles
  visibilityTexture = createR8Texture(
    GridTiles, GridTiles, newSeq[uint8](GridTiles * GridTiles)
  )

proc uploadTerrainMesh() =
  ## Uploads terrain vertices after the shared geometry bake.
  replaceBuffer(vertexBuffer, mesh)

proc uploadWaterMesh() =
  ## Uploads surface geometry after the shared water bake.
  replaceBuffer(waterVertexBuffer, waterMesh)

proc uploadTreeMesh() =
  ## Uploads the packed foliage geometry.
  replaceBuffer(treeVertexBuffer, treeMesh)

proc uploadPropMesh() =
  ## Uploads the packed colored scenery geometry.
  replaceBuffer(propVertexBuffer, propMesh)

proc updateTerrainMeshRange(offset, count: int) =
  ## Refreshes changed edge overlays from the current complete vertex data.
  replaceBuffer(vertexBuffer, mesh)

proc uploadTexturedBatch(batch: var TexturedBatch) =
  ## Uploads only a changed batch while preserving clean scene batches.
  replaceBuffer(batch.vertexBuffer, batch.mesh)

proc releaseTexturedBatch(batch: var TexturedBatch) =
  ## Releases a batch's geometry while leaving its shared texture alive.
  destroy(batch.vertexBuffer)
  batch = TexturedBatch()

proc releasePropModel(model: PropModel) =
  ## Releases both vertex representations owned by a standalone prop model.
  destroy(model.vertexBuffer)
  destroy(model.texturedVertexBuffer)
  model.vertexBuffer = nil
  model.texturedVertexBuffer = nil

proc uploadTerrainData(texture: var Texture, values: seq[float32]): Vec2 =
  ## Packs RGBA data records into a nearest-filtered floating-point texture.
  if values.len == 0 or values.len mod 4 != 0:
    raise newException(
      QuadTerrainError, "Terrain data needs complete RGBA records."
    )
  let
    count = values.len div 4
    width = min(1024, count)
    height = (count + width - 1) div width
  if count > 16_777_215 or height > 16384:
    raise newException(QuadTerrainError, "Terrain data exceeds GPU capacity.")
  var data = newSeq[float32](width * height * 4)
  copyMem(data[0].addr, unsafeAddr values[0], values.len * sizeof(float32))
  updateRgba32fTexture(texture, width, height, data)
  vec2(width.float32, height.float32)

proc uploadTerrainVisibility*(values: openArray[uint8], size = GridTiles) =
  ## Uploads a tile visibility map with arbitrary, tightly packed row widths.
  if visibilityTexture == nil:
    return
  if size <= 0 or values.len != size * size:
    raise newException(
      QuadTerrainError, "Terrain visibility needs one value per world tile."
    )
  updateR8Texture(visibilityTexture, size, size, values)
  visibilitySize = size

proc uploadAmbientOcclusion*(
    values: openArray[uint8], size: int, origin, span: Vec2
) =
  ## Uploads sky visibility at four receiver heights into RGBA channels.
  if size <= 0 or values.len != size * size * 4 or
      span.x <= 0 or span.y <= 0:
    raise newException(QuadTerrainError, "Invalid ambient occlusion field.")
  updateRgba8Texture(ambientTexture, size, size, values)
  ambientOrigin = origin
  ambientSpan = span

proc clearAmbientOcclusion*() =
  ## Releases optional ambient maps and restores unoccluded lighting.
  deleteTexture(ambientTexture)
  deleteTexture(ambientFallbackTexture)

proc uploadGroundMask*(values: openArray[uint8], size: int) =
  ## Uploads the two-channel terrain coverage mask.
  if size <= 0 or values.len != size * size * 2:
    raise newException(QuadTerrainError, "Ground mask needs two bytes per texel.")
  updateRg8Texture(groundMaskTexture, size, size, values)
  groundMaskActive = true

proc setEnvUniforms(program: MetalProgram) =
  ## Binds the shared environment palette and ambient visibility field.
  let
    highlight = environmentHighlight
    shadow = environmentShadow
  program.setUniform("envHighlight", vec3(highlight.r, highlight.g, highlight.b))
  program.setUniform("envShadow", vec3(shadow.r, shadow.g, shadow.b))
  program.setUniform("envLightDirection", -environmentLight)
  program.setUniform("envLightLevel", lightLevel)
  program.setUniform("ambientEnabled", float32(ambientTexture != nil))
  program.setUniform("ambientBounds", vec4(
    ambientOrigin.x, ambientOrigin.y, ambientSpan.x, ambientSpan.y
  ))
  if ambientTexture != nil:
    program.bindTexture("ambientMap", ambientTexture)
  else:
    if ambientFallbackTexture == nil:
      ambientFallbackTexture = createRgba8Texture(
        1, 1, [255'u8, 255, 255, 255]
      )
    program.bindTexture("ambientMap", ambientFallbackTexture)

proc setShadowUniforms(program: MetalProgram) =
  ## Binds the two interpolated sun maps with Metal's receiver orientation.
  program.setUniform("shadowMvp0", sunShadowMvp(0))
  program.setUniform("shadowMvp1", sunShadowMvp(1))
  program.setUniform("shadowStep", sunShadowBlend)
  program.setUniform("shadowsOn", float32(sunShadowsActive()))
  program.setUniform("shadowStrength", sunShadowStrength * lightLevel)
  program.setUniform("shadowBias", sunShadowBias)
  program.setUniform("shadowTexel", SunShadowTexel)
  program.setUniform("shadowSoftness", sunShadowSoftness)
  program.setUniform("shadingStrength", sunShadingStrength)
  program.bindTexture("shadowMapPcf0", sunShadowTextures[0])
  program.bindTexture("shadowMapPcf1", sunShadowTextures[1])

proc setVisibilityUniforms(program: MetalProgram) =
  ## Uses the same tile visibility coordinates for all terrain materials.
  program.setUniform("visibilityOffset", visibilitySize.float32 / 2)
  program.setUniform("visibilityScale", 1.0'f / visibilitySize.float32)
  program.bindTexture("visibilityTex", visibilityTexture)

proc bindTerrainData() =
  ## Binds material blends and procedural brush records to the terrain shader.
  terrainProgram.setUniform("unboostedMaterial", terrainUnboostedMaterial)
  terrainProgram.setUniform("generatedEnabled", float32(generatedTerrain))
  terrainProgram.setUniform("heightBlendEnabled", float32(terrainHeightBlending))
  terrainProgram.setUniform("splatsEnabled", float32(terrainSplats))
  terrainProgram.setUniform("splatAmount", clamp(terrainSplatAmount, 0.0'f, 1.0'f))
  terrainProgram.setUniform("splatDataSize", splatDimensions)
  terrainProgram.setUniform("blendDataSize", blendDimensions)
  terrainProgram.bindTexture("splatColors", splatColorArray)
  terrainProgram.bindTexture("splatHeights", splatHeightArray)
  terrainProgram.bindTexture("splatData", splatDataTexture)
  terrainProgram.bindTexture("blendData", blendDataTexture)

proc bindGroundMask() =
  ## Binds the optional coverage mask and circular curb controls.
  terrainProgram.setUniform("groundMaskEnabled", float32(groundMaskActive))
  terrainProgram.setUniform("groundLayers", groundLayerIndices)
  terrainProgram.setUniform("groundRing", groundRingValues)
  terrainProgram.setUniform("groundRingShape", groundRingShapeValues)
  if groundMaskTexture == nil:
    groundMaskTexture = createRg8Texture(1, 1, [0'u8, 0])
  terrainProgram.bindTexture("groundMask", groundMaskTexture)

proc drawTerrainRange*(
    viewProjection: Mat4, firstVertex, vertexCount: int, showEdges = false
) =
  ## Draws a contiguous visible subset of the baked terrain.
  if vertexCount <= 0 or vertexBuffer == nil:
    return
  terrainProgram.setEnvUniforms()
  terrainProgram.setShadowUniforms()
  terrainProgram.setVisibilityUniforms()
  terrainProgram.setUniform("mvp", viewProjection)
  terrainProgram.setUniform("borderWidthUniform", borderWidth)
  terrainProgram.setUniform("heightScale", amplitude)
  terrainProgram.setUniform("edgesEnabled", float32(showEdges))
  terrainProgram.setUniform("texScale", terrainTextureScale)
  terrainProgram.setUniform("blendDepth", terrainBlendDepth)
  terrainProgram.setUniform("heightBlend", terrainHeightBlend)
  terrainProgram.bindTexture("terrainTextures", terrainTextureArray)
  bindTerrainData()
  bindGroundMask()
  draw(terrainProgram, vertexBuffer, vertexCount,
    DrawState(depthTest: true, depthWrite: true), first = firstVertex)

proc uploadPropModel(model: PropModel) =
  ## Uploads the original colored model once for immediate prop drawing.
  if model.vertexBuffer == nil:
    model.vertexBuffer = newBuffer(model.vertices)
    model.vertexCount = model.vertices.len div 9

proc uploadTexturedPropModel(model: PropModel) =
  ## Uploads the shared model-space textured representation on first use.
  if model.texturedVertexBuffer == nil:
    model.texturedVertexBuffer = newBuffer(texturedPropMesh(model))
    model.vertexCount = model.vertices.len div 9

proc drawProp*(
    pack: PropPack, name: string, position: Vec3,
    rotation, propScale: float32, viewProjection: Mat4,
    tint = vec4(1, 1, 1, 1)
) =
  ## Draws one standalone prop with the same palette and shadows as terrain.
  if not pack.hasProp(name):
    return
  let
    model = pack.models[pack.names[name]]
    transform = translate(position) * rotateY(rotation) * scale(vec3(propScale))
    textured = model.textureArray != nil
    program = if textured: texturedInstantProgram else: propProgram
  var state = DrawState(depthTest: true, depthWrite: true)
  program.setEnvUniforms()
  program.setShadowUniforms()
  program.setVisibilityUniforms()
  program.setUniform("mvp", viewProjection * transform)
  program.setUniform("propModel", transform)
  program.setUniform("propTint", tint)
  if textured:
    model.uploadTexturedPropModel()
    program.setUniform("treeAlphaCutoff", TreeAlphaCutoff)
    program.bindTexture("treeTextures", model.textureArray)
    draw(program, model.texturedVertexBuffer, model.vertexCount, state)
  else:
    model.uploadPropModel()
    if tint.w < 1.0'f:
      state.blend = StraightAlpha
      state.depthWrite = false
    draw(program, model.vertexBuffer, model.vertexCount, state)

proc drawTexturedBatch(batch: TexturedBatch, viewProjection: Mat4) =
  ## Draws a textured scenery batch using its per-vertex material tint.
  texturedPropProgram.setEnvUniforms()
  texturedPropProgram.setShadowUniforms()
  texturedPropProgram.setVisibilityUniforms()
  texturedPropProgram.setUniform("mvp", viewProjection)
  texturedPropProgram.setUniform("propModel", mat4())
  texturedPropProgram.setUniform("treeAlphaCutoff", TreeAlphaCutoff)
  texturedPropProgram.bindTexture("treeTextures", batch.textureArray)
  draw(texturedPropProgram, batch.vertexBuffer, batch.mesh.len div 12,
    DrawState(depthTest: true, depthWrite: true))

proc drawTerrain*(
    viewProjection: Mat4, showEdges = false,
    drawGround = true, drawProps = true
) {.measure.} =
  ## Draws opaque terrain, colored props, and cutout foliage in scene order.
  if drawGround:
    drawTerrainRange(viewProjection, 0, meshVertexCount, showEdges)
  if not drawProps:
    return
  let state = DrawState(depthTest: true, depthWrite: true)
  if propMesh.len > 0:
    propProgram.setEnvUniforms()
    propProgram.setShadowUniforms()
    propProgram.setVisibilityUniforms()
    propProgram.setUniform("mvp", viewProjection)
    propProgram.setUniform("propModel", mat4())
    propProgram.setUniform("propTint", vec4(1))
    draw(propProgram, propVertexBuffer, propMesh.len div 9, state)
  if treeMesh.len > 0:
    treeProgram.setEnvUniforms()
    treeProgram.setShadowUniforms()
    treeProgram.setVisibilityUniforms()
    treeProgram.setUniform("mvp", viewProjection)
    treeProgram.setUniform("treeAlphaCutoff", TreeAlphaCutoff)
    treeProgram.bindTexture("treeTextures", treeTextureArray)
    draw(treeProgram, treeVertexBuffer, treeMesh.len div TreeVertexSize, state)
  for batch in texturedBatches:
    if batch.mesh.len > 0:
      drawTexturedBatch(batch, viewProjection)

proc waterShaderProgram*(): MetalProgram =
  ## Returns the active water program for additional override shader inputs.
  waterProgram

proc drawWater*(
    viewProjection: Mat4, cameraEye: Vec3, offset = vec2(0),
    opacity = 0.55'f, highlightOpacity = 0.45'f,
    firstVertex = 0, vertexCount = -1
) =
  ## Draws transparent water after opaque objects, preserving override inputs.
  let count =
    if vertexCount < 0:
      waterMesh.len div 6 - firstVertex
    else:
      vertexCount
  if count <= 0 or waterVertexBuffer == nil:
    return
  waterProgram.setEnvUniforms()
  waterProgram.setVisibilityUniforms()
  waterProgram.setUniform("mvp", viewProjection)
  waterProgram.setUniform("cameraPos", cameraEye)
  waterProgram.setUniform("waterOffset", offset)
  waterProgram.setUniform("waterOpacity", opacity)
  waterProgram.setUniform("waterHighlightOpacity", highlightOpacity)
  waterProgram.bindTexture("waterNormals", waterNormalTextureArray)
  let blend =
    if waterPremultipliedAlpha:
      PremultipliedAlpha
    else:
      StraightAlpha
  draw(waterProgram, waterVertexBuffer, count,
    DrawState(depthTest: true, depthWrite: false, blend: blend),
    first = firstVertex)

proc drawDepthMesh(
    buffer: MetalBuffer, count, stride: int,
    transform: Mat4, texture: Texture = nil, first = 0
) =
  ## Reuses the baked vertex buffer in the current sun depth target.
  if count <= 0 or buffer == nil:
    return
  let cutout = texture != nil
  let program =
    if cutout:
      bindSunCutoutDepth(transform, TreeAlphaCutoff)
      sunBindCutoutTexture(texture)
      sunCutoutProgramId()
    else:
      bindSunDepth(transform)
      sunDepthProgramId()
  draw(program, buffer, count,
    DrawState(depthTest: true, depthWrite: true), first = first,
    layout = depthLayout(stride, cutout))

proc drawTerrainSunDepth*(firstVertex = 0, vertexCount = -1) {.measure.} =
  ## Draws baked terrain and all scenery into the active sun depth map.
  let
    transform = sunDepthPassMvp()
    count =
      if vertexCount < 0:
        meshVertexCount - firstVertex
      else:
        vertexCount
  drawDepthMesh(vertexBuffer, count, TerrainVertexSize, transform,
    first = firstVertex)
  drawDepthMesh(propVertexBuffer, propMesh.len div 9, 9, transform)
  drawDepthMesh(treeVertexBuffer, treeMesh.len div TreeVertexSize,
    TreeVertexSize, transform, treeTextureArray)
  for batch in texturedBatches:
    drawDepthMesh(batch.vertexBuffer, batch.mesh.len div 12,
      12, transform, batch.textureArray)

proc drawPropSunDepth*(
    pack: PropPack, name: string, position: Vec3,
    rotation, propScale: float32
) =
  ## Draws one immediate prop as a caster in the active sun depth map.
  if not pack.hasProp(name):
    return
  let
    model = pack.models[pack.names[name]]
    transform = sunDepthPassMvp() * translate(position) *
      rotateY(rotation) * scale(vec3(propScale))
  if model.textureArray != nil:
    model.uploadTexturedPropModel()
    drawDepthMesh(model.texturedVertexBuffer, model.vertexCount,
      12, transform, model.textureArray)
  else:
    model.uploadPropModel()
    drawDepthMesh(model.vertexBuffer, model.vertexCount, 9, transform)
