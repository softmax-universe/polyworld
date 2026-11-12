import
  std/[math, tables],
  chroma, gltf, opengl, silky/atlas, vmath, windy,
  polyworld/[assets, characters, chargen, groves, pathing, quadterrain,
    rtscameras, shadows, terrainsurfaces, toon, treegen, worldbars, worldtexts],
  polyworld/common as artpaths,
  ../light_vs_dark/assets as lvdassets,
  ../light_vs_dark/appearances as lvdlooks,
  ../light_vs_dark/content as lvdcontent,
  common, maps

const
  BuildingNames = ["town_hall", "farm", "church"]
  VillagerPositions = [vec2(-0.8'f, -1.7'f), vec2(3.2'f, -2.6'f),
    vec2(8.0'f, -4.3'f)]
  CreatureScale = 1.9'f
  LabelInk = rgbx(255, 255, 255, 255)
  LabelBackground = rgbx(0, 0, 0, 150)

type MonsterScene* = ref object
  characters: CharacterScene
  creature, villager: CharacterModel
  grove: Grove
  buildings, berries: PropPack
  labels: WorldBarRenderer
  landmarkTexts: seq[WorldText]
  creatureText: WorldText
  labelTexture: GLuint
  closed: bool

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
  scene.berries.closePropPack()
  scene.grove.trees.closePropPack()
  scene.grove.rocks.closePropPack()
  for model in [scene.creature, scene.villager]:
    if model != nil:
      model.file.root.clearFromGpu()
      for merged in model.mergedMeshes:
        merged.clearFromGpu()
  if scene.characters != nil:
    scene.characters.context.destroy()
  scene.creature = nil
  scene.villager = nil
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
    var berrySettings = treegen.preset(20, seed = map.seed + 71)
    berrySettings.leafColor = vec3(0.26'f, 0.49'f, 0.17'f)
    berrySettings.flowerKind = PurpleBlossoms
    berrySettings.flowerDensity = 0.65'f
    berrySettings.flowerColor = vec3(0.48'f, 0.13'f, 0.65'f)
    let berryNode = treegen.generate(berrySettings)
    berryNode.name = "berries"
    scene.berries = createPropPack(@[berryNode], textureSize = 256)
    clearProps()
    for scenery in map.props:
      let pack =
        if scenery.prop == "berries":
          scene.berries
        else:
          scene.buildings
      pack.placeProp(
        scenery.prop,
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
    var villagerEntry = roster.players[0][PeonUnit.ord]
    villagerEntry.skinRgb = [0.82'f, 0.65'f, 0.48'f]
    scene.villager = lvdlooks.loadUnitModel(
      manifest,
      villagerEntry,
      PeonUnit
    )
    scene.characters = newCharacterScene(window)
    scene.characters.useToonShading()
    scene.characters.setToonHour(14.5'f)
    setEnvironmentPalette(scene.characters.toon)
    scene.labels = initWorldBarRenderer()
    scene.labelTexture = atlasTexture
    let font = atlas.fonts["WorldName"]
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
    villagerPoses: array[VillagerPositions.len, CharacterPose]
  scene.characters.prepareCharacter(
    monsterPose,
    scene.creature,
    position,
    world.creature.facing,
    scene.creature.clipIndex(world.creatureClip()),
    time,
    sizeFactor = CreatureScale
  )
  for i, anchor in VillagerPositions:
    let
      point = anchor + vec2(sin(time * 0.2'f + i.float32) * 0.25'f,
        cos(time * 0.2'f + i.float32) * 0.25'f)
      clip =
        if i == 2:
          "Interact"
        else:
          "Idle_Loop"
    scene.characters.prepareCharacter(
      villagerPoses[i],
      scene.villager,
      world.map.scenePosition(point),
      i.float32 * 1.2'f,
      scene.villager.clipIndex(clip),
      time + i.float32
    )
  sunDepthPasses(window.size):
    drawTerrainSunDepth()
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
  scene.characters.drawCharacter(monsterPose)
  for pose in villagerPoses.mitems:
    scene.characters.drawCharacter(pose)
  scene.characters.finishCharacters()
  drawWater(viewProjection, eye, opacity = 0.7'f,
    highlightOpacity = 0.15'f)
  scene.labels.clear()
  for i, place in world.map.landmarks:
    scene.labels.addText(
      scene.landmarkTexts[i],
      world.map.scenePosition(place.position) + vec3(0, 0.6'f, 0),
      LabelInk,
      LabelBackground
    )
  scene.labels.addText(
    scene.creatureText, position + vec3(0, 3.7'f, 0),
    LabelInk, LabelBackground
  )
  scene.labels.draw(viewProjection, cameraRight, cameraUp, scene.labelTexture)
