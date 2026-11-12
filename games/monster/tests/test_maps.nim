import
  std/math,
  vmath,
  polyworld/pathing,
  ../[common, maps, sim]

proc reachable(map: MonsterMap): seq[bool] =
  ## Floods the clearing to verify every named place has a walking route.
  const Neighbors = [(-1, 0), (1, 0), (0, -1), (0, 1)]
  var
    pending = @[MapSize div 2 * MapSize + MapSize div 2]
    cursor = 0
  result = newSeq[bool](MapSize * MapSize)
  result[pending[0]] = true
  while cursor < pending.len:
    let
      index = pending[cursor]
      x = index mod MapSize
      z = index div MapSize
    inc cursor
    for (dx, dz) in Neighbors:
      let
        nx = x + dx
        nz = z + dz
      if nx < 0 or nx >= MapSize or nz < 0 or nz >= MapSize:
        continue
      let next = nz * MapSize + nx
      if not result[next] and not map.blocked[next]:
        result[next] = true
        pending.add next

echo "Testing Monster meadow generation"
for seed in [0, 1, 42, 1049, 89_271]:
  let
    map = generateMap(seed)
    same = generateMap(seed)
    connected = map.reachable()
  doAssert map.ground.originX == (GridTiles - MapSize) div 2
  doAssert map.ground.originZ == (GridTiles - MapSize) div 2
  doAssert map.ground.tiles.len == MapSize * MapSize
  doAssert map.ground.tiles == same.ground.tiles
  doAssert map.blocked == same.blocked
  doAssert map.relief == same.relief
  doAssert map.landmarks.len == 6
  var trees, stream: int
  for i, tile in map.ground.tiles:
    doAssert tile.impassable == map.blocked[i]
    if tile.kind == TreeTile:
      inc trees
      doAssert map.blocked[i]
    elif tile.kind == MarshTile:
      inc stream
      doAssert map.blocked[i]
  doAssert trees > 30
  doAssert stream > 100
  for landmark in map.landmarks:
    let
      point = landmark.position + vec2(MapHalf)
      index = floor(point.y).int * MapSize + floor(point.x).int
    doAssert connected[index], "Unreachable landmark: " & landmark.id
    doAssert abs(map.groundHeight(landmark.position)) < 1
    var world = newWorld(map)
    let route = map.route(world.creature.position, landmark.position)
    doAssert route.len > 0
    world.instruct(@[CreatureAction(kind: MoveAction, target: landmark.id)])
    var ticks = 0
    while world.active or world.actions.len > 0:
      world.step()
      inc ticks
      doAssert ticks < 4000, "Movement stalled: " & landmark.id
      doAssert map.walkable(world.creature.position)
    doAssert length(world.creature.position - landmark.position) < 0.01'f
echo "Monster meadow generation passed"
