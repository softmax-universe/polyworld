import
  std/[math, tables],
  chroma, gltf, silky/atlas, vmath, windy,
  polyworld/[renderer, modelresources, assets, characters, chargen, daycycles, groves, lighting,
    pathing, quadterrain, rtscameras, selectionoutlines, shadows,
    terrainsurfaces, toon, treegen, worldbars, worldtexts],
  polyworld/common as artpaths,
  ../light_vs_dark/assets as lvdassets,
  ../light_vs_dark/appearances as lvdlooks,
  ../light_vs_dark/content as lvdcontent,
  common, maps, resources, selections

const
  BuildingNames = ["town_hall", "farm"]
  VillageColors = [
    vec3(0.22'f, 0.48'f, 0.84'f),
    vec3(0.88'f, 0.40'f, 0.16'f),
    vec3(0.14'f, 0.68'f, 0.55'f)
  ]
  VillagerColors = [
    [0.22'f, 0.40'f, 0.75'f], [0.34'f, 0.60'f, 0.88'f],
    [0.79'f, 0.29'f, 0.12'f], [0.88'f, 0.53'f, 0.22'f],
    [0.12'f, 0.53'f, 0.43'f], [0.24'f, 0.72'f, 0.61'f]
  ]
  CreatureScale = 1.9'f
  LabelInk = rgbx(255, 255, 255, 255)
  LabelBackground = rgbx(0, 0, 0, 150)

type
  CachedText = object
    value: string
    height, width: float32
    text: WorldText
  SupplyPlacement = object
    name: string
    position: Vec3
    size, yaw: float32
    selection: Selection
  SceneryPlacement = object
    pack: PropPack
    name: string
    position: Vec3
    size, yaw: float32
    selection: Selection
  MonsterScene* = ref object
    characters: CharacterScene
    creature: CharacterModel
    villagers: array[VillagerColors.len, CharacterModel]
    woodcutters: array[VillagerColors.len, CharacterModel]
    grove: Grove
    buildings, huts, berries, supplies: PropPack
    labels: WorldBarRenderer
    selectionOutline: SelectionOutline
    landmarkTexts: seq[WorldText]
    villagerTexts, villageTexts: seq[CachedText]
    creatureText: WorldText
    labelFont: FontAtlas
    atlasSize: int
    labelTexture: TextureHandle
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

proc addBeam(node: Node, start, finish: Vec3, width: float32, tint: Vec3) =
  ## Builds a thin straight pole or fishing line between two local points.
  let
    direction = normalize(finish - start)
    reference = if abs(direction.y) > 0.9'f:
        vec3(0, 0, 1)
      else: vec3(0, 1, 0)
    side = normalize(cross(direction, reference))
    front = cross(side, direction)
  node.addBox(vec3(0), vec3(width, length(finish - start), width), tint)
  let primitive = node.mesh.primitives[^1]
  for point in primitive.points.mitems:
    point = start + side * point.x + direction * point.y + front * point.z
  for normal in primitive.normals.mitems:
    normal = side * normal.x + direction * normal.y + front * normal.z

proc fishingRodNode(): Node =
  ## Makes a bank-side rod and fine line readable without a floating label.
  result = Node(name: "fishing_rod", visible: true, scale: vec3(1),
    rot: quat(0, 0, 0, 1), mesh: Mesh())
  let tip = vec3(0.2'f, 1.75'f, 2.4'f)
  result.addBeam(vec3(0.2'f, 0.55'f, 0.2'f), tip, 0.035'f,
    vec3(0.53'f, 0.34'f, 0.13'f))
  result.addBeam(tip, vec3(0.2'f, 0.05'f, 2.65'f), 0.012'f,
    vec3(0.8'f, 0.85'f, 0.8'f))

proc bannerNode(index: int): Node =
  ## Makes a village-colored pennant that marks its communal hall.
  result = Node(
    name: "village_banner_" & $index, visible: true, scale: vec3(1),
    rot: quat(0, 0, 0, 1), mesh: Mesh()
  )
  result.addBox(vec3(0), vec3(0.14'f, 4.2'f, 0.14'f),
    vec3(0.40'f, 0.26'f, 0.14'f))
  result.addBox(vec3(0.72'f, 2.95'f, 0), vec3(1.5'f, 1.05'f, 0.06'f),
    VillageColors[index mod VillageColors.len])
  result.addBox(vec3(0, 4.2'f, 0), vec3(0.24'f),
    vec3(0.88'f, 0.75'f, 0.44'f))

proc ruinNode(name: string, building: bool): Node =
  ## Makes broken masonry and scorched timber that remain visibly selectable.
  result = Node(name: name, visible: true, scale: vec3(1),
    rot: quat(0, 0, 0, 1), mesh: Mesh())
  let spread = if building: 1.2'f else: 0.65'f
  result.addBox(vec3(0, 0.01'f, 0),
    vec3(spread * 2.6'f, 0.08'f, spread * 2.4'f),
    vec3(0.25'f, 0.22'f, 0.18'f))
  for i in 0 ..< 13:
    let
      angle = i.float32 * 2.4'f
      radius = spread * (0.35'f + (i mod 3).float32 * 0.3'f)
      height = 0.18'f + (i mod 4).float32 * 0.14'f
    result.addBox(vec3(cos(angle) * radius, 0.08'f, sin(angle) * radius),
      vec3(0.32'f + (i mod 3).float32 * 0.14'f, height, 0.42'f),
      vec3(0.4'f + (i mod 3).float32 * 0.08'f))
  for i in 0 ..< 3:
    result.addBox(vec3(-0.4'f + i.float32 * 0.5'f, 0.2'f,
      -0.4'f + i.float32 * 0.4'f), vec3(0.18'f, 0.16'f, spread * 1.7'f),
      vec3(0.27'f, 0.16'f, 0.08'f))
  if building:
    result.addBox(vec3(-spread, 0, -spread), vec3(0.38'f, 1.1'f, 0.4'f),
      vec3(0.48'f, 0.45'f, 0.4'f))
    result.addBox(vec3(spread, 0, -spread * 0.5'f),
      vec3(0.3'f, 0.8'f, 0.32'f), vec3(0.3'f, 0.18'f, 0.1'f))

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
  scene.selectionOutline.closeSelectionOutline()
  clearSceneProps()
  scene.buildings.closePropPack()
  scene.huts.closePropPack()
  scene.berries.closePropPack()
  scene.supplies.closePropPack()
  scene.grove.trees.closePropPack()
  scene.grove.rocks.closePropPack()
  var models = @[scene.creature]
  models.add scene.villagers
  models.add scene.woodcutters
  for model in models:
    if model != nil:
      model.file.root.clearModelGpu()
      for merged in model.mergedMeshes:
        merged.clearModelGpu()
  if scene.characters != nil:
    scene.characters.context.destroy()
  scene.creature = nil
  for model in scene.villagers.mitems:
    model = nil
  for model in scene.woodcutters.mitems:
    model = nil
  scene.characters = nil
  scene.closed = true

proc addClip(model: CharacterModel, manifest: Manifest, name: string) =
  ## Binds an extra Monster animation to the already loaded character rig.
  if name in model.clips:
    return
  var path: string
  for clip in manifest.clips:
    if clip.name == name:
      path = ChargenLibrary & "/" & clip.file
      break
  if path.len == 0:
    raise newException(MonsterError, "Missing character animation: " & name)
  let file = readGltfFile(path)
  if file.root.animations.len != 1 or file.root.animations[0].name != name:
    raise newException(MonsterError, "Invalid character animation: " & name)
  var joints: Table[string, Node]
  for node in model.file.root.walkNodes:
    if node.mesh == nil:
      joints[node.name] = node
  let clip = file.root.animations[0]
  for channel in clip.channels:
    if channel.target.name notin joints:
      raise newException(MonsterError,
        "Unknown animation joint: " & channel.target.name)
    channel.target = joints[channel.target.name]
  model.clips[name] = model.file.root.animations.len
  model.file.root.animations.add clip

proc newMonsterScene*(
  window: Window,
  map: MonsterMap,
  atlas: SilkyAtlas,
  atlasTexture: TextureHandle
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
    for i in 0 ..< VillageColors.len:
      supplyNodes.add bannerNode(i)
    supplyNodes.add ruinNode("building_ruins", true)
    supplyNodes.add ruinNode("smashed_supplies", false)
    supplyNodes.add fishingRodNode()
    scene.supplies = createPropPack(supplyNodes)
    clearProps()
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
    scene.creature.addClip(manifest, "Punch_Jab")
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
      villagerEntry.preset = lvdassets.woodAxePreset(villagerEntry.preset)
      scene.woodcutters[i] = lvdlooks.loadUnitModel(
        manifest, villagerEntry, PeonUnit
      )
      for model in [scene.villagers[i], scene.woodcutters[i]]:
        for clip in ["Hit_Chest", "Sprint_Loop", "Sitting_Idle_Loop",
          "Walk_Loop", "Fixing_Kneeling", "Idle_Talking_Loop"]:
            model.addClip(manifest, clip)
    scene.characters = newCharacterScene(window)
    scene.characters.useToonShading()
    scene.characters.toon.setArenaHour(clockHour(0'i32, common.TickRate))
    setEnvironmentPalette(scene.characters.toon)
    scene.labels = initWorldBarRenderer()
    scene.selectionOutline = initSelectionOutline()
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
  if world.active and world.current.kind == AttackAction and world.elapsed > 0:
    return "Punch_Jab"
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
  if cached.value != value or cached.height != height or cached.width != width:
    cached.value = value
    cached.height = height
    cached.width = width
    cached.text = layoutText(scene.labelFont, scene.atlasSize, value,
      height = height, maximumWidth = width)

proc villagerClip(villager: Villager): string =
  ## Uses the same visible animation for drawing and mesh selection.
  if villager.health <= 0: "Death01"
  elif villager.hitTime > 0: "Hit_Chest"
  elif villager.moving and villager.fear > 0: "Sprint_Loop"
  elif villager.moving: "Walk_Loop"
  elif villager.sleeping: "Sitting_Idle_Loop"
  elif villager.task in {IdleTask, FleeTask, WanderTask}: "Idle_Loop"
  elif villager.task == ChatTask: "Idle_Talking_Loop"
  elif villager.task in {RepairTask, ChoreTask}: "Fixing_Kneeling"
  elif villager.task == GatherTask:
    case villager.resource
    of BerriesResource, GrainResource: "Fixing_Kneeling"
    of SoftwoodResource, HardwoodResource: "Sword_Attack"
    of FishResource: "Sitting_Idle_Loop"
    of StoneResource: "Interact"
  else: "Interact"

proc villagerModel(
  scene: MonsterScene,
  world: World,
  villager: Villager,
  index: int
): CharacterModel =
  ## Keeps the equipped axe identical in drawing, shadows, and mesh picking.
  let
    village = world.households[villager.home].village
    variant = (village mod VillageColors.len) * 2 + index mod 2
  if villager.health > 0 and villager.task == GatherTask and
    villager.resource in {SoftwoodResource, HardwoodResource}:
      scene.woodcutters[variant]
  else:
    scene.villagers[variant]

proc villagerTime(
  villager: Villager,
  model: CharacterModel,
  clip, index: int,
  time: float32
): float32 =
  ## Keeps hit and death poses fixed while ordinary activities animate.
  if villager.health <= 0 or villager.hitTime > 0:
    clamp(1 - villager.hitTime / HitDuration, 0'f, 1'f) *
      model.clipDuration(clip)
  elif not villager.moving and villager.task in
    {GatherTask, ChoreTask, RepairTask, RefuelTask, ChatTask}:
      villager.elapsed * 0.75'f
  elif villager.moving and villager.fear <= 0:
    time * 0.85'f + index.float32
  else:
    time + index.float32

proc creatureTime(
  world: World,
  model: CharacterModel,
  clip: int,
  time: float32
): float32 =
  ## Shares the attack windup pose with rendering and selection.
  if world.active and world.current.kind == AttackAction and
    world.elapsed > 0:
      clamp(world.elapsed / AttackWindup, 0'f, 1'f) *
        model.clipDuration(clip) * 0.45'f
  else:
    time

proc supplyPlacements(world: World): seq[SupplyPlacement] =
  ## Lists visible supplies once with their inventory owner and transform.
  template supply(kind, point, scale, rotation, owner: untyped) =
    result.add SupplyPlacement(name: $kind, position: point,
      size: scale, yaw: rotation, selection: owner)
  template stockpile(stock, point, owner: untyped) =
    block:
      var slot = 0
      for kind in ResourceKind:
        if stock[kind] <= 0:
          continue
        let position = point + vec2(
          0.9'f + (slot mod 3).float32 * 0.65'f,
          -0.3'f + (slot div 3).float32 * 0.65'f)
        supply(kind, world.map.scenePosition(position), 0.65'f, 0'f, owner)
        inc slot
  for source in world.sources:
    if source.destroyed:
      result.add SupplyPlacement(name: "smashed_supplies",
        position: world.map.scenePosition(source.position), size: 0.8'f,
        selection: Selection(kind: SourceSelection, id: source.id))
      continue
    for i in 0 ..< min(3, (source.amount + 7) div 8):
      let point = source.position + vec2(0.9'f + i.float32 * 0.7'f, 0)
      supply(source.resource, world.map.scenePosition(point), 0.75'f, 0'f,
        Selection(kind: SourceSelection, id: source.id))
  for house in world.households:
    if house.integrity <= 0:
      continue
    let owner = Selection(kind: HouseholdSelection, id: house.id)
    stockpile(house.stock, house.position, owner)
    for i in 0 ..< int(ceil((100'f - house.integrity) / 20'f)):
      let point = house.position + vec2(
        -1.2'f - (i mod 2).float32 * 0.42'f,
        -0.2'f + (i div 2).float32 * 0.48'f)
      supply(StoneResource, world.map.scenePosition(point), 0.45'f,
        i.float32 * 1.1'f, owner)
  for i, village in world.villages:
    if village.health <= 0:
      continue
    let owner = Selection(kind: VillageSelection, id: village.id)
    stockpile(village.stock, village.position, owner)
    result.add SupplyPlacement(
      name: "village_banner_" & $(i mod VillageColors.len),
      position: world.map.scenePosition(village.position + vec2(-2, 0.5'f)),
      size: 1, selection: owner)
  for person in world.villagers:
    if person.health > 0 and not person.moving and
      person.task == GatherTask and person.resource == FishResource:
        result.add SupplyPlacement(name: "fishing_rod",
          position: world.map.scenePosition(person.position),
          size: 1, yaw: person.facing,
          selection: Selection(kind: VillagerSelection, id: person.id))
    for kind in ResourceKind:
      if person.cargo[kind] > 0:
        let point =
          if person.health <= 0:
            world.map.scenePosition(person.position + vec2(0.6'f, 0))
          else:
            world.map.scenePosition(person.position) +
              vec3(sin(person.facing) * 0.35'f, 0.75'f,
                cos(person.facing) * 0.35'f)
        supply(kind, point, 0.55'f, person.facing,
          Selection(kind: VillagerSelection, id: person.id))
        break
  for kind in ResourceKind:
    if world.creature.cargo[kind] > 0:
      let point = world.map.scenePosition(world.creature.position) +
        vec3(sin(world.creature.facing) * 0.8'f, 1.1'f,
          cos(world.creature.facing) * 0.8'f)
      supply(kind, point, 1.2'f, world.creature.facing,
        Selection(kind: MossSelection, id: "moss"))
      break

proc sceneryPlacements(
  scene: MonsterScene,
  world: World
): seq[SceneryPlacement] =
  ## Shares live intact or ruined meshes across shadows, drawing, and picking.
  for scenery in world.map.props:
    let owner = world.scenerySelection(scenery)
    var item = SceneryPlacement(
      pack:
        if scenery.prop == "hut": scene.huts
        elif scenery.prop == "berries": scene.berries
        else: scene.buildings,
      name: if scenery.prop == "hut": "blacksmith" else: scenery.prop,
      position: world.map.scenePosition(scenery.position),
      size: scenery.size, yaw: -scenery.yaw, selection: owner)
    if world.selectionDestroyed(owner):
      item.pack = scene.supplies
      item.name = if scenery.prop in ["hut", "town_hall"]:
        "building_ruins" else: "smashed_supplies"
      item.size = case scenery.prop
        of "town_hall": 1.4'f
        of "hut": 1'f
        of "farm": 1.3'f
        else: 0.65'f
    result.add item

proc drawScenery(
  placements: openArray[SceneryPlacement],
  viewProjection: Mat4,
  shadow = false
) =
  ## Draws changing scenery without leaving intact baked meshes or shadows.
  for item in placements:
    if shadow:
      item.pack.drawPropSunDepth(item.name, item.position, item.yaw, item.size)
    else:
      item.pack.drawProp(item.name, item.position, item.yaw, item.size,
        viewProjection)

proc drawSupplies(
  scene: MonsterScene,
  placements: openArray[SupplyPlacement],
  viewProjection: Mat4,
  shadow = false
) =
  ## Draws each supply using the same transform used by mesh picking.
  for item in placements:
    if shadow:
      scene.supplies.drawPropSunDepth(item.name, item.position,
        item.yaw, item.size)
    else:
      scene.supplies.drawProp(item.name, item.position, item.yaw,
        item.size, viewProjection)

proc terrainDistance(map: MonsterMap, origin, direction: Vec3): float32 =
  ## Finds the visible terrain surface so clicks cannot pass through hills.
  result = Inf.float32
  for z in 0 ..< MapSize:
    for x in 0 ..< MapSize:
      let
        point = vec2(x.float32 - MapHalf, z.float32 - MapHalf)
        a = map.scenePosition(point)
        b = map.scenePosition(point + vec2(1, 0))
        c = map.scenePosition(point + vec2(0, 1))
        d = map.scenePosition(point + vec2(1, 1))
      for distance in [rayTriangle(origin, direction, a, b, c),
        rayTriangle(origin, direction, b, d, c)]:
          if distance > 0:
            result = min(result, distance)

proc nearRay(origin, direction, point: Vec3, radius: float32): bool =
  ## Skips scenery whose bounding sphere is clear of the pointer ray.
  let along = dot(point - origin, direction)
  along > -radius and
    lengthSq(point - origin - direction * max(0'f, along)) <= radius * radius

proc pickSelectionAt*(
  scene: MonsterScene,
  world: World,
  mouse, windowSize: Vec2,
  cameraTarget: Vec3,
  cameraDistance, time: float32
): Selection =
  ## Selects the nearest rendered mesh without changing the simulation.
  result = Selection(kind: NoSelection)
  if scene == nil or scene.closed or windowSize.x <= 0 or windowSize.y <= 0:
    return
  let
    eye = rtsCameraEye(cameraTarget, cameraDistance)
    view = lookAt(eye, cameraTarget, vec3(0, 1, 0))
    projection = perspective(RtsFieldOfView, windowSize.x / windowSize.y,
      0.1'f, 300'f)
    (origin, ray) = mouseRay(mouse, windowSize, projection * view)
    direction = normalize(ray)
  var nearest = world.map.terrainDistance(origin, direction)
  template consider(target, distance: untyped) =
    block:
      let hit = distance
      if hit > 0 and hit < nearest:
        nearest = hit
        result = target
  let monsterClip = scene.creature.clipIndex(world.creatureClip())
  consider(Selection(kind: MossSelection, id: "moss"),
    scene.creature.pickCharacter(origin, direction,
      world.map.scenePosition(world.creature.position), world.creature.facing,
      monsterClip, world.creatureTime(scene.creature, monsterClip, time),
      CreatureScale))
  for i, person in world.villagers:
    let
      model = scene.villagerModel(world, person, i)
      clip = model.clipIndex(person.villagerClip())
    consider(Selection(kind: VillagerSelection, id: person.id),
      model.pickCharacter(origin, direction,
        world.map.scenePosition(person.position), person.facing, clip,
        person.villagerTime(model, clip, i, time)))
  for item in scene.sceneryPlacements(world):
    consider(item.selection, item.pack.pickProp(item.name, origin,
      direction, item.position, item.yaw, item.size))
  for item in world.supplyPlacements():
    consider(item.selection, scene.supplies.pickProp(item.name, origin,
      direction, item.position, item.yaw, item.size))
  for i, tile in world.map.ground.tiles:
    if tile.kind != TreeTile:
      continue
    let
      point = vec2((i mod MapSize).float32 - MapHalf + 0.5'f,
        (i div MapSize).float32 - MapHalf + 0.5'f)
      position = world.map.scenePosition(point)
    if not nearRay(origin, direction, position + vec3(0, 4, 0), 7):
      continue
    consider(Selection(kind: NoSelection), scene.grove.trees.pickProp(
      modelName(LightTree, (i + world.map.seed) mod BrushVariants),
      origin, direction, position, -(i mod 17).float32 * 0.37'f,
      1.45'f + (i mod 5).float32 * 0.08'f))
  for i in 0 ..< 12:
    let point = vec2(24'f + sin(i.float32 * 1.8'f) * 2'f,
      i.float32 * 4.7'f - 27'f)
    consider(Selection(kind: NoSelection), scene.grove.rocks.pickProp(
      modelName(LightRock, i mod BrushVariants), origin, direction,
      world.map.scenePosition(point), -i.float32, 0.55'f))

proc pickSelection*(
  scene: MonsterScene,
  window: Window,
  world: World,
  cameraTarget: Vec3,
  cameraDistance, time: float32
): Selection =
  ## Adapts native pointer coordinates to the mesh inspection query.
  scene.pickSelectionAt(world, window.mousePos.vec2, window.size.vec2,
    cameraTarget, cameraDistance, time)

proc drawScene*(
  scene: MonsterScene,
  window: Window,
  world: World,
  cameraTarget: Vec3,
  cameraDistance: float32,
  time: float32,
  selection = Selection()
) =
  ## Draws one complete world frame before the conversation overlay.
  if scene == nil or scene.closed or window.size.y <= 0:
    return
  scene.characters.toon.setArenaHour(clockHour(time * common.TickRate.float32,
    common.TickRate))
  setEnvironmentPalette(scene.characters.toon)
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
  let
    monsterClip = scene.creature.clipIndex(world.creatureClip())
    monsterTime = world.creatureTime(scene.creature, monsterClip, time)
    supplies = world.supplyPlacements()
    scenery = scene.sceneryPlacements(world)
  scene.characters.prepareCharacter(
    monsterPose,
    scene.creature,
    position,
    world.creature.facing,
    monsterClip,
    monsterTime,
    sizeFactor = CreatureScale
  )
  for i, villager in world.villagers:
    let
      model = scene.villagerModel(world, villager, i)
      clipIndex = model.clipIndex(villager.villagerClip())
      animationTime = villager.villagerTime(model, clipIndex, i, time)
    scene.characters.prepareCharacter(
      villagerPoses[i],
      model,
      world.map.scenePosition(villager.position),
      villager.facing,
      clipIndex,
      animationTime
    )
  sunDepthPasses(window.size):
    drawTerrainSunDepth()
    scenery.drawScenery(viewProjection, shadow = true)
    scene.drawSupplies(supplies, viewProjection, shadow = true)
    scene.characters.sunDepthPass = true
    scene.characters.drawCharacter(monsterPose)
    for pose in villagerPoses.mitems:
      scene.characters.drawCharacter(pose)
    scene.characters.sunDepthPass = false
  scene.characters.beginCharacters(window, view, projection, eye)
  clearFrame(color(0.14'f, 0.22'f, 0.25'f, 1'f))
  scene.characters.toon.drawBackground()
  drawTerrain(viewProjection)
  scenery.drawScenery(viewProjection)
  scene.drawSupplies(supplies, viewProjection)
  scene.characters.drawCharacter(monsterPose)
  for i, pose in villagerPoses.mpairs:
    let tint =
      if world.villagers[i].hitTime > HitDuration * 0.5'f:
        color(1.8'f, 1.8'f, 1.8'f, 1)
      elif world.villagers[i].health <= 0:
        color(0.6'f, 0.6'f, 0.6'f, 1)
      else:
        color(1, 1, 1, 1)
    scene.characters.drawCharacter(pose, tint)
  scene.characters.finishCharacters()
  drawWater(viewProjection, eye, opacity = 0.7'f,
    highlightOpacity = 0.15'f)
  let selected = world.resolveSelection(selection)
  scene.selectionOutline.beginMask(window.size)
  case selected.kind
  of MossSelection, VillagerSelection:
    scene.characters.beginCharacters(window, view, projection, eye)
    if selected.kind == MossSelection:
      scene.characters.drawCharacter(monsterPose)
    else:
      scene.characters.drawCharacter(
        villagerPoses[world.villagerIndex(selected.id)])
    scene.characters.finishCharacters()
  of HouseholdSelection, VillageSelection, SourceSelection:
    for item in scenery:
      if item.selection != selected:
        continue
      item.pack.drawProp(item.name, item.position, item.yaw, item.size,
        viewProjection)
  of NoSelection:
    discard
  for item in supplies:
    if item.selection == selected:
      scene.supplies.drawProp(item.name, item.position, item.yaw,
        item.size, viewProjection)
  scene.selectionOutline.drawOutline()
  scene.labels.clear()
  let labelScale = clamp(cameraDistance / 40, 1'f, 1.25'f)
  for i, place in world.map.landmarks:
    if place.kind notin {HomeLandmark, RiverLandmark, ForestLandmark}:
      continue
    scene.labels.addText(scene.landmarkTexts[i],
      world.map.scenePosition(place.position) + vec3(0, 0.6'f, 0),
      LabelInk, LabelBackground)
  scene.villageTexts.setLen(world.villages.len)
  for i, village in world.villages:
    scene.updateText(scene.villageTexts[i], village.name,
      0.8'f * labelScale, 12'f * labelScale)
    scene.labels.addText(scene.villageTexts[i].text,
      world.map.scenePosition(village.position) +
        vec3(0, 1.8'f * labelScale, 0), LabelInk, LabelBackground)
  scene.villagerTexts.setLen(world.villagers.len)
  for i, person in world.villagers:
    let point = world.map.scenePosition(person.position)
    scene.updateText(scene.villagerTexts[i], person.name, 0.44'f)
    scene.labels.addText(scene.villagerTexts[i].text,
      point + vec3(0, (if person.health > 0: 2.15'f else: 0.85'f), 0),
      LabelInk, LabelBackground)
    if person.hitTime > 0:
      let progress = 1 - person.hitTime / HitDuration
      scene.labels.addBillboardRing(point + vec3(0, 0.8'f, 0),
        vec2(0), 0.4'f + progress * 0.5'f, 0.05'f, 1,
        rgbx(255, 255, 255, uint8(220 * (1 - progress))))
  scene.labels.addText(
    scene.creatureText, position + vec3(0, 3.7'f, 0),
    LabelInk, LabelBackground
  )
  scene.labels.draw(viewProjection, cameraRight, cameraUp, scene.labelTexture)
