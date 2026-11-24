import
  std/[math, sets],
  vmath,
  polyworld/[pathing, rockgen],
  ../[assets, groves, maps]

echo "Checking generated scenery placement, harvesting, and restoration"
doAssert sceneryGroup(0, 100) == sceneryGroup(31, 100)
doAssert sceneryGroup(0, 100) != sceneryGroup(32, 100)
doAssert sceneryGroup(0, 100) != sceneryGroup(32 * 100, 100)
doAssert sceneryGroup(99 * 100 + 99, 100) < 0
for seed in [2026, 42, 73]:
  let
    map = generateMap(seed.int32)
    tiles = layers[0].tiles
    placements = grovePlacements(map.treeWood, seed, map.forestRocks)
  doAssert placements == grovePlacements(map.treeWood, seed, map.forestRocks)
  doAssert layers[0].tiles == tiles
  var
    treeTiles, rockTiles: HashSet[int]
    wood = newSeq[int16](map.treeWood.len)
    rockGeometry: array[BrushVariants, RockGeometry]
  for variant in 0 ..< BrushVariants:
    # Match the mesh seed used by polyworld/groves.generateGrove.
    let modelSeed = int(
      (seed.int64 * 104_729 + LightRock.ord.int64 * 7_919 +
        variant.int64 * 997 + 42) mod 1_000_000_000
    )
    rockGeometry[variant] = generateGeometry(
      rockSettings(false, variant, modelSeed)
    )
  for index, amount in map.treeWood:
    wood[index] = amount
  for placement in placements:
    doAssert placement.variant in 0 ..< BrushVariants
    doAssert placement.scale > 0
    doAssert placement.visible(wood)
    if placement.kind == LightTree:
      doAssert placement.tile notin treeTiles
      treeTiles.incl placement.tile
      let amount = wood[placement.tile]
      wood[placement.tile] = 0
      doAssert not placement.visible(wood)
      wood[placement.tile] = amount
      doAssert placement.visible(wood)
    else:
      doAssert placement.kind == LightRock
      doAssert placement.tile notin rockTiles
      rockTiles.incl placement.tile
      doAssert tiles[placement.tile].kind == RockTile
      doAssert tiles[placement.tile].impassable ==
        (placement.tile.int32 in map.forestRocks)
      doAssert tiles[placement.tile].impassable,
        "Every rendered boulder must identify blocked terrain"
      doAssert map.treeWood[placement.tile] == 0
      let
        cosine = cos(placement.rotation)
        sine = sin(placement.rotation)
      for vertex in rockGeometry[placement.variant].mesh.vertices:
        let
          x = (vertex.position.x * cosine + vertex.position.z * sine) *
            placement.scale
          z = (vertex.position.z * cosine - vertex.position.x * sine) *
            placement.scale
        doAssert abs(x) < 0.5'f and abs(z) < 0.5'f,
          "Rotated boulders must not extend into adjacent walkable tiles"
  for index, amount in map.treeWood:
    doAssert (index in treeTiles) == (amount > 0)
  doAssert treeTiles.len > 0
  doAssert rockTiles.len == map.forestRocks.len
  doAssert map.forestRocks.len ==
    (treeTiles.len + map.forestRocks.len) div 10
  doAssert wood == map.treeWood
  echo seed, ": ", treeTiles.len, " trees, ", rockTiles.len, " rocks"

echo "Checking the native and browser ground use only generated assets"
doAssert not LvdTerrainAssets.grass and not LvdTerrainAssets.water
doAssert not LvdWebTerrainAssets.grass and not LvdWebTerrainAssets.water

echo "LvD generated scenery passed"
