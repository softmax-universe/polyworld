import
  std/[os, strutils],
  chroma, pixie, silky, vmath,
  polyworld/gameuis,
  polyworld/common as artpaths,
  common, resources, hudlayouts, selections

when defined(silkyTesting):
  import silky/testwindow
else:
  import windy

const
  HudAssetDir =
    when defined(emscripten): "/monster-hud"
    else: currentSourcePath().parentDir / "assets" / "hud"
  HudFrameKey* = "monster_woodland_frame"
  HudPortraitKey* = "monster_woodland_portrait"
  HudVillagerPortraitKey* = "monster_villager_portrait"
  HudHousePortraitKey* = "monster_house_portrait"
  HudHallPortraitKey* = "monster_hall_portrait"
  HudResourceKeys*: array[ResourceKind, string] = [
    "monster_berries", "monster_grain", "monster_fish",
    "monster_pine", "monster_oak", "monster_stone"
  ]
  White = rgbx(255, 255, 255, 255)

type UtilityMeter = object
  title: string
  value: float32
  maximum: float32 = 100
  tint: ColorRGBX

proc readHudAsset(name: string): Image =
  ## Loads a bundled HUD image and reports an actionable asset error.
  try:
    readImage(HudAssetDir / name)
  except PixieError as error:
    raise newException(MonsterError,
      "Could not load Monster HUD asset " & name & ": " & error.msg)

proc pack(builder: AtlasBuilder, key: string, image: Image) =
  ## Adds one sprite while checking the shared atlas has room for it.
  if not builder.addImage(key, image):
    raise newException(MonsterError,
      "The UI atlas is too small for Monster HUD sprite " & key & ".")

proc addHudAssets*(builder: AtlasBuilder) =
  ## Packs the transparent frame, portrait, and six resource illustrations.
  let frame = readHudAsset("woodland-frame.png")
  if frame.width != HudSourceSize.x.int or frame.height != HudSourceSize.y.int:
    raise newException(MonsterError,
      "The woodland HUD frame must match its 2098 by 749 layout.")
  builder.pack(HudFrameKey, frame)
  let
    portrait = readHudAsset("moss-portrait.png")
    portraitSize = min(portrait.width, portrait.height)
    face = portrait.subImage(
      int(portraitSize.float32 * 0.19'f),
      int(portraitSize.float32 * 0.10'f),
      int(portraitSize.float32 * 0.62'f),
      int(portraitSize.float32 * 0.62'f)
    )
  builder.pack(HudPortraitKey, face.resize(128, 128))
  for (key, path) in [
    (HudVillagerPortraitKey, "characters/chargen/portraits/lvd/0_0.png"),
    (HudHousePortraitKey, "terrain/lvd_buildings/portraits/blacksmith.png"),
    (HudHallPortraitKey, "terrain/lvd_buildings/portraits/town_hall.png")
  ]:
    try:
      let profile = readImage(artpaths.DataRoot / path)
      builder.pack(key, profile.resize(128, 128))
    except PixieError as error:
      raise newException(MonsterError,
        "Could not load inspection portrait " & path & ": " & error.msg)
  let sheet = readHudAsset("resource-icons.png")
  if sheet.width < 3 or sheet.height < 2:
    raise newException(MonsterError,
      "The resource illustration sheet must contain a three by two grid.")
  for kind in ResourceKind:
    let
      column = kind.ord mod 3
      row = kind.ord div 3
      left = column * sheet.width div 3
      top = row * sheet.height div 2
      right = (column + 1) * sheet.width div 3
      bottom = (row + 1) * sheet.height div 2
      icon = sheet.subImage(left, top, right - left, bottom - top)
    builder.pack(HudResourceKeys[kind], icon.resize(128, 128))

proc drawHudSprite*(
  sk: Silky,
  key: string,
  panel: GameUiPanel,
  tint = White,
  radius = 0'f
) =
  ## Draws a HUD sprite into an explicit rectangle without stretching its UVs.
  if sk.atlas.isNil or key notin sk.atlas.entries or
    panel.size.x <= 0 or panel.size.y <= 0:
      return
  if radius > 0.5'f:
    sk.drawRoundedImage(key, panel.origin, panel.size, radius, tint)
  else:
    let entry = sk.atlas.entries[key]
    sk.drawQuad(panel.origin, panel.size,
      vec2(entry.x.float32, entry.y.float32),
      vec2(entry.width.float32, entry.height.float32), tint)

proc drawHudFrame*(sk: Silky, panel: GameUiPanel) =
  ## Draws the outer frame while omitting its former six inventory boxes.
  if sk.atlas.isNil or HudFrameKey notin sk.atlas.entries:
    return
  let
    entry = sk.atlas.entries[HudFrameKey]
    scale = panel.size / HudSourceSize
  for part in [
    rect(0, 0, 2098, 328), rect(0, 618, 2098, 131),
    rect(0, 328, 1600, 290), rect(1995, 328, 103, 290)
  ]:
    sk.drawQuad(panel.origin + part.xy * scale, part.wh * scale,
      vec2(entry.x.float32, entry.y.float32) + part.xy,
      part.wh, White)

proc drawLabel(
  sk: Silky,
  text: string,
  panel: GameUiPanel,
  font = "Hud",
  align = LeftAlign
) =
  ## Draws bright readable text and exposes its value to the UI harness.
  when defined(silkyTesting):
    sk.beginWidget("label", text = text,
      rect = rect(panel.origin.x, panel.origin.y, panel.size.x, panel.size.y))
  discard sk.drawText(font, text, panel.origin, White,
    maxWidth = panel.size.x, maxHeight = panel.size.y,
    hAlign = align, vAlign = MiddleAlign)
  when defined(silkyTesting):
    sk.endWidget()

proc drawName(sk: Silky, title: string, panel: GameUiPanel) =
  ## Keeps longer inspected names inside the portrait header.
  var font = "Bold"
  if not sk.atlas.isNil and font in sk.atlas.fonts:
    if sk.getTextSize(font, title).x > panel.size.x:
      font = "Hud"
    if sk.getTextSize(font, title).x > panel.size.x:
      font = "Small"
  sk.drawLabel(title, panel, font)

proc drawFill(
  sk: Silky,
  panel: GameUiPanel,
  value, maximum: float32,
  tint: ColorRGBX
) =
  ## Fills a real bounded quantity against its dark track.
  sk.drawRect(panel.origin, panel.size, rgbx(0, 0, 0, 190))
  sk.drawRect(panel.origin,
    vec2(panel.size.x * clamp(value / max(1'f, maximum), 0'f, 1'f),
      panel.size.y), tint)

proc drawMeter(
  sk: Silky,
  panel: GameUiPanel,
  title: string,
  value: float32,
  tint: ColorRGBX,
  maximum = 100'f
) =
  ## Combines a bright need label with its actual percentage meter.
  let
    height = panel.size.y
    label = GameUiPanel(origin: panel.origin,
      size: vec2(panel.size.x, height * 0.62'f))
    track = GameUiPanel(origin: panel.origin + vec2(0, height * 0.75'f),
      size: vec2(panel.size.x, height * 0.22'f))
  let quantity = if maximum == 100: $int(value) & "%"
    else: $int(value) & "/" & $int(maximum)
  sk.drawLabel(title & " " & quantity, label, "Hud")
  sk.drawFill(track, value, maximum, tint)

proc drawInventory(
  sk: Silky,
  stock: Inventory,
  slots: array[ResourceKind, GameUiPanel],
  emptyText: string
) =
  ## Shows only present resources, with counts directly over their icons.
  var next = 0
  for kind in ResourceKind:
    if stock[kind] <= 0:
      continue
    let
      slot = slots[ResourceKind(next)]
      quantity = GameUiPanel(
        origin: slot.origin + vec2(0, max(0'f, slot.size.y - 22)),
        size: vec2(slot.size.x, min(22'f, slot.size.y))
      )
    when defined(silkyTesting):
      sk.beginWidget("inventory-item", text = kind.resourceName(),
        rect = rect(slot.origin, slot.size))
    sk.drawHudSprite(HudResourceKeys[kind], slot)
    discard sk.drawText("Bold", $stock[kind], quantity.origin + vec2(1),
      rgbx(0, 0, 0, 240), maxWidth = quantity.size.x,
      maxHeight = quantity.size.y, hAlign = RightAlign, vAlign = MiddleAlign)
    sk.drawLabel($stock[kind], quantity, "Bold", RightAlign)
    when defined(silkyTesting):
      sk.endWidget()
    inc next
  if next == 0:
    let panel = GameUiPanel(origin: slots[BerriesResource].origin,
      size: vec2(slots[StoneResource].origin.x +
        slots[StoneResource].size.x - slots[BerriesResource].origin.x, 24))
    sk.drawLabel(emptyText, panel, "Hud")

proc drawUtility(
  sk: Silky,
  window: Window,
  boxes: ChatLayout,
  meters: openArray[UtilityMeter],
  stock: Inventory,
  emptyText, activity: string,
  frame: FrameState
) =
  ## Stacks an activity, meters, and items in one scrollable viewport.
  let
    panel = boxes.utility
    padding = 6'f * boxes.artScale
    meterStep = 62'f * boxes.artScale
    rowStep = 124'f * boxes.artScale
    iconSize = 110'f * boxes.artScale
    activityWidth = panel.size.x - padding * 2 - 12
    lineHeight = max(16'f, sk.getTextSize("Small", "Ag").y)
  var
    line: string
    lines = 0
  for word in strutils.splitWhitespace(activity):
    let candidate = if line.len == 0: word else: line & " " & word
    if line.len > 0 and sk.getTextSize("Small", candidate).x > activityWidth:
      inc lines
      line = word
    else:
      line = candidate
  if line.len > 0:
    inc lines
  let activityHeight = if lines > 0:
      lines.float32 * lineHeight + padding * 2
    else: 0'f
  var count = 0
  for amount in stock:
    if amount > 0:
      inc count
  let
    rows = (count + 2) div 3
    inventoryHeight = if rows == 0: 24'f
      else: (rows - 1).float32 * rowStep + iconSize
    total = padding * 2 + activityHeight +
      meters.len.float32 * meterStep + inventoryHeight
    scrollWidth = if total > panel.size.y: 12'f else: 0'f
    contentWidth = panel.size.x - padding * 2 - scrollWidth
    content = GameUiPanel(origin: panel.origin,
      size: vec2(panel.size.x - scrollWidth, panel.size.y))
  if total <= panel.size.y:
    frame.scrollingY = false
  sk.frameScrollbars(window, frame, rect(panel.origin, panel.size),
    vec2(panel.size.x, total), vec2(1))
  var origin = panel.origin + vec2(padding, padding - frame.scrollPos.y)
  sk.pushClipRect(rect(content.origin, content.size))
  if lines > 0:
    when defined(silkyTesting):
      sk.beginWidget("activity", text = activity,
        rect = rect(origin, vec2(activityWidth, activityHeight)))
    discard sk.drawText("Small", activity, origin, White,
      maxWidth = activityWidth, maxHeight = activityHeight,
      wordWrap = true)
    when defined(silkyTesting):
      sk.endWidget()
    origin.y += activityHeight
  for meter in meters:
    sk.drawMeter(GameUiPanel(origin: origin,
      size: vec2(contentWidth, 54'f * boxes.artScale)),
      meter.title, meter.value, meter.tint, meter.maximum)
    origin.y += meterStep
  var slots: array[ResourceKind, GameUiPanel]
  for kind in ResourceKind:
    slots[kind] = GameUiPanel(
      origin: origin + vec2((kind.ord mod 3).float32 * contentWidth / 3,
        (kind.ord div 3).float32 * rowStep),
      size: vec2(min(iconSize, contentWidth / 3))
    )
  sk.drawInventory(stock, slots, emptyText)
  sk.popClipRect()

proc drawSelectionStats*(
  sk: Silky,
  window: Window,
  world: World,
  boxes: ChatLayout,
  selection: Selection,
  frame: FrameState
) =
  ## Inspects the selected resident, home, or stash without issuing orders.
  let selected = world.resolveSelection(selection)
  var
    name = "Moss"
    portrait = HudPortraitKey
    primary = "Health " & $int(world.creature.health) & "%"
    value = world.creature.health
    maximum = 100'f
    subtitle = "Carrying " & $world.creature.cargo.total() & "/6"
    stock = world.creature.cargo
    emptyText = "Empty hands"
    activity = ""
    meters: seq[UtilityMeter]
  case selected.kind
  of VillagerSelection:
    let person = world.villagers[world.villagerIndex(selected.id)]
    name = person.name
    portrait = HudVillagerPortraitKey
    primary = "Health " & $int(person.health) & "%"
    value = person.health
    subtitle = if person.health > 0:
        person.attitude() & " / " & $person.cargo.total() & " carried"
      else: "Dead"
    stock = person.cargo
    if person.health > 0:
      activity = person.activity
      meters.add UtilityMeter(title: "Hunger", value: person.hunger,
        tint: rgbx(237, 167, 62, 255))
      meters.add UtilityMeter(title: "Sleepiness", value: person.sleepiness,
        tint: rgbx(165, 140, 232, 255))
      meters.add UtilityMeter(title: "Fear", value: person.fearLevel,
        tint: rgbx(235, 91, 65, 255))
      meters.add UtilityMeter(title: "Trust", value: person.trust,
        tint: rgbx(80, 180, 230, 255))
  of HouseholdSelection:
    let house = world.households[world.householdIndex(selected.id)]
    name = house.name
    portrait = HudHousePortraitKey
    primary = "Health " & $int(house.integrity) & "%"
    value = house.integrity
    subtitle = if house.integrity > 0: "Home supplies" else: "Ruins"
    stock = house.stock
    emptyText = "No supplies"
    if house.integrity > 0:
      meters.add UtilityMeter(title: "Warmth", value: house.fuel,
        tint: rgbx(237, 167, 62, 255))
  of VillageSelection:
    let village = world.villages[world.villageIndex(selected.id)]
    name = village.name
    portrait = HudHallPortraitKey
    primary = "Health " & $int(village.health) & "%"
    value = village.health
    subtitle = if village.health > 0: "Village hall" else: "Ruins"
    stock = village.stock
    emptyText = "No supplies"
    if village.health > 0:
      meters.add UtilityMeter(title: "Storage", value: stock.total().float32,
        maximum: 4096, tint: rgbx(80, 180, 230, 255))
  of SourceSelection:
    let source = world.sources[world.sourceIndex(selected.id)]
    name = source.name
    portrait = HudResourceKeys[source.resource]
    primary = if source.destroyed: "Destroyed"
      else: "Available " & $source.amount & "/" & $source.capacity
    value = source.amount.float32
    maximum = source.capacity.float32
    subtitle = if source.owner >= 0 and source.owner < world.villages.len:
      world.villages[source.owner].name else: "Shared"
    stock = default(Inventory)
    stock[source.resource] = source.amount
    emptyText = "No supplies"
  of MossSelection, NoSelection:
    meters.add UtilityMeter(title: "Energy", value: world.creature.energy,
      tint: rgbx(80, 180, 230, 255))
  sk.drawHudSprite(portrait, boxes.portrait,
    radius = min(boxes.portrait.size.x, boxes.portrait.size.y) / 2)
  sk.drawName(name, boxes.name)
  sk.drawLabel(primary, boxes.primaryLabel, "Small")
  sk.drawFill(boxes.primaryMeter, value, maximum, rgbx(109, 198, 46, 255))
  sk.drawLabel(subtitle, boxes.carrying, "Small")
  sk.drawUtility(window, boxes, meters, stock, emptyText, activity, frame)
