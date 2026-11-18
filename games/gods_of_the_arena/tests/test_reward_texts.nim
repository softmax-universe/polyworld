## Reward feedback stays local, bounded, separated, and replay-safe.

import
  vmath,
  ../[rewardtexts, sim]

let
  world = World()
  projection = scale(vec3(0.1'f))
  viewport = vec2(1280, 720)
var texts: RewardTexts
texts.syncRewardTexts(world, 1)
inc world.tick
world.rewardEffects = @[
  RewardEffect(heroId: 1, victimId: 10, gold: 10, xp: 5),
  RewardEffect(heroId: 2, victimId: 10, xp: 20),
  RewardEffect(heroId: 1, victimId: 11)
]
texts.collectRewardTexts(world, 1, 0)
doAssert texts.entries.len == 1
doAssert texts.entries[0].gold == 10 and texts.entries[0].xp == 5
texts.collectRewardTexts(world, 1, 0)
doAssert texts.entries.len == 1, "Repeated frames must not duplicate rewards"

let initial = texts.layoutRewardTexts(projection, viewport, 1)
doAssert initial.len == 1
doAssert initial[0].size.y == RewardRowHeight * 2 + RewardRowGap
texts.advanceRewardTexts(0.25'f)
let moved = texts.layoutRewardTexts(projection, viewport, 1)
doAssert abs(initial[0].origin.y - moved[0].origin.y -
  0.25'f * RewardRiseSpeed) < 0.001'f
doAssert initial[0].size == moved[0].size,
  "Gold and XP must keep their gap while moving at the same speed"
texts.advanceRewardTexts(0)
doAssert texts.entries[0].age == 0.25'f, "Paused rewards must remain still"

inc world.tick
world.rewardEffects = @[
  RewardEffect(heroId: 1, victimId: 11, gold: 10, xp: 5),
  RewardEffect(heroId: 1, victimId: 12, xp: 5)
]
texts.collectRewardTexts(world, 1, 0)
let grouped = texts.layoutRewardTexts(projection, viewport, 1)
doAssert grouped.len == 3
for i in 0 ..< grouped.len:
  for j in i + 1 ..< grouped.len:
    doAssert grouped[j].origin.y + grouped[j].size.y < grouped[i].origin.y,
      "Simultaneous deaths at one location must occupy separate lanes"
texts.advanceRewardTexts(0.2'f)
let later = texts.layoutRewardTexts(projection, viewport, 1)
for i in 0 ..< grouped.len:
  doAssert abs(grouped[i].origin.y - later[i].origin.y -
    0.2'f * RewardRiseSpeed) < 0.001'f

let retina = texts.layoutRewardTexts(projection, viewport * 2, 2)
for i in 0 ..< later.len:
  doAssert abs(retina[i].origin.y - later[i].origin.y) < 0.001'f
  doAssert retina[i].size == later[i].size
texts.advanceRewardTexts(RewardLifetime)
doAssert texts.entries.len == 0

texts.entries = @[
  RewardText(position: WorldPoint(x: -2 * WorldScale), gold: 10, xp: 5),
  RewardText(position: WorldPoint(x: 2 * WorldScale), gold: 10, xp: 5)
]
discard texts.layoutRewardTexts(projection, viewport, 1)
let zoomed = texts.layoutRewardTexts(scale(vec3(0.005'f)), viewport, 1)
doAssert zoomed[1].origin.y + zoomed[1].size.y < zoomed[0].origin.y,
  "Camera zoom must not leave existing reward groups overlapping"

texts.syncRewardTexts(world, 1)
inc world.tick
texts.collectRewardTexts(world, 1, 1)
doAssert texts.entries.len == 0, "Unseen deaths must not reveal their positions"
inc world.tick
texts.collectRewardTexts(world, 1, 0)
doAssert texts.entries.len == 2
world.tick += 10
texts.collectRewardTexts(world, 1, 0)
doAssert texts.entries.len == 0, "Fast forwarding must establish a silent baseline"
inc world.tick
texts.collectRewardTexts(world, 1, 0)
doAssert texts.entries.len == 2
texts.collectRewardTexts(world, 2, 0)
doAssert texts.entries.len == 0, "Changing the local hero clears old rewards"
texts.syncRewardTexts(world, 1)
inc world.tick
world.rewardEffects.setLen(0)
for i in 0 ..< RewardTextLimit + 12:
  world.rewardEffects.add RewardEffect(heroId: 1, victimId: i.int32, xp: 5)
texts.collectRewardTexts(world, 1, 0)
doAssert texts.entries.len == RewardTextLimit
texts.syncRewardTexts(world, 1)
doAssert texts.entries.len == 0
echo "PASS reward text ownership, deduplication, lanes, speed, expiry and seeks"
