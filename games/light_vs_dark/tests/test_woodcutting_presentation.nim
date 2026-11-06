## Exercise presentation over an actual order, harvest, delivery and stop.
import ../[content, maps, sim, woodcuttingpresentation]

let game = newGame(generateMap(DefaultSeed), TickRate * 180)
let w = game.world
let worker = w.units[0]
var tree = -1'i32
var best = int32.high
for i, wood in w.treeWood:
  if wood > 0:
    let distance = tileDistance(worker.tile,
      tile2(i.int32 mod w.map.side, i.int32 div w.map.side))
    if distance < best:
      tree = i.int32
      best = distance
let before = game.stateHash()
doAssert not worker.woodAxeVisible and not worker.woodChopping
doAssert game.stateHash() == before
assert w.applyHarvest(worker.owner, worker.id, tree, 1)
doAssert worker.state == UnitToTree
doAssert worker.woodAxeVisible and not worker.woodChopping
doAssert worker.woodAnimationClip("Jog_Fwd_Loop") == "Jog_Fwd_Loop"
for _ in 0 ..< TickRate * 60:
  w.tickWorld(nil)
  if worker.state == UnitChopping: break
doAssert worker.state == UnitChopping
doAssert worker.woodAxeVisible and worker.woodChopping
doAssert worker.woodAnimationClip("Interact") == "Sword_Attack"
doAssert worker.woodAnimationTime(99, 0) == 0
doAssert worker.woodAnimationTime(99, 0.5) > 0
w.tickWorld(nil)
doAssert worker.woodAnimationTime(99, 0) > 0
let hash = game.stateHash()
discard worker.woodAxeVisible
discard worker.woodChopping
doAssert game.stateHash() == hash
for _ in 0 ..< TickRate * 60:
  w.tickWorld(nil)
  if worker.state in {UnitToDropWood, UnitDepositWood}: break
doAssert worker.state in {UnitToDropWood, UnitDepositWood}
doAssert worker.woodAxeVisible and not worker.woodChopping
doAssert worker.woodAnimationClip("Jog_Fwd_Loop") == "Jog_Fwd_Loop"
doAssert worker.woodAnimationTime(99, 0) == 99
for _ in 0 ..< TickRate * 60:
  w.tickWorld(nil)
  if worker.state == UnitToTree: break
doAssert worker.state == UnitToTree
doAssert worker.woodAxeVisible and not worker.woodChopping
doAssert w.applyCancel(worker.owner, worker.id)
doAssert not worker.woodAxeVisible and not worker.woodChopping
let soldier = Unit(kind: SoldierUnit, state: UnitChopping, hp: 10)
doAssert not soldier.woodAxeVisible and not soldier.woodChopping
worker.hp = 0
doAssert not worker.woodAxeVisible and not worker.woodChopping
echo "Wood axe follows actual approach/chop/delivery/return/stop lifecycle"
