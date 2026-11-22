## Deterministic pathing test scenes using the ordinary Light vs Dark simulation.

import
  fixxy,
  polyworld/pathing,
  ../[content, maps, sim]

export fixxy, content, maps, sim

const
  PathingUnitCount* = 100
  PathingDurationTicks* = 1800
  PathingMapSide = 80'i32

type
  PathingScenario* = enum
    OpenField, OpposingStreams, CrossingStreams, NarrowChoke, BuildingDetour

  PathingRect* = object
    x*, y*, width*, height*: int32

  PathingScene* = object
    world*: World
    starts*, goals*: seq[FixedVec2]
    groups*: seq[int]
    obstacles*: seq[PathingRect]
    bounds*: PathingRect

const
  ScenarioNames*: array[PathingScenario, string] = [
    "Open field", "Opposing streams", "Crossing streams", "Narrow choke",
    "Building detour"
  ]
  ScenarioDescriptions*: array[PathingScenario, string] = [
    "A compact group opens out into its destination formation.",
    "Two friendly groups pass through each other in opposite directions.",
    "Two friendly groups cross at right angles and keep their own goals.",
    "A compact group funnels through a two-tile opening and spreads out.",
    "A group takes clear routes around two offset building footprints."
  ]

proc emptyWorld(): World =
  ## Keeps real match rules and offscreen halls on a flat, obstacle-free map.
  var map = MapData(
    seed: 73021,
    side: PathingMapSide,
    passable: newSeq[uint8](PathingMapSide * PathingMapSide),
    kinds: newSeq[uint8](PathingMapSide * PathingMapSide),
    treeWood: newSeq[int16](PathingMapSide * PathingMapSide),
    heights: newSeq[int16](PathingMapSide * PathingMapSide),
    hallOrigin: @[tile2(3, 3), tile2(72, 72)]
  )
  let layer = QuadLayer(
    originX: GridTiles div 2 - PathingMapSide.int div 2,
    originZ: GridTiles div 2 - PathingMapSide.int div 2,
    width: PathingMapSide.int,
    depth: PathingMapSide.int,
    tiles: newSeq[Tile](PathingMapSide * PathingMapSide)
  )
  for i in 0 ..< map.passable.len:
    map.passable[i] = 1
    layer.tiles[i].flags =
      TileExists or TileConnectedEast or TileConnectedSouth
  map.terrain = @[layer]
  result = newWorld(map, 100000)
  # Opening peons are replaced by controlled, friendly movement groups.
  result.units.setLen(0)
  for slot in result.unitSlot.mitems:
    slot = -1
  for occupant in result.occupancy.mitems:
    occupant = NoEntity
  for player in result.players.mitems:
    player.foodUsed = 0

proc plantTrees(scene: var PathingScene, obstacle: PathingRect) =
  ## Adds visible, harvestable trees and their ordinary movement blockers.
  scene.obstacles.add obstacle
  for y in obstacle.y ..< obstacle.y + obstacle.height:
    for x in obstacle.x ..< obstacle.x + obstacle.width:
      let index = scene.world.map.tileIndex(x, y)
      scene.world.blocker[index] = TreeBlocker
      scene.world.treeWood[index] = WoodPerTree
      scene.world.map.treeWood[index] = WoodPerTree
      scene.world.map.kinds[index] = TreeTile.uint8
      scene.world.map.terrain[0].tiles[index].kind = TreeTile
  inc scene.world.pathTerrainRevision

proc addBuilding(scene: var PathingScene, kind: BuildingKind, x, y: int32) =
  ## Creates a completed real structure through the normal placement pipeline.
  let
    world = scene.world
    builder = world.spawnUnit(0, PeonUnit, tile2(18, 24))
  world.players[0].gold = 10000
  world.players[0].wood = 10000
  doAssert world.applyBuild(0, builder, kind.ord.int32, x, y)
  world.buildings[^1].state = BuildingComplete
  world.buildings[^1].hp = world.buildings[^1].maxHp
  world.buildings[^1].buildTicks = 0
  world.buildings[^1].builderId = NoEntity
  let size = world.buildings[^1].footprint
  scene.obstacles.add PathingRect(
    x: x, y: y, width: size.width, height: size.depth
  )
  # Setup builders never enter the test scene or leave pending requests.
  world.units.setLen(0)
  for slot in world.unitSlot.mitems:
    slot = -1
  for occupant in world.occupancy.mitems:
    occupant = NoEntity
  world.pathQueue.setLen(0)

proc addUnit(scene: var PathingScene, start, goal: FixedVec2, group: int) =
  ## Registers an ordinary soldier and issues its exact movement destination.
  let
    world = scene.world
    startTile = tile2(whole(start.x), whole(start.y))
    goalTile = tile2(whole(goal.x), whole(goal.y))
    id = world.spawnUnit(0, SoldierUnit, startTile)
    unit = world.units[world.unitIndex(id)]
    center = fixedVec2(
      fixed(goalTile.x.int32) + FixedHalf,
      fixed(goalTile.y.int32) + FixedHalf
    )
  unit.body.pos = start
  unit.tile = startTile
  scene.starts.add start
  scene.goals.add goal
  scene.groups.add group
  doAssert world.applyMove(
    0, id, goalTile.x.int32, goalTile.y.int32, goal - center
  )

proc createScene*(scenario: PathingScenario): PathingScene =
  ## Recreates a complete scene, including deterministic paths and body state.
  result.world = emptyWorld()
  case scenario
  of OpenField:
    result.bounds = PathingRect(x: 18, y: 29, width: 45, height: 20)
  of OpposingStreams:
    result.bounds = PathingRect(x: 16, y: 29, width: 50, height: 16)
  of CrossingStreams:
    result.bounds = PathingRect(x: 18, y: 18, width: 48, height: 42)
  of NarrowChoke:
    result.bounds = PathingRect(x: 18, y: 29, width: 45, height: 20)
    # The wall reaches map edges so every route uses the visible opening.
    result.plantTrees(PathingRect(x: 39, y: 0, width: 2, height: 39))
    result.plantTrees(PathingRect(x: 39, y: 41, width: 2, height: 39))
  of BuildingDetour:
    result.bounds = PathingRect(x: 18, y: 27, width: 45, height: 21)
    result.addBuilding(FarmBuilding, 37, 33)
    result.addBuilding(TownHallBuilding, 39, 36)
  for i in 0 ..< PathingUnitCount:
    let
      split = scenario in {OpposingStreams, CrossingStreams}
      group = if split: i mod 2 else: i div (PathingUnitCount div 2)
      rank = if split: i div 2 else: i
      column = int32(rank mod 10)
      row = int32(rank div 10)
    var
      start = fixedVec2(
        21.5'fx + fixed(column) * FixedHalf,
        34.5'fx + fixed(row) * FixedHalf
      )
      goal = fixedVec2(49.5'fx + fixed(column), 34.5'fx + fixed(row))
    if split:
      if group == 0:
        goal.x = 53.5'fx + fixed(column)
      elif scenario == OpposingStreams:
        start.x = 53.5'fx + fixed(column) * FixedHalf
        goal.x = 19.5'fx + fixed(column)
      else:
        start = fixedVec2(
          36.5'fx + fixed(column) * FixedHalf,
          21.5'fx + fixed(row) * FixedHalf
        )
        goal = fixedVec2(35.5'fx + fixed(column), 52.5'fx + fixed(row))
    result.addUnit(start, goal, group)
