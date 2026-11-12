import
  std/[math, tables],
  chroma, gltf, opengl, silky/atlas, vmath, windy,
  polyworld/[assets, characters, chargen, groves, pathing, quadterrain,
    rtscameras, shadows, terrainsurfaces, toon, treegen, worldbars, worldtexts],
  polyworld/common as artpaths,
  ../light_vs_dark/assets as lvdassets,
  ../light_vs_dark/appearances as lvdlooks,
  ../light_vs_dark/content as lvdcontent,
  common, maps, resources

const
  BuildingNames = ["town_hall", "farm"]
  VillagerColors = [
    [0.72'f, 0.31'f, 0.23'f], [0.29'f, 0.47'f, 0.68'f],
    [0.65'f, 0.49'f, 0.22'f], [0.44'f, 0.32'f, 0.60'f],
    [0.27'f, 0.53'f, 0.37'f], [0.62'f, 0.38'f, 0.48'f]
  ]
  CreatureScale = 1.9'f
  LabelInk = rgbx(255, 255, 255, 255)
  LabelBackground = rgbx(0, 0, 0, 150)

type
  CachedText = object
    value: string
    text: WorldText
  MonsterScene* = ref object
    characters: CharacterScene
    creature: CharacterModel
    villagers: array[VillagerColors.len, CharacterModel]
    grove: Grove
    buildings, huts, berries, supplies: PropPack
    labels: WorldBarRenderer
    landmarkTexts: seq[WorldText]
    sourceTexts, householdTexts, villagerTexts: seq[CachedText]
    hallText: CachedText
    creatureText: WorldText
    labelFont: FontAtlas
    atlasSize: int
    labelTexture: GLuint
    closed: bool

proc addBox(node: Node, position, size, tint: Vec3) =
  ## Adds a colored box to a small supply prop without external assets.
  const
    Points = [
      vec3(-0.5, 0, -0.5), vec3(0.5, 0, -0.5),
      vec3(0.5, 1, -0.5), vec3(-0.5, 1, -0.5),
      vec3(-0.5, 0, 0.5), vec3(0.5, 0, 0.5),
      vec3(0.5, 1, 0.5), vec3(-0.5, 1, 0.5)
    ]
    Faces = [
      [0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3],
      [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]
    ]
  let primitive = Primitive(
    mode: TrianglesMode,
    material: Material(baseColorFactor: color(tint.x, tint.y, tint.z, 1))
  )
  for face in Faces:
    let normal = normalize(cross(
      Points[face[1]] - Points[face[0]],
      Points[face[2]] - Points[face[0]]
    ))
    for corner in [0, 1, 2, 0, 2, 3]:
      primitive.indices32.add primitive.points.len.uint32
      primitive.points.add Points[face[corner]] * size + position
      primitive.normals.add normal
  node.mesh.primitives.add primitive

proc supplyNode(kind: ResourceKind): Node =
  ## Makes food crates, contrasting wood bundles, and a small stone stack.
  result = Node(
    name: $kind, visible: true, scale: vec3(1),
    rot: quat(0, 0, 0, 1), mesh: Mesh()
  )
  case kind
  of BerriesResource, GrainResource, FishResource:
    let
      wood = vec3(0.48'f, 0.30'f, 0.14'f)
      food = case kind
        of BerriesResource: vec3(0.55'f, 0.12'f, 0.32'f)
        of GrainResource: vec3(0.86'f, 0.67'f, 0.28'f)
        else: vec3(0.40'f, 0.67'f, 0.74'f)
    result.addBox(vec3(0), vec3(0.8'f, 0.12'f, 0.6'f), wood)
    for x in [-0.38'f, 0.38'f]:
      result.addBox(vec3(x, 0.1'f, 0), vec3(0.08'f, 0.35'f, 0.6'f), wood)
    for z in [-0.28'f, 0.28'f]:
      result.addBox(vec3(0, 0.1'f, z), vec3(0.8'f, 0.35'f, 0.08'f), wood)
    for i in 0 ..< 6:
      let size =
        if kind == FishResource: vec3(0.08'f, 0.09'f, 0.4'f)
        else: vec3(0.18'f, 0.22'f, 0.18'f)
      result.addBox(vec3((i mod 3).float32 * 0.23'f - 0.23'f,
        0.27'f, (i div 3).float32 * 0.22'f - 0.11'f), size, food)
  of SoftwoodResource, HardwoodResource:
    let tint =
      if kind == SoftwoodResource: vec3(0.68'f, 0.43'f, 0.22'f)
      else: vec3(0.35'f, 0.22'f, 0.14'f)
    for i in 0 ..< 4:
      result.addBox(vec3((i mod 2).float32 * 0.28'f - 0.14'f,
        (i div 2).float32 * 0.24'f, 0), vec3(0.25'f, 0.22'f, 1'f), tint)
    result.addBox(vec3(0, 0, 0), vec3(0.61'f, 0.51'f, 0.06'f),
      vec3(0.76'f, 0.68'f, 0.48'f))
  of StoneResource:
    for i in 0 ..< 3:
      result.addBox(vec3((i mod 2).float32 * 0.37'f - 0.16'f,
        (i div 2).float32 * 0.26'f, 0), vec3(0.34'f, 0.26'f, 0.44'f),
        vec3(0.53'f + i.float32 * 0.04'f))

proc scenePosition(map: MonsterMap, position: Vec2): Vec3 =
  ## Grounds a simulation position on the visible terrain surface.
  vec3(position.x, map.groundHeight(position), position.y)

proc waterLayer(map: MonsterMap): QuadLayer =
  ## Covers the stream bed with one shallow transparent water surface.
  result = QuadLayer(
    originX: map.ground.originX,
    originZ: map.ground.originZ,
    width: MapSize,
    depth: MapSize,
    water: true,
    tiles: newSeq[Tile](MapSize * MapSize)
  )
  for i, tile in map.ground.tiles:
    if tile.kind == MarshTile:
      result.tiles[i] = Tile(
        flags: TileExists or TileConnectedEast or TileConnectedSouth,
        kind: MarshTile,
        tops: [-2'i16, -2, -2, -2]
      )

proc close*(scene: MonsterScene) =
  ## Releases placed scenery and its generated graphics resources once.
  if scene == nil or scene.closed:
    return
  scene.labels.closeWorldBarRenderer()
  clearSceneProps()
  scene.buildings.closePropPack()
  scene.huts.closePropPack()
  scene.berries.closePropPack()
  scene.supplies.closePropPack()
  scene.grove.trees.closePropPack()
  scene.grove.rocks.closePropPack()
  var models = @[scene.creature]
  models.add scene.villagers
  for model in models:
    if model != nil:
      model.file.root.clearFromGpu()
      for merged in model.mergedMeshes:
        merged.clearFromGpu()
  if scene.characters != nil:
    scene.characters.context.destroy()
  scene.creature = nil
  for model in scene.villagers.mitems:
    model = nil
  scene.characters = nil
  scene.closed = true

proc newMonsterScene*(
  window: Window,
  map: MonsterMap,
  atlas: SilkyAtlas,
  atlasTexture: GLuint
): MonsterScene =
  ## Loads the village, generated woodland, and the temporary LvD creature.
  result = MonsterScene()
  let scene = result
  try:
    installImmutableLayers(@[map.ground, waterLayer(map)])
    quadterrain.seed = map.seed
    initTerrain(
      NoTrees,
      GeneratedTerrain,
      NoRocks,
      settings = TerrainAssets(grass: false, water: true, size: 512)
    )
    groundRelief = map.relief
    setTileMaterial(
      RoadTile.int,
      DirtSurface.float32,
      DirtSurface.float32,
      vec3(1),
      vec3(0.85'f),
      2
    )
    setTileMaterial(
      MarshTile.int,
      MarshSurface.float32,
      MarshSurface.float32,
      vec3(0.8'f, 0.87'f, 0.75'f),
      vec3(0.8'f),
      1
    )
    scene.grove = generateGrove(map.seed, {LightTree, LightRock})
    var buildingPaths: seq[string]
    for name in BuildingNames:
      buildingPaths.add artpaths.DataRoot &
        "/terrain/lvd_buildings/models/" & name & ".glb"
    scene.buildings = loadPropPack(
      buildingPaths,
      unitHeight = false,
      textured = true,
      textureSize = 512,
      mergeNodes = true,
      materialColors = true
    )
    scene.huts = loadPropPack(
      artpaths.DataRoot & "/terrain/lvd_buildings/models/blacksmith.glb",
      unitHeight = true,
      textured = true,
      textureSize = 512,
      mergeNodes = true,
      materialColors = true
    )
    var berrySettings = treegen.preset(20, seed = map.seed + 71)
    berrySettings.leafColor = vec3(0.26'f, 0.49'f, 0.17'f)
    berrySettings.flowerKind = PurpleBlossoms
    berrySettings.flowerDensity = 0.65'f
    berrySettings.flowerColor = vec3(0.48'f, 0.13'f, 0.65'f)
    let berryNode = treegen.generate(berrySettings)
    berryNode.name = "berries"
    scene.berries = createPropPack(@[berryNode], textureSize = 256)
    var supplyNodes: seq[Node]
    for kind in ResourceKind:
      supplyNodes.add supplyNode(kind)
    scene.supplies = createPropPack(supplyNodes)
    clearProps()
    for scenery in map.props:
      let pack =
        if scenery.prop == "berries":
          scene.berries
        elif scenery.prop == "hut":
          scene.huts
        else:
          scene.buildings
      pack.placeProp(
        if scenery.prop == "hut": "blacksmith" else: scenery.prop,
        map.scenePosition(scenery.position),
        rotation = scenery.yaw,
        scale = scenery.size
      )
    for i, tile in map.ground.tiles:
      if tile.kind != TreeTile:
        continue
      let
        point = vec2((i mod MapSize).float32 - MapHalf + 0.5'f,
          (i div MapSize).float32 - MapHalf + 0.5'f)
        variant = (i + map.seed) mod BrushVariants
      scene.grove.trees.placeProp(
        modelName(LightTree, variant),
        map.scenePosition(point),
        rotation = (i mod 17).float32 * 0.37'f,
        scale = 1.45'f + (i mod 5).float32 * 0.08'f
      )
    for i in 0 ..< 12:
      let point = vec2(24'f + sin(i.float32 * 1.8'f) * 2'f,
        i.float32 * 4.7'f - 27'f)
      scene.grove.rocks.placeProp(
        modelName(LightRock, i mod BrushVariants),
        map.scenePosition(point),
        rotation = i.float32,
        scale = 0.55'f
      )
    bakeTerrain()
    showAllTerrain()
    let
      manifest = readManifest(ChargenLibrary)
      roster = lvdassets.readCharacterRoster()
    var monsterEntry = roster.players[0][SummonUnit.ord]
    monsterEntry.skinRgb = roster.players[0][PeonUnit.ord].skinRgb
    scene.creature = lvdlooks.loadUnitModel(
      manifest,
      monsterEntry,
      SummonUnit
    )
    for i in 0 ..< scene.villagers.len:
      var villagerEntry = roster.players[0][PeonUnit.ord]
      villagerEntry.skinRgb = [
        0.76'f - (i mod 3).float32 * 0.10'f,
        0.58'f - (i mod 3).float32 * 0.10'f,
        0.43'f - (i mod 3).float32 * 0.08'f
      ]
      for part in villagerEntry.preset.parts.mitems:
        if part.category == "Chest":
          part.rgb = @(VillagerColors[i])
      scene.villagers[i] = lvdlooks.loadUnitModel(
        manifest, villagerEntry, PeonUnit
      )
    scene.characters = newCharacterScene(window)
    scene.characters.useToonShading()
    scene.characters.setToonHour(14.5'f)
    setEnvironmentPalette(scene.characters.toon)
    scene.labels = initWorldBarRenderer()
    scene.labelTexture = atlasTexture
    let font = atlas.fonts["WorldName"]
    scene.labelFont = font
    scene.atlasSize = atlas.size
    for place in map.landmarks:
      scene.landmarkTexts.add layoutText(
        font, atlas.size, place.name, height = 0.55'f, maximumWidth = 8'f
      )
    scene.creatureText = layoutText(
      font, atlas.size, "Moss", height = 0.75'f
    )
  except CatchableError as error:
    scene.close()
    raise newException(MonsterError, "Cannot load the meadow: " & error.msg)

proc creatureClip(world: World): string =
  ## Chooses an animation from the creature's actual simulated activity.
  if world.creature.moving:
    return "Jog_Fwd_Loop"
  if world.active:
    case world.current.kind
    of DanceAction:
      return "Dance_Loop"
    of GatherAction, GiveAction, EatAction:
      return "Interact"
    else:
      discard
  "Idle_Loop"

proc updateText(
  scene: MonsterScene,
  cached: var CachedText,
  value: string,
  height: float32,
  width = 7'f
) =
  ## Rebuilds a world label only when its displayed state changes.
  if cached.value != value:
    cached.value = value
    cached.text = layoutText(scene.labelFont, scene.atlasSize, value,
      height = height, maximumWidth = width)

proc villagerDetail(villager: Villager): string =
  ## Keeps world labels brief while the sidebar shows the full destination.
  case villager.task
  of IdleTask:
    ""
  of GatherTask:
    if villager.moving: "Fetching" else: "Gathering"
  of WithdrawTask:
    "Collecting"
  of DeliverTask:
    if villager.cargo.total() > 0: villager.cargo.inventoryText()
    else: "Homeward"
  of EatTask:
    "Eating"
  of RefuelTask:
    "Hearth"
  of RepairTask:
    "Repairs"

proc drawSupplies(
  scene: MonsterScene,
  world: World,
  viewProjection: Mat4,
  shadow = false
) =
  ## Places real source stock, household supplies, and carried bundles.
  proc supply(kind: ResourceKind, position: Vec3, size: float32, yaw = 0'f) =
    ## Uses the same resource shape in the visible and shadow passes.
    if shadow:
      scene.supplies.drawPropSunDepth($kind, position, yaw, size)
    else:
      scene.supplies.drawProp($kind, position, yaw, size, viewProjection)
  proc stockpile(stock: Inventory, position: Vec2) =
    ## Shows one stack for every kind actually stored at this destination.
    var index = 0
    for kind in ResourceKind:
      if stock[kind] <= 0:
        continue
      let point = position + vec2(
        0.9'f + (index mod 3).float32 * 0.65'f,
        -0.3'f + (index div 3).float32 * 0.65'f
      )
      supply(kind, world.map.scenePosition(point), 0.65'f)
      inc index
  for source in world.sources:
    for i in 0 ..< min(3, (source.amount + 7) div 8):
      let point = source.position + vec2(0.9'f + i.float32 * 0.7'f, 0)
      supply(source.resource, world.map.scenePosition(point), 0.75'f)
  for household in world.households:
    stockpile(household.stock, household.position)
    for i in 0 ..< int(ceil((100'f - household.integrity) / 20'f)):
      let point = household.position + vec2(
        -1.2'f - (i mod 2).float32 * 0.42'f,
        -0.2'f + (i div 2).float32 * 0.48'f
      )
      supply(StoneResource, world.map.scenePosition(point), 0.45'f,
        i.float32 * 1.1'f)
  for place in world.map.landmarks:
    if place.id == "village":
      stockpile(world.stock, place.position)
  for villager in world.villagers:
    for kind in ResourceKind:
      if villager.cargo[kind] > 0:
        let position = world.map.scenePosition(villager.position) +
          vec3(sin(villager.facing) * 0.35'f, 0.75'f,
            cos(villager.facing) * 0.35'f)
        supply(kind, position, 0.55'f, villager.facing)
        break
  for kind in ResourceKind:
    if world.creature.cargo[kind] > 0:
      let position = world.map.scenePosition(world.creature.position) +
        vec3(sin(world.creature.facing) * 0.8'f, 1.1'f,
          cos(world.creature.facing) * 0.8'f)
      supply(kind, position, 1.2'f, world.creature.facing)
      break

proc drawScene*(
  scene: MonsterScene,
  window: Window,
  world: World,
  cameraTarget: Vec3,
  cameraDistance: float32,
  time: float32
) =
  ## Draws one complete world frame before the conversation overlay.
  if scene == nil or scene.closed or window.size.y <= 0:
    return
  let
    eye = rtsCameraEye(cameraTarget, cameraDistance)
    view = lookAt(eye, cameraTarget, vec3(0, 1, 0))
    projection = perspective(
      RtsFieldOfView,
      window.size.x.float32 / window.size.y.float32,
      0.1'f,
      300'f
    )
    position = world.map.scenePosition(world.creature.position)
    viewProjection = projection * view
    cameraForward = normalize(cameraTarget - eye)
    cameraRight = normalize(cross(cameraForward, vec3(0, 1, 0)))
    cameraUp = normalize(cross(cameraRight, cameraForward))
  var
    monsterPose: CharacterPose
    villagerPoses = newSeq[CharacterPose](world.villagers.len)
  scene.characters.prepareCharacter(
    monsterPose,
    scene.creature,
    position,
    world.creature.facing,
    scene.creature.clipIndex(world.creatureClip()),
    time,
    sizeFactor = CreatureScale
  )
  for i, villager in world.villagers:
    let
      model = scene.villagers[i mod scene.villagers.len]
      clip =
        if villager.moving:
          "Jog_Fwd_Loop"
        elif villager.task != IdleTask:
          "Interact"
        else:
          "Idle_Loop"
    scene.characters.prepareCharacter(
      villagerPoses[i],
      model,
      world.map.scenePosition(villager.position),
      villager.facing,
      model.clipIndex(clip),
      time + i.float32
    )
  sunDepthPasses(window.size):
    drawTerrainSunDepth()
    scene.drawSupplies(world, viewProjection, shadow = true)
    scene.characters.sunDepthPass = true
    scene.characters.drawCharacter(monsterPose)
    for pose in villagerPoses.mitems:
      scene.characters.drawCharacter(pose)
    scene.characters.sunDepthPass = false
  scene.characters.beginCharacters(window, view, projection, eye)
  glClearColor(0.14'f, 0.22'f, 0.25'f, 1'f)
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
  scene.characters.toon.drawBackground()
  drawTerrain(viewProjection)
  scene.drawSupplies(world, viewProjection)
  scene.characters.drawCharacter(monsterPose)
  for pose in villagerPoses.mitems:
    scene.characters.drawCharacter(pose)
  scene.characters.finishCharacters()
  drawWater(viewProjection, eye, opacity = 0.7'f,
    highlightOpacity = 0.15'f)
  scene.labels.clear()
  for i, place in world.map.landmarks:
    if world.sourceIndex(place.id) >= 0 or world.householdIndex(place.id) >= 0:
      continue
    scene.labels.addText(
      scene.landmarkTexts[i],
      world.map.scenePosition(place.position) + vec3(0, 0.6'f, 0),
      LabelInk,
      LabelBackground
    )
    if place.id == "village":
      scene.updateText(scene.hallText,
        "Food " & $world.stock.foodTotal() & "  Wood " &
        $(world.stock[SoftwoodResource] + world.stock[HardwoodResource]) &
        "  Stone " & $world.stock[StoneResource], 0.32'f)
      scene.labels.addText(scene.hallText.text,
        world.map.scenePosition(place.position) + vec3(0, 0.15'f, 0),
        LabelInk, LabelBackground)
  scene.sourceTexts.setLen(world.sources.len)
  for i, source in world.sources:
    scene.updateText(scene.sourceTexts[i],
      source.name & ": " & $source.amount, 0.5'f, 9'f)
    scene.labels.addText(scene.sourceTexts[i].text,
      world.map.scenePosition(source.position) + vec3(0, 0.7'f, 0),
      LabelInk, LabelBackground)
  scene.householdTexts.setLen(world.households.len * 2)
  for i, house in world.households:
    let point = world.map.scenePosition(house.position)
    scene.updateText(scene.householdTexts[i * 2], house.name, 0.5'f)
    scene.updateText(scene.householdTexts[i * 2 + 1],
      "Food " & $house.stock.foodTotal() & "  Warmth " & $int(house.fuel) &
      "%  Home " & $int(house.integrity) & "%", 0.32'f, 7.5'f)
    scene.labels.addText(scene.householdTexts[i * 2].text,
      point + vec3(0, 1.1'f, 0), LabelInk, LabelBackground)
    scene.labels.addText(scene.householdTexts[i * 2 + 1].text,
      point + vec3(0, 0.6'f, 0), LabelInk, LabelBackground)
  scene.villagerTexts.setLen(world.villagers.len * 2)
  for i, villager in world.villagers:
    let
      point = world.map.scenePosition(villager.position)
      detail = villager.villagerDetail()
    scene.updateText(scene.villagerTexts[i * 2], villager.name, 0.44'f)
    scene.updateText(scene.villagerTexts[i * 2 + 1], detail, 0.3'f, 5.5'f)
    scene.labels.addText(scene.villagerTexts[i * 2].text,
      point + vec3(0, 2.15'f, 0), LabelInk, LabelBackground)
    scene.labels.addText(scene.villagerTexts[i * 2 + 1].text,
      point + vec3(0, 1.78'f, 0), LabelInk, LabelBackground)
  scene.labels.addText(
    scene.creatureText, position + vec3(0, 3.7'f, 0),
    LabelInk, LabelBackground
  )
  scene.labels.draw(viewProjection, cameraRight, cameraUp, scene.labelTexture)
