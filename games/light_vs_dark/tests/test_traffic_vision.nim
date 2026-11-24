## Cache output must exactly match the original ray painter at every cell.
import trafficfixture, polyworld/visions, ../rendervisibility
proc checkVision(w: World) =
  var blockers = newSeq[int16](w.blocker.len)
  for i,b in w.blocker:
    if b == TreeBlocker: blockers[i] = 24
    elif b != NoEntity: blockers[i] = 28
  for player in 0'i32 ..< w.players.len.int32:
    var expected = newSeq[bool](w.blocker.len)
    proc paint(x,y,r: int32, eye:int16) =
      for off in visionCircleTiles(r):
        let px = x+off.dx.int32
        let py = y+off.dz.int32
        if w.map.inGrid(px,py) and offsetVisible(w.map.side,w.map.heights,
            blockers,x,y,w.map.heights[w.map.tileIndex(x,y)].int64+eye.int64,off):
          expected[w.map.tileIndex(px,py)] = true
    for u in w.units:
      if (u.owner == player or w.diplomacy.sharesVision(player,u.owner)) and
          u.state != UnitDying:
        paint(u.tile.x,u.tile.y,unitOf(u.owner,u.kind).sightTiles,14)
    for b in w.buildings:
      if (b.owner == player or w.diplomacy.sharesVision(player,b.owner)) and
          b.state != BuildingDying:
        for y in b.origin.y.int32 ..< b.origin.y.int32+b.footprint.depth:
          for x in b.origin.x.int32 ..< b.origin.x.int32+b.footprint.width:
            paint(x,y,BuildingTable[b.kind].sightTiles,24)
    for i,v in expected:
      doAssert v == (w.visibleStamp[player][i] == w.visionGeneration[player])
let f = trafficFixture(20,"choke")
for tick in 0 ..< 150:
  f.world.tickWorld(nil)
  # Vision is computed before movement, so explicitly rebuild for this check.
  f.world.rebuildVision()
  checkVision(f.world)
# Force changed blockers and heights, sources, and a distinct alternating world.
let peer = f.world.clone()
for w in [f.world,peer]:
  w.blocker[w.map.tileIndex(39,40)] = TreeBlocker
  w.terrainEdits.add TileEdit(tick:w.tick,index:w.map.tileIndex(39,40))
  w.units[0].state = UnitDying
  w.rebuildVision()
  checkVision(w)
doAssert Game(world:f.world).stateHash() == Game(world:peer).stateHash()

block miningKeepsEntranceVision:
  let
    w = trafficFixture(0, "miners").world
    entrance = tile2(56, 40)
    id = w.spawnUnit(0, PeonUnit, entrance)
    miner = w.units[w.unitIndex(id)]
    probe = tile2(52, 40)
  w.rebuildVision()
  let before = w.renderVisibilityValues(1, CurrentSightMask)
  doAssert w.visible(0, probe) and not w.visible(1, probe),
    "The peon must be the only source of sight near the mine"
  doAssert w.applyHarvest(0, id, FirstMineId, 0)
  w.tickWorld(nil)
  doAssert miner.state == UnitInMine and miner.tile == entrance
  var insideTicks = 0
  while miner.state == UnitInMine:
    w.rebuildVision()
    checkVision(w)
    doAssert w.renderVisibilityValues(1, CurrentSightMask) == before,
      "Entering and working inside a mine must retain the same sight"
    for view in 0'i32 .. w.players.len.int32:
      doAssert not w.renderUnitVisible(view, miner),
        "Mining sight must not render a hidden peon"
    inc insideTicks
    doAssert insideTicks <= MineTicks + 1
    w.tickWorld(nil)
  doAssert insideTicks == MineTicks + 1
  doAssert miner.carryGold == GoldPerTrip
  w.rebuildVision()
  checkVision(w)
  doAssert w.visible(0, miner.tile) and w.renderUnitVisible(1, miner)

block miningSharesAndWithdrawsVision:
  let
    w = trafficFixture(0, "miners").world
    id = w.spawnUnit(0, PeonUnit, tile2(56, 40))
    miner = w.units[w.unitIndex(id)]
    probe = tile2(52, 40)
    pair = w.diplomacy.pairIndex(0, 1)
  doAssert w.applyHarvest(0, id, FirstMineId, 0)
  w.tickWorld(nil)
  doAssert miner.state == UnitInMine
  for state in [Allied, AllianceEnding, Neutral]:
    w.diplomacy.pairs[pair].state = state
    w.rebuildVision()
    checkVision(w)
    doAssert w.visible(0, probe)
    doAssert w.visible(1, probe) == (state != Neutral)
    doAssert not w.unitVisible(1, miner)
  w.damageEntity(id, miner.hp)
  w.rebuildVision()
  checkVision(w)
  doAssert not w.visible(0, probe), "A dead miner must stop granting sight"

echo "Cached vision matches original rays, terrain invalidation and peers"
