## Native buffers and material textures shared by model rendering passes.

import
  std/tables,
  chroma, pixie, vmath, gltf,
  common

when defined(useMetal4): import ../metal/meshtextures
else: import ../native/meshtextures
export meshtextures.newCubeTexture

type
  ModelVertex = object
    position: Vec3
    color: Vec4
    normal: Vec3
    uv: Vec2
    tangent: Vec4
    joints: UVec4
    weights: Vec4
    uv1: Vec2

  MeshBuffers* = object
    vertices*, indices*: VertexBuffer
    count*: int
    index32*: bool
    topology*: common.Primitive
    source: gltf.Primitive
    version: uint64

  MaterialTextures* = object
    baseColor*, emissive*, metallicRoughness*, normal*, occlusion*: GpuImage
    source: Material
    version: uint64

  MeshCache* = object
    meshes: Table[pointer, MeshBuffers]
    materials: Table[pointer, MaterialTextures]
    white, black, flatNormal: GpuImage
    shadowFallback: RenderTarget

var modelMeshCache*: MeshCache

const ModelLayout* = VertexLayout(
  stride: sizeof(ModelVertex),
  attributes: @[
    VertexAttribute(name: "vertexPosition", format: Float3,
      offset: offsetOf(ModelVertex, position)),
    VertexAttribute(name: "vertexColor", format: Float4,
      offset: offsetOf(ModelVertex, color)),
    VertexAttribute(name: "vertexNormal", format: Float3,
      offset: offsetOf(ModelVertex, normal)),
    VertexAttribute(name: "vertexUV", format: Float2,
      offset: offsetOf(ModelVertex, uv)),
    VertexAttribute(name: "vertexTangent", format: Float4,
      offset: offsetOf(ModelVertex, tangent)),
    VertexAttribute(name: "vertexJoints", format: UInt4,
      offset: offsetOf(ModelVertex, joints)),
    VertexAttribute(name: "vertexWeights", format: Float4,
      offset: offsetOf(ModelVertex, weights)),
    VertexAttribute(name: "vertexUV1", format: Float2,
      offset: offsetOf(ModelVertex, uv1))
  ]
)

proc release*(cache: var MeshCache, primitive: gltf.Primitive) =
  ## Releases a primitive's owned buffers before rebuilding shadow batches.
  let key = cast[pointer](primitive)
  if key in cache.meshes:
    cache.meshes[key].vertices.destroy()
    cache.meshes[key].indices.destroy()
    cache.meshes.del(key)

proc geometry*(cache: var MeshCache, primitive: gltf.Primitive): MeshBuffers =
  ## Uploads changed CPU geometry without sharing glTF renderer ownership.
  let key = cast[pointer](primitive)
  if key in cache.meshes and
    cache.meshes[key].version == primitive.geometryVersion:
      return cache.meshes[key]
  cache.release(primitive)
  var vertices = newSeq[ModelVertex](primitive.points.len)
  for i, point in primitive.points:
    vertices[i] = ModelVertex(
      position: point,
      color: vec4(1),
      normal: vec3(0, 1, 0),
      tangent: vec4(1, 0, 0, 1),
      weights: vec4(1, 0, 0, 0)
    )
    if i < primitive.colors.len:
      let c = primitive.colors[i]
      vertices[i].color = vec4(c.r.float32, c.g.float32,
        c.b.float32, c.a.float32) / 255
    if i < primitive.normals.len:
      vertices[i].normal = primitive.normals[i]
    if i < primitive.uvs.len:
      vertices[i].uv = primitive.uvs[i]
    if i < primitive.uvs1.len:
      vertices[i].uv1 = primitive.uvs1[i]
    if i < primitive.tangents.len:
      vertices[i].tangent = primitive.tangents[i]
    if i < primitive.jointIds.len:
      let joints = primitive.jointIds[i]
      vertices[i].joints = uvec4(joints[0].uint32, joints[1].uint32,
        joints[2].uint32, joints[3].uint32)
    if i < primitive.jointWeights.len:
      vertices[i].weights = primitive.jointWeights[i]
  result = MeshBuffers(
    source: primitive,
    version: primitive.geometryVersion,
    vertices: newBuffer(vertices),
    count: vertices.len,
    topology: Triangles
  )
  case primitive.mode
  of PointsMode: result.topology = Points
  of LinesMode, LineLoopMode, LineStripMode: result.topology = Lines
  of TriangleStripMode: result.topology = TriangleStrip
  else: discard
  if primitive.mode in {TriangleFanMode, LineLoopMode, LineStripMode}:
    var source: seq[uint32]
    if primitive.indices32.len > 0:
      source = primitive.indices32
    elif primitive.indices16.len > 0:
      for index in primitive.indices16:
        source.add index.uint32
    else:
      for i in 0 ..< vertices.len:
        source.add i.uint32
    var indices: seq[uint32]
    if primitive.mode == TriangleFanMode:
      for i in 2 ..< source.len:
        indices.add [source[0], source[i - 1], source[i]]
    else:
      for i in 1 ..< source.len:
        indices.add [source[i - 1], source[i]]
      if primitive.mode == LineLoopMode and source.len > 1:
        indices.add [source[^1], source[0]]
    result.indices = newBuffer(indices)
    result.count = indices.len
    result.index32 = true
  elif primitive.indices16.len > 0:
    result.indices = newBuffer(primitive.indices16)
    result.count = primitive.indices16.len
  elif primitive.indices32.len > 0:
    result.indices = newBuffer(primitive.indices32)
    result.count = primitive.indices32.len
    result.index32 = true
  cache.meshes[key] = result

proc solidTexture(pixel: ColorRGBX): GpuImage =
  ## Creates one fallback texel with straight RGBA channels.
  let image = newImage(1, 1)
  image.data[0] = pixel
  newTexture(image)

proc textures*(cache: var MeshCache, material: Material): MaterialTextures =
  ## Retains material textures until their explicit version changes.
  if cache.white == nil:
    cache.white = solidTexture(rgbx(255, 255, 255, 255))
    cache.black = solidTexture(rgbx(0, 0, 0, 255))
    cache.flatNormal = solidTexture(rgbx(128, 128, 255, 255))
  let key = cast[pointer](material)
  if key in cache.materials and
    cache.materials[key].version == material.materialVersion:
      return cache.materials[key]
  result = MaterialTextures(source: material, version: material.materialVersion)
  result.baseColor = uploadTexture(material.baseColor,
    material.baseColorSampler, cache.white)
  result.emissive = uploadTexture(material.emissive,
    material.emissiveSampler, cache.black)
  result.metallicRoughness = uploadTexture(material.metallicRoughness,
    material.metallicRoughnessSampler, cache.white)
  result.normal = uploadTexture(material.normal,
    material.normalSampler, cache.flatNormal)
  result.occlusion = uploadTexture(material.occlusion,
    material.occlusionSampler, cache.white)
  if key in cache.materials:
    let old = cache.materials[key]
    for texture in [old.baseColor, old.emissive, old.metallicRoughness,
      old.normal, old.occlusion]:
      if texture != cache.white and texture != cache.black and
        texture != cache.flatNormal:
          texture.destroy()
  cache.materials[key] = result

proc drawGeometry*(program: ShaderProgram, buffers: MeshBuffers,
    state: DrawState) =
  ## Draws an uploaded primitive using its original topology and index width.
  var actualState = state
  actualState.primitive = buffers.topology
  common.draw(program, buffers.vertices, buffers.count, actualState,
    buffers.indices, index32 = buffers.index32)

proc colorVector*(color: Color): Vec4 =
  ## Converts a shared color to the shader's four-component representation.
  vec4(color.r, color.g, color.b, color.a)

proc release*(cache: var MeshCache, material: Material) =
  ## Drops cached texture images after a material changes without a version bump.
  let key = cast[pointer](material)
  if key notin cache.materials:
    return
  let old = cache.materials[key]
  for texture in [old.baseColor, old.emissive, old.metallicRoughness,
    old.normal, old.occlusion]:
    if texture != cache.white and texture != cache.black and
      texture != cache.flatNormal:
        texture.destroy()
  cache.materials.del(key)

proc clearModelResources*() =
  ## Releases every cached model resource before the engine device shuts down.
  for buffers in modelMeshCache.meshes.values:
    buffers.vertices.destroy()
    buffers.indices.destroy()
  var materials: seq[Material]
  for textures in modelMeshCache.materials.values:
    materials.add textures.source
  for material in materials:
    modelMeshCache.release(material)
  modelMeshCache.shadowFallback.destroy()
  modelMeshCache.white.destroy()
  modelMeshCache.black.destroy()
  modelMeshCache.flatNormal.destroy()
  modelMeshCache = MeshCache()

proc modelShadowTexture*(texture: GpuImage): GpuImage =
  ## Supplies a valid comparison texture when an application disables shadows.
  if texture != nil:
    return texture
  if modelMeshCache.shadowFallback == nil:
    modelMeshCache.shadowFallback = newRenderTarget(1, 1, color = false)
    pushTarget(modelMeshCache.shadowFallback)
    clearDepth()
    popTarget()
  modelMeshCache.shadowFallback.depth

proc whiteModelTexture*(): GpuImage =
  ## Returns the neutral fallback after a material has initialized the cache.
  modelMeshCache.white
