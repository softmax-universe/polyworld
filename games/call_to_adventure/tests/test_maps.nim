## Call to Adventure map generation: seed determinism, connectivity, and
## a complete descent on every seed the generator claims to support.

import
  std/[strutils, times],
  polyworld/pathing,
  ../[content, maps]

echo "Testing the same seed generates the same dungeon"
block:
  let first = generateMap(2026)
  let firstHash = first.hash
  let second = generateMap(2026)
  doAssert second.hash == firstHash,
    "generation is not a pure function of the seed"
  doAssert terrainHash() == firstHash
  doAssert first.ramps.len == second.ramps.len
  doAssert first.entrance == second.entrance
  doAssert first.vault == second.vault
  doAssert first.seed == 2026

  let other = generateMap(2027)
  doAssert other.hash != firstHash,
    "a different seed must produce a different dungeon"
  doAssert other.ramps.len > 0

echo "Testing Old Halls themes and Surface scenery"
block:
  for seed in 2026'i32 .. 2031'i32:
    let
      dungeon = generateMap(seed)
      repeat = generateMap(seed)
    doAssert dungeon.decor == repeat.decor
    var surface: set[DecorKind]
    var arches = 0
    for prop in dungeon.decor:
      if prop.kind == ArchDecor:
        inc arches
        doAssert prop.span > 0
        doAssert isWalkable(int(prop.tile.level), int(prop.tile.x), int(prop.tile.z))
    doAssert arches >= dungeon.rooms[OldHallsLevel].len
    for prop in dungeon.decor:
      if prop.tile.level == SurfaceLevel:
        surface.incl prop.kind
    doAssert surface == {TreeDecor, RockDecor, BushDecor}

    var
      seen: set[RoomTheme]
      previous = NoRoomTheme
    for room in dungeon.rooms[OldHallsLevel]:
      doAssert room.theme != NoRoomTheme and room.theme != previous
      seen.incl room.theme
      previous = room.theme
      var count = 0
      for z in room.z ..< room.z + room.depth:
        for x in room.x ..< room.x + room.width:
          let tile = layers[OldHallsLevel].tiles[z * GridTiles + x]
          if tile.kind == room.theme.roomFloor:
            inc count
      doAssert count > 0
      var
        placed: set[DecorKind]
        statues: set[range[0..1]]
        altarCount = 0
      for prop in dungeon.decor:
        if int(prop.tile.level) == OldHallsLevel and
            room.contains(int32(prop.tile.x), int32(prop.tile.z)):
          placed.incl prop.kind
          case prop.kind
          of StatueDecor:
            doAssert prop.span in 0..1
            statues.incl range[0..1](prop.span)
          of AltarDecor:
            doAssert prop.span in [1'i32, 3]
            inc altarCount
          else:
            discard
      if room.theme == TempleTheme:
        doAssert statues == {range[0..1](0), range[0..1](1)}
        doAssert altarCount == 1
      let expected =
        case room.theme
        of ArmoryTheme: {HeraldryDecor, WeaponsDecor, ArmorDecor, TargetDecor}
        of LibraryTheme: {ShelvesDecor, BooksDecor, CircleDecor}
        of DungeonTheme: {BonesDecor, ShacklesDecor, PrisonRackDecor}
        of TempleTheme:
          {AltarDecor, StatueDecor, GemsDecor, RugDecor, ColumnDecor, GobletNicheDecor}
        of NoRoomTheme: {}
      doAssert expected <= placed, $room.theme & ": " & $placed
      doAssert TorchDecor in placed and WallTrimDecor in placed, $room.theme
    doAssert seen == {ArmoryTheme, LibraryTheme, DungeonTheme, TempleTheme}

echo "Testing every level is populated and connected"
block:
  let dungeon = generateMap(2026)
  dungeon.verifyDungeon()
  for level in 0 ..< LevelCount:
    doAssert dungeon.rooms[level].len > 0, "level " & $level & " has no rooms"
    var walkable = 0
    for z in 0 ..< GridTiles:
      for x in 0 ..< GridTiles:
        if isWalkable(level, x, z):
          inc walkable
    doAssert walkable > 200,
      "level " & $level & " has only " & $walkable & " walkable tiles"
    doAssert walkable < 4_000,
      "level " & $level & " still fills the slab, " & $walkable &
      " walkable tiles"

echo "Testing levels sit in separate height bands"
block:
  discard generateMap(2026)
  # Overlapping bands are what would let computeEdgeLink match two levels by
  # accident, so pin the separation rather than trusting the constants.
  for level in 0 ..< LevelCount - 1:
    doAssert levelBase(level) - levelBase(level + 1) == BandSteps
  doAssert int(WallSteps) < int(BandSteps),
    "a level's apron must not reach the level above it"
  doAssert int(WallSteps) <= 16,
    "walls should sit about a character high, not three times that"
  doAssert int(SlabSteps) < int(BandSteps),
    "a floor slab must not reach the level above it"

echo "Testing the party can descend to the vault and climb back out"
block:
  let dungeon = generateMap(2026)
  doAssert dungeon.ramps.len == LevelCount - 1,
    "expected one ramp per level boundary, got " & $dungeon.ramps.len
  doAssert dungeon.descentPath(),
    "the vault must be reachable from the entrance and back"

echo "Testing every ramp links across exactly one band"
block:
  let dungeon = generateMap(2026)
  for ramp in dungeon.ramps:
    doAssert ramp.lower == ramp.upper + 1
    let down = edgeLink(
      int(ramp.upper), int(ramp.topX), int(ramp.topZ), 1)  # south
    doAssert down.open, "ramp top is not linked"
    doAssert down.layer == int(ramp.lower)
    doAssert isWalkable(
      int(ramp.lower), int(ramp.bottomX), int(ramp.bottomZ)),
      "the bottom landing must be walkable"

echo "Testing each descent has its own place"
block:
  # A single shared stair column let the party fall straight to the bottom
  # without exploring. Every stairwell must sit somewhere else, and must be
  # well away from where the party arrives on that level.
  let dungeon = generateMap(2026)
  for first in 0 ..< dungeon.ramps.len:
    for second in first + 1 ..< dungeon.ramps.len:
      let
        a = dungeon.ramps[first]
        b = dungeon.ramps[second]
      doAssert not (a.topX == b.topX and a.topZ == b.topZ),
        "two descents share a location"

  var arrival = dungeon.entrance
  for ramp in dungeon.ramps:
    let walk = abs(int32(arrival.x) - ramp.topX) +
      abs(int32(arrival.z) - ramp.topZ)
    doAssert walk >= 12,
      "the stair down from level " & $ramp.upper & " is only " & $walk &
      " tiles from where the party arrives; it should be a hike"
    arrival = TileRef(
      level: int8(ramp.lower), x: uint8(ramp.bottomX), z: uint8(ramp.bottomZ))

echo "Testing a stairwell is a real hole in the floor above"
block:
  # Otherwise the ramp clips through the floor it descends from.
  let dungeon = generateMap(2026)
  for ramp in dungeon.ramps:
    for step in 1 .. RampLength:
      let z = ramp.topZ + int32(step)
      for lane in -1'i32 .. 1'i32:
        let x = ramp.topX + lane
        doAssert not layers[ramp.upper].tiles[
            z * GridTiles + x].exists,
          "level " & $ramp.upper & " still has floor over its own stairwell " &
          "at (" & $x & "," & $z & ")"
        doAssert isWalkable(int(ramp.lower), int(x), int(z)),
          "the ramp itself must be walkable at (" & $x & "," & $z & ")"

echo "Testing floors stay sparse and use pillars"
block:
  let dungeon = generateMap(2026)
  var pillars = 0
  for level in 1 ..< LevelCount:
    for z in 0 ..< GridTiles:
      for x in 0 ..< GridTiles:
        let tile = layers[level].tiles[z * GridTiles + x]
        if not tile.exists or not tile.impassable:
          continue
        let tops = tile.tops
        doAssert tops[0] == tops[1] and tops[1] == tops[2] and
          tops[2] == tops[3],
          "impassable tiles must be flat, not angled corners"
        var floorNeighbors = 0
        for dz in -1 .. 1:
          for dx in -1 .. 1:
            if dx == 0 and dz == 0:
              continue
            if isWalkable(level, x + dx, z + dz):
              inc floorNeighbors
        if floorNeighbors >= 6:
          inc pillars
  doAssert pillars >= 6, "expected pillared halls, found " & $pillars
  var kinds: set[RoomKind]
  for level in 1 ..< LevelCount:
    for room in dungeon.rooms[level]:
      kinds.incl room.kind
  doAssert PillarRoom in kinds, "no pillared hall was generated"

echo "Testing generation across many seeds"
block:
  let started = cpuTime()
  for seed in 1'i32 .. 40'i32:
    let dungeon = generateMap(seed)
    dungeon.verifyDungeon()
    doAssert dungeon.descentPath(),
      "seed " & $seed & " produced a dungeon that cannot be completed"
  echo "  40 seeds in ", (cpuTime() - started).formatFloat(ffDecimal, 2), " s"

echo "test_maps: all checks passed"
