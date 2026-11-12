import
  std/[math, random],
  vmath,
  polyworld/[pathing, terrainreliefs],
  common

proc riverCenter(z: float32): float32 {.raises: [].} =
  ## Traces the stream along the eastern edge of the meadow.
  19.0'f + sin(z * 0.115'f) * 2.2'f

proc elevation(x, z: float32): float32 {.raises: [].} =
  ## Shapes a gentle meadow with a shallow stream bed.
  let
    bank = abs(x - riverCenter(z))
    hills = sin(x * 0.11'f) * cos(z * 0.09'f) * 0.32'f
    water = clamp((2.5'f - bank) / 1.5'f, 0'f, 1'f)
  hills * (1 - water) - water * 0.85'f

proc groundHeight*(
  map: MonsterMap,
  position: Vec2
): float32 {.raises: [].} =
  ## Samples the terrain triangles and their decorative surface relief.
  let
    local = position + vec2(MapHalf)
    x = clamp(floor(local.x).int, 0, MapSize - 1)
    z = clamp(floor(local.y).int, 0, MapSize - 1)
    tile = map.ground.tiles[z * MapSize + x]
    dx = clamp(local.x - x.float32, 0'f, 1'f)
    dz = clamp(local.y - z.float32, 0'f, 1'f)
    heights = unpack(tile.tops)
  result =
    if dx + dz <= 1:
      heights[0] + (heights[1] - heights[0]) * dx +
        (heights[2] - heights[0]) * dz
    else:
      heights[1] * (1 - dz) + heights[2] * (1 - dx) +
        heights[3] * (dx + dz - 1)
  result += reliefHeight(map.relief, map.ground, position.x, position.y)

proc segmentDistance(
  point, first, last: Vec2
): float32 {.raises: [].} =
  ## Measures clearance from the center of a walking trail.
  let
    direction = last - first
    amount = clamp(dot(point - first, direction) / lengthSq(direction),
      0'f, 1'f)
  length(point - first - direction * amount)

proc generateMap*(seed = 42): MonsterMap =
  ## Builds a seeded village clearing, woodland, berry patch, and stream.
  result = MonsterMap(
    seed: seed,
    ground: QuadLayer(
      originX: (GridTiles - MapSize) div 2,
      originZ: (GridTiles - MapSize) div 2,
      width: MapSize,
      depth: MapSize,
      tiles: newSeq[Tile](MapSize * MapSize)
    ),
    blocked: newSeq[bool](MapSize * MapSize),
    landmarks: @[
      Landmark(id: "village", name: "Village hall",
        kind: VillageLandmark, position: vec2(0, 0)),
      Landmark(id: "berries", name: "Wild berry patch",
        kind: BerryLandmark, position: vec2(-11, -7)),
      Landmark(id: "farm", name: "Miller's farm",
        kind: FarmLandmark, position: vec2(9, -5)),
      Landmark(id: "home", name: "Sleeping glade",
        kind: HomeLandmark, position: vec2(-11, 9)),
      Landmark(id: "river", name: "Willow stream",
        kind: RiverLandmark, position: vec2(15, 3)),
      Landmark(id: "forest", name: "Whispering woods",
        kind: ForestLandmark, position: vec2(-20, -13)),
      Landmark(id: "fish", name: "Willow fishing bank",
        kind: ResourceLandmark, position: vec2(15, -6)),
      Landmark(id: "pine", name: "Fallen pine wood",
        kind: ResourceLandmark, position: vec2(-17, 4)),
      Landmark(id: "oak", name: "Fallen oak wood",
        kind: ResourceLandmark, position: vec2(-18, -17)),
      Landmark(id: "stone", name: "Loose stone",
        kind: ResourceLandmark, position: vec2(-4, -16)),
      Landmark(id: "miller_hut", name: "Miller's hut",
        kind: HouseholdLandmark, position: vec2(6, -10)),
      Landmark(id: "weaver_hut", name: "Weaver's hut",
        kind: HouseholdLandmark, position: vec2(-4, 3)),
      Landmark(id: "mason_hut", name: "Mason's hut",
        kind: HouseholdLandmark, position: vec2(5, 8))
    ],
    props: @[
      Scenery(prop: "town_hall", position: vec2(-3, -5),
        size: 0.45'f),
      Scenery(prop: "hut", position: vec2(9, -10),
        size: 2.7'f, yaw: -1.57'f),
      Scenery(prop: "hut", position: vec2(-7, 3),
        size: 2.7'f, yaw: 1.57'f),
      Scenery(prop: "hut", position: vec2(5, 5),
        size: 2.7'f),
      Scenery(prop: "farm", position: vec2(12, -9),
        size: 0.42'f, yaw: 0.3'f),
      Scenery(prop: "berries", position: vec2(-13, -8),
        size: 1.25'f),
      Scenery(prop: "berries", position: vec2(-11, -9),
        size: 1.1'f),
      Scenery(prop: "berries", position: vec2(-9, -8),
        size: 0.95'f)
    ]
  )
  let trails = [
    (vec2(-11, 9), vec2(0, 0)),
    (vec2(0, 0), vec2(9, -5)),
    (vec2(0, 0), vec2(-11, -7)),
    (vec2(-11, -7), vec2(-20, -13)),
    (vec2(0, 0), vec2(15, 3)),
    (vec2(9, -5), vec2(15, -6)),
    (vec2(-11, 9), vec2(-17, 4)),
    (vec2(-11, -7), vec2(-18, -17)),
    (vec2(-11, -7), vec2(-4, -16)),
    (vec2(0, 0), vec2(6, -10)),
    (vec2(0, 0), vec2(-4, 3)),
    (vec2(0, 0), vec2(5, 8))
  ]
  var
    rng = initRand(seed)
    natural = newSeq[bool](MapSize * MapSize)
  for z in 0 ..< MapSize:
    for x in 0 ..< MapSize:
      let
        index = z * MapSize + x
        point = vec2(x.float32 - MapHalf + 0.5'f,
          z.float32 - MapHalf + 0.5'f)
        stream = abs(point.x - riverCenter(point.y)) < 1.75'f
        border = x == 0 or z == 0 or
          x == MapSize - 1 or z == MapSize - 1
      var
        kind = GrassTile
        trail = false
        blocked = stream or border
      for ends in trails:
        if segmentDistance(point, ends[0], ends[1]) < 0.85'f:
          trail = true
      if stream:
        kind = MarshTile
      elif trail or length(point) < 2.5'f:
        kind = RoadTile
      for scenery in result.props:
        let radius =
          if scenery.prop == "berries":
            0.7'f
          elif scenery.prop == "town_hall":
            2.5'f
          else:
            2.0'f
        if length(point - scenery.position) < radius:
          blocked = true
          if scenery.prop != "berries":
            kind = RoadTile
      var tile = Tile(
        kind: kind,
        flags: TileExists or TileConnectedEast or TileConnectedSouth
      )
      if blocked:
        tile.flags = tile.flags or TileImpassable
      for corner in 0 .. 3:
        tile.tops[corner] = int16(round(elevation(
          x.float32 - MapHalf + (corner mod 2).float32,
          z.float32 - MapHalf + (corner div 2).float32
        ) * HeightSteps))
      result.ground.tiles[index] = tile
      result.blocked[index] = blocked
      natural[index] = kind == GrassTile
  for i in 0 ..< 420:
    let
      x = rng.rand(2 .. MapSize - 3)
      z = rng.rand(2 .. MapSize - 3)
      index = z * MapSize + x
      point = vec2(x.float32 - MapHalf + 0.5'f,
        z.float32 - MapHalf + 0.5'f)
    if result.blocked[index] or point.x > 16 or
      (point.x > -9 and point.y > -15 and point.y < 17):
        continue
    var clear = true
    for landmark in result.landmarks:
      if length(point - landmark.position) < 3.3'f:
        clear = false
    for ends in trails:
      if segmentDistance(point, ends[0], ends[1]) < 2.3'f:
        clear = false
    for tz in max(0, z - 1) .. min(MapSize - 1, z + 1):
      for tx in max(0, x - 1) .. min(MapSize - 1, x + 1):
        if result.ground.tiles[tz * MapSize + tx].kind == TreeTile:
          clear = false
    if clear:
      result.ground.tiles[index].kind = TreeTile
      result.ground.tiles[index].flags =
        result.ground.tiles[index].flags or TileImpassable
      result.blocked[index] = true
  result.relief = buildRelief(result.ground, natural, seed, height = 0.18'f)
