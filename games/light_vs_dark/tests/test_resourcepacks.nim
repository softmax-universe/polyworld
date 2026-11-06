import ../[content, maps, resourcepacks, sim]

proc pack(unit: Unit): ResourcePack =
  ## Reads cargo through the same presentation decision used by graphics.
  carriedPack(unit.kind, unit.hp, unit.carryGold, unit.carryWood)

let
  game = newGame(generateMap(DefaultSeed), TickRate * 180)
  world = game.world
  worker = world.units[0]
var
  tree = -1'i32
  nearest = int32.high
for i, wood in world.treeWood:
  if wood > 0:
    let distance = tileDistance(
      worker.tile, tile2(i.int32 mod world.map.side, i.int32 div world.map.side)
    )
    if distance < nearest:
      tree = i.int32
      nearest = distance
doAssert worker.pack == NoPack
doAssert world.applyHarvest(worker.owner, worker.id, tree, 1)
var delivered = false
for tick in 0 ..< TickRate * 120:
  world.tickWorld(nil)
  if worker.carryWood > 0:
    doAssert worker.pack == WoodPack
    delivered = true
  elif delivered:
    doAssert worker.pack == NoPack
    break
doAssert delivered and worker.carryWood == 0

block interruptedCargo:
  worker.carryGold = 25
  worker.carryWood = 0
  doAssert world.applyCancel(worker.owner, worker.id)
  let before = game.stateHash()
  doAssert worker.pack == GoldPack
  doAssert game.stateHash() == before
  worker.carryGold = 0
  doAssert worker.pack == NoPack
  worker.carryWood = 10
  doAssert worker.pack == WoodPack
  worker.hp = 0
  doAssert worker.pack == NoPack
  worker.kind = SoldierUnit
  worker.hp = 10
  doAssert worker.pack == NoPack

echo "Resource backpacks follow cargo, delivery, interrupted orders and death"
