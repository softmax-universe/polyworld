## Floating, player-owned rewards anchored to the defeated unit.

import
  chroma, pixie, silky, vmath,
  polyworld/chrome,
  sim

const
  RewardLifetime* = 1.4'f
  RewardRiseSpeed* = 30.0'f
  RewardRowHeight* = 26.0'f
  RewardRowGap* = 3.0'f
  RewardTextLimit* = 48
  RewardOrbKey* = "gota_reward_xp"
  RewardIconSize = 24.0'f
  RewardGroupGap = 8.0'f

type
  RewardTextError* = object of CatchableError
  RewardText* = object
    position*: WorldPoint
    gold*, xp*: int
    age*: float32
    lift: float32
  RewardPlacement* = object
    index*: int
    origin*, size*: Vec2
    opacity*: float32
  RewardTexts* = object
    world: World
    heroId, tick: int32
    ready: bool
    viewport: Vec2
    scale: float32
    entries*: seq[RewardText]
    placements: seq[RewardPlacement]

proc addRewardIcons*(builder: AtlasBuilder) =
  ## Draws a luminous XP orb into the existing UI atlas.
  let
    orb = newImage(64, 64)
    context = newContext(orb)
  for disc in [
    (32'f, 33'f, 29'f, color(0.39, 0.19, 0.68, 0.18)),
    (32'f, 33'f, 25'f, color(0.63, 0.44, 1, 0.48)),
    (32'f, 33'f, 21'f, color(0.25, 0.13, 0.48, 1)),
    (31'f, 31'f, 19'f, color(0.57, 0.33, 0.9, 1)),
    (29'f, 28'f, 15'f, color(0.75, 0.53, 1, 1)),
    (25'f, 23'f, 9'f, color(0.9, 0.77, 1, 1)),
    (24'f, 21'f, 5'f, color(1, 0.96, 1, 1))
  ]:
    context.fillStyle = disc[3]
    context.fillCircle(circle(vec2(disc[0], disc[1]), disc[2]))
  if not builder.addImage(RewardOrbKey, orb):
    raise newException(RewardTextError,
      "The UI atlas is too small for reward icons")

proc syncRewardTexts*(texts: var RewardTexts, world: World, heroId: int32) =
  ## Discards stale feedback on entry, viewpoint changes, and replay seeks.
  texts.world = world
  texts.heroId = heroId
  texts.tick = world.tick
  texts.ready = true
  texts.entries.setLen(0)
  texts.placements.setLen(0)

proc collectRewardTexts*(texts: var RewardTexts, world: World,
    heroId: int32, viewMode: int32) =
  ## Consumes one fresh tick, restricted to the local hero's visible rewards.
  if not texts.ready or texts.world != world or texts.heroId != heroId or
      world.tick < texts.tick or world.tick > texts.tick + 1:
    texts.syncRewardTexts(world, heroId)
    return
  if texts.tick == world.tick:
    return
  texts.tick = world.tick
  if heroId == 0:
    return
  for reward in world.rewardEffects:
    if reward.heroId != heroId or (reward.gold <= 0 and reward.xp <= 0):
      continue
    if viewMode in 1'i32 .. 2'i32 and
        not world.visible(Team(viewMode - 1), reward.position):
      continue
    if texts.entries.len == RewardTextLimit:
      texts.entries.delete(0)
    texts.entries.add RewardText(
      position: reward.position,
      gold: max(reward.gold, 0),
      xp: max(reward.xp, 0)
    )

proc advanceRewardTexts*(texts: var RewardTexts, dt: float32) =
  ## Moves both reward rows at one speed and retires expired groups.
  var count = 0
  for i in 0 ..< texts.entries.len:
    texts.entries[i].age += max(dt, 0)
    if texts.entries[i].age < RewardLifetime:
      texts.entries[count] = texts.entries[i]
      inc count
  texts.entries.setLen(count)

proc overlaps(first, second: RewardPlacement): bool =
  ## Keeps neighboring groups apart, including their text outlines.
  first.origin.x < second.origin.x + second.size.x + RewardGroupGap and
    first.origin.x + first.size.x + RewardGroupGap > second.origin.x and
    first.origin.y < second.origin.y + second.size.y + RewardGroupGap and
    first.origin.y + first.size.y + RewardGroupGap > second.origin.y

proc layoutRewardTexts*(texts: var RewardTexts, viewProjection: Mat4,
    viewport: Vec2, scale: float32): seq[RewardPlacement] =
  ## Projects frozen death anchors and assigns stable, separated text lanes.
  texts.placements.setLen(0)
  if viewport.x <= 0 or viewport.y <= 0 or scale <= 0:
    return
  if texts.viewport != viewport or texts.scale != scale:
    for entry in texts.entries.mitems:
      entry.lift = 0
    texts.viewport = viewport
    texts.scale = scale
  let area = viewport / scale
  for index, entry in texts.entries.mpairs:
    let
      point = vec3(entry.position.x.float32, entry.position.y.float32,
        entry.position.z.float32) / WorldScale.float32 + vec3(0, 1.7'f, 0)
      clip = viewProjection * vec4(point, 1)
    if clip.w <= 0 or clip.z < -clip.w or clip.z > clip.w:
      continue
    let
      anchor = vec2(clip.x / clip.w * 0.5'f + 0.5'f,
        0.5'f - clip.y / clip.w * 0.5'f) * area
      rows = (if entry.gold > 0 and entry.xp > 0: 2 else: 1)
      width = RewardIconSize + 7 +
        (max(($entry.gold).len, ($entry.xp).len) + 1).float32 * 12
      height = rows.float32 * RewardRowHeight +
        (rows - 1).float32 * RewardRowGap
    if anchor.x < 0 or anchor.x > area.x or
        anchor.y < 0 or anchor.y > area.y:
      continue
    let base = anchor - vec2(width / 2, height +
      entry.age * RewardRiseSpeed + entry.lift)
    var placement = RewardPlacement(
      index: index,
      origin: base,
      size: vec2(width, height),
      opacity: clamp((RewardLifetime - entry.age) / 0.45'f, 0.0'f, 1.0'f)
    )
    for attempt in 0 ..< texts.placements.len:
      var moved = false
      for other in texts.placements:
        if placement.overlaps(other):
          placement.origin.y = other.origin.y - height - RewardGroupGap
          moved = true
      if not moved:
        break
    entry.lift += base.y - placement.origin.y
    texts.placements.add placement
  texts.placements

proc drawRewardRow(sk: Silky, amount: int, icon: string, origin: Vec2,
    width, opacity: float32, tint: Color) =
  ## Draws a compact icon and outlined amount without a panel background.
  let
    label = "+" & $amount
    position = origin + vec2(RewardIconSize + 5, 0)
    size = vec2(width - RewardIconSize - 5, RewardRowHeight)
    shadow = color(0.025, 0.02, 0.045, opacity).asRgbx
  for offset in [vec2(-1, 0), vec2(1, 0), vec2(0, -1), vec2(0, 1)]:
    sk.drawLabel(label, position + offset, size, shadow, "Bold")
  sk.drawLabel(label, position, size,
    color(tint.r, tint.g, tint.b, opacity).asRgbx, "Bold")
  sk.drawSprite(icon, origin + vec2(0, 1), vec2(RewardIconSize),
    color(1, 1, 1, opacity).asRgbx)

proc drawRewardTexts*(sk: Silky, texts: var RewardTexts,
    viewProjection: Mat4, viewport: Vec2) =
  ## Draws gold above XP, preserving a fixed row gap throughout the rise.
  let placements = texts.layoutRewardTexts(viewProjection, viewport, sk.uiScale)
  for placement in placements:
    let entry = texts.entries[placement.index]
    var origin = placement.origin
    if entry.gold > 0:
      sk.drawRewardRow(entry.gold, "gold", origin, placement.size.x,
        placement.opacity, color(1, 0.83, 0.31, 1))
      origin.y += RewardRowHeight + RewardRowGap
    if entry.xp > 0:
      sk.drawRewardRow(entry.xp, RewardOrbKey, origin, placement.size.x,
        placement.opacity, color(0.84, 0.66, 1, 1))
