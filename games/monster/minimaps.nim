import
  std/math,
  chroma, pixie, silky, vmath,
  polyworld/[gameuis, pathing, rtscameras],
  common, hudassets

const
  White = rgbx(255, 255, 255, 255)
  VillageColors = [
    rgbx(83, 155, 237, 255),
    rgbx(235, 133, 65, 255),
    rgbx(60, 207, 168, 255)
  ]

proc minimapArea*(panel: GameUiPanel): GameUiPanel {.raises: [].} =
  ## Uses the exact opening inside the woodland frame for drawing and input.
  panel

proc minimapPosition*(
  position: Vec2,
  panel: GameUiPanel
): Vec2 {.raises: [].} =
  ## Projects a world XZ position onto the fixed-north terrain map.
  let area = panel.minimapArea()
  area.origin + clamp((position + vec2(MapHalf)) / (MapHalf * 2),
    vec2(0), vec2(1)) * area.size

proc creatureHit*(
  point: Vec2,
  panel: GameUiPanel,
  world: World
): bool {.raises: [].} =
  ## Makes the creature portrait easy to click at every supported UI scale.
  panel.minimapArea().contains(point) and
    lengthSq(point - minimapPosition(world.creature.position, panel)) <= 196

proc terrainColor(kind: uint32): ColorRGBX {.raises: [].} =
  ## Uses GotA's readable meadow, forest, trail, and stream palette.
  case kind
  of TreeTile:
    rgbx(54, 139, 65, 255)
  of MarshTile:
    rgbx(70, 157, 185, 255)
  of RoadTile:
    rgbx(165, 147, 81, 255)
  else:
    rgbx(139, 198, 106, 255)

proc drawSprite(
  sk: Silky,
  name: string,
  origin, size: Vec2,
  color = White,
  radius = 0'f
) =
  ## Draws GotA's stretched glyphs without importing its native window chrome.
  if name notin sk.atlas.entries:
    sk.drawRect(origin, size, color)
  elif radius > 0.5'f:
    sk.drawRoundedImage(name, origin, size, radius, color)
  else:
    let uv = sk.atlas.entries[name]
    sk.drawQuad(origin, size, vec2(uv.x.float32, uv.y.float32),
      vec2(uv.width.float32, uv.height.float32), color)

proc drawCameraFrame(sk: Silky, viewport: MinimapViewRect) =
  ## Outlines the shared camera footprint with GotA's two-pixel frame.
  let
    origin = viewport.origin
    size = viewport.size
    color = rgbx(255, 242, 187, 255)
  sk.drawRect(origin, vec2(size.x, 2), color)
  sk.drawRect(origin + vec2(0, size.y - 2), vec2(size.x, 2), color)
  sk.drawRect(origin, vec2(2, size.y), color)
  sk.drawRect(origin + vec2(size.x - 2, 0), vec2(2, size.y), color)

proc drawTerrain(sk: Silky, area: GameUiPanel, map: MonsterMap) =
  ## Draws the terrain in merged horizontal spans, as GotA does.
  if map.ground.isNil or map.ground.tiles.len != MapSize * MapSize:
    sk.drawRect(area.origin, area.size, rgbx(0, 0, 0, 160))
    return
  let tileSize = area.size / MapSize.float32
  for y in 0 ..< MapSize:
    var x = 0
    while x < MapSize:
      let color = terrainColor(map.ground.tiles[y * MapSize + x].kind)
      var finish = x + 1
      while finish < MapSize and
        terrainColor(map.ground.tiles[y * MapSize + finish].kind) == color:
          inc finish
      sk.drawRect(area.origin + vec2(x.float32, y.float32) * tileSize,
        vec2((finish - x).float32, 1) * tileSize, color)
      x = finish

proc drawIcon(
  sk: Silky,
  name: string,
  point: Vec2,
  size: float32,
  color: ColorRGBX
) =
  ## Outlines a settlement or villager glyph using GotA's map styling.
  sk.drawSprite(name, point - vec2((size + 2) / 2), vec2(size + 2),
    rgbx(16, 19, 24, 255))
  sk.drawSprite(name, point - vec2(size / 2), vec2(size), color)

proc drawCreature(
  sk: Silky,
  panel: GameUiPanel,
  world: World,
  following: bool
) =
  ## Reuses GotA's directional map marker with an upright creature portrait.
  const
    MarkerCenter = vec2(0.5'f, 50'f / 128'f)
    Corners = [vec2(0, 0), vec2(1, 0), vec2(1, 1), vec2(0, 1)]
  let
    point = minimapPosition(world.creature.position, panel)
    markerSize = clamp(panel.size.x * 0.1875'f, 36'f, 48'f)
    markerColor =
      if following: rgbx(255, 242, 187, 255)
      else: White
    forward = vec2(sin(world.creature.facing), cos(world.creature.facing))
    right = vec2(forward.y, -forward.x)
  if "map_marker" in sk.atlas.entries:
    let
      entry = sk.atlas.entries["map_marker"]
      uvOrigin = vec2(entry.x.float32, entry.y.float32)
      uvSize = vec2(entry.width.float32, entry.height.float32)
    var positions, uvs: array[4, Vec2]
    for i, corner in Corners:
      let offset = (corner - MarkerCenter) * markerSize
      positions[i] = point + right * offset.x + forward * offset.y
      uvs[i] = uvOrigin + corner * uvSize
    for indices in [[0, 1, 2], [0, 2, 3]]:
      sk.drawTriangle(
        [positions[indices[0]], positions[indices[1]], positions[indices[2]]],
        [uvs[indices[0]], uvs[indices[1]], uvs[indices[2]]],
        [markerColor, markerColor, markerColor]
      )
  sk.drawSprite(WhiteTileKey, point - vec2(13), vec2(26),
    markerColor, radius = 13)
  sk.drawSprite(HudPortraitKey, point - vec2(11), vec2(22), radius = 11)

proc drawMinimap*(
  sk: Silky,
  panel: GameUiPanel,
  world: World,
  cameraTarget: Vec3,
  cameraDistance, aspect: float32,
  following: bool
) =
  ## Draws GotA's fixed-north map, live inhabitants, and camera footprint.
  let area = panel.minimapArea()
  sk.drawTerrain(area, world.map)
  sk.pushClipRect(rect(area.origin, area.size))
  for person in world.villagers:
    if person.health <= 0:
      continue
    let village =
      if person.home >= 0 and person.home < world.households.len:
        world.households[person.home].village
      else: 0
    sk.drawIcon("contact", minimapPosition(person.position, panel), 5,
      VillageColors[clamp(village, 0, VillageColors.high)])
  for i, village in world.villages:
    let
      point = minimapPosition(village.position, panel)
      labelSize = sk.getTextSize("Small", village.name)
      origin = clamp(point + vec2(0, 10) - vec2(labelSize.x / 2, 0),
        area.origin, area.origin + max(vec2(0), area.size - labelSize))
    sk.drawIcon("tower", point, 14,
      (if village.health > 0: VillageColors[i mod VillageColors.len]
        else: rgbx(130, 130, 130, 255)))
    sk.drawRect(origin - vec2(3, 1), labelSize + vec2(6, 2),
      rgbx(0, 0, 0, 160))
    discard sk.drawText("Small", village.name, origin, White)
  sk.drawCameraFrame(minimapViewport(cameraTarget, cameraDistance,
    max(0.1'f, aspect), area.origin, area.size, MapHalf))
  sk.drawCreature(panel, world, following)
  sk.popClipRect()
