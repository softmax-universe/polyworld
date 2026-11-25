## Renders a baked terrain water layer through the public Metal water API.

when not defined(useMetal4):
  {.error: "Compile this native rendering test with -d:useMetal4.".}

import
  pixie, shady, vmath, windy,
  polyworld/[assets, pathing, quadterrain, shadows, waters],
  polyworld/backends/metal/common

proc checkColor(pixel: ColorRGBX, expected: array[3, int]) =
  ## Allows one byte of conversion error in a GPU-rendered water color.
  doAssert abs(pixel.r.int - expected[0]) <= 1, $pixel
  doAssert abs(pixel.g.int - expected[1]) <= 1, $pixel
  doAssert abs(pixel.b.int - expected[2]) <= 1, $pixel
  doAssert pixel.a == 255, $pixel

proc backgroundVert(
  gl_Position: var Vec4, uv: var Vec2, position: Vec2
) =
  ## Maps a scene gradient to logical bottom-left viewport coordinates.
  gl_Position = vec4(position.x, position.y, 0, 1)
  uv = position * 0.5'f + vec2(0.5)

proc backgroundFrag(fragColor: var Vec4, uv: Vec2) =
  ## Gives the captured scene different colors above and below the water.
  fragColor = vec4(uv.x, uv.y, 0.2, 1)

proc checkWaterBody() =
  ## Checks reflected and tinted water over the captured opaque scene.
  let window = newWindow(
    "Metal water body check", ivec2(64), visible = false, vsync = false
  )
  defer: window.close()
  initMetal(window)
  defer: shutdownMetal()
  installWaters()
  initTerrain(
    NoTrees, GeneratedTerrain, NoRocks,
    settings = TerrainAssets(size: 256)
  )
  defer: closeSunShadows()
  initWaters()
  defer: destroyWaters()
  let layer = QuadLayer(
    originX: GridTiles div 2 - 2, originZ: GridTiles div 2 - 2,
    width: 4, depth: 4, water: true, tiles: newSeq[Tile](16)
  )
  for tile in layer.tiles.mitems:
    tile.flags = TileExists
    tile.tops = [8'i16, 8, 8, 8]
  installImmutableLayers(@[layer])
  bakeTerrain()
  buildShoreFields()
  doAssert waterLayerRanges[0].len > 0
  let
    eye = vec3(0, 8, 0)
    view = lookAt(eye, vec3(0, 1, 0), vec3(0, 0, -1))
    projection = ortho(-3.0'f, 3, -3, 3, 0.1, 20)
    viewProjection = projection * view
    sky = color(0.8, 0.2, 0.1, 1)
  var params = DefaultWaterParams
  params.color = vec3(0.1, 0.8, 0.2)
  params.colorStrength = 1
  params.reflectiveness = 1
  params.fresnelStrength = 0
  params.sheenStrength = 0
  params.glintStrength = 0
  params.waveHeight = 0
  params.refraction = 0
  params.distortion = 0
  params.foamOpacity = 0
  params.fadeDistance = 0.01
  let body = WaterBody(layer: 0, params: params)
  for reflected in [false, true]:
    beginFrame(64, 64, color(0.1, 0.2, 0.3, 1))
    captureScene(window.size)
    if reflected:
      beginReflection(window.size)
      drawWaterSky(viewProjection, eye, sky, sky, sky)
      endReflection()
    drawWaterBody(
      body, viewProjection, eye, window.size, vec3(0, 1, 0),
      color(1, 1, 1, 1), ivec4(0, 0, 64, 64), reflected
    )
    let output = captureImage()
    output[3, 3].checkColor([26, 51, 77])
    output[32, 32].checkColor(
      if reflected: [204, 51, 26] else: [26, 204, 51]
    )
    echo "Metal water body rendered with reflection ", reflected
  let
    background = newProgram(
      toShader(backgroundVert, metalMSL, shaderVertex),
      toShader(backgroundFrag, metalMSL, shaderFragment),
      VertexLayout(stride: sizeof(Vec2), attributes: @[
        VertexAttribute(name: "position", format: Float2, offset: 0)
      ])
    )
    backgroundVertices = newBuffer([
      vec2(-1, -1), vec2(3, -1), vec2(-1, 3)
    ])
  defer:
    destroy(background)
    destroy(backgroundVertices)
  params.colorStrength = 0
  let clearWater = WaterBody(layer: 0, params: params)
  beginFrame(64, 64, color(1, 0, 0, 1))
  draw(background, backgroundVertices, 3)
  captureScene(window.size)
  drawWaterBody(
    clearWater, viewProjection, eye, window.size, vec3(0, 1, 0),
    color(1, 1, 1, 1), ivec4(0, 0, 64, 64), false
  )
  let refracted = captureImage()
  refracted[32, 20].checkColor([129, 173, 51])
  refracted[32, 44].checkColor([129, 78, 51])
  echo "Metal water refraction preserves the captured scene's Y coordinates"
  echo "Baked Metal water layer capture, tint and reflection passed"

checkWaterBody()
