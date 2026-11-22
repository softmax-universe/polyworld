## Native production pose regression; no window, browser, or GL context needed.
## Include graphics so these are the exact capture/render/visibility functions.
include ../graphics
import trafficfixture

const Alphas = [0'f32, 0.25'f32, 0.5'f32, 0.75'f32, 1'f32]

proc sealMineRing(w: World, mine: Building, opening: Tile2, sealed: bool) =
  for y in mine.origin.y.int32 - 1 .. mine.origin.y.int32 + mine.footprint.depth:
    for x in mine.origin.x.int32 - 1 .. mine.origin.x.int32 + mine.footprint.width:
      if not covers(mine.origin, mine.footprint, x, y) and tile2(x, y) != opening:
        w.blocker[w.map.tileIndex(x, y)] = if sealed: TreeBlocker else: 0

proc miningCycle(exitDelta: Tile2) =
  run = Game(world: trafficFixture(0, "miners").world)
  let w = run.world
  let id = w.spawnUnit(0, PeonUnit, tile2(56, 40))
  let miner = w.units[w.unitIndex(id)]
  let mine = w.buildings[w.buildingIndex(FirstMineId)]
  let opening = tile2(mine.origin.x + exitDelta.x, mine.origin.y + exitDelta.y)
  doAssert w.applyHarvest(0, id, FirstMineId, 0)
  let control = Game(world: w.clone())
  interpolateVisuals = true
  let ordinary = CharacterModel()
  let goldCargo = CharacterModel()
  resourceModels.setLen(w.players.len)
  resourceModels[0][GoldPack][false] = goldCargo
  doAssert renderUnitModel(miner, ordinary) == ordinary
  viewMode = 0
  previousUnitPositions.clear()
  previousUnitFacings.clear()
  let entry = unitWorldPoint(miner)
  var insideTicks = 0

  proc step() =
    let before = run.stateHash()
    captureUnitPoses()
    doAssert run.stateHash() == before, "Pose capture changed authority"
    w.tickWorld(nil)
    control.world.tickWorld(nil)
    doAssert run.stateHash() == control.stateHash(), "Rendered/control hashes diverged"

  step()
  doAssert miner.state == UnitInMine
  w.sealMineRing(mine, opening, true)
  control.world.sealMineRing(mine, opening, true)
  while miner.state == UnitInMine:
    inc insideTicks
    doAssert insideTicks <= MineTicks + 2
    let before = run.stateHash()
    for alpha in Alphas:
      frameAlpha = alpha
      discard renderPoint(miner)
      discard renderFacing(miner)
      for mode in 0'i32 .. w.players.len.int32:
        viewMode = mode
        doAssert not shownUnit(miner), "A hidden miner became a visible phantom"
    doAssert run.stateHash() == before
    step()

  doAssert insideTicks == MineTicks + 1, "Must exercise the entire mining countdown"
  doAssert miner.state == UnitToDropGold and miner.tile == opening
  doAssert miner.carryGold == GoldPerTrip
  doAssert w.buildings[w.buildingIndex(FirstMineId)].minersInside == 0
  let exit = unitWorldPoint(miner)
  doAssert exit != entry, "Fixture must emerge at a different perimeter position"
  let before = run.stateHash()
  viewMode = 1
  doAssert shownUnit(miner)
  for alpha in Alphas:
    frameAlpha = alpha
    doAssert renderPoint(miner) == exit,
      "Mine emergence must SNAP at alpha=" & $alpha & " entry=" & $entry &
      " exit=" & $exit & " actual=" & $renderPoint(miner)
    doAssert renderFacing(miner) == unitYaw(miner)
    doAssert renderAnimation(miner) == miner.animation
    doAssert renderUnitModel(miner, ordinary) == goldCargo
  doAssert run.stateHash() == before

  # Restore travel space and prove smoothing resumes on the very next tick.
  w.sealMineRing(mine, opening, false)
  control.world.sealMineRing(mine, opening, false)
  step()
  let next = unitWorldPoint(miner)
  doAssert next != exit, "The post-exit tick must actually move"
  for alpha in Alphas:
    frameAlpha = alpha
    doAssert renderPoint(miner) == mix(exit, next, alpha)
  interpolateVisuals = false
  frameAlpha = 0
  doAssert renderPoint(miner) == next
  interpolateVisuals = true

  # Complete the real trip (not just a synthetic hidden/visible transition).
  for tick in 0 ..< 1800:
    if w.players[0].goldGathered > 0: break
    step()
  doAssert w.players[0].goldGathered == GoldPerTrip
  doAssert miner.carryGold == 0
  doAssert run.stateHash() == control.stateHash()
  echo "Mine exit ", opening, ": full countdown, snap alpha 0..1, next-tick smoothing, deposit; hash=", run.stateHash()

for delta in [tile2(1, -1), tile2(3, 1), tile2(1, 3), tile2(-1, 2),
    tile2(-1, -1), tile2(3, -1), tile2(-1, 3), tile2(3, 3)]:
  miningCycle(delta)

block constructionInteriorStillOverridesInterpolation:
  run = Game(world: trafficFixture(0, "miners").world)
  let w = run.world
  w.players[0].gold = 10000
  w.players[0].wood = 10000
  let id = w.spawnUnit(0, PeonUnit, tile2(35, 35))
  let builder = w.units[w.unitIndex(id)]
  doAssert w.applyBuild(0, id, FarmBuilding.ord.int32, 35, 35)
  doAssert builder.state == UnitBuilding
  let work = w.constructionPresentation(builder)
  doAssert work.active
  let x = work.tilePoint.x - mapHalf()
  let z = work.tilePoint.y - mapHalf()
  let expected = vec3(x, surfaceHeight(x, z) + work.floorLift, z)
  let before = run.stateHash()
  captureUnitPoses()
  doAssert previousUnitPositions[id] == unitWorldPoint(builder)
  doAssert expected != unitWorldPoint(builder)
  for smoothing in [false, true]:
    interpolateVisuals = smoothing
    for alpha in Alphas:
      frameAlpha = alpha
      doAssert renderPoint(builder) == expected
      doAssert renderFacing(builder) == work.yaw
      doAssert renderAnimation(builder) == AttackAnimation
  doAssert run.stateHash() == before
  echo "Production construction interior/yaw/animation override preserved"

echo "Production mine-exit interpolation regression passed"
