## GPU terrain, scenery, and water rendering from shared Shady programs.

import
  std/[os, random, strformat, strutils, tables],
  chroma, gltf, pixie, pixie/internal, shady, vmath,
  ../../[assets, common, pathing, profiles, shadows, terrainblends,
    terrainmaps, terrainreliefs, terrainsurfaces, textures, toon]
import ./common as driver
when defined(useDirectX) or defined(useVulkan): import ../../frustums

type
  TerrainVertexArray = VertexBuffer
  TerrainBuffer = VertexBuffer
  TerrainCount = int

include ../../shared/terrainshaders
include ../../shared/terrainstate

var
  terrainProgram, waterProgram, propProgram, treeProgram: ShaderProgram
  texturedPropProgram, texturedInstantProgram: ShaderProgram

include ../../shared/terrainhooks
include ../../shared/terrainmeshes

when defined(useDirectX) or defined(useVulkan):
  var visibilityByGroup: Table[int32, seq[bool]]
  var visibilityRevision: uint64

  proc setPropVisibility*(group: int32, visible: seq[bool]) =
    visibilityByGroup.withValue(group, old):
      if old[] == visible: return
    visibilityByGroup[group] = visible
    inc visibilityRevision

  type SceneProp* = tuple[pack: PropPack, name: string, position: Vec3, facing, scale: float32]

  proc replaceTexturedGroup*(group: int32, props: openArray[SceneProp]) =
    ## Rebuild just the changed textured batches when a landmark is added or lost.
    var kept = 0
    for i in 0 ..< propPlacements.len:
      if propPlacements[i].group == group: continue
      if kept != i: swap(propPlacements[kept], propPlacements[i])
      inc kept
    propPlacements.setLen(kept)
    for slot, prop in props:
      # Baked placement yaw uses the opposite sign to vmath's rotateY.
      prop.pack.placeProp(prop.name, prop.position, -prop.facing, prop.scale, group = group)
      propPlacements[^1].slot = slot
    rebuildTexturedBatches()

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

proc replaceBuffer[T](buffer: var VertexBuffer, values: seq[T]) =
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
    nativeStage(terrainVert, shaderVertex),
    nativeStage(terrainFrag, shaderFragment), terrainLayout()
  )
  waterProgram =
    if waterShaderOverride.vertex.len > 0:
      newProgram(waterShaderOverride.vertex,
        waterShaderOverride.fragment, waterLayout())
    else:
      newProgram(
        nativeStage(waterVert, shaderVertex),
        nativeStage(waterFrag, shaderFragment), waterLayout()
      )
  propProgram = newProgram(
    nativeStage(propVert, shaderVertex),
    nativeStage(propFrag, shaderFragment), propLayout()
  )
  treeProgram = newProgram(
    nativeStage(treeVert, shaderVertex),
    nativeStage(treeFrag, shaderFragment), treeLayout()
  )
  texturedPropProgram = newProgram(
    nativeStage(texturedPropVert, shaderVertex),
    nativeStage(texturedPropFrag, shaderFragment), texturedLayout()
  )
  texturedInstantProgram = newProgram(
    nativeStage(texturedPropVert, shaderVertex),
    nativeStage(texturedInstantFrag, shaderFragment), texturedLayout()
  )

when defined(useDirectX) or defined(useVulkan):
  var
    casterRevision: uint64
    terrainShadowCache: array[2, tuple[target: RenderTarget, transform: Mat4,
      geometry, textures, visibility: uint64]]
template invalidateTerrainShadows() =
  when defined(useDirectX) or defined(useVulkan): inc casterRevision

proc initTerrainBuffers() =
  ## Defers GPU allocations until the shared geometry is first uploaded.
  invalidateTerrainShadows()
  when defined(useDirectX) or defined(useVulkan):
    visibilityByGroup.clear()
    for cached in terrainShadowCache.mitems:
      destroy(cached.target)
      cached.target = nil
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
  invalidateTerrainShadows()
  replaceBuffer(vertexBuffer, mesh)

proc uploadWaterMesh() =
  ## Uploads surface geometry after the shared water bake.
  replaceBuffer(waterVertexBuffer, waterMesh)

proc uploadTreeMesh() =
  ## Uploads the packed foliage geometry.
  invalidateTerrainShadows()
  replaceBuffer(treeVertexBuffer, treeMesh)

proc uploadPropMesh() =
  ## Uploads the packed colored scenery geometry.
  invalidateTerrainShadows()
  replaceBuffer(propVertexBuffer, propMesh)

proc updateTerrainMeshRange(offset, count: int) =
  ## Refreshes changed edge overlays from the current complete vertex data.
  invalidateTerrainShadows()
  replaceBuffer(vertexBuffer, mesh)

proc uploadTexturedBatch(batch: var TexturedBatch) =
  ## Uploads only a changed batch while preserving clean scene batches.
  invalidateTerrainShadows()
  when defined(useDirectX) or defined(useVulkan):
    # Keep the original triangle order and every material seam. Local sharing
    # bounds bake-time memory even for forests with millions of vertices.
    type Vertex = array[12, uint32]
    var unique: seq[Vertex]
    let count = batch.mesh.len div 12
    var indices = newSeq[uint32](count)
    var cache = initTable[Vertex, uint32]()
    for i in 0 ..< count:
      if i mod 3072 == 0: cache.clear()
      var v: Vertex
      copyMem(v.addr, batch.mesh[12 * i].addr, sizeof(Vertex))
      let next = unique.len.uint32
      let index = cache.mgetOrPut(v, next)
      if index == next: unique.add v
      indices[i] = index
    batch.bounds.setLen(0)
    var first = 0
    for placement in batch.placements:
      let size = placement.model.vertices.len div 9
      if size == 0: continue
      var box = emptyBounds()
      for i in first ..< first + size:
        box.extend(vec3(batch.mesh[12*i], batch.mesh[12*i+1], batch.mesh[12*i+2]))
      batch.bounds.add (first, size, placement.slot, box)
      first += size
    doAssert first == count
    replaceBuffer(batch.vertexBuffer, unique)
    replaceBuffer(batch.indices, indices)
  else:
    replaceBuffer(batch.vertexBuffer, batch.mesh)

proc releaseTexturedBatch(batch: var TexturedBatch) =
  ## Releases a batch's geometry while leaving its shared texture alive.
  invalidateTerrainShadows()
  when defined(useDirectX) or defined(useVulkan): destroy(batch.indices)
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

proc setEnvUniforms(program: ShaderProgram) =
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

proc setShadowUniforms(program: ShaderProgram) =
  ## Binds the two interpolated sun maps with the GPU's receiver orientation.
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

proc setVisibilityUniforms(program: ShaderProgram) =
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

when defined(useDirectX) or defined(useVulkan):
  proc drawVisible(batch: TexturedBatch, transform: Mat4, program: ShaderProgram, layout = VertexLayout()) =
    # Consecutive visible placements share one indexed range. All positions are
    # world-space and each pass supplies the exact matrix used by its shader.
    var planes: array[6, Vec4]
    for axis in 0 .. 2:
      for col in 0 .. 3:
        planes[2*axis][col] = transform[col, 3] + transform[col, axis]
        planes[2*axis+1][col] = transform[col, 3] - transform[col, axis]
    var ranges: seq[IndexRange]
    var active: ptr seq[bool]
    visibilityByGroup.withValue(batch.group, slots): active = slots
    for instance in batch.bounds:
      if active != nil and not active[][instance.slot]: continue
      var visible = true
      for plane in planes:
        let x = if plane.x < 0: instance.box.min.x else: instance.box.max.x
        let y = if plane.y < 0: instance.box.min.y else: instance.box.max.y
        let z = if plane.z < 0: instance.box.min.z else: instance.box.max.z
        if plane.x*x + plane.y*y + plane.z*z + plane.w < -0.001'f32:
          visible = false
          break
      if not visible: continue
      if ranges.len > 0 and ranges[^1].first + ranges[^1].count == instance.first:
        ranges[^1].count += instance.count
      else:
        ranges.add (instance.first, instance.count)
    if ranges.len > 0:
      draw(program, batch.vertexBuffer, batch.mesh.len div 12, DrawState(depthTest: true, depthWrite: true),
        indices = batch.indices, layout = layout, ranges = ranges)

proc drawTexturedBatch(batch: TexturedBatch, viewProjection: Mat4) =
  ## Draws a textured scenery batch using its per-vertex material tint.
  texturedPropProgram.setEnvUniforms()
  texturedPropProgram.setShadowUniforms()
  texturedPropProgram.setVisibilityUniforms()
  texturedPropProgram.setUniform("mvp", viewProjection)
  texturedPropProgram.setUniform("propModel", mat4())
  texturedPropProgram.setUniform("treeAlphaCutoff", TreeAlphaCutoff)
  texturedPropProgram.bindTexture("treeTextures", batch.textureArray)
  when defined(useDirectX) or defined(useVulkan):
    batch.drawVisible(viewProjection, texturedPropProgram)
  else:
    draw(texturedPropProgram, batch.vertexBuffer, batch.mesh.len div 12, DrawState(depthTest: true, depthWrite: true))

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

proc waterShaderProgram*(): ShaderProgram =
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
    buffer: VertexBuffer, count, stride: int,
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
    when defined(useDirectX) or defined(useVulkan):
      bindSunCutoutDepth(transform, TreeAlphaCutoff)
      sunBindCutoutTexture(batch.textureArray)
      batch.drawVisible(transform, sunCutoutProgramId(), depthLayout(12, true))
    else:
      drawDepthMesh(batch.vertexBuffer, batch.mesh.len div 12, 12, transform, batch.textureArray)

when defined(useDirectX) or defined(useVulkan):
  proc drawCachedTerrainSunDepth*(step: int) =
    ## Seed a freshly cleared shadow pass with its stationary terrain casters.
    ## Buildings and animated characters are drawn into the live map afterward.
    let target = gpuRenderer.target
    let cached = addr terrainShadowCache[step]
    if cached.target == nil or cached.target.width != target.width or cached.target.height != target.height:
      destroy(cached.target)
      cached.target = newRenderTarget(target.width, target.height, color = false)
      cached.geometry = uint64.high
    let transform = sunDepthPassMvp()
    if cached.geometry == casterRevision and cached.textures == textureArrayRevision and cached.visibility == visibilityRevision and cached.transform == transform:
      copyTarget(cached.target, target, color = false)
    else:
      drawTerrainSunDepth()
      copyTarget(target, cached.target, color = false)
      cached.transform = transform
      cached.geometry = casterRevision
      cached.textures = textureArrayRevision
      cached.visibility = visibilityRevision

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
