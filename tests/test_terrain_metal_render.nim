## Exercises native Metal terrain, scenery, water, and shadow pixels.

when not defined(useMetal4):
  {.error: "Run this rendering regression with -d:useMetal4.".}

include ../src/polyworld/backends/passes/quadterrain
import windy

const TestSize = 192

proc coloredPixels(image: Image): int =
  ## Counts pixels drawn over the opaque black test background.
  for pixel in image.data:
    if pixel.r.int + pixel.g.int + pixel.b.int > 24:
      inc result

proc channelTotals(image: Image): array[3, int] =
  ## Measures the material color without depending on exact raster edges.
  for pixel in image.data:
    result[0] += pixel.r.int
    result[1] += pixel.g.int
    result[2] += pixel.b.int

proc darkenedPixels(reference, shadowed: Image): int =
  ## Counts receiver pixels made visibly darker by a shadow caster.
  doAssert reference.width == shadowed.width
  doAssert reference.height == shadowed.height
  for i, pixel in reference.data:
    let
      before = pixel.r.int + pixel.g.int + pixel.b.int
      after = shadowed.data[i].r.int + shadowed.data[i].g.int +
        shadowed.data[i].b.int
    if before > after + 24:
      inc result

proc solidImage(value: ColorRGBX): Image =
  ## Creates a small unambiguous texture-array layer for the pixel checks.
  result = newImage(4, 4)
  result.fill(value)

proc fixturePack(tint: Vec3, texture: Texture = nil): PropPack =
  ## Builds a vertical two-triangle prop with a known material and bounds.
  let model = PropModel(
    name: "card", height: 1.4'f, textureArray: texture, materialColors: true
  )
  for point in [
    vec3(-0.55, 0, 0), vec3(0.55, 0, 0), vec3(-0.55, 1.4, 0),
    vec3(0.55, 0, 0), vec3(0.55, 1.4, 0), vec3(-0.55, 1.4, 0)
  ]:
    model.vertices.add [
      point.x, point.y, point.z, tint.x, tint.y, tint.z,
      0.0'f, 0, 1
    ]
    model.uvs.add [(point.x + 0.55'f) / 1.1'f, point.y / 1.4'f, 1.0'f]
  result = PropPack(models: @[model])
  result.names[model.name] = 0

proc installTreeFixture() =
  ## Uploads the foliage layout with its UVs selecting array layer one.
  treeMesh.setLen(0)
  for point in [
    vec3(-0.55, 0, 0), vec3(0.55, 0, 0), vec3(-0.55, 1.4, 0),
    vec3(0.55, 0, 0), vec3(0.55, 1.4, 0), vec3(-0.55, 1.4, 0)
  ]:
    treeMesh.add [
      point.x, point.y, point.z,
      (point.x + 0.55'f) / 1.1'f, point.y / 1.4'f, 1.0'f,
      0.0'f, 0, 1, 1
    ]
  uploadTreeMesh()

template renderImage(body: untyped): Image =
  ## Captures a completed offscreen frame without presenting a window.
  block:
    beginFrame(TestSize, TestSize, color(0, 0, 0, 1))
    body
    let captured = captureImage()
    endFrame(present = false)
    captured

proc groundCapture(matrix: Mat4, casters: bool): Image =
  ## Draws ground receiving shadows from only the current scenery fixture.
  renderImage:
    sunDepthPasses(ivec2(TestSize, TestSize)):
      if casters:
        drawTerrainSunDepth(vertexCount = 0)
    drawTerrain(matrix, drawProps = false)

proc assertCasterShadow(
    matrix: Mat4, label: string, cutout: Texture = nil
) =
  ## Proves each vertex layout and cutout shader writes usable shadow depth.
  sunShadowsEnabled = true
  setEnvironmentPalette(color(0.8, 0.8, 0.8), color(0.04, 0.04, 0.04),
    -sunDirection)
  let
    unshadowed = groundCapture(matrix, false)
    shadowed = groundCapture(matrix, true)
    changed = darkenedPixels(unshadowed, shadowed)
  doAssert changed > 30,
    label & " must cast a visible terrain shadow, got " & $changed & " pixels."
  if cutout != nil:
    updateTextureArrayLayer(cutout, 1, @[solidImage(rgbx(0, 0, 0, 0))])
    let transparentShadow = groundCapture(matrix, true)
    doAssert darkenedPixels(unshadowed, transparentShadow) == 0,
      label & " transparent fragments must not cast shadows."
  sunShadowsEnabled = false
  setEnvironmentPalette(color(0.8, 0.8, 0.8), color(0.8, 0.8, 0.8))
  echo label, " shadow: ", changed, " pixels"

block nativeRendering:
  let window = newWindow(
    "Metal terrain regression", ivec2(TestSize, TestSize),
    visible = false, vsync = false
  )
  defer:
    closeSunShadows()
    shutdownMetal()
    window.close()
  initMetal(window)
  pollEvents()
  initSunShadows(lightRadius = 8, lightDistance = 20)
  initTerrain(
    treeStyle = NoTrees,
    terrainStyle = GeneratedTerrain,
    rockStyle = NoRocks,
    settings = TerrainAssets(size: 1024)
  )
  sunAzimuth = 25
  sunElevation = 55
  sunShadowStrength = 1
  sunShadowBias = 0.0005'f
  updateSunMatrix()
  sunShadowsEnabled = false
  setEnvironmentPalette(color(0.8, 0.8, 0.8), color(0.8, 0.8, 0.8))
  var layer = QuadLayer(
    originX: GridTiles div 2 - 1, originZ: GridTiles div 2 - 1,
    width: 2, depth: 2, tiles: newSeq[Tile](4)
  )
  for tile in layer.tiles.mitems:
    tile.flags = TileExists or TileConnectedEast or TileConnectedSouth
    tile.kind = GrassTile
  installImmutableLayers(@[layer])
  bakeTerrain()
  let
    center = vec3(0, 0.5, 0)
    cameraEye = center + vec3(3, 4, 6)
    matrix = ortho(-1.8'f, 1.8'f, -1.8'f, 1.8'f, 0.1'f, 40'f) *
      lookAt(cameraEye, center, vec3(0, 1, 0))
    ground = renderImage:
      drawTerrain(matrix, drawProps = false)
  doAssert coloredPixels(ground) > 1000,
    "Generated terrain must produce visible Metal pixels."
  echo "Terrain: ", coloredPixels(ground), " pixels"

  let colored = fixturePack(vec3(1, 0.08, 0.04))
  colored.placeProp("card", vec3(0), 0, 1)
  bakeProps()
  let coloredImage = renderImage:
    drawTerrain(matrix, drawGround = false)
  let coloredChannels = channelTotals(coloredImage)
  doAssert coloredPixels(coloredImage) > 400
  doAssert coloredChannels[0] > coloredChannels[1] * 3
  doAssert coloredChannels[0] > coloredChannels[2] * 3
  assertCasterShadow(matrix, "Colored props")

  clearSceneProps()
  bakeProps()
  let
    green = solidImage(rgbx(20, 220, 35, 255))
    transparent = solidImage(rgbx(0, 0, 0, 0))
    propTexture = createTextureArray(@[
      @[solidImage(rgbx(240, 20, 20, 255))], @[green]
    ], repeat = false)
    textured = fixturePack(vec3(1), propTexture)
  textured.placeProp("card", vec3(0), 0, 1)
  bakeProps()
  let texturedImage = renderImage:
    drawTerrain(matrix, drawGround = false)
  let texturedChannels = channelTotals(texturedImage)
  doAssert coloredPixels(texturedImage) > 400
  doAssert texturedChannels[1] > texturedChannels[0] * 3
  doAssert texturedChannels[1] > texturedChannels[2] * 3,
    "Textured props must sample the selected texture-array layer."
  updateTextureArrayLayer(propTexture, 1, @[transparent])
  let emptyProp = renderImage:
    drawTerrain(matrix, drawGround = false)
  doAssert coloredPixels(emptyProp) == 0,
    "Transparent textured prop fragments must be discarded."
  updateTextureArrayLayer(propTexture, 1, @[green])
  assertCasterShadow(matrix, "Textured props", propTexture)

  clearSceneProps()
  bakeProps()
  let blue = solidImage(rgbx(20, 35, 220, 255))
  treeTextureArray = createTextureArray(@[
    @[solidImage(rgbx(240, 20, 20, 255))], @[blue]
  ], repeat = false)
  installTreeFixture()
  let treeImage = renderImage:
    drawTerrain(matrix, drawGround = false)
  let treeChannels = channelTotals(treeImage)
  doAssert coloredPixels(treeImage) > 400
  doAssert treeChannels[2] > treeChannels[0] * 3
  doAssert treeChannels[2] > treeChannels[1] * 3,
    "Trees must sample the selected texture-array layer."
  updateTextureArrayLayer(treeTextureArray, 1, @[transparent])
  let emptyTree = renderImage:
    drawTerrain(matrix, drawGround = false)
  doAssert coloredPixels(emptyTree) == 0,
    "Transparent foliage fragments must be discarded."
  updateTextureArrayLayer(treeTextureArray, 1, @[blue])
  assertCasterShadow(matrix, "Trees", treeTextureArray)

  waterMesh.setLen(0)
  for point in [
    vec3(-0.9, 0.2, -0.9), vec3(0.9, 0.2, -0.9), vec3(-0.9, 0.2, 0.9),
    vec3(0.9, 0.2, -0.9), vec3(0.9, 0.2, 0.9), vec3(-0.9, 0.2, 0.9)
  ]:
    waterMesh.add [point.x, point.y, point.z, 0.0'f, 1, 0]
  uploadWaterMesh()
  let waterImage = renderImage:
    drawWater(matrix, cameraEye, opacity = 1, highlightOpacity = 0)
  doAssert coloredPixels(waterImage) > 400,
    "The default water shader must draw visible Metal pixels."
  let transparentWater = renderImage:
    drawWater(matrix, cameraEye, opacity = 0, highlightOpacity = 0)
  doAssert coloredPixels(transparentWater) == 0,
    "Zero-opacity water must leave the target color unchanged."
  let groundAfterWater = renderImage:
    drawWater(matrix, cameraEye, opacity = 1, highlightOpacity = 0)
    drawTerrain(matrix, drawProps = false)
  var hiddenGroundPixels = 0
  for i, pixel in ground.data:
    if pixel.r.int + pixel.g.int + pixel.b.int > 24 and
        groundAfterWater.data[i] != pixel:
      inc hiddenGroundPixels
  doAssert hiddenGroundPixels == 0,
    "Water must not write depth and hide later opaque geometry."
  echo "Default water: ", coloredPixels(waterImage), " pixels"

echo "Metal terrain, scenery, water, texture arrays, and shadows passed"
