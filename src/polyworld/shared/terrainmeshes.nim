proc setEnvironmentPalette*(
    highlight, shadow: Color, lightDirection = ToonLightDirection
) =
  ## Sets the palette and light every environment shader draws with.
  environmentHighlight = highlight
  environmentShadow = shadow
  environmentLight = lightDirection

proc setEnvironmentPalette*(toon: ToonContext) =
  ## Matches the environment to a character toon context, so scene and
  ## characters share one palette and light.
  setEnvironmentPalette(toon.highlightColor, toon.shadowColor, toon.lightDirection)

proc bakedTexel(image: Image, x, y: int): ColorRGBX =
  ## The colour to bake for one uv sample. Cutout foliage atlases are mostly
  ## transparent and store premultiplied colour, so a vertex whose uv lands
  ## on a clear texel must not bake black: the nearest texel with coverage
  ## in a widening window stands in, and the colour is unpremultiplied.
  for radius in 0 .. 24:
    for dy in -radius .. radius:
      for dx in -radius .. radius:
        if max(abs(dx), abs(dy)) != radius:
          continue
        let
          px = x + dx
          py = y + dy
        if px < 0 or py < 0 or px >= image.width or py >= image.height:
          continue
        let texel = image[px, py]
        if texel.a >= 8:
          return rgbx(
            uint8(min(int(texel.r) * 255 div int(texel.a), 255)),
            uint8(min(int(texel.g) * 255 div int(texel.a), 255)),
            uint8(min(int(texel.b) * 255 div int(texel.a), 255)),
            255)
  rgbx(128, 128, 128, 255)

proc atlasLayer(images: var seq[Image], image: Image): float32 =
  ## The layer one material image will occupy in a pack's texture array.
  for i, known in images:
    if known == image:
      return float32(i)
  images.add image
  float32(images.len - 1)

proc collectPropModels(
    node: gltf.Node, parent: Mat4, models: var seq[PropModel],
    skipPrefix = "", only: seq[string] = @[], images: ptr seq[Image] = nil,
    centerModels = true, materialColors = false,
    textureOverride: Image = nil
) =
  ## Flattens renderable glTF nodes into normalized colored triangle models.
  ## With `only` given, nodes not named in it are skipped. With `images`
  ## given, every material image is gathered there and each vertex keeps
  ## its uv and image layer, for packs drawn textured.
  let world = parent * (translate(node.pos) * node.rot.mat4 * scale(node.scale))
  if node.mesh != nil and
      (skipPrefix.len == 0 or not node.name.startsWith(skipPrefix)) and
      (only.len == 0 or node.name in only):
    var
      points: seq[Vec3]
      colors: seq[Vec3]
      uvs: seq[Vec3]
      sourceNormals: seq[Vec3]
      low = vec3(float32.high, float32.high, float32.high)
      high = vec3(float32.low, float32.low, float32.low)
    # Normals need the inverse transpose: node scales can be wildly
    # non-uniform (the rock pack), which distorts rotated normals.
    let normalMatrix = world.inverse.transpose
    for primitive in node.mesh.primitives:
      let
        image =
          if primitive.material == nil or primitive.material.baseColor == nil:
            nil
          elif textureOverride != nil:
            textureOverride
          else:
            primitive.material.baseColor
        layer =
          if images != nil and image != nil: atlasLayer(images[], image)
          else: 0.0'f32
      template addCorner(index: int) =
        let point = world * primitive.points[index]
        low = min(low, point)
        high = max(high, point)
        points.add point
        if index < primitive.uvs.len:
          uvs.add vec3(primitive.uvs[index].x, primitive.uvs[index].y, layer)
        else:
          uvs.add vec3(0, 0, layer)
        if index < primitive.normals.len:
          let transformed = normalMatrix * vec4(
            primitive.normals[index].x,
            primitive.normals[index].y,
            primitive.normals[index].z,
            0
          )
          sourceNormals.add normalize(vec3(
            transformed.x,
            transformed.y,
            transformed.z
          ))
        else:
          sourceNormals.add vec3(0, 0, 0)
        if materialColors:
          var tint = vec3(1)
          if primitive.material != nil:
            let factor = primitive.material.baseColorFactor
            tint = vec3(factor.r, factor.g, factor.b)
          if index < primitive.colors.len:
            let shade = primitive.colors[index]
            tint *= vec3(shade.r.float32, shade.g.float32,
              shade.b.float32) / 255'f
          colors.add tint
        elif image != nil and index < primitive.uvs.len:
          let
            uv = primitive.uvs[index]
            px = clamp(int(uv.x * image.width.float32), 0, image.width - 1)
            py = clamp(int(uv.y * image.height.float32), 0, image.height - 1)
            sample = bakedTexel(image, px, py)
          colors.add vec3(
            sample.r.float32 / 255 * primitive.material.baseColorFactor.r,
            sample.g.float32 / 255 * primitive.material.baseColorFactor.g,
            sample.b.float32 / 255 * primitive.material.baseColorFactor.b
          )
        elif primitive.material != nil:
          # No UVs (e.g. the grass pack): flat material color.
          colors.add vec3(
            primitive.material.baseColorFactor.r,
            primitive.material.baseColorFactor.g,
            primitive.material.baseColorFactor.b
          )
        else:
          colors.add vec3(0.5, 0.5, 0.5)
      if primitive.indices32.len > 0:
        for index in primitive.indices32:
          addCorner(index.int)
      elif primitive.indices16.len > 0:
        for index in primitive.indices16:
          addCorner(index.int)
    if points.len > 0:
      let
        height = max(high.y - low.y, 0.001'f32)
        center = (low + high) / 2
      var model = PropModel(
        name: node.name, height: height, materialColors: materialColors
      )
      for t in countup(0, points.len - 3, 3):
        # Authored normals when the model has them; otherwise flat facet
        # normals from the triangle.
        var facet = cross(
          points[t + 1] - points[t], points[t + 2] - points[t])
        if facet.length > 0:
          facet = facet.normalize
        else:
          facet = vec3(0, 1, 0)
        for i in t .. t + 2:
          let
            point =
              if centerModels:
                points[i] - vec3(center.x, low.y, center.z)
              else:
                points[i]
            normal =
              if sourceNormals[i].length > 0.5: sourceNormals[i]
              else: facet
          model.vertices.add point.x
          model.vertices.add point.y
          model.vertices.add point.z
          model.vertices.add colors[i].x
          model.vertices.add colors[i].y
          model.vertices.add colors[i].z
          model.vertices.add normal.x
          model.vertices.add normal.y
          model.vertices.add normal.z
          model.uvs.add uvs[i].x
          model.uvs.add uvs[i].y
          model.uvs.add uvs[i].z
      models.add model
  for child in node.nodes:
    collectPropModels(
      child, world, models, skipPrefix, only, images, centerModels,
      materialColors, textureOverride)

proc mergePropModels(models: seq[PropModel], name: string): PropModel =
  ## Centers a complete asset once, preserving offsets between its meshes.
  result = PropModel(name: name)
  if models.len > 0:
    result.materialColors = models[0].materialColors
  var
    low = vec3(float32.high)
    high = vec3(float32.low)
  for model in models:
    result.vertices.add model.vertices
    result.uvs.add model.uvs
    for i in countup(0, model.vertices.len - 9, 9):
      let point = vec3(
        model.vertices[i], model.vertices[i + 1], model.vertices[i + 2])
      low = min(low, point)
      high = max(high, point)
  if result.vertices.len == 0:
    raise newException(QuadTerrainError, "No prop meshes in asset: " & name)
  let center = vec3((low.x + high.x) / 2, low.y, (low.z + high.z) / 2)
  result.height = max(high.y - low.y, 0.001'f)
  for i in countup(0, result.vertices.len - 9, 9):
    result.vertices[i] -= center.x
    result.vertices[i + 1] -= center.y
    result.vertices[i + 2] -= center.z

proc scalePack(models: var seq[PropModel], targetTallest: float32) =
  ## Scales a whole pack by one factor (tallest model becomes targetTallest
  ## tiles) so relative sizes within the pack are preserved.
  var tallest = 0.001'f32
  for model in models:
    tallest = max(tallest, model.height)
  let packScale = targetTallest / tallest
  for model in models.mitems:
    model.height *= packScale
    var i = 0
    while i < model.vertices.len:
      model.vertices[i] *= packScale
      model.vertices[i + 1] *= packScale
      model.vertices[i + 2] *= packScale
      i += 9

proc normalizeModels(models: var seq[PropModel]) =
  ## Scales each model independently to unit height — for packs whose
  ## showroom sizes vary wildly and carry no meaningful relative scale.
  for model in models.mitems:
    let factor = 1.0'f32 / max(model.height, 0.001)
    model.height = 1.0
    var i = 0
    while i < model.vertices.len:
      model.vertices[i] *= factor
      model.vertices[i + 1] *= factor
      model.vertices[i + 2] *= factor
      i += 9

proc brighten(models: var seq[PropModel], factor: float32) =
  ## Scales the baked vertex colors; some packs are authored very dark.
  for model in models.mitems:
    var i = 0
    while i < model.vertices.len:
      model.vertices[i + 3] = min(model.vertices[i + 3] * factor, 1.0)
      model.vertices[i + 4] = min(model.vertices[i + 4] * factor, 1.0)
      model.vertices[i + 5] = min(model.vertices[i + 5] * factor, 1.0)
      i += 9

## Handpainted trees: textured glb meshes from ../polyworld_data/terrain/handpainted_trees.
## Every variant of a model shares its UV layout, so one texture array holds
## all the paintings and each planted tree picks a layer.

proc collectTreeMesh(
    node: gltf.Node, parent: Mat4,
    points: var seq[Vec3], uvs: var seq[Vec2], normals: var seq[Vec3]
) =
  ## Flattens a glb node tree into world-space triangle soup keeping UVs.
  let world = parent * (translate(node.pos) * node.rot.mat4 * scale(node.scale))
  if node.mesh != nil:
    let normalMatrix = world.inverse.transpose
    for primitive in node.mesh.primitives:
      template addCorner(index: int) =
        points.add world * primitive.points[index]
        uvs.add primitive.uvs[index]
        let transformed = normalMatrix * vec4(
          primitive.normals[index].x, primitive.normals[index].y,
          primitive.normals[index].z, 0)
        normals.add normalize(vec3(transformed.x, transformed.y, transformed.z))
      if primitive.indices32.len > 0:
        for index in primitive.indices32:
          addCorner(index.int)
      else:
        for index in primitive.indices16:
          addCorner(index.int)
  for child in node.nodes:
    collectTreeMesh(child, world, points, uvs, normals)

proc loadTreeModel(
    name: string, weight: float32, summerLayers, autumnLayers: seq[int]
): TreeModel =
  ## Loads one tree glb, recentering it on its trunk base.
  var
    points: seq[Vec3]
    uvs: seq[Vec2]
    normals: seq[Vec3]
  collectTreeMesh(
    readGltfFile(&"{DataRoot}/terrain/handpainted_trees/{name}.glb").root, mat4(),
    points, uvs, normals)
  var
    low = vec3(float32.high, float32.high, float32.high)
    high = vec3(float32.low, float32.low, float32.low)
  for point in points:
    low = min(low, point)
    high = max(high, point)
  let center = (low + high) / 2
  result = TreeModel(
    name: name, height: high.y - low.y, weight: weight,
    summerLayers: summerLayers, autumnLayers: autumnLayers)
  for i, point in points:
    let p = point - vec3(center.x, low.y, center.z)
    result.width = max(result.width, 2 * sqrt(p.x * p.x + p.z * p.z))
    result.vertices.add p.x
    result.vertices.add p.y
    result.vertices.add p.z
    result.vertices.add uvs[i].x
    result.vertices.add uvs[i].y
    result.vertices.add normals[i].x
    result.vertices.add normals[i].y
    result.vertices.add normals[i].z

proc scaleTrees(models: var seq[TreeModel], targetTallest: float32) =
  ## Scales the whole tree pack by one factor so relative sizes hold.
  var tallest = 0.001'f32
  for model in models:
    tallest = max(tallest, model.height)
  let packScale = targetTallest / tallest
  for model in models.mitems:
    model.height *= packScale
    model.width *= packScale
    var i = 0
    while i < model.vertices.len:
      model.vertices[i] *= packScale
      model.vertices[i + 1] *= packScale
      model.vertices[i + 2] *= packScale
      i += 8

proc pickTreeModel(rng: var Rand): int =
  ## Weighted choice over the tree models.
  var total = 0.0'f32
  for model in treeModels:
    total += model.weight
  var roll = rng.rand(total.float)
  for i, model in treeModels:
    roll -= model.weight
    if roll <= 0:
      return i
  treeModels.high

proc mipChain(image: Image): seq[Image] =
  ## Full mip chain down to 1x1, box filtered in pixie's premultiplied space.
  result.add image
  while result[^1].width > 1:
    result.add result[^1].minifyBy2()

proc coverage(image: Image): float32 =
  ## Fraction of texels that pass the cutout test.
  var passing = 0
  for c in image.data:
    if c.a.float32 / 255 >= TreeAlphaCutoff:
      inc passing
  passing.float32 / image.data.len.float32

proc loadTreeTextures(style: TreeStyle): seq[seq[Image]] =
  ## Coverage-preserving mip chains. Box filtering thin leaf shapes into
  ## their transparent surroundings drags alpha under the cutoff, so plain
  ## mips shed leaves level by level and distant trees go bald. Each level
  ## instead gets its alpha rescaled until the same fraction of texels
  ## passes the cutout as at full resolution.
  for name in treeTextures(style):
    let chain = mipChain(readImage(&"{DataRoot}/terrain/handpainted_trees/{name}.png"))
    let target = coverage(chain[0])
    for level, mip in chain:
      # Filtered in premultiplied space (no dark fringes); the cutout
      # shader wants straight color.
      mip.data.toStraightAlpha()
      if level == 0:
        continue
      var lo = 1.0'f32
      var hi = 8.0'f32
      for step in 0 ..< 10:
        let mid = (lo + hi) / 2
        var passing = 0
        for c in mip.data:
          if min(c.a.float32 * mid / 255, 1.0) >= TreeAlphaCutoff:
            inc passing
        if passing.float32 / mip.data.len.float32 < target:
          lo = mid
        else:
          hi = mid
      let alphaScale = (lo + hi) / 2
      for c in mip.data.mitems:
        c.a = uint8(min(c.a.float32 * alphaScale, 255))
    result.add chain

proc loadPropPack*(
    paths: openArray[string], unitHeight = true, brightness = 1.0'f,
    only: seq[string] = @[], textured = false, repeatTexture = false,
    textureSize = 0, mergeNodes = false, materialColors = false,
    textureOverride: Image = nil
): PropPack =
  ## Loads named glTF props, scaled to unit height unless disabled.
  ## MergeNodes joins each file into one prop named after its file stem.
  ## Textured keeps material images and requires an initialized renderer.
  ## TextureOverride swaps textured materials without changing their UVs.
  result = PropPack()
  var images: seq[Image]
  if textured and materialColors:
    # Untextured primitives use layer zero with their material color.
    let white = newImage(1, 1)
    white.fill(rgbx(255, 255, 255, 255))
    images.add white
  for path in paths:
    var models: seq[PropModel]
    collectPropModels(
      readGltfFile(path).root, mat4(), models, only = only,
      images = if textured: images.addr else: nil,
      centerModels = not mergeNodes, materialColors = materialColors,
      textureOverride = textureOverride)
    if mergeNodes:
      result.models.add mergePropModels(models, path.splitFile.name)
    else:
      result.models.add models
  if textured and images.len > 0:
    var size = 1
    for image in images:
      size = max(size, max(image.width, image.height))
    if textureSize > 0:
      size = min(size, textureSize)
    var chains: seq[seq[Image]]
    for image in images:
      let square =
        if image.width == size and image.height == size: image
        else: image.resize(size, size)
      chains.add mipChain(square)
    let wrap =
      if repeatTexture:
        true
      else:
        false
    result.textureArray = createTextureArray(chains, wrap)
    for model in result.models:
      model.textureArray = result.textureArray
  if unitHeight:
    result.models.normalizeModels()
  if brightness != 1.0'f32:
    result.models.brighten(brightness)
  for i, model in result.models:
    result.names[model.name] = i

proc loadPropPack*(
    path: string, unitHeight = true, brightness = 1.0'f,
    only: seq[string] = @[], textured = false, repeatTexture = false,
    textureSize = 0, mergeNodes = false, materialColors = false,
    textureOverride: Image = nil
): PropPack =
  ## Loads an original single-file prop pack through the shared collector.
  loadPropPack(
    @[path], unitHeight, brightness, only, textured, repeatTexture,
    textureSize, mergeNodes, materialColors, textureOverride)

proc createPropPack*(
    nodes: openArray[gltf.Node], textureSize = 512,
    repeatTexture = false, mipmaps = true
): PropPack =
  ## Uploads generated nodes once, preserving their sizes, colors, and shading.
  result = PropPack()
  var images: seq[Image]
  for node in nodes:
    collectPropModels(
      node, mat4(), result.models, images = images.addr,
      centerModels = false, materialColors = true
    )
  if images.len > 0:
    var chains: seq[seq[Image]]
    for image in images:
      # Generator images use straight alpha; filtering needs premultiplied RGB.
      let source = image.copy()
      source.data.toPremultipliedAlpha()
      let square =
        if source.width == textureSize and source.height == textureSize:
          source
        else:
          source.resize(textureSize, textureSize)
      var chain = if mipmaps: mipChain(square) else: @[square]
      for mip in chain.mitems:
        mip.data.toStraightAlpha()
      chains.add chain
    result.textureArray = createTextureArray(
      chains,
      if repeatTexture: true else: false
    )
    for model in result.models:
      model.textureArray = result.textureArray
  for i, model in result.models:
    result.names[model.name] = i

proc retexturePropPack*(
  source: PropPack,
  image: Image,
  textureSize = 512,
  whiteLayer = -1
): PropPack =
  ## Reuses flattened geometry with a new atlas and optional unpainted layer.
  if source == nil or source.textureArray == default(Texture) or image == nil:
    raise newException(QuadTerrainError, "Retexturing needs a textured pack.")
  for model in source.models:
    if not model.materialColors:
      raise newException(
        QuadTerrainError, "Retexturing needs material colors, not baked paint."
      )
  var size = max(image.width, image.height)
  if textureSize > 0:
    size = min(size, textureSize)
  var chains: seq[seq[Image]]
  if whiteLayer >= 0:
    let white = newImage(size, size)
    white.fill(rgbx(255, 255, 255, 255))
    chains.add mipChain(white)
  let square =
    if image.width == size and image.height == size:
      image
    else:
      image.resize(size, size)
  chains.add mipChain(square)
  result = PropPack(
    textureArray: createTextureArray(chains, false)
  )
  for original in source.models:
    let model = PropModel(
      name: original.name,
      height: original.height,
      vertices: original.vertices,
      uvs: original.uvs,
      materialColors: true,
      textureArray: result.textureArray
    )
    for i in countup(2, model.uvs.high, 3):
      model.uvs[i] =
        if whiteLayer >= 0 and model.uvs[i] != whiteLayer.float32:
          1
        else:
          0
    result.names[model.name] = result.models.len
    result.models.add model

proc hasProp*(pack: PropPack, name: string): bool =
  ## Returns whether a pack contains a model with the requested node name.
  pack != nil and name in pack.names

proc propSize*(pack: PropPack, name: string): Vec3 =
  ## Measures one loaded prop after normalization, before placement scaling.
  if not pack.hasProp(name):
    raise newException(QuadTerrainError, "Unknown prop model: " & name)
  let model = pack.models[pack.names[name]]
  var
    low = vec3(float32.high)
    high = vec3(float32.low)
  for i in countup(0, model.vertices.len - 9, 9):
    let point = vec3(
      model.vertices[i], model.vertices[i + 1], model.vertices[i + 2])
    low = min(low, point)
    high = max(high, point)
  high - low

proc pickProp*(
    pack: PropPack,
    name: string,
    origin,
    dir,
    position: Vec3,
    rotation,
    propScale: float32
): float32 =
  ## Ray distance to a placed prop's triangles, or -1 when they miss.
  result = -1
  if not pack.hasProp(name):
    return
  let
    model = pack.models[pack.names[name]]
    world =
      translate(position) * rotateY(rotation) *
      scale(vec3(propScale, propScale, propScale))
  var i = 0
  while i + 26 < model.vertices.len:
    let
      a = world * vec3(
        model.vertices[i],
        model.vertices[i + 1],
        model.vertices[i + 2]
      )
      b = world * vec3(
        model.vertices[i + 9],
        model.vertices[i + 10],
        model.vertices[i + 11]
      )
      c = world * vec3(
        model.vertices[i + 18],
        model.vertices[i + 19],
        model.vertices[i + 20]
      )
      distance = rayTriangle(origin, dir, a, b, c)
    if distance > 0 and (result < 0 or distance < result):
      result = distance
    i += 27

proc placeProp*(
    pack: PropPack,
    name: string,
    position: Vec3,
    rotation = 0.0'f32,
    scale = 1.0'f32,
    tint = vec3(1, 1, 1),
    stretch = vec3(1, 1, 1),
    group = 0'i32
) =
  ## Places a prop; stable groups keep independent textured batches reusable.
  ## Tint multiplies paint or vertex colors; stretch scales before rotation.
  if not pack.hasProp(name):
    raise newException(
      QuadTerrainError,
      "terrain prop '" & name & "' was not found in the loaded pack"
    )
  propPlacements.add PropPlacement(
    model: pack.models[pack.names[name]],
    group: group,
    position: position,
    rotation: rotation,
    scale: scale,
    stretch: stretch,
    tint: tint
  )

proc clearProps*() =
  ## Clears all explicit prop placements without changing scattered props.
  propPlacements.setLen(0)

proc setTileColor*(kind: int, top, skirt: Vec3) =
  ## Replaces one tile kind's tint without changing its texture materials.
  while tileMaterialTable.len <= kind:
    tileMaterialTable.add TileMaterial(
      top: vec3(1, 0, 1),
      skirt: vec3(0.5, 0, 0.5),
      topMaterial: StoneMaterial,
      skirtMaterial: DirtMaterial,
      blendPriority: int32(tileMaterialTable.len + 10)
    )
  tileMaterialTable[kind].top = top
  tileMaterialTable[kind].skirt = skirt

proc setTileMaterial*(
    kind: int,
    topMaterial,
    skirtMaterial: float32,
    top,
    skirt: Vec3,
    blendPriority: int32
) =
  ## Registers one textured tile style, growing the flat style table.
  setTileColor(kind, top, skirt)
  tileMaterialTable[kind].topMaterial = topMaterial
  tileMaterialTable[kind].skirtMaterial = skirtMaterial
  tileMaterialTable[kind].blendPriority = blendPriority

proc averageColor(image: Image): Vec3 =
  ## Averages premultiplied texture colors by their coverage, before lighting.
  var sums: array[4, uint64]
  for pixel in image.data:
    sums[0] += pixel.r.uint64
    sums[1] += pixel.g.uint64
    sums[2] += pixel.b.uint64
    sums[3] += pixel.a.uint64
  if sums[3] == 0:
    return vec3(0)
  vec3(sums[0].float32, sums[1].float32, sums[2].float32) /
    sums[3].float32

proc loadTerrainMaterials(settings: TerrainAssets): seq[seq[Image]] =
  ## Each material's basecolor with its height map packed into alpha. The
  ## alpha isn't coverage here, so mips must not premultiply by it: build
  ## the chain from the opaque color and re-pack height per level.
  terrainAverageColors.setLen(0)
  for name in settings.materials:
    let
      colors = mipChain(readImage(
        &"{DataRoot}/terrain/cartoon_textures/{name}_color.png"))
      heights = mipChain(readImage(
        &"{DataRoot}/terrain/cartoon_textures/{name}_height.png"))
    if colors[0].width != settings.size or
        colors[0].height != settings.size or
        heights.len != colors.len:
      raise newException(
        QuadTerrainError,
        "terrain material has the wrong dimensions: " & name
      )
    terrainAverageColors.add averageColor(colors[0])
    for level in 0 ..< colors.len:
      for i in 0 ..< colors[level].data.len:
        colors[level].data[i].a = heights[level].data[i].r
    result.add colors

proc generatedMaterial(directory, name: string): tuple[color, height: Image] =
  ## Loads an aligned generated pair and attaches color coverage to relief.
  try:
    result.color = readImage(
      DataRoot & "/terrain/" & directory & "/" & name & ".rgb.png"
    )
    result.height = readImage(
      DataRoot & "/terrain/" & directory & "/" & name & ".height.png"
    )
  except PixieError:
    raise newException(QuadTerrainError, getCurrentExceptionMsg())
  if result.color.width != GeneratedTextureSize or
    result.color.height != GeneratedTextureSize or
    result.height.width != GeneratedTextureSize or
    result.height.height != GeneratedTextureSize:
      raise newException(QuadTerrainError, "Expected 256x256 material: " & name)
  for i, value in result.height.data:
    let alpha = result.color.data[i].a
    if value.a != 255 or value.r != value.g or value.g != value.b or
      (directory == "tiles" and alpha != 255):
        raise newException(QuadTerrainError, "Invalid terrain channels: " & name)
    if directory == "stamps":
      let gray = ((value.r.int * alpha.int + 127) div 255).uint8
      result.height.data[i] = rgbx(gray, gray, gray, alpha)

proc loadGeneratedTiles(
    extraTiles: openArray[string],
    extraImages: openArray[GeneratedTileImages]
): seq[seq[Image]] =
  ## Packs independently filtered color and height into the terrain array.
  terrainAverageColors.setLen(0)
  var pairs: seq[GeneratedTileImages]
  for name in @SurfaceNames & @extraTiles:
    pairs.add generatedMaterial("tiles", name)
  pairs.add extraImages
  for pair in pairs:
    if pair.color.width != GeneratedTextureSize or
        pair.color.height != GeneratedTextureSize or
        pair.height.width != GeneratedTextureSize or
        pair.height.height != GeneratedTextureSize:
      raise newException(QuadTerrainError, "Expected 256x256 terrain images")
    let
      colors = mipChain(pair.color)
      heights = mipChain(pair.height)
    terrainAverageColors.add averageColor(colors[0])
    for level in 0 ..< colors.len:
      for i in 0 ..< colors[level].data.len:
        colors[level].data[i].a = heights[level].data[i].r
    result.add colors

proc loadGeneratedStamps(): tuple[colors, heights: seq[seq[Image]]] =
  ## Keeps splat colors and relief in separate arrays with identical coverage.
  for name in SurfaceNames:
    let pair = generatedMaterial("stamps", name)
    result.colors.add mipChain(pair.color)
    result.heights.add mipChain(pair.height)

proc rebuildTerrainData(hardMaterials: openArray[int]) {.measure.} =
  ## Refreshes visual sidecars without altering terrain or simulation flags.
  if not generatedTerrain:
    return
  var materials: seq[int]
  for style in tileMaterialTable:
    materials.add style.topMaterial.int
  try:
    generatedMap = buildTerrainMap(
      layers,
      materials,
      seed,
      1.0'f / terrainTextureScale,
      terrainGrassPatchSize,
      amplitude,
      terrainSplatCount,
      terrainSplatChance,
      terrainAverageColors.len,
      groundMaterialOverrides,
      hardMaterials
    )
  except TerrainMapError:
    raise newException(QuadTerrainError, getCurrentExceptionMsg())
  blendDimensions = uploadTerrainData(blendDataTexture, generatedMap.blends)
  splatDimensions = uploadTerrainData(splatDataTexture, generatedMap.brushes)
  terrainSplatPlacements = generatedMap.placements
  terrainPeakSplats = generatedMap.peak

proc loadWaterNormals(): seq[seq[Image]] =
  ## Water detail uses the same mipmapped texture-array path as terrain and
  ## trees, with one shared-data image per layer.
  for name in WaterNormalTextures:
    result.add mipChain(readImage(
      &"{DataRoot}/terrain/water_normals/{name}.jpg"))

proc setTerrainMaterial*(index: int, color, height: Image) =
  ## Replaces one material layer with a generated basecolor and height map,
  ## packed the same way as the shipped materials. Needs the texture array
  ## that initTerrain builds.
  if terrainTextureArray == default(Texture):
    raise newException(
      QuadTerrainError,
      "terrain materials can only be replaced after initTerrain"
    )
  let
    materialCount = terrainAverageColors.len
    size =
      if generatedTerrain:
        GeneratedTextureSize
      else:
        terrainMaterialSize
  if index < 0 or index >= materialCount:
    raise newException(
      QuadTerrainError,
      "terrain material index out of range: " & $index
    )
  if color.width != size or
      color.height != size or
      height.width != color.width or height.height != color.height:
    raise newException(
      QuadTerrainError,
      "terrain material replacement has the wrong dimensions"
    )
  if terrainMaterialCompressed:
    let replacement = loadTerrainTextures(terrainMaterialPaths, forceRgba = true)
    deleteTexture(terrainTextureArray)
    terrainTextureArray = replacement.texture
    terrainMaterialCompressed = false
  let
    colors = mipChain(color)
    heights = mipChain(height)
  terrainAverageColors[index] = averageColor(colors[0])
  var packed: seq[Image]
  for level in 0 ..< colors.len:
    let mip = colors[level]
    if terrainMaterialPaths.len > 0 and mip.width < 4:
      break
    for i in 0 ..< mip.data.len:
      mip.data[i].a = heights[level].data[i].r
    packed.add mip
  updateTextureArrayLayer(terrainTextureArray, index, packed)

proc clearGroundMask*() =
  ## Returns the terrain to plain corner-material blending.
  groundMaskActive = false

proc setGroundLayers*(stone, dirt, grass: float32, curb = 0.0'f32) =
  ## Names the texture-array layers the ground mask path draws with. The
  ## curb layer only matters while a ground ring is set.
  groundLayerIndices = vec4(stone, dirt, grass, curb)

proc setGroundRing*(
    centerX, centerZ, inner, outer: float32,
    stones, cells: int, fade: float32
) =
  ## Draws a curb of cut stones around a circle in world xz: `stones` around
  ## the ring from a sheet holding `cells` stones per side, one stone row
  ## spanning inner .. outer, dropping out over `fade` past the outer edge.
  groundRingValues = vec4(centerX, centerZ, inner, outer)
  groundRingShapeValues = vec3(float32(stones), float32(cells), fade)

proc clearGroundRing*() =
  ## Removes the curb.
  groundRingShapeValues = vec3(0)

proc showAllTerrain*() =
  ## Restores fully lit terrain for an omniscient spectator view.
  var values = newSeq[uint8](visibilitySize * visibilitySize)
  for value in values.mitems:
    value = 255
  uploadTerrainVisibility(values, visibilitySize)

## Prop scattering

proc groundOffset*(worldX, worldZ: float32): float32 =
  ## Reads the visual ground displacement for props, units, and effects.
  if layers.len > 0:
    result = reliefHeight(groundRelief, layers[0], worldX, worldZ)

proc renderTops(layerIndex, index: int): array[4, float32] =
  ## Adds optional visual relief to one tile's unpacked ground corners.
  result = layers[layerIndex].tiles[index].tops.unpack
  if layerIndex == 0 and groundRelief.len > 0:
    for corner in 0 .. 3:
      result[corner] += groundRelief[index][corner]

proc scatterGrass*(
    count, randomSeed: int,
    matchTerrain = false,
    exclusionMask: openArray[uint8] = [],
    exclusionMaskSize = 0,
    exclusionMaskChannels = 0,
    exclusionThreshold = 96'u8
) =
  ## Grass puffs: walkable decoration scattered on plain grass tiles only,
  ## jittered inside the tile, optionally colored from the terrain beneath.
  ## A visual-material mask can suppress puffs where paint replaces grass.
  ## Call after the ground layer is built and before bakeTerrain.
  if exclusionMask.len > 0:
    doAssert exclusionMaskSize > 0 and exclusionMaskChannels > 0
    doAssert exclusionMask.len ==
      exclusionMaskSize * exclusionMaskSize * exclusionMaskChannels
  grassPlacements.setLen(0)
  grassMatchesTerrain = matchTerrain
  if grassModels.len == 0 or layers.len == 0:
    return
  template gtile(x, z: int): Tile =
    layers[0].tiles[(z) * layers[0].width + (x)]
  var grassRng = initRand(randomSeed.int64 * 31_337'i64 + 7'i64)
  var attempts = 0
  var placed = 0
  while placed < count and attempts < count * 20:
    inc attempts
    let
      x = grassRng.rand(layers[0].width - 1)
      z = grassRng.rand(layers[0].depth - 1)
    if not gtile(x, z).exists or gtile(x, z).impassable or
        gtile(x, z).kind != GrassTile:
      continue
    let
      h = renderTops(0, z * layers[0].width + x)
      offsetX = 0.15'f32 + grassRng.rand(0.7).float32
      offsetZ = 0.15'f32 + grassRng.rand(0.7).float32
      height = (h[0] * (1 - offsetX) + h[1] * offsetX) * (1 - offsetZ) +
        (h[2] * (1 - offsetX) + h[3] * offsetX) * offsetZ
    if exclusionMask.len > 0:
      let
        maskX = clamp(int(
          (x.float32 + offsetX) * exclusionMaskSize.float32 /
            layers[0].width.float32), 0, exclusionMaskSize - 1)
        maskZ = clamp(int(
          (z.float32 + offsetZ) * exclusionMaskSize.float32 /
            layers[0].depth.float32), 0, exclusionMaskSize - 1)
        maskIndex = (maskZ * exclusionMaskSize + maskX) *
          exclusionMaskChannels
      var painted = false
      for channel in 0 ..< exclusionMaskChannels:
        if exclusionMask[maskIndex + channel] >= exclusionThreshold:
          painted = true
          break
      if painted:
        continue
    grassPlacements.add TreePlacement(
      model: grassRng.rand(grassModels.len - 1),
      position: vec3(
        (layers[0].originX + x).float32 - HalfGrid + offsetX,
        height,
        (layers[0].originZ + z).float32 - HalfGrid + offsetZ
      ),
      rotation: grassRng.rand(2.0 * PI).float32,
      scale: 0.7'f32 + grassRng.rand(0.7).float32
    )
    inc placed

proc plantRocks*(
    pack: PropPack,
    names: openArray[string],
    kind: uint32,
    randomSeed: int,
    height = 1.6'f,
    sizeRange = vec2(0.8'f, 1.2'f),
    burial = 0.2'f,
    tint = vec3(1),
    mask: openArray[bool] = []
) =
  ## Plants tinted blocker rocks with a seeded size range and buried fraction.
  if pack == nil or names.len == 0 or layers.len == 0:
    return
  let ground = layers[0]
  doAssert mask.len == 0 or mask.len == ground.tiles.len
  for z in 0 ..< ground.depth:
    for x in 0 ..< ground.width:
      let tile = ground.tiles[z * ground.width + x]
      if not tile.exists or tile.kind != kind:
        continue
      if mask.len > 0 and not mask[z * ground.width + x]:
        continue
      var rng = initRand(
        x.int64 * 73_856_093 + z.int64 * 19_349_663 +
          randomSeed.int64 * 83_492_791 + 1
      )
      let
        model = rng.rand(names.high)
        size = height * (sizeRange.x +
          rng.rand((sizeRange.y - sizeRange.x).float).float32)
        tops = renderTops(0, z * ground.width + x)
      pack.placeProp(
        names[model],
        vec3(
          (ground.originX + x).float32 - HalfGrid + 0.5'f,
          (tops[1] + tops[2]) / 2 - size * burial,
          (ground.originZ + z).float32 - HalfGrid + 0.5'f
        ),
        rotation = rng.rand(2 * PI).float32,
        scale = size,
        tint = tint
      )

proc scatterRocks*(count, randomSeed: int, scale = 1.0'f) =
  ## Scatters decorative boulders with scaled size and burial depth.
  rockPlacements.setLen(0)
  if rockModels.len == 0 or layers.len == 0:
    return
  template gtile(x, z: int): Tile =
    layers[0].tiles[(z) * layers[0].width + (x)]
  var rockRng = initRand(randomSeed.int64 * 104_729'i64 + 3'i64)
  var attempts = 0
  while rockPlacements.len < count and attempts < count * 40:
    inc attempts
    let
      x = rockRng.rand(layers[0].width - 1)
      z = rockRng.rand(layers[0].depth - 1)
    if not gtile(x, z).exists or gtile(x, z).impassable or
        gtile(x, z).kind != RockTile:
      continue  # natural rock only; StoneTile construction gets none
    let
      h = renderTops(0, z * layers[0].width + x)
      model = rockRng.rand(rockModels.len - 1)
      boulderScale = (rockScaleRange.x +
        rockRng.rand(rockScaleRange.y.float).float32) * scale
    rockPlacements.add TreePlacement(
      model: model,
      position: vec3(
        (layers[0].originX + x).float32 - HalfGrid + 0.5,
        (h[0] + h[1] + h[2] + h[3]) / 4.0 -
          rockModels[model].height * boulderScale * rockBurial,
        (layers[0].originZ + z).float32 - HalfGrid + 0.5
      ),
      rotation: rockRng.rand(2.0 * PI).float32,
      scale: boulderScale
    )

## Mesh

proc bakeInstance(
    model: PropModel,
    position: Vec3,
    rotation,
    instanceScale: float32,
    writeIndex: var int,
    stretch = vec3(1, 1, 1),
    tint = vec3(1, 1, 1)
) =
  ## Writes one transformed prop instance into the shared baked prop mesh.
  let
    cosine = cos(rotation)
    sine = sin(rotation)
  var i = 0
  while i < model.vertices.len:
    let
      x = model.vertices[i] * instanceScale * stretch.x
      y = model.vertices[i + 1] * instanceScale * stretch.y
      z = model.vertices[i + 2] * instanceScale * stretch.z
      normalX = model.vertices[i + 6]
      normalZ = model.vertices[i + 8]
    propMesh[writeIndex] = position.x + cosine * x - sine * z
    propMesh[writeIndex + 1] = position.y + y
    propMesh[writeIndex + 2] = position.z + sine * x + cosine * z
    propMesh[writeIndex + 3] = model.vertices[i + 3] * tint.x
    propMesh[writeIndex + 4] = model.vertices[i + 4] * tint.y
    propMesh[writeIndex + 5] = model.vertices[i + 5] * tint.z
    propMesh[writeIndex + 6] = cosine * normalX - sine * normalZ
    propMesh[writeIndex + 7] = model.vertices[i + 7]
    propMesh[writeIndex + 8] = sine * normalX + cosine * normalZ
    writeIndex += 9
    i += 9

proc bakePlacements(
    models: openArray[PropModel],
    placements: openArray[TreePlacement],
    writeIndex: var int
) =
  ## Writes a set of prop placements into the shared baked prop mesh.
  for placement in placements:
    if models[placement.model].textureArray != default(Texture):
      continue
    bakeInstance(
      models[placement.model], placement.position,
      placement.rotation, placement.scale, writeIndex)

proc terrainTileColor*(layerIndex, tileIndex: int): Vec3 =
  ## Reads a baked tile's average texture color and authored tint.
  let
    tile = layers[layerIndex].tiles[tileIndex]
    style = tileMaterialTable[tile.kind.int]
    material =
      if generatedTerrain:
        generatedMap.layers[layerIndex].materials[tileIndex]
      else:
        style.topMaterial.int
  terrainAverageColors[material] * style.top

proc terrainColorAt(position: Vec3): Vec3 =
  ## Blends texture averages at a grass root using the terrain's neighborhoods.
  let
    ground = layers[0]
    tileX = int(floor(position.x + HalfGrid)) - ground.originX
    tileZ = int(floor(position.z + HalfGrid)) - ground.originZ
    tileIndex = tileZ * ground.width + tileX
    style = tileMaterialTable[ground.tiles[tileIndex].kind.int]
  result = terrainAverageColors[style.topMaterial.int]
  if generatedTerrain:
    let
      tilePos = vec2(position.x, position.z)
      tileUv = tilePos - floor(tilePos)
      quadrant = int(floor(tileUv.x + 0.5'f)) +
        int(floor(tileUv.y + 0.5'f)) * 2
      centerUv = tilePos - floor(tilePos + vec2(0.5)) + vec2(0.5)
      first = (generatedMap.layers[0].ranges[tileIndex].z.int + quadrant) * 4
      materials = vec4(
        generatedMap.blends[first],
        generatedMap.blends[first + 1],
        generatedMap.blends[first + 2],
        generatedMap.blends[first + 3]
      )
      weights = materialWeights(radialWeights(centerUv), materials)
    result = vec3(0)
    for i in 0 .. 3:
      if materials[i] >= 0:
        result += terrainAverageColors[materials[i].int] * weights[i]
  let elevation = clamp(
    position.y / max(amplitude, 0.001'f) * 0.5'f + 0.5'f,
    0.0'f,
    1.0'f
  )
  result *= style.top * (0.75'f + 0.5'f * elevation)

proc bakeGrassPlacements(writeIndex: var int) =
  ## Replaces the grass mesh's green paint with the local terrain color.
  for placement in grassPlacements:
    let first = writeIndex
    bakeInstance(
      grassModels[placement.model],
      placement.position,
      placement.rotation,
      placement.scale,
      writeIndex
    )
    if grassMatchesTerrain:
      let color = terrainColorAt(placement.position)
      for i in countup(first, writeIndex - 9, 9):
        propMesh[i + 3] = color.x
        propMesh[i + 4] = color.y
        propMesh[i + 5] = color.z

proc bakeTree(
    model: TreeModel,
    textureLayer: int,
    position: Vec3,
    rotation,
    instanceScale,
    widthScale,
    brightness: float32,
    writeIndex: var int
) =
  ## Writes one transformed tree instance into the baked tree mesh.
  let
    cosine = cos(rotation)
    sine = sin(rotation)
  var i = 0
  while i < model.vertices.len:
    let
      x = model.vertices[i] * instanceScale * widthScale
      y = model.vertices[i + 1] * instanceScale
      z = model.vertices[i + 2] * instanceScale * widthScale
      normal = normalize(vec3(
        model.vertices[i + 5] / widthScale,
        model.vertices[i + 6],
        model.vertices[i + 7] / widthScale
      ))
    treeMesh[writeIndex] = position.x + cosine * x - sine * z
    treeMesh[writeIndex + 1] = position.y + y
    treeMesh[writeIndex + 2] = position.z + sine * x + cosine * z
    treeMesh[writeIndex + 3] = model.vertices[i + 3]
    treeMesh[writeIndex + 4] = model.vertices[i + 4]
    treeMesh[writeIndex + 5] = textureLayer.float32
    treeMesh[writeIndex + 6] = cosine * normal.x - sine * normal.z
    treeMesh[writeIndex + 7] = normal.y
    treeMesh[writeIndex + 8] = sine * normal.x + cosine * normal.z
    treeMesh[writeIndex + 9] = brightness
    writeIndex += TreeVertexSize
    i += 8

proc treeTileSeed(x, z: int): int64 {.inline.} =
  ## Returns the deterministic decoration seed for one tree tile.
  x.int64 * 73_856_093'i64 +
    z.int64 * 19_349_663'i64 +
    seed.int64 * 83_492_791'i64 +
    1'i64

proc chooseTree(x, z: int): TreeChoice =
  ## Chooses a stable tree appearance within the configured size limits.
  var rng = initRand(treeTileSeed(x, z))
  result.model = pickTreeModel(rng)
  let layers =
    if autumnTrees: treeModels[result.model].autumnLayers
    else: treeModels[result.model].summerLayers
  result.textureLayer = layers[rng.rand(layers.len - 1)]
  result.rotation = rng.rand(2.0 * PI).float32
  result.scale = (0.85'f32 + rng.rand(0.45).float32) * treeHeight / 8.4'f32
  result.widthScale = 1
  if treeWidth > 0:
    result.widthScale = min(
      1.0'f,
      treeWidth / max(
        treeModels[result.model].width * result.scale,
        0.001'f
      )
    )

proc treeBrightness(index: int): float32 =
  ## Reads visual tree overrides or the ordinary tree tile material.
  if treeTileBrightness.len > 0:
    return treeTileBrightness[index]
  if layers[0].tiles[index].kind == TreeTile:
    return 1

proc treeMeshFloatCount(): int =
  ## Counts the exact float storage needed by the baked tree mesh.
  if treeModels.len > 0 and layers.len > 0:
    let ground = layers[0]
    for z in 0 ..< ground.depth:
      for x in 0 ..< ground.width:
        let tile = ground.tiles[z * ground.width + x]
        if tile.exists and treeBrightness(z * ground.width + x) > 0:
          result += treeModels[chooseTree(x, z).model].vertices.len div 8 *
            TreeVertexSize

proc propMeshFloatCount(): int =
  ## Counts the exact float storage needed by the baked prop mesh.
  for placement in grassPlacements:
    result += grassModels[placement.model].vertices.len
  for placement in rockPlacements:
    if rockModels[placement.model].textureArray == default(Texture):
      result += rockModels[placement.model].vertices.len
  for placement in propPlacements:
    if placement.model.textureArray == default(Texture):
      result += placement.model.vertices.len

proc bakeTexturedInstance(
    model: PropModel,
    position: Vec3,
    rotation,
    instanceScale: float32,
    tint: Vec3,
    stretch: Vec3,
    mesh: var seq[float32]
) =
  ## Appends one transformed textured prop to a batch mesh.
  let
    cosine = cos(rotation)
    sine = sin(rotation)
  var i = 0
  while i < model.vertices.len:
    let
      x = model.vertices[i] * instanceScale * stretch.x
      y = model.vertices[i + 1] * instanceScale * stretch.y
      z = model.vertices[i + 2] * instanceScale * stretch.z
      normalX = model.vertices[i + 6]
      normalZ = model.vertices[i + 8]
      uv = i div 9 * 3
    mesh.add position.x + cosine * x - sine * z
    mesh.add position.y + y
    mesh.add position.z + sine * x + cosine * z
    mesh.add model.uvs[uv]
    mesh.add model.uvs[uv + 1]
    mesh.add model.uvs[uv + 2]
    mesh.add cosine * normalX - sine * normalZ
    mesh.add model.vertices[i + 7]
    mesh.add sine * normalX + cosine * normalZ
    for channel in 0 ..< 3:
      mesh.add tint[channel] * (
        if model.materialColors: model.vertices[i + 3 + channel]
        else: 1.0'f
      )
    i += 9

proc queueTexturedPlacement(
  placement: PropPlacement,
  slots: var Table[(uint, int32), int]
) =
  ## Collects placements without discarding previously baked meshes.
  let textureArray = placement.model.textureArray
  if textureArray == default(Texture):
    return
  let key = (textureId(textureArray), placement.group)
  if key notin slots:
    slots[key] = texturedBatches.len
    texturedBatches.add TexturedBatch(
      textureArray: textureArray, group: placement.group
    )
  texturedBatches[slots[key]].pending.add placement

proc prepareTexturedBatches() =
  ## Compares complete placement records and rebuilds only changed groups.
  var slots: Table[(uint, int32), int]
  for i, batch in texturedBatches.mpairs:
    batch.pending.setLen(0)
    slots[(textureId(batch.textureArray), batch.group)] = i
  for placement in rockPlacements:
    queueTexturedPlacement(PropPlacement(
      model: rockModels[placement.model],
      position: placement.position,
      rotation: placement.rotation,
      scale: placement.scale,
      tint: vec3(1),
      stretch: vec3(1)
    ), slots)
  for placement in propPlacements:
    queueTexturedPlacement(placement, slots)
  profileBlock "textured geometry":
    for batch in texturedBatches.mitems:
      batch.dirty = batch.pending != batch.placements
      if not batch.dirty:
        continue
      swap(batch.placements, batch.pending)
      batch.mesh.setLen(0)
      for placement in batch.placements:
        bakeTexturedInstance(
          placement.model,
          placement.position,
          placement.rotation,
          placement.scale,
          placement.tint,
          placement.stretch,
          batch.mesh
        )

proc clearSceneProps*() =
  ## Releases match placements and their batches while keeping shared assets.
  propPlacements.setLen(0)
  for batch in texturedBatches.mitems:
    releaseTexturedBatch(batch)
  texturedBatches.setLen(0)

proc closePropPack*(pack: PropPack) =
  ## Releases a generated pack after removing its placements from the scene.
  if pack == nil:
    return
  for model in pack.models:
    releasePropModel(model)
  deleteTexture(pack.textureArray)
  pack.models.setLen(0)
  pack.names.clear()

proc rebuildTexturedBatches() {.measure.} =
  ## Preserves clean buffers and uploads only changed textured groups.
  prepareTexturedBatches()
  profileBlock "textured upload":
    for batch in texturedBatches.mitems:
      if not batch.dirty:
        continue
      if batch.placements.len == 0:
        releaseTexturedBatch(batch)
        continue
      if batch.mesh.len == 0:
        continue
      uploadTexturedBatch(batch)
  var kept = 0
  for i in 0 ..< texturedBatches.len:
    if texturedBatches[i].placements.len == 0:
      continue
    if i != kept:
      swap(texturedBatches[kept], texturedBatches[i])
    inc kept
  texturedBatches.setLen(kept)

proc bakeTreeTiles(writeIndex: var int) =
  ## Plants tile trees using optional visual replacements and brightness.
  if treeModels.len == 0 or layers.len == 0:
    return
  let ground = layers[0]
  for z in 0 ..< ground.depth:
    for x in 0 ..< ground.width:
      let t = ground.tiles[z * ground.width + x]
      let brightness = treeBrightness(z * ground.width + x)
      if not t.exists or brightness <= 0:
        continue
      let
        h = renderTops(0, z * ground.width + x)
        choice = chooseTree(x, z)
      bakeTree(
        treeModels[choice.model],
        choice.textureLayer,
        vec3(
          (ground.originX + x).float32 - HalfGrid + 0.5,
          # Tile centres lie on the renderer's v10-v01 diagonal. Sampling
          # that edge keeps roots on the visible terrain instead of on the
          # bilinear/four-corner mean of a non-planar slope.
          (h[1] + h[2]) / 2.0,
          (ground.originZ + z).float32 - HalfGrid + 0.5
        ),
        choice.rotation,
        choice.scale,
        choice.widthScale,
        brightness,
        writeIndex
      )

proc rebuildTreeMesh() {.measure.} =
  ## Bakes trees, grass, rocks, and props into their colored or textured lists.
  if not terrainInitialized:
    return
  doAssert treeTileBrightness.len == 0 or
    (layers.len > 0 and treeTileBrightness.len == layers[0].tiles.len)
  treeMesh = newSeq[float32](treeMeshFloatCount())
  var treeIndex = 0
  bakeTreeTiles(treeIndex)
  doAssert treeIndex == treeMesh.len
  if treeMesh.len > 0:
    uploadTreeMesh()
  propMesh = newSeq[float32](propMeshFloatCount())
  var writeIndex = 0
  bakeGrassPlacements(writeIndex)
  bakePlacements(rockModels, rockPlacements, writeIndex)
  for placement in propPlacements:
    if placement.model.textureArray != default(Texture):
      continue
    bakeInstance(
      placement.model,
      placement.position,
      placement.rotation,
      placement.scale,
      writeIndex,
      placement.stretch,
      placement.tint
    )
  doAssert writeIndex == propMesh.len
  rebuildTexturedBatches()
  if propMesh.len > 0:
    uploadPropMesh()

proc bakeProps*() {.measure.} =
  ## Refreshes scenery without touching ground geometry, materials, or water.
  rebuildTreeMesh()

proc addTriangle(
    a,
    b,
    c,
    normalA,
    normalB,
    normalC,
    tint: Vec3,
    materials: Vec4,
    weightA,
    weightB,
    weightC: Vec4,
    edgeMask = 0.0'f,
    splatRange = vec3(0, 0, -1)
) =
  ## Appends one textured terrain triangle to the interleaved mesh.
  let start = mesh.len
  mesh.setLen(start + TerrainVertexSize * 3)
  template writeVertex(
      offset: int,
      vertex: Vec3,
      normal: Vec3,
      weight: Vec4
  ) =
    ## Writes one terrain vertex at a known mesh offset.
    mesh[start + offset] = vertex.x
    mesh[start + offset + 1] = vertex.y
    mesh[start + offset + 2] = vertex.z
    mesh[start + offset + 3] = edgeMask
    mesh[start + offset + 4] = normal.x
    mesh[start + offset + 5] = normal.y
    mesh[start + offset + 6] = normal.z
    mesh[start + offset + 7] = tint.x
    mesh[start + offset + 8] = tint.y
    mesh[start + offset + 9] = tint.z
    mesh[start + offset + 10] = materials.x
    mesh[start + offset + 11] = materials.y
    mesh[start + offset + 12] = materials.z
    mesh[start + offset + 13] = materials.w
    mesh[start + offset + 14] = weight.x
    mesh[start + offset + 15] = weight.y
    mesh[start + offset + 16] = weight.z
    mesh[start + offset + 17] = weight.w
    mesh[start + offset + 18] = splatRange.x
    mesh[start + offset + 19] = splatRange.y
    mesh[start + offset + 20] = splatRange.z
  writeVertex(0, a, normalA, weightA)
  writeVertex(TerrainVertexSize, b, normalB, weightB)
  writeVertex(TerrainVertexSize * 2, c, normalC, weightC)

proc addWall(
    top0,
    top1,
    bottom0,
    bottom1,
    normal,
    tint: Vec3,
    material: float32
) =
  ## Connects two edges; degenerates to a single triangle when a corner
  ## pair coincides. Walls use one unblended skirt material.
  let
    materials = vec4(material)
    weight = CornerWeights[0]
  addTriangle(
    top0,
    top1,
    bottom0,
    normal,
    normal,
    normal,
    tint,
    materials,
    weight,
    weight,
    weight
  )
  addTriangle(
    top1,
    bottom1,
    bottom0,
    normal,
    normal,
    normal,
    tint,
    materials,
    weight,
    weight,
    weight
  )

proc faceNormal(h: array[4, float32]): Vec3 =
  ## Gradient normal of one tile's bilinear top surface (unit tile size).
  let
    slopeX = ((h[1] + h[3]) - (h[0] + h[2])) * 0.5
    slopeZ = ((h[2] + h[3]) - (h[0] + h[1])) * 0.5
  normalize(vec3(-slopeX, 1, -slopeZ))

proc cornerNormal(
    layer: QuadLayer, faceNormals: seq[Vec3], x, z, cornerIndex: int
): Vec3 =
  ## Averages the face normals of the tiles sharing this corner, but only
  ## those whose corner height matches exactly — smooth shading across
  ## continuous terrain, hard breaks at cliffs and disconnections.
  let
    cornerX = x + (cornerIndex and 1)
    cornerZ = z + (cornerIndex shr 1)
    myHeight = layer.tiles[z * layer.width + x].tops[cornerIndex]
  var total: Vec3
  for (tileX, tileZ, corner) in [
    (cornerX - 1, cornerZ - 1, 3), (cornerX, cornerZ - 1, 2),
    (cornerX - 1, cornerZ, 1), (cornerX, cornerZ, 0)
  ]:
    if tileX < 0 or tileX >= layer.width or tileZ < 0 or tileZ >= layer.depth:
      continue
    let i = tileZ * layer.width + tileX
    if not layer.tiles[i].exists or layer.tiles[i].tops[corner] != myHeight:
      continue
    total = total + faceNormals[i]
  if total.length < 0.001:
    vec3(0, 1, 0)
  else:
    total.normalize

proc tileMaterial(kind: uint32): TileMaterial =
  ## Returns one clamped tile material style.
  tileMaterialTable[min(kind, tileMaterialTable.high.uint32).int]

proc cornerMaterial(
    layer: QuadLayer,
    x,
    z,
    cornerIndex: int
): float32 =
  ## Chooses the highest-priority material meeting one exact-height corner.
  let
    cornerX = x + (cornerIndex and 1)
    cornerZ = z + (cornerIndex shr 1)
    myHeight = layer.tiles[z * layer.width + x].tops[cornerIndex]
  var best = layer.tiles[z * layer.width + x].kind
  for (tileX, tileZ, corner) in [
    (cornerX - 1, cornerZ - 1, 3),
    (cornerX, cornerZ - 1, 2),
    (cornerX - 1, cornerZ, 1),
    (cornerX, cornerZ, 0)
  ]:
    if tileX < 0 or tileX >= layer.width or
        tileZ < 0 or tileZ >= layer.depth:
      continue
    let index = tileZ * layer.width + tileX
    if not layer.tiles[index].exists or
        layer.tiles[index].tops[corner] != myHeight:
      continue
    let kind = layer.tiles[index].kind
    if tileMaterial(kind).blendPriority >
        tileMaterial(best).blendPriority:
      best = kind
  tileMaterial(best).topMaterial

proc emitStairTreads(
    northWest, northEast, southWest, southEast: Vec3,
    style: TileMaterial, materials: Vec4,
    edgeMask: float32, splatRange: Vec3, treads: int,
    westSide, eastSide: bool
): int =
  ## A tile's navigation surface spans the full rise. Draw level stone
  ## treads above it, with a riser at each lip and closed outer cheeks.
  let
    up = vec3(0, 1, 0)
    rise = (northWest.y - southWest.y) / treads.float32
  for step in 0 ..< treads:
    let
      front = step.float32 / treads.float32
      back = (step + 1).float32 / treads.float32
      a = mix(northWest, southWest, front)
      b = mix(northEast, southEast, front)
      c = mix(northWest, southWest, back) + up * rise
      d = mix(northEast, southEast, back) + up * rise
    let
      nw = mix(CornerWeights[0], CornerWeights[2], front)
      ne = mix(CornerWeights[1], CornerWeights[3], front)
      sw = mix(CornerWeights[0], CornerWeights[2], back)
      se = mix(CornerWeights[1], CornerWeights[3], back)
    addTriangle(a, b, c, up, up, up, style.top, materials,
      nw, ne, sw, edgeMask, splatRange)
    addTriangle(b, d, c, up, up, up, style.top, materials,
      ne, se, sw, edgeMask, splatRange)
  let topEnd = mesh.len
  for step in 0 ..< treads:
    let
      front = step.float32 / treads.float32
      back = (step + 1).float32 / treads.float32
      a = mix(northWest, southWest, front)
      b = mix(northEast, southEast, front)
      c = mix(northWest, southWest, back) + up * rise
      d = mix(northEast, southEast, back) + up * rise
    addWall(c, d, c - up * rise, d - up * rise,
      vec3(0, 0, 1), style.skirt, style.skirtMaterial)
    if westSide:
      addWall(a, c, a, c - up * rise, vec3(-1, 0, 0),
        style.skirt, style.skirtMaterial)
    if eastSide:
      addWall(b, d, b, d - up * rise, vec3(1, 0, 0),
        style.skirt, style.skirtMaterial)
  topEnd

proc recessWidth*(recess: WallRecess, progress: float32): float32 =
  recess.halfWidth * (1 - progress * progress)

proc addRecessedWall(top0, top1, bottom0, bottom1, normal, tint: Vec3,
    material: float32, recess: WallRecess) =
  ## Leave the face intact around the opening and line the pocket with stone.
  let
    center = (top0 + top1) * 0.5
    along = normalize(top1 - top0)
    up = vec3(0, 1, 0)
    level = center - up * (center.y - recess.base)
    sill = recess.bottom
    spring = recess.spring
    radius = recess.halfWidth
    inward = -normal * recess.depth
  proc point(x, y: float32): Vec3 =
    level + along * x + up * y
  proc band(y0, y1, r0, r1: float32) =
    addWall(point(-0.5, y1), point(-r1, y1),
      point(-0.5, y0), point(-r0, y0), normal, tint, material)
    addWall(point(r1, y1), point(0.5, y1),
      point(r0, y0), point(0.5, y0), normal, tint, material)
  addWall(point(-0.5, sill), point(0.5, sill), bottom0, bottom1,
    normal, tint, material)
  band(sill, spring, radius, radius)
  addWall(point(radius, spring), point(radius, spring) + inward,
    point(radius, sill), point(radius, sill) + inward,
    -along, tint * 0.80, material)
  addWall(point(-radius, spring) + inward, point(-radius, spring),
    point(-radius, sill) + inward, point(-radius, sill),
    along, tint * 0.80, material)
  let
    shelfLeft = point(-radius, sill)
    shelfRight = point(radius, sill)
  addWall(shelfLeft, shelfRight, shelfLeft + inward, shelfRight + inward,
    up, tint, material)
  const Segments = 12
  for i in 0 ..< Segments:
    let
      t0 = i.float32 / Segments.float32
      t1 = (i + 1).float32 / Segments.float32
      y0 = spring + recess.rise * t0
      y1 = spring + recess.rise * t1
      r0 = recess.recessWidth(t0)
      r1 = recess.recessWidth(t1)
    band(y0, y1, r0, r1)
    for sign in [-1'f32, 1]:
      let
        a = point(sign * r1, y1)
        b = point(sign * r0, y0)
        lipNormal = normalize(along * (-sign * (y1 - y0)) -
          up * (r0 - r1))
      addWall(a, a + inward, b, b + inward,
        lipNormal, tint * 0.75, material)
  let peak = spring + recess.rise
  addWall(top0, top1, point(-0.5, peak), point(0.5, peak),
    normal, tint, material)
  let backTint = tint * 0.43
  addWall(point(-radius, spring) + inward, point(radius, spring) + inward,
    shelfLeft + inward, shelfRight + inward, normal, backTint, material)
  for i in 0 ..< Segments:
    let
      t0 = i.float32 / Segments.float32
      t1 = (i + 1).float32 / Segments.float32
      y0 = spring + recess.rise * t0
      y1 = spring + recess.rise * t1
      r0 = recess.recessWidth(t0)
      r1 = recess.recessWidth(t1)
    addWall(point(-r1, y1) + inward, point(r1, y1) + inward,
      point(-r0, y0) + inward, point(r0, y0) + inward,
      normal, backTint, material)

proc emitLayer(
    layerIndex: int,
    layer: QuadLayer,
    floorY: float32,
    blockers: openArray[seq[int32]],
    stairKind: uint32,
    stairTreads: int,
    wallRecesses: Table[(int, int, int), WallRecess]
) =
  ## Emits one solid tile layer with tops, skirts, cliffs, and edge masks.
  let w = layer.width
  template wallFace(
      top0, top1, bottom0, bottom1, normal, tint, material: untyped,
      wallX, wallZ, facing: int
  ) =
    let key = (wallX, wallZ, facing)
    if key in wallRecesses:
      let
        recess = wallRecesses[key]
        outward = case facing
          of 0: vec3(1, 0, 0)
          of 1: vec3(0, 0, 1)
          of 2: vec3(-1, 0, 0)
          else: vec3(0, 0, -1)
      addRecessedWall(top0, top1, bottom0, bottom1, outward, tint, material,
        recess)
    else:
      addWall(top0, top1, bottom0, bottom1, normal, tint, material)

  var faceNormals = newSeq[Vec3](layer.tiles.len)
  for i, t in layer.tiles:
    if t.exists:
      faceNormals[i] = faceNormal(renderTops(layerIndex, i))
  for z in 0 ..< layer.depth:
    for x in 0 ..< w:
      let
        i = z * w + x
        t = layer.tiles[i]
      if not t.exists:
        continue
      let
        x0 = (layer.originX + x).float32 - HalfGrid
        x1 = x0 + 1
        z0 = (layer.originZ + z).float32 - HalfGrid
        z1 = z0 + 1
        h = renderTops(layerIndex, i)
        b = t.bottoms.unpack
        v00 = vec3(x0, h[0], z0)
        v10 = vec3(x1, h[1], z0)
        v01 = vec3(x0, h[2], z1)
        v11 = vec3(x1, h[3], z1)
        edgeMask = float32(pathing.edgeMask(layerIndex, x, z, blockers))

      let
        style = tileMaterial(t.kind)
        materials =
          if generatedTerrain:
            vec4(generatedMap.layers[layerIndex].materials[i].float32)
          else:
            vec4(
              cornerMaterial(layer, x, z, 0),
              cornerMaterial(layer, x, z, 1),
              cornerMaterial(layer, x, z, 2),
              cornerMaterial(layer, x, z, 3)
            )
        splatRange =
          if generatedTerrain:
            generatedMap.layers[layerIndex].ranges[i]
          else:
            vec3(0, 0, -1)
        n0 = cornerNormal(layer, faceNormals, x, z, 0)
        n1 = cornerNormal(layer, faceNormals, x, z, 1)
        n2 = cornerNormal(layer, faceNormals, x, z, 2)
        n3 = cornerNormal(layer, faceNormals, x, z, 3)
      let firstTop = mesh.len
      let lastTop =
        if stairTreads > 0 and t.kind == stairKind and h[0] > h[2] and
            h[0] == h[1] and h[2] == h[3]:
          let
            westSide = x == 0 or layer.tiles[i - 1].kind != stairKind or
              layer.tiles[i - 1].tops != t.tops
            eastSide = x == w - 1 or layer.tiles[i + 1].kind != stairKind or
              layer.tiles[i + 1].tops != t.tops
          emitStairTreads(v00, v10, v01, v11, style, materials, edgeMask,
            splatRange, stairTreads, westSide, eastSide)
        else:
          addTriangle(
            v00,
            v10,
            v01,
            n0,
            n1,
            n2,
            style.top,
            materials,
            CornerWeights[0],
            CornerWeights[1],
            CornerWeights[2],
            edgeMask,
            splatRange
          )
          addTriangle(
            v10,
            v11,
            v01,
            n1,
            n3,
            n2,
            style.top,
            materials,
            CornerWeights[1],
            CornerWeights[3],
            CornerWeights[2],
            edgeMask,
            splatRange
          )
          mesh.len
      tileTopOffsets[layerIndex][i] = firstTop ..< lastTop

      if layer.slab:
        # Underside of the slab; never walkable.
        let
          down = vec3(0, -1, 0)
          skirtMaterials = vec4(style.skirtMaterial)
          weight = CornerWeights[0]
        addTriangle(
          vec3(x0, b[0], z0), vec3(x1, b[1], z0), vec3(x0, b[2], z1),
          down, down, down, style.skirt, skirtMaterials,
          weight, weight, weight)
        addTriangle(
          vec3(x1, b[1], z0), vec3(x1, b[3], z1), vec3(x0, b[2], z1),
          down, down, down, style.skirt, skirtMaterials,
          weight, weight, weight)

      # East edge: side wall when open, connecting wall when heights differ.
      # Mismatch walls are emitted from the east/south side only, so each
      # shared edge produces exactly one wall.
      if x == w - 1 or
        not layer.tiles[z * w + x + 1].exists or
        not t.connectedEast:
        let
          y0 = if layer.slab: b[1] else: floorY
          y1 = if layer.slab: b[3] else: floorY
        wallFace(
          v10,
          v11,
          vec3(x1, y0, z0),
          vec3(x1, y1, z1),
          vec3(1, 0, 0),
          style.skirt,
          style.skirtMaterial,
          x, z, 0
        )
      else:
        let n = layer.tiles[z * w + x + 1]
        let nh = renderTops(layerIndex, z * w + x + 1)
        if h[1] != nh[0] or h[3] != nh[2]:
          # The cliff face belongs to the higher side; use its skirt color.
          let cliffStyle =
            if h[1] + h[3] >= nh[0] + nh[2]:
              style
            else:
              tileMaterial(n.kind)
          if (x + 1, z, 2) in wallRecesses:
            wallFace(vec3(x1, nh[0], z0), vec3(x1, nh[2], z1), v10, v11,
              vec3(-1, 0, 0), cliffStyle.skirt, cliffStyle.skirtMaterial,
              x + 1, z, 2)
          else:
            addWall(
              v10,
              v11,
              vec3(x1, nh[0], z0),
              vec3(x1, nh[2], z1),
              vec3(1, 0, 0),
              cliffStyle.skirt,
              cliffStyle.skirtMaterial
            )
        if layer.slab:
          let nb = n.bottoms.unpack
          if b[1] != nb[0] or b[3] != nb[2]:
            addWall(
              vec3(x1, b[1], z0), vec3(x1, b[3], z1),
              vec3(x1, nb[0], z0), vec3(x1, nb[2], z1), vec3(1, 0, 0),
              style.skirt, style.skirtMaterial)

      # South edge.
      if z == layer.depth - 1 or
        not layer.tiles[(z + 1) * w + x].exists or
        not t.connectedSouth:
        let
          y0 = if layer.slab: b[2] else: floorY
          y1 = if layer.slab: b[3] else: floorY
        wallFace(
          v01,
          v11,
          vec3(x0, y0, z1),
          vec3(x1, y1, z1),
          vec3(0, 0, 1),
          style.skirt,
          style.skirtMaterial,
          x, z, 1
        )
      else:
        let n = layer.tiles[(z + 1) * w + x]
        let nh = renderTops(layerIndex, (z + 1) * w + x)
        if h[2] != nh[0] or h[3] != nh[1]:
          let cliffStyle =
            if h[2] + h[3] >= nh[0] + nh[1]:
              style
            else:
              tileMaterial(n.kind)
          if (x, z + 1, 3) in wallRecesses:
            wallFace(vec3(x0, nh[0], z1), vec3(x1, nh[1], z1), v01, v11,
              vec3(0, 0, -1), cliffStyle.skirt, cliffStyle.skirtMaterial,
              x, z + 1, 3)
          else:
            addWall(
              v01,
              v11,
              vec3(x0, nh[0], z1),
              vec3(x1, nh[1], z1),
              vec3(0, 0, 1),
              cliffStyle.skirt,
              cliffStyle.skirtMaterial
            )
        if layer.slab:
          let nb = n.bottoms.unpack
          if b[2] != nb[0] or b[3] != nb[1]:
            addWall(
              vec3(x0, b[2], z1), vec3(x1, b[3], z1),
              vec3(x0, nb[0], z1), vec3(x1, nb[1], z1), vec3(0, 0, 1),
              style.skirt, style.skirtMaterial)

      # West and north edges only need side walls when open (the neighbor,
      # if present and connected, already emitted any mismatch wall).
      if x == 0 or not layer.tiles[z * w + x - 1].exists or
          not layer.tiles[z * w + x - 1].connectedEast:
        let
          y0 = if layer.slab: b[0] else: floorY
          y1 = if layer.slab: b[2] else: floorY
        wallFace(
          v00,
          v01,
          vec3(x0, y0, z0),
          vec3(x0, y1, z1),
          vec3(-1, 0, 0),
          style.skirt,
          style.skirtMaterial,
          x, z, 2
        )
      if z == 0 or not layer.tiles[(z - 1) * w + x].exists or
          not layer.tiles[(z - 1) * w + x].connectedSouth:
        let
          y0 = if layer.slab: b[0] else: floorY
          y1 = if layer.slab: b[1] else: floorY
        wallFace(
          v00,
          v10,
          vec3(x0, y0, z0),
          vec3(x1, y1, z0),
          vec3(0, 0, -1),
          style.skirt,
          style.skirtMaterial,
          x, z, 3
        )

proc emitWaterLayer(layer: QuadLayer) =
  ## Flat water surface plus side faces where the water ends; drawn in its
  ## own transparent pass, so it goes to a separate mesh.
  proc addWaterTriangle(a, b, c, normal: Vec3) =
    ## Appends one position-and-normal water triangle.
    for v in [a, b, c]:
      waterMesh.add v.x
      waterMesh.add v.y
      waterMesh.add v.z
      waterMesh.add normal.x
      waterMesh.add normal.y
      waterMesh.add normal.z
  let w = layer.width
  var surface = float32.low
  for z in 0 ..< layer.depth:
    for x in 0 ..< w:
      let t = layer.tiles[z * w + x]
      if not t.exists:
        continue
      surface = max(surface, t.tops.unpack[0])
      let
        x0 = (layer.originX + x).float32 - HalfGrid
        x1 = x0 + 1
        z0 = (layer.originZ + z).float32 - HalfGrid
        z1 = z0 + 1
        top = t.tops.unpack[0]
        bottom = t.bottoms.unpack[0]
        up = vec3(0, 1, 0)
      addWaterTriangle(
        vec3(x0, top, z0),
        vec3(x1, top, z0),
        vec3(x0, top, z1),
        up
      )
      addWaterTriangle(
        vec3(x1, top, z0),
        vec3(x1, top, z1),
        vec3(x0, top, z1),
        up
      )
      # Side faces on water boundaries.
      if x == w - 1 or not layer.tiles[z * w + x + 1].exists:
        addWaterTriangle(
          vec3(x1, top, z0),
          vec3(x1, top, z1),
          vec3(x1, bottom, z0),
          vec3(1, 0, 0)
        )
        addWaterTriangle(
          vec3(x1, top, z1),
          vec3(x1, bottom, z1),
          vec3(x1, bottom, z0),
          vec3(1, 0, 0)
        )
      if x == 0 or not layer.tiles[z * w + x - 1].exists:
        addWaterTriangle(
          vec3(x0, top, z0),
          vec3(x0, top, z1),
          vec3(x0, bottom, z0),
          vec3(-1, 0, 0)
        )
        addWaterTriangle(
          vec3(x0, top, z1),
          vec3(x0, bottom, z1),
          vec3(x0, bottom, z0),
          vec3(-1, 0, 0)
        )
      if z == layer.depth - 1 or not layer.tiles[(z + 1) * w + x].exists:
        addWaterTriangle(
          vec3(x0, top, z1),
          vec3(x1, top, z1),
          vec3(x0, bottom, z1),
          vec3(0, 0, 1)
        )
        addWaterTriangle(
          vec3(x1, top, z1),
          vec3(x1, bottom, z1),
          vec3(x0, bottom, z1),
          vec3(0, 0, 1)
        )
      if z == 0 or not layer.tiles[(z - 1) * w + x].exists:
        addWaterTriangle(
          vec3(x0, top, z0),
          vec3(x1, top, z0),
          vec3(x0, bottom, z0),
          vec3(0, 0, -1)
        )
        addWaterTriangle(
          vec3(x1, top, z0),
          vec3(x1, bottom, z0),
          vec3(x0, bottom, z0),
          vec3(0, 0, -1)
        )
  waterLayerSurfaces[^1] = if surface == float32.low: 0'f32 else: surface

## Public API

proc initTerrain*(
  treeStyle: TreeStyle = MixedTrees,
  terrainStyle: TerrainStyle = CartoonTerrain,
  rockStyle: RockStyle = LowPolyRocks,
  extraTiles: openArray[string] = [],
  settings = DefaultTerrainAssets,
  extraImages: openArray[GeneratedTileImages] = []
) =
  ## Initializes terrain rendering once before bakeTerrain.
  ## Extra generated tile names append after SurfaceNames without splat stamps.
  ## Assets load from ../polyworld_data/terrain/ relative to the repo root.
  if terrainStyle != GeneratedTerrain and
      (extraTiles.len > 0 or extraImages.len > 0):
    raise newException(QuadTerrainError, "Extra tiles need generated terrain.")
  terrainMaterialSize = settings.size
  terrainUnboostedMaterial = -1.0'f
  treeTileBrightness.setLen(0)
  groundRelief.setLen(0)
  groundMaterialOverrides.setLen(0)
  terrainMaterialPaths.setLen(0)
  terrainMaterialCompressed = false
  initSunShadows()
  generatedTerrain = terrainStyle == GeneratedTerrain
  if generatedTerrain:
    # Restore the complete authored preset together. These controls are public
    # for the terrain experiment, so a previous scene may have changed any of
    # them before another generated terrain is initialized.
    terrainTextureScale = 1.0'f / 2.5'f
    terrainBlendDepth = 0.43'f
    terrainHeightBlend = 1.30'f
    terrainHeightBlending = true
    terrainSplats = true
    terrainSplatCount = 1
    terrainSplatChance = 0.40'f
    terrainSplatAmount = 1.0'f
    terrainGrassPatchSize = 24.0'f
    for kind, material in [
      GrassSurface, DirtSurface, GravelSurface,
      MarshSurface, CobbleSurface, ForestSurface
    ]:
      setTileMaterial(
        kind, material.float32, DirtSurface.float32,
        vec3(1), vec3(0.85), kind.int32
      )
  initTerrainPrograms()
  if generatedTerrain:
    terrainTextureArray = createTextureArray(
      loadGeneratedTiles(extraTiles, extraImages), true
    )
    let stamps = loadGeneratedStamps()
    splatColorArray = createTextureArray(stamps.colors, false)
    splatHeightArray = createTextureArray(stamps.heights, false)
  else:
    if settings.compressed:
      for name in settings.materials:
        terrainMaterialPaths.add DataRoot & "/terrain/cartoon_textures/" &
          name & ".ktx2"
      let loaded = loadTerrainTextures(terrainMaterialPaths)
      terrainTextureArray = loaded.texture
      terrainMaterialCompressed = loaded.compressed
      # Cartoon terrain does not use the generated-terrain color classifier.
      terrainAverageColors = newSeq[Vec3](settings.materials.len)
    else:
      terrainTextureArray = createTextureArray(
        loadTerrainMaterials(settings), true
      )
    let placeholder = @[@[newImage(1, 1)]]
    splatColorArray = createTextureArray(placeholder, false)
    splatHeightArray = createTextureArray(placeholder, false)
  let empty = @[0.0'f, 0.0'f, 0.0'f, 0.0'f]
  splatDimensions = uploadTerrainData(splatDataTexture, empty)
  blendDimensions = uploadTerrainData(blendDataTexture, empty)
  if treeStyle != NoTrees:
    treeTextureArray = createTextureArray(
      loadTreeTextures(treeStyle), false
    )
  if settings.water:
    waterNormalTextureArray = createTextureArray(loadWaterNormals(), true)
  else:
    # Flat shader water needs a complete sampler without imported normal maps.
    let flat = newImage(1, 1)
    flat.fill(rgbx(128, 128, 255, 255))
    waterNormalTextureArray = createTextureArray(
      @[@[flat], @[flat]], true
    )
  initTerrainVisibility()
  showAllTerrain()
  initTerrainBuffers()
  terrainInitialized = true

  # Planting weights and texture array layers per tree model. Fir 03 is a
  # tall old-growth fir with a small crown, planted sparingly; the pack's
  # fir 04 is a bare snag and is left out of the forest entirely.
  case treeStyle
  of NoTrees:
    discard
  of MixedTrees:
    treeModels.add loadTreeModel("tree_fir_01", 25, @[0], @[0])
    treeModels.add loadTreeModel("tree_fir_02", 20, @[0], @[0])
    treeModels.add loadTreeModel("tree_fir_03", 6, @[0], @[0])
    treeModels.add loadTreeModel(
      "tree_leafy_simple", 24, @[1, 2, 5, 6], @[1, 2, 3, 4, 5, 6])
    treeModels.add loadTreeModel(
      "tree_leafy_double", 23, @[7, 8, 11, 12], @[7, 8, 9, 10, 11, 12])
  of EvergreenTrees:
    # Compact layered firs dominate, with a few green broadleaf trees.
    treeModels.add loadTreeModel("tree_fir_01", 52, @[0], @[0])
    treeModels.add loadTreeModel("tree_fir_02", 42, @[0], @[0])
    treeModels.add loadTreeModel(
      "tree_leafy_simple", 6, @[2, 6], @[2, 6])
  of DenseTrees:
    treeModels.add loadTreeModel("tree_fir_01", 25, @[0], @[0])
    treeModels.add loadTreeModel("tree_fir_02", 20, @[0], @[0])
  treeModels.scaleTrees(8.4)
  if settings.grass:
    collectPropModels(readGltfFile(GrassPath).root, mat4(), grassModels)
    grassModels.scalePack(0.7)
  case rockStyle
  of NoRocks:
    discard
  of LowPolyRocks:
    collectPropModels(
      readGltfFile(DataRoot & "/terrain/low_poly_rocks.glb").root,
      mat4(),
      rockModels
    )
    rockModels.normalizeModels()
    rockModels.brighten(2.4)
  of PaintedRocks:
    let
      paths =
        if settings.splitProps: propPaths(PaintedRockPath, PaintedRockNames)
        else: @[PaintedRockPath]
      pack = loadPropPack(
        paths,
        only = @PaintedRockNames,
        textured = true,
        repeatTexture = true
      )
    rockModels = pack.models
    rockScaleRange = vec2(1.1, 1.1) * 0.75'f
    rockBurial = 0.43'f

proc bakeTerrain*(
    rebuildWalkability = true,
    blockers: openArray[seq[int32]] = [],
    stairKind = uint32.high,
    stairTreads = 0,
    hardMaterials: openArray[int] = [],
    wallRecesses: openArray[WallRecess] = []
) {.measure.} =
  ## Rebuilds and uploads terrain and props, with optional tile edge blockers.
  ## Nonzero per-layer blockers affect the overlay only. Omitted grids are open.
  ## Skip walkability rebuilding only after computing the final terrain edits.
  mesh.setLen(0)
  tileTopOffsets.setLen(layers.len)
  for i, layer in layers:
    tileTopOffsets[i] = newSeq[Slice[int]](layer.tiles.len)
    for span in tileTopOffsets[i].mitems:
      span = 0 ..< 0
  waterMesh.setLen(0)
  layerVertexRanges.setLen(0)
  waterLayerRanges.setLen(0)
  waterLayerSurfaces.setLen(0)
  doAssert groundRelief.len == 0 or
    (layers.len > 0 and groundRelief.len == layers[0].tiles.len)
  let floorY = -amplitude - 6
  if rebuildWalkability:
    computeWalkable()
  rebuildTerrainData(hardMaterials)
  var recesses = newSeq[Table[(int, int, int), WallRecess]](layers.len)
  for recess in wallRecesses:
    recesses[recess.layer][(recess.x, recess.z, recess.facing)] = recess
  profileBlock "terrain geometry":
    for i in 0 ..< layers.len:
      let
        first = mesh.len div TerrainVertexSize
        firstWater = waterMesh.len div 6
      waterLayerSurfaces.add 0
      if layers[i].water:
        emitWaterLayer(layers[i])
      else:
        emitLayer(i, layers[i], floorY, blockers, stairKind, stairTreads, recesses[i])
      layerVertexRanges.add first ..< (mesh.len div TerrainVertexSize)
      waterLayerRanges.add firstWater ..< (waterMesh.len div 6)
  rebuildTreeMesh()
  if waterMesh.len > 0:
    uploadWaterMesh()
  meshVertexCount = mesh.len div TerrainVertexSize
  if mesh.len > 0:
    uploadTerrainMesh()

proc updateTerrainEdges*(walkable: PathWalkable) =
  ## Refreshes debug edges from live navigation without rebuilding terrain.
  var
    firstChanged = mesh.len
    lastChanged = 0
  for layerIndex, offsets in tileTopOffsets:
    let width = layers[layerIndex].width
    for i, span in offsets:
      if span.a > span.b:
        continue
      let offset = span.a
      let mask = float32(pathing.edgeMask(
        layerIndex, i mod width, i div width, walkable = walkable))
      if mesh[offset + 3] == mask:
        continue
      for vertex in countup(span.a, span.b, TerrainVertexSize):
        mesh[vertex + 3] = mask
      firstChanged = min(firstChanged, offset)
      lastChanged = max(lastChanged, span.b + 1)
  if firstChanged < lastChanged:
    updateTerrainMeshRange(firstChanged, lastChanged - firstChanged)


proc texturedPropMesh(model: PropModel): seq[float32] =
  ## Builds the model-space textured vertex layout used by both renderers.
  var i = 0
  while i < model.vertices.len:
    let uv = i div 9 * 3
    result.add model.vertices[i]
    result.add model.vertices[i + 1]
    result.add model.vertices[i + 2]
    result.add model.uvs[uv]
    result.add model.uvs[uv + 1]
    result.add model.uvs[uv + 2]
    result.add model.vertices[i + 6]
    result.add model.vertices[i + 7]
    result.add model.vertices[i + 8]
    for channel in 0 ..< 3:
      result.add(
        if model.materialColors: model.vertices[i + 3 + channel]
        else: 1.0'f
      )
    i += 9
