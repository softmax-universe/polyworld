type
  QuadTerrainError* = object of CatchableError

  PropModel = ref object
    name: string
    height: float32         # model height before pack scaling
    vertices: seq[float32]  # x y z r g b nx ny nz; pack-scaled, base at y 0
    uvs: seq[float32]       # u v layer per vertex, into the pack's atlases
    textureArray: Texture    # the pack's atlas array; 0 draws vertex colors
    materialColors: bool   # Generated material tints and vertex shading.
    texturedVertexArray: TerrainVertexArray       # immediate textured draw, on first use
    texturedVertexBuffer: TerrainBuffer
    texturedDepthVertexArray: TerrainVertexArray
    vertexArray: TerrainVertexArray
    vertexBuffer: TerrainBuffer
    depthVertexArray: TerrainVertexArray  # position-only view for the sun depth pass
    vertexCount: TerrainCount
  TreePlacement = object
    model: int
    position: Vec3
    rotation: float32
    scale: float32  # mild per-instance jitter around 1

  PropPack* = ref object
    models: seq[PropModel]
    names: OrderedTable[system.string, int]
    textureArray: Texture    # set when the pack was loaded textured

  TexturedBatch = object
    ## Retains one texture and caller-selected group between scene updates.
    textureArray: Texture
    group: int32
    placements, pending: seq[PropPlacement]
    dirty: bool
    mesh: seq[float32]      # x y z u v layer nx ny nz r g b
    vertexArray, depthVertexArray: TerrainVertexArray
    vertexBuffer: TerrainBuffer

  PropPlacement = object
    model: PropModel
    group: int32
    position: Vec3
    rotation: float32
    scale: float32
    stretch: Vec3           # per-axis scale in model space, before turning
    tint: Vec3              # multiplies the texture of textured models

  TreeModel = object
    name: string
    height: float32         # model height before pack scaling
    width: float32          # Crown diameter around the trunk at any rotation.
    weight: float32         # relative planting frequency
    vertices: seq[float32]  # x y z u v nx ny nz; pack-scaled, base at y 0
    summerLayers: seq[int]  # tree texture array layers this mesh can wear:
    autumnLayers: seq[int]  # greens only, or greens plus reds and yellows

var
  treeModels: seq[TreeModel]   # trees; occupy a tile and block it
  grassModels: seq[PropModel]  # grass puffs; walkable decoration
  rockModels: seq[PropModel]   # boulders; half-buried on rock tiles
  grassPlacements: seq[TreePlacement]
  grassMatchesTerrain = false
  rockPlacements: seq[TreePlacement]
  rockScaleRange = vec2(0.9, 1.1)
  rockBurial = 0.45'f
  propPlacements: seq[PropPlacement]
  texturedBatches: seq[TexturedBatch]

const
  TreeAlphaCutoff = 0.5'f32

const
  TerrainTextureSize = 1024
  GeneratedTextureSize = 256
  TerrainVertexSize = 21
  TreeVertexSize = 10
  GrassMaterial* = 0.0'f32
  SandMaterial* = 1.0'f32
  CliffMaterial* = 2.0'f32
  MarshMaterial* = 3.0'f32
  StoneMaterial* = 4.0'f32
  DirtMaterial* = 5.0'f32
  VolcanicMaterial* = 6.0'f32
  UnderwaterMaterial* = 7.0'f32

var
  amplitude* = 2.91'f32   # height scale for shading; also sets the floor
  borderWidth* = 0.05'f32 # width of the passability border strips
  terrainTextureScale* = 0.27'f
    ## Texture repeats per tile, with higher values making smaller patterns.
  terrainUnboostedMaterial* = -1.0'f
    ## Texture layer without elevation or exposure boosts; minus one disables.
  terrainBlendDepth* = 0.12'f32  # blend band width; smaller is more abrupt
  terrainHeightBlend* = 1.2'f32  # how strongly height maps steer the blend
  terrainHeightBlending* = true
  terrainSplats* = true
  terrainSplatCount* = 1
  terrainSplatChance* = 0.4'f
  terrainSplatAmount* = 1.0'f
  terrainGrassPatchSize* = 24.0'f
  terrainSplatPlacements*, terrainPeakSplats*: int
  treeHeight* = 6.0'f32   # tallest tree in tiles, before per-tree jitter
  treeWidth* = 0.0'f
    ## Maximum crown diameter in tiles, or zero to keep the pack proportions.
  treeTileBrightness*: seq[float32]
    ## Optional ground-tile tree brightness; zero omits a tree.
  groundRelief*: TerrainRelief
    ## Visual corner offsets, leaving packed gameplay elevations unchanged.
  groundMaterialOverrides*: seq[int]
    ## Optional generated ground materials; minus one keeps the tile style.
  autumnTrees* = false    # leafy trees may also wear red and yellow
  seed* = 1988            # seeds the per-tile tree rng in bakeTreeTiles
  layerVertexRanges*: seq[Slice[int]]
  waterLayerRanges*: seq[Slice[int]]
    ## Per layer, its vertices in the water mesh (empty for land layers); pass one to
    ## drawWater to draw that water alone.
  waterLayerSurfaces*: seq[float32]
    ## Per layer, the height of its water's surface (its highest top; 0 for land layers).
    ## Filled by bakeTerrain: which baked vertices belong to which layer, so
    ## callers can draw a subset without re-emitting anything.

type TileMaterial* = object
  top*: Vec3
  skirt*: Vec3
  topMaterial*: float32
  skirtMaterial*: float32
  blendPriority*: int32

# Tile material index: texture layers, tints, and blending priority by kind.
var
  terrainMaterialSize = TerrainTextureSize
  terrainMaterialPaths: seq[string]
  terrainMaterialCompressed = false

var tileMaterialTable* = @[
  TileMaterial(
    top: vec3(1),
    skirt: vec3(0.85),
    topMaterial: GrassMaterial,
    skirtMaterial: DirtMaterial,
    blendPriority: 1
  ),
  TileMaterial(
    top: vec3(1),
    skirt: vec3(0.85),
    topMaterial: SandMaterial,
    skirtMaterial: DirtMaterial,
    blendPriority: 5
  ),
  TileMaterial(
    top: vec3(1),
    skirt: vec3(0.9),
    topMaterial: CliffMaterial,
    skirtMaterial: VolcanicMaterial,
    blendPriority: 4
  ),
  TileMaterial(
    top: vec3(1),
    skirt: vec3(0.8, 0.8, 0.75),
    topMaterial: MarshMaterial,
    skirtMaterial: DirtMaterial,
    blendPriority: 2
  ),
  TileMaterial(
    top: vec3(1),
    skirt: vec3(0.9),
    topMaterial: StoneMaterial,
    skirtMaterial: StoneMaterial,
    blendPriority: 6
  ),
  TileMaterial(
    top: vec3(1),
    skirt: vec3(0.85),
    topMaterial: GrassMaterial,
    skirtMaterial: DirtMaterial,
    blendPriority: 0
  ),
]

type GeneratedTileImages* = tuple[color, height: Image]

var
  vertexArray: TerrainVertexArray
  vertexBuffer: TerrainBuffer
  mesh: seq[float32]
  tileTopOffsets: seq[seq[Slice[int]]]
  meshVertexCount = 0
  propVertexArray: TerrainVertexArray
  propVertexBuffer: TerrainBuffer
  propMesh: seq[float32]   # x y z r g b nx ny nz; grass, boulders, props
  treeVertexArray: TerrainVertexArray
  treeVertexBuffer: TerrainBuffer
  treeMesh: seq[float32]   # x y z u v layer nx ny nz brightness.
  waterVertexArray: TerrainVertexArray
  waterVertexBuffer: TerrainBuffer
  waterMesh: seq[float32]  # x y z nx ny nz

const CornerWeights = [
  vec4(1, 0, 0, 0),
  vec4(0, 1, 0, 0),
  vec4(0, 0, 1, 0),
  vec4(0, 0, 0, 1)
]

type TreeChoice = object
  ## What one tree tile grows: model, painting, rotation, and size, all
  ## derived deterministically from the tile coordinates.
  model: int
  textureLayer: int
  rotation: float32
  scale: float32
  widthScale: float32

type WallRecess* = object
  ## An opening in the rendered face of a wall tile. Facing uses edgeLink's
  ## east, south, west, north order, pointing out of the wall.
  layer*, x*, z*, facing*: int
  base*, bottom*, spring*, rise*, halfWidth*, depth*: float32


var
  terrainInitialized = false
  ambientTexture, ambientFallbackTexture: Texture
  ambientOrigin: Vec2
  ambientSpan = vec2(1)
  environmentHighlight = ToonPalettes[0].highlight
  environmentShadow = ToonPalettes[0].shadow
  environmentLight = ToonLightDirection
  visibilitySize = GridTiles
  terrainTextureArray, visibilityTexture, groundMaskTexture: Texture
  splatColorArray, splatHeightArray, splatDataTexture, blendDataTexture: Texture
  splatDimensions, blendDimensions: Vec2
  generatedMap: TerrainMap
  terrainAverageColors: seq[Vec3]
  generatedTerrain = false
  groundMaskActive = false
  groundLayerIndices = vec4(4, 5, 0, 0)
  groundRingValues = vec4(0)
  groundRingShapeValues = vec3(0)
  waterNormalTextureArray, treeTextureArray: Texture
