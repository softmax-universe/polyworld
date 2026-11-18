## Call to Adventure Silky HUD.
##
## Two columns frame the dungeon. On the left, the level plate (its name,
## the quest and the party's status) over the Warrior's and the Mage's
## sheets; on the right, a parchment map of the level over the Ranger's and
## the Druid's. Each sheet shows its hero's meters, gear and skills.

import
  std/[algorithm, math, random, strformat],
  chroma, pixie, silky, vmath, windy,
  polyworld/[assets, stats, metrics, actioncam, chrome, common, configs,
    gameuis, inputs, pathing, player],
  content, maps, sim, game, controls, gear, isocam, layouts, skillstate

const
  ## Skill states laid over an icon. Silky blends premultiplied colors.
  CooldownShade = rgbx(0, 0, 0, 178)
  NoManaTint = rgbx(16, 42, 112, 140)
  ActionKeys = ["Q", "W", "E", "R"]
  HeroPortraitKeys*: array[HeroClass, string] = [
    "hero_fighter", "hero_wizard", "hero_rogue", "hero_cleric"
  ]
  ClassNames: array[HeroClass, string] = ["Warrior", "Mage", "Ranger", "Druid"]
  ClassMarkers: array[HeroClass, string] = ["defend", "cosmic", "bow", "leaf"]
    ## The glyph each hero shows on the map.
  ParchmentKey = "cta_parchment"
  ## Fonts packed for this HUD by `addHudArt`.
  TitleFont = "CtaTitle"
  BarFont = "CtaBar"
  CaptionFont = "CtaCaption"
  TimerFont = "CtaTimer"
  MapFont = "CtaMap"

  PanelTop = rgbx(30, 27, 30, 242)
  PanelBottom = rgbx(14, 13, 16, 242)
  TrimBright = rgbx(196, 156, 80, 255)
  TrimDark = rgbx(92, 71, 40, 255)
  TrimSelected = rgbx(255, 222, 130, 255)
  Gold = rgbx(234, 194, 106, 255)
  Parchment = rgbx(238, 224, 190, 255)
  Muted = rgbx(150, 144, 130, 255)
  Ink = rgbx(74, 48, 26, 255)

type
  WellTint = enum
    ## Gear wells are tinted like item rarity: the class's weapons and armor
    ## gold, the rest of what it wears blue and green, carried loot violet.
    PlainWell, GoldWell, BlueWell, GreenWell, MagicWell

  HudChrome = object
    layout: GameUiLayout
    plate: GameUiPanel
    map: GameUiPanel
    sheets: array[PartySize, GameUiPanel]

  MapView = object
    ## How one floor fits the parchment: tile (x, z) has its corner at
    ## `origin + (vec2(x, z) - first) * cell`.
    level: int
    origin: Vec2
    first: Vec2
    cell: float32
    tiles: Vec2
    paper: GameUiPanel

const
  WellColors: array[WellTint, tuple[top, bottom, edge: ColorRGBX]] = [
    (rgbx(30, 29, 33, 255), rgbx(18, 18, 21, 255), rgbx(66, 60, 52, 255)),
    (rgbx(104, 84, 34, 255), rgbx(52, 40, 16, 255), rgbx(196, 160, 78, 255)),
    (rgbx(38, 56, 112, 255), rgbx(18, 26, 58, 255), rgbx(86, 116, 188, 255)),
    (rgbx(42, 64, 40, 255), rgbx(20, 32, 22, 255), rgbx(96, 128, 78, 255)),
    (rgbx(72, 40, 104, 255), rgbx(34, 18, 52, 255), rgbx(158, 108, 214, 255))
  ]
  SlotCaptions: array[EquipSlot, string] = [
    "MAIN HAND", "ARMOR", "OFF HAND", "HELMET", "GLOVES", "BOOTS",
    "BELT", "AMULET", "RING", "RING"
  ]
    ## Named in an empty well, so a blank still says what it is for.
  RowTints: array[EquipSlot, WellTint] = [
    GoldWell, GoldWell, GoldWell,
    BlueWell, BlueWell, BlueWell,
    GreenWell, GreenWell, GreenWell, GreenWell
  ]

var
  statsState: StatsState
  lastMap: MapView
    ## The map as last drawn, so a click lands where the player saw it.
  mapHeld: bool
    ## True while a drag on the map pans the camera. The map holds still
    ## meanwhile: scrolling after the camera would move the ground under
    ## the pointer and run the pan away.

proc currentLayout*(window: Window): GameUiLayout =
  ## Returns the nine-region HUD layout in Silky layout space.
  initGameUiLayout(
    vec2(window.size.x.float32, window.size.y.float32) /
      gameUiScale(window),
    TransportHeight
  )

## Atlas art

proc keyedIcon(path: string): Image =
  ## Loads item art painted on a dark backdrop and clears the backdrop, so
  ## the item sits on the well's own tint.
  result = readImage(path)
  var border: array[3, seq[int]]
  for i in 0 ..< result.width:
    for j in [0, result.height - 1]:
      let c = result[i, j]
      border[0].add c.r.int
      border[1].add c.g.int
      border[2].add c.b.int
  for j in 0 ..< result.height:
    for i in [0, result.width - 1]:
      let c = result[i, j]
      border[0].add c.r.int
      border[1].add c.g.int
      border[2].add c.b.int
  var backdrop: array[3, float32]
  for channel in 0 ..< 3:
    border[channel].sort()
    backdrop[channel] = border[channel][border[channel].len div 2].float32
  for pixel in result.data.mitems:
    let
      r = pixel.r.float32
      g = pixel.g.float32
      b = pixel.b.float32
      distance = sqrt(
        (r - backdrop[0]) ^ 2 + (g - backdrop[1]) ^ 2 + (b - backdrop[2]) ^ 2
      )
      alpha = clamp((distance - 10) / 40, 0, 1) * pixel.a.float32 / 255
    pixel = rgbx(
      uint8(r * alpha), uint8(g * alpha), uint8(b * alpha), uint8(alpha * 255)
    )

proc parchmentImage(width, height: int): Image =
  ## Paints an old map sheet: warm paper, soft blotches, and edges browned
  ## by age.
  result = newImage(width, height)
  var rng = initRand(1771)
  const Grid = 8
  var blotch: array[Grid + 1, array[Grid + 1, float32]]
  for row in blotch.mitems:
    for value in row.mitems:
      value = rng.rand(1.0).float32
  for y in 0 ..< height:
    for x in 0 ..< width:
      let
        u = x.float32 / width.float32 * Grid
        v = y.float32 / height.float32 * Grid
        i = min(int(u), Grid - 1)
        j = min(int(v), Grid - 1)
        fu = u - i.float32
        fv = v - j.float32
        su = fu * fu * (3 - 2 * fu)
        sv = fv * fv * (3 - 2 * fv)
        cloud = mix(
          mix(blotch[j][i], blotch[j][i + 1], su),
          mix(blotch[j + 1][i], blotch[j + 1][i + 1], su),
          sv
        )
        edge = min(
          min(x, width - 1 - x).float32 / width.float32,
          min(y, height - 1 - y).float32 / height.float32
        )
        burn = clamp(edge * 9 + cloud * 0.25 - 0.1, 0, 1)
        grain = rng.rand(1.0).float32 * 0.06 - 0.03
        light = (0.82 + cloud * 0.14 + grain) * (0.62 + 0.38 * burn)
      result[x, y] = rgbx(
        uint8(clamp(226 * light, 0, 255)),
        uint8(clamp(201 * light, 0, 255)),
        uint8(clamp(152 * light, 0, 255)),
        255
      )

proc addHudArt*(builder: AtlasBuilder) =
  ## Packs the fonts, gear art and parchment the hero sheets and map draw.
  for name in gearIcons():
    let path = DataRoot & "/" & GearIconDir & name & ".png"
    if not builder.addImage(gearKey(name), keyedIcon(path)):
      raise newException(ValueError, "the UI atlas is too small for gear art")
  if not builder.addImage(ParchmentKey, parchmentImage(256, 128)):
    raise newException(ValueError, "the UI atlas is too small for the map")
  builder.addFont(BoldFontPath, TitleFont, 26.0)
  builder.addFont(BoldFontPath, BarFont, 12.0)
  builder.addFont(BoldFontPath, CaptionFont, 10.0)
  builder.addFont(BoldFontPath, TimerFont, 17.0)
  builder.addFont(BoldFontPath, MapFont, 14.0)

## Stats overlay

proc currentMetrics(slot: int, complete: bool): MetricRow =
  ## Combines authoritative totals with live or original replay telemetry.
  result = run.metrics.read(slot, run.world.tick, complete)
  if run.historyPlayback:
    result = result.withTelemetry(
      run.history, slot, run.world.tick, complete
    )
  if run.replayMode:
    result = result.withTelemetry(
      run.replayData.metrics, slot, run.world.tick, complete
    )

proc currentStats(): StatsTable =
  ## Adapts the actual roster and outcome to the shared table.
  run.sampleMetrics()
  result = StatsTable(kind: AdventureStats, tick: run.world.tick,
    complete: run.world.outcome != RunningOutcome, winner: -1)
  let wins = run.world.scores()
  const Roles = ["FIGHTER", "WIZARD", "ROGUE", "CLERIC"]
  for slot in 0 ..< PartySize:
    let hero = run.world.actors[slot]
    var outcome = ""
    if not hero.alive:
      outcome = "FALLEN"
    elif result.complete:
      if wins[slot] > 0:
        outcome = "WINNER"
      elif run.world.returned[slot]:
        outcome = "ESCAPED"
      else:
        outcome = "STRANDED"
    result.rows.add StatsRow(
      slot: slot,
      name: run.config.players[slot].displayName(slot),
      subtitle: Roles[hero.heroClass.ord],
      portrait: HeroPortraitKeys[hero.heroClass],
      outcome: outcome,
      fallen: not hero.alive,
      selected: not run.replayMode and options.playerSlot == slot + 1,
      metrics: currentMetrics(slot, result.complete)
    )

proc statsContains(window: Window, mouse: Vec2): bool =
  ## Tests the overlay before allowing input through to the existing HUD.
  if not statsState.visible(window.tabHeld):
    return false
  statsState.mouseOverStats(window, currentLayout(window),
    currentStats(), mouse)

proc hudClicked(window: Window, sk: Silky, panel: GameUiPanel): bool =
  ## Keeps covered HUD controls from receiving an overlay click.
  not window.statsContains(sk.mousePos) and chrome.clicked(window, sk, panel)

## Placement

proc placeChrome(layout: GameUiLayout): HudChrome =
  ## Places the two columns: a top panel over two hero sheets each.
  result.layout = layout
  result.plate = layout.panel(GameUiRegion.TopLeft, PanelPlate)
  result.map = layout.panel(GameUiRegion.TopRight, PanelMap)
  let size = vec2(ColumnWidth, layout.sheetHeight())
  for slot in 0 ..< PartySize:
    let above =
      if slot == 0: result.plate
      elif slot == 2: result.map
      else: result.sheets[slot - 1]
    result.sheets[slot] = GameUiPanel(
      origin: vec2(above.origin.x, above.origin.y + above.size.y + ColumnGap),
      size: size
    )

proc currentChrome(window: Window): HudChrome =
  ## Places every HUD panel for the current window.
  placeChrome(currentLayout(window))

proc hudFreeBand*(window: Window): tuple[lift, free: float32] =
  ## The open screen band between the two columns and above the replay
  ## bar, as the camera lift that centers the target in it and its height
  ## fraction. The columns flank the band, so only the bar takes height.
  let
    layout = currentLayout(window)
    height = max(layout.size.y, 1)
    bottom = layout.transportHeight / height
  (lift: bottom / 2, free: max(1 - bottom, 0.1'f32))

proc mapPaper(panel: GameUiPanel): GameUiPanel =
  ## Returns the parchment inside the map's frame.
  panel.inset(5)

proc mouseOverUi*(window: Window, mouse: Vec2): bool =
  ## Returns whether camera input begins inside any visible HUD panel.
  if window.statsContains(mouse) or mouseOverDebugMenu(mouse):
    return true
  let chrome = currentChrome(window)
  mouseOverPanels(
    mouse,
    chrome.layout,
    [chrome.plate, chrome.map, chrome.sheets[0], chrome.sheets[1],
      chrome.sheets[2], chrome.sheets[3]]
  )

## Drawing primitives

proc whiteUv(sk: Silky): Vec2 =
  ## Returns the atlas point every flat-colored triangle samples.
  let white = sk.atlas.entries[WhiteTileKey]
  vec2(white.x.float32 + white.width.float32 / 2,
    white.y.float32 + white.height.float32 / 2)

proc drawGradient(sk: Silky, pos, size: Vec2, top, bottom: ColorRGBX) =
  ## Fills a rectangle shading from one color at the top to another below.
  let
    uv = sk.whiteUv
    a = pos
    b = pos + vec2(size.x, 0)
    c = pos + size
    d = pos + vec2(0, size.y)
  sk.drawTriangle([a, b, c], [uv, uv, uv], [top, top, bottom])
  sk.drawTriangle([a, c, d], [uv, uv, uv], [top, bottom, bottom])

proc drawBorder(sk: Silky, pos, size: Vec2, width: float32,
    color: ColorRGBX) =
  ## Strokes the inside edge of a rectangle.
  sk.drawRect(pos, vec2(size.x, width), color)
  sk.drawRect(pos + vec2(0, size.y - width), vec2(size.x, width), color)
  sk.drawRect(pos + vec2(0, width), vec2(width, size.y - width * 2), color)
  sk.drawRect(pos + vec2(size.x - width, width),
    vec2(width, size.y - width * 2), color)

proc drawDiamond(sk: Silky, center: Vec2, radius: float32,
    color: ColorRGBX) =
  ## Draws a small square stood on its corner.
  let
    uv = sk.whiteUv
    n = center + vec2(0, -radius)
    e = center + vec2(radius, 0)
    s = center + vec2(0, radius)
    w = center + vec2(-radius, 0)
  sk.drawTriangle([n, e, s], [uv, uv, uv], [color, color, color])
  sk.drawTriangle([n, s, w], [uv, uv, uv], [color, color, color])

proc drawTrim(sk: Silky, panel: GameUiPanel, selected = false) =
  ## Strokes the gold trim of a panel: a bright outer line, a dark inner
  ## one, and a stud at each corner.
  let trim = if selected: TrimSelected else: TrimBright
  sk.drawBorder(panel.origin, panel.size, 2, trim)
  sk.drawBorder(panel.origin + vec2(4), panel.size - vec2(8), 1, TrimDark)
  for corner in [vec2(0), vec2(1, 0), vec2(0, 1), vec2(1)]:
    let point = panel.origin + vec2(3) + corner * (panel.size - vec2(6))
    sk.drawDiamond(point, 5, trim)
    sk.drawDiamond(point, 2, PanelBottom)

proc drawGoldPanel(sk: Silky, panel: GameUiPanel, selected = false) =
  ## Draws one dark HUD panel in its gold trim.
  sk.drawGradient(panel.origin, panel.size, PanelTop, PanelBottom)
  sk.drawTrim(panel, selected)

proc drawWell(sk: Silky, well: GameUiPanel, tint: WellTint) =
  ## Draws an equipment or skill well, tinted like the item it holds.
  let colors = WellColors[tint]
  sk.drawGradient(well.origin, well.size, colors.top, colors.bottom)
  sk.drawBorder(well.origin, well.size, 1, colors.edge)

proc drawShadowLabel(sk: Silky, text: string, pos, size: Vec2,
    color: ColorRGBX, font: string, align = CenterAlign) =
  ## Draws text with a dark drop shadow, readable over busy art.
  sk.drawLabel(text, pos + vec2(1, 1), size, rgbx(0, 0, 0, 230), font, align)
  sk.drawLabel(text, pos, size, color, font, align)

proc drawGlyph(sk: Silky, name: string, center: Vec2, size: float32,
    color: ColorRGBX) =
  ## Draws a white HUD glyph centered on a point, tinted.
  sk.drawSprite(name, center - vec2(size / 2), vec2(size), color)

proc drawMarker(sk: Silky, name: string, center: Vec2, size: float32,
    color: ColorRGBX) =
  ## Draws a map glyph over a dark halo so it reads on the parchment.
  sk.drawGlyph(name, center, size + 4, rgbx(40, 24, 12, 230))
  sk.drawGlyph(name, center, size, color)

## Readouts

proc heroColor*(class: HeroClass): ColorRGBX =
  ## Returns the stable presentation color for one party role.
  case class
  of FighterClass: rgbx(74, 128, 236, 255)
  of WizardClass: rgbx(176, 98, 236, 255)
  of RogueClass: rgbx(240, 194, 58, 255)
  of ClericClass: rgbx(96, 192, 82, 255)

proc healthColor(actor: Actor): ColorRGBX =
  ## Returns a health color that moves from green through yellow to red.
  let ratio =
    if actor.maxHp <= 0:
      0'i32
    else:
      int32(actor.hp) * 100 div int32(actor.maxHp)
  if ratio > 60:
    rgbx(58, 182, 72, 255)
  elif ratio > 30:
    rgbx(229, 184, 54, 255)
  else:
    rgbx(216, 67, 62, 255)

proc abilityIconKey(ability: Ability): string =
  ## Returns the atlas name packed from one ability art file.
  "ability_" & AbilityIconFiles[ability]

proc drawAbilityState(
    sk: Silky,
    pos: Vec2,
    size: float32,
    ability: Ability,
    actor: Actor,
    renderAlpha: float32,
    paysMana: bool
) =
  ## Lays a skill's state over its icon: tinted blue while the hero cannot
  ## pay for it, dimmed clockwise where its cooldown has yet to clear, and
  ## the seconds left on a wait long enough to be worth reading.
  let left = actor.cooldownLeft(ability, renderAlpha)
  if paysMana and actor.lacksMana(ability):
    sk.drawRect(pos, vec2(size), NoManaTint)
  if left > 0:
    sk.drawClockShade(pos, size, 1 - left, CooldownShade)
  let seconds = actor.cooldownSeconds(ability, renderAlpha)
  if seconds > 0 and
      Abilities[ability].cooldownTicks.int32 >= TickRate * 3 div 2:
    hudScratch.setLen(0)
    hudScratch.addHudInt(int(ceil(seconds)))
    hudScratch.add 's'
    sk.drawShadowLabel(
      hudScratch, vec2(pos.x, pos.y + size * 0.5), vec2(size, size * 0.5),
      rgbx(255, 255, 255, 255), if size >= 48: TimerFont else: BarFont
    )

proc drawSkillIcon(
    sk: Silky,
    well: GameUiPanel,
    ability: Ability,
    actor: Actor,
    renderAlpha: float32
) =
  ## Draws one skill in its well under its state.
  sk.drawWell(well, PlainWell)
  if ability == NoAbility:
    return
  let size = min(well.size.x, well.size.y) - 2
  let pos = well.origin + (well.size - vec2(size)) * 0.5'f32
  sk.drawSprite(abilityIconKey(ability), pos, vec2(size))
  sk.drawAbilityState(pos, size, ability, actor, renderAlpha, true)
  sk.drawBorder(well.origin, well.size, 1, WellColors[PlainWell].edge)

proc selectedVisible*(tile: TileRef): bool =
  ## Returns whether any living party member sees a tile.
  for slot in 0 ..< min(PartySize, run.world.actors.len):
    if run.world.actors[slot].alive and
        run.world.visible(int32(slot), tile):
      return true

proc clockHour*(): float32 =
  ## The accelerated expedition clock in hours, 0 ..< 24 with a fraction:
  ## the party sets out at 10:00 and one real second is one game minute.
  let total = 10 * 60 + int(run.world.tick) div int(TickRate)
  float32(total mod (24 * 60)) / 60

proc smoothClockHour*(tick: float32): float32 =
  ## The same expedition clock from a fractional tick (whole ticks plus the
  ## frame's sub-tick blend), continuous instead of stepping once per whole
  ## game minute — the sun and its shadows glide with it.
  var minutes = 10.0'f32 * 60.0'f32 + tick / float32(TickRate)
  minutes = minutes - float32(24 * 60) * floor(minutes / float32(24 * 60))
  minutes / 60.0'f32

proc hudHour(): int =
  ## Returns the displayed hour of the accelerated expedition clock.
  int(clockHour())

proc addHudClock(s: var string) =
  ## Appends the accelerated expedition clock.
  let
    total = 10 * 60 + int(run.world.tick) div int(TickRate)
    minuteOfDay = total mod (24 * 60)
    hour = minuteOfDay div 60
    minute = minuteOfDay mod 60
    hour12 =
      if hour mod 12 == 0: 12
      else: hour mod 12
  s.addHudInt(hour12)
  s.add ':'
  s.addPad2(minute)
  s.add ' '
  if hour < 12:
    s.add "AM"
  else:
    s.add "PM"

proc questTile(level: int32): TileRef =
  ## Returns the current floor's stair or vault objective marker.
  if run.world.phase == DescendingPhase:
    if level >= LevelCount - 1:
      return run.dungeon.vault
    for ramp in run.dungeon.ramps:
      if ramp.upper == level:
        return TileRef(
          level: int8(level),
          x: uint8(ramp.topX),
          z: uint8(ramp.topZ)
        )
  else:
    if level <= 0:
      return run.dungeon.entrance
    for ramp in run.dungeon.ramps:
      if ramp.lower == level:
        return TileRef(
          level: int8(level),
          x: uint8(ramp.bottomX),
          z: uint8(ramp.bottomZ)
        )
  TileRef(level: int8(level))

proc questTitle(level: int32): string =
  ## Names what the party is after on the shown floor.
  if run.world.isArena:
    "Win the Fight"
  elif run.world.phase == ReturningPhase:
    "Escape the Dungeon"
  elif level >= LevelCount - 1:
    "Clear the Vault"
  elif run.monstersOn(level) > 0:
    "Clear " & Themes[level].name
  else:
    "Descend to " & Themes[level + 1].name

proc selectHeroSlot(
    primaryId: var int,
    selectedIds: var array[PartySize, bool],
    followSelection: var bool,
    slot: int,
    additive: bool
) =
  ## Selects one party slot from a HUD click.
  if slot < 0 or slot >= min(PartySize, run.world.actors.len):
    return
  var count = 0
  for selected in selectedIds:
    if selected:
      inc count
  if not additive:
    for i in 0 ..< PartySize:
      selectedIds[i] = false
  elif selectedIds[slot] and count > 1:
    selectedIds[slot] = false
    if slot == primaryId:
      for i in 0 ..< PartySize:
        if selectedIds[i]:
          primaryId = i
          break
    followSelection = false
    for i in 0 ..< min(PartySize, run.world.actors.len):
      if selectedIds[i] and run.world.actors[i].alive:
        followSelection = true
        break
    return
  selectedIds[slot] = true
  primaryId = slot
  followSelection = run.world.actors[slot].alive

## Map

proc exploredBox(level: int): (IVec2, IVec2) =
  ## Returns the first and last corners of what the party has seen of one
  ## floor, and where its heroes stand there, so the map frames the known
  ## part of the floor. Snapped outward to 4 tiles so it steps rather than
  ## creeps as the party explores.
  const Snap = 4'i32
  var
    first = ivec2(GridTiles.int32, GridTiles.int32)
    last = ivec2(-1, -1)
  proc grow(x, z: int32) =
    first = ivec2(min(first.x, x), min(first.y, z))
    last = ivec2(max(last.x, x), max(last.y, z))
  for z in 0 ..< GridTiles:
    for x in 0 ..< GridTiles:
      if run.world.explored(
          TileRef(level: int8(level), x: uint8(x), z: uint8(z))):
        grow(x.int32, z.int32)
  for slot in 0 ..< PartySize:
    let actor = run.world.actors[slot]
    if actor.alive and int(actor.home.level) == level:
      grow(actor.home.x.int32, actor.home.z.int32)
  if last.x < 0:
    return (ivec2(0, 0), ivec2(GridTiles.int32 - 1, GridTiles.int32 - 1))
  first = ivec2(first.x div Snap * Snap, first.y div Snap * Snap)
  last = ivec2(
    (last.x div Snap + 1) * Snap - 1, (last.y div Snap + 1) * Snap - 1)
  (first, last)

proc mapView(panel: GameUiPanel, level: int, focus: Vec2): MapView =
  ## Fits what the party knows of one floor, plus a margin, onto the
  ## parchment, a tile no larger than `MaxCell` pixels. Once that would
  ## shrink a tile below `MinCell`, the map keeps that scale and scrolls
  ## instead, centered on `focus` (grid units) as far as the known part
  ## allows.
  const
    Margin = 2'i32
    MaxCell = 7'f32
    MinCell = 3'f32
  let
    paper = panel.mapPaper()
    inner = GameUiPanel(origin: paper.origin + vec2(8, 20),
      size: paper.size - vec2(16, 26))
    (first, last) = exploredBox(level)
    lo = (first - ivec2(Margin)).vec2
    span = (last - first + ivec2(1 + Margin * 2)).vec2
    cell = clamp(
      min(inner.size.x / span.x, inner.size.y / span.y), MinCell, MaxCell)
    tiles = inner.size / cell
  var start = lo - (tiles - span) * 0.5'f32
  for axis in 0 .. 1:
    if span[axis] > tiles[axis]:
      start[axis] = clamp(
        focus[axis] - tiles[axis] / 2, lo[axis], lo[axis] + span[axis] -
          tiles[axis])
  MapView(
    level: level,
    origin: inner.origin,
    first: start,
    cell: cell,
    tiles: tiles,
    paper: paper
  )

proc mapPoint(view: MapView, grid: Vec2): Vec2 =
  ## Converts a point in grid units (tile x and z) into the map.
  view.origin + (grid - view.first) * view.cell

proc gridPoint(view: MapView, point: Vec2): Vec2 =
  ## Converts a map point back into grid units.
  (point - view.origin) / view.cell + view.first

proc tileMapCenter(view: MapView, tile: TileRef): Vec2 =
  ## Returns the map point at the middle of a tile.
  view.mapPoint(vec2(tile.x.float32 + 0.5, tile.z.float32 + 0.5))

proc updateMinimapCamera*(
    window: Window,
    mouse: Vec2,
    cameraTarget: var Vec3,
    minimapPanning: var bool,
    followSelection: var bool,
    viewLevel: int
) =
  ## Moves the free camera while the primary button drags on the map.
  if window.statsContains(mouse):
    minimapPanning = false
    mapHeld = false
    return
  let
    chrome = currentChrome(window)
    paper = chrome.map.mapPaper()
    view =
      if lastMap.cell > 0 and lastMap.paper.origin == paper.origin and
          lastMap.paper.size == paper.size: lastMap
      else: mapView(chrome.map, viewLevel,
        vec2(cameraTarget.x, cameraTarget.z) + vec2(HalfGrid))
  if window.mousePressed(MouseLeft) and view.paper.contains(mouse):
    minimapPanning = true
    followSelection = false
  if not window.mouseDown(MouseLeft):
    minimapPanning = false
  mapHeld = minimapPanning
  if minimapPanning:
    let
      raw = view.gridPoint(mouse)
      grid = vec2(
        clamp(raw.x, view.first.x, view.first.x + view.tiles.x),
        clamp(raw.y, view.first.y, view.first.y + view.tiles.y)
      )
      x = clamp(int(grid.x), 0, GridTiles - 1)
      z = clamp(int(grid.y), 0, GridTiles - 1)
      tile = tileCenter(view.level, x, z)
      point = grid - vec2(HalfGrid)
    cameraTarget = vec3(point.x, tile.y, point.y)

proc drawMapCamera(
    sk: Silky,
    window: Window,
    view: MapView,
    cameraTarget: Vec3,
    cameraDistance: float32
) =
  ## Draws the isometric camera's visible ground footprint, a diamond on
  ## the north-up map, clipped to the parchment.
  let
    aspect = window.size.x.float32 / max(window.size.y.float32, 1)
    footprint = isoGroundFootprint(
      isoViewProjection(
        cameraTarget, cameraDistance, aspect, window.hudFreeBand().lift),
      cameraTarget.y
    )
    uv = sk.whiteUv
    color = rgbx(92, 52, 24, 220)
    thickness = 1.5'f32
  var corners: array[4, Vec2]
  for i, ground in footprint:
    corners[i] = view.mapPoint(ground + vec2(HalfGrid))
  for i in 0 ..< 4:
    let
      first = corners[i]
      last = corners[(i + 1) mod 4]
      delta = last - first
      length = delta.length
    if length <= 0:
      continue
    let
      offset = vec2(-delta.y, delta.x) * (thickness / (2 * length))
      a = first - offset
      b = first + offset
      c = last + offset
      d = last - offset
    sk.drawTriangle([a, b, c], [uv, uv, uv], [color, color, color],
      view.paper.origin, view.paper.size)
    sk.drawTriangle([a, c, d], [uv, uv, uv], [color, color, color],
      view.paper.origin, view.paper.size)

proc knownFloor(level, x, z: int): bool =
  ## True for a floor tile the party has seen.
  x >= 0 and z >= 0 and x < GridTiles and z < GridTiles and
    isWalkable(level, x, z) and run.world.explored(
      TileRef(level: int8(level), x: uint8(x), z: uint8(z)))

proc mapShade(level, x, z: int): int =
  ## Returns how one tile inks on the map: 0 blank paper, 1 a remembered
  ## floor, 2 a floor the party sees now, 3 the wall edging a seen floor.
  ## Sight only marks floors, so a wall is inked by the floor beside it.
  if isWalkable(level, x, z):
    let tile = TileRef(level: int8(level), x: uint8(x), z: uint8(z))
    if not run.world.explored(tile):
      return 0
    return if selectedVisible(tile): 2 else: 1
  for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1),
      (1, 1), (-1, 1), (1, -1), (-1, -1)]:
    if knownFloor(level, x + dx, z + dz):
      return 3

proc drawMap(
    sk: Silky,
    window: Window,
    panel: GameUiPanel,
    level: int,
    selectedIds: array[PartySize, bool],
    cameraTarget: Vec3,
    cameraDistance: float32
) =
  ## Draws the shown floor as an old map: the explored rooms inked on
  ## parchment, the heroes, the foes they see and where the quest leads.
  const Shades = [
    rgbx(0, 0, 0, 0), rgbx(238, 222, 182, 255), rgbx(251, 242, 214, 255),
    rgbx(78, 52, 30, 255)
  ]
  let view =
    if mapHeld and lastMap.level == level and lastMap.cell > 0 and
        lastMap.paper.origin == panel.mapPaper().origin:
      lastMap
    else:
      mapView(panel, level,
        vec2(cameraTarget.x, cameraTarget.z) + vec2(HalfGrid))
  lastMap = view
  sk.drawRect(panel.origin, panel.size, PanelBottom)
  sk.drawSprite(ParchmentKey, view.paper.origin, view.paper.size)
  let
    firstX = max(int(view.first.x), 0)
    firstZ = max(int(view.first.y), 0)
    endX = min(int(ceil(view.first.x + view.tiles.x)), GridTiles)
    endZ = min(int(ceil(view.first.y + view.tiles.y)), GridTiles)
  sk.pushClipRect(rect(view.paper.origin, view.paper.size))
  for z in firstZ ..< endZ:
    var
      runStart = firstX
      runShade = -1
    let y = view.origin.y + (z.float32 - view.first.y) * view.cell
    for x in firstX .. endX:
      let shade =
        if x < endX: mapShade(level, x, z)
        else: -1
      if shade != runShade:
        if runShade > 0:
          let left = view.origin.x + (runStart.float32 - view.first.x) *
            view.cell
          sk.drawRect(
            vec2(left, y),
            vec2((x - runStart).float32 * view.cell, view.cell),
            Shades[runShade]
          )
        runStart = x
        runShade = shade
  let objective = questTile(int32(level))
  if int(objective.level) == level and
      (objective.x > 0'u8 or objective.z > 0'u8):
    sk.drawMarker("quest_marker", view.tileMapCenter(objective), 13,
      rgbx(232, 176, 40, 255))
  for actor in run.world.actors:
    if actor.kind != MonsterActor or not actor.alive or
        int(actor.home.level) != level or not selectedVisible(actor.home):
      continue
    let
      center = view.tileMapCenter(actor.home)
      rank = actor.species.monsterRank
    case rank
    of ChampionRank:
      sk.drawMarker("boss", center, 14, rgbx(214, 44, 36, 255))
    of SwarmRank:
      sk.drawRect(center - vec2(1.5), vec2(3), rgbx(176, 40, 30, 255))
    else:
      let
        uv = sk.whiteUv
        r = 4.5'f32
        dark = rgbx(60, 20, 12, 255)
        red = rgbx(214, 44, 36, 255)
      sk.drawTriangle(
        [center + vec2(0, -r - 1.5), center + vec2(r + 1.5, r + 1),
          center + vec2(-r - 1.5, r + 1)],
        [uv, uv, uv], [dark, dark, dark])
      sk.drawTriangle(
        [center + vec2(0, -r), center + vec2(r, r * 0.8),
          center + vec2(-r, r * 0.8)],
        [uv, uv, uv], [red, red, red])
  for slot in 0 ..< PartySize:
    let actor = run.world.actors[slot]
    if not actor.alive or int(actor.home.level) != level:
      continue
    sk.drawMarker(ClassMarkers[actor.heroClass], view.tileMapCenter(actor.home),
      if selectedIds[slot]: 15 else: 12, heroColor(actor.heroClass))
  sk.drawMapCamera(window, view, cameraTarget, cameraDistance)
  sk.popClipRect()
  let paper = view.paper
  sk.drawLabel(Themes[level].name, paper.origin + vec2(9, 4),
    vec2(paper.size.x * 0.6, 20), Ink, MapFont)
  let north = paper.origin + vec2(paper.size.x - 16, 10)
  sk.drawTriangle(
    [north + vec2(0, -5), north + vec2(4, 4), north + vec2(-4, 4)],
    [sk.whiteUv, sk.whiteUv, sk.whiteUv], [Ink, Ink, Ink])
  sk.drawLabel("N", north + vec2(-8, 5), vec2(16, 14), Ink, CaptionFont,
    CenterAlign)
  sk.drawBorder(paper.origin, paper.size, 1, rgbx(120, 88, 50, 255))
  sk.drawBorder(panel.origin, panel.size, 2, TrimBright)
  for corner in [vec2(0), vec2(1, 0), vec2(0, 1), vec2(1)]:
    let
      point = panel.origin + corner * panel.size
      inward = vec2(1) - corner * 2
    sk.drawRect(
      point + vec2(min(inward.x, 0) * 16, min(inward.y, 0) * 4),
      vec2(16, 4), TrimBright)
    sk.drawRect(
      point + vec2(min(inward.x, 0) * 4, min(inward.y, 0) * 16),
      vec2(4, 16), TrimBright)

## Level plate

proc inCombat(level: int): bool =
  ## True while a foe the party sees on this floor is chasing or fighting.
  for actor in run.world.actors:
    if actor.kind == MonsterActor and actor.alive and
        int(actor.home.level) == level and
        actor.state in {ChasingState, FightingState, KitingState} and
        selectedVisible(actor.home):
      return true

proc foesInSight(level: int): int =
  ## Counts the living foes the party sees on this floor.
  for actor in run.world.actors:
    if actor.kind == MonsterActor and actor.alive and
        int(actor.home.level) == level and selectedVisible(actor.home):
      inc result

proc drawPlate(sk: Silky, panel: GameUiPanel, level: int) =
  ## Draws the level plate: the floor's name and number, the quest, and a
  ## status line with the fight, the foes in sight and the clock.
  sk.drawGoldPanel(panel)
  sk.drawDiamond(panel.origin + vec2(panel.size.x / 2, 1), 7, TrimBright)
  sk.drawDiamond(panel.origin + vec2(panel.size.x / 2, 1), 4,
    rgbx(70, 140, 230, 255))
  let parts = panel.platePanels()
  sk.drawGlyph("door", parts.icon.origin + parts.icon.size / 2, 34, Gold)
  sk.drawLabel(
    sk.fittedLabel(Themes[level].name, parts.title.size.x, TitleFont),
    parts.title.origin, parts.title.size, Gold, TitleFont
  )
  sk.drawGradient(parts.progress.origin, parts.progress.size,
    rgbx(36, 32, 30, 255), rgbx(20, 18, 18, 255))
  sk.drawBorder(parts.progress.origin, parts.progress.size, 1, TrimDark)
  hudScratch.setLen(0)
  hudScratch.addHudInt(level + 1)
  hudScratch.add " / "
  hudScratch.addHudInt(LevelCount)
  sk.drawLabel(hudScratch, parts.progress.origin, parts.progress.size,
    Parchment, "Bold", CenterAlign)
  let rule = TrimDark
  sk.drawRect(vec2(panel.origin.x + 12, parts.quest.origin.y - 5),
    vec2(panel.size.x - 24, 1), rule)
  sk.drawRect(vec2(panel.origin.x + 12, parts.status.origin.y - 5),
    vec2(panel.size.x - 24, 1), rule)
  sk.drawGlyph("quest_scroll",
    parts.questIcon.origin + parts.questIcon.size / 2, 22, Parchment)
  let foes = run.monstersOn(level)
  var foeText = ""
  if foes > 0:
    foeText.addHudInt(foes.int)
    foeText.add " foes"
  let foeWidth = sk.getTextSize("Small", foeText).x
  sk.drawLabel(
    sk.fittedLabel(questTitle(int32(level)),
      parts.quest.size.x - foeWidth - 8, "Default"),
    parts.quest.origin, parts.quest.size, Parchment, "Default"
  )
  sk.drawLabel(foeText, parts.quest.origin, parts.quest.size, Muted, "Small",
    RightAlign)
  let
    status = parts.status
    combat = inCombat(level)
    (glyph, state, stateColor) =
      if run.world.phase == WipedPhase:
        ("skull", "Party fallen", rgbx(220, 90, 80, 255))
      elif run.world.phase == EscapedPhase:
        ("crown", "Escaped", Gold)
      elif combat:
        ("battle", "In combat", Gold)
      elif run.world.phase == ReturningPhase:
        ("stairs_up", "Returning", Parchment)
      else:
        ("compass", "Exploring", Parchment)
    hour = hudHour()
  hudScratch.setLen(0)
  hudScratch.addHudClock()
  let
    clockWidth = sk.getTextSize("Hud", hudScratch).x
    clockLeft = status.origin.x + status.size.x - clockWidth
    middle = status.origin.y + status.size.y / 2
  sk.drawGlyph(glyph, vec2(status.origin.x + 9, middle), 18, stateColor)
  sk.drawLabel(state, status.origin + vec2(24, 0),
    vec2(110, status.size.y), stateColor, "Bold")
  sk.drawGlyph(if hour < 6 or hour >= 18: "night" else: "day",
    vec2(clockLeft - 13, middle), 18, Gold)
  sk.drawLabel(hudScratch, vec2(clockLeft, status.origin.y),
    vec2(clockWidth + 2, status.size.y), Parchment, "Hud")
  var sight = ""
  sight.addHudInt(foesInSight(level))
  sight.add " nearby"
  let
    left = status.origin.x + 24 + sk.getTextSize("Bold", state).x + 8
    right = clockLeft - 28
  sk.drawLabel(sight, vec2(left, status.origin.y),
    vec2(max(right - left, 0), status.size.y), Muted, "Hud", CenterAlign)
  for x in [left, right]:
    sk.drawRect(vec2(x, status.origin.y + 4), vec2(1, status.size.y - 8),
      TrimDark)

## Hero sheets

proc carriedLoot(actor: Actor): array[InventorySlots, int] =
  ## Returns the loot kind (its ord) in each bag slot, or -1.
  for bag in 0 ..< InventorySlots:
    result[bag] = -1
    let index = run.world.itemIndex(actor.inventory[bag])
    if index >= 0:
      result[bag] = run.world.items[index].kind.ord

proc drawGearIcon(sk: Silky, well: GameUiPanel, name: string) =
  ## Draws a piece of worn gear centered in its well.
  let size = min(well.size.x, well.size.y) - 4
  sk.drawSprite(gearKey(name), well.origin + (well.size - vec2(size)) / 2,
    vec2(size))

proc drawSheet(
    sk: Silky,
    window: Window,
    panel: GameUiPanel,
    slot: int,
    selected: bool,
    playerHero: bool,
    renderAlpha: float32
): bool =
  ## Draws one hero's sheet, and returns whether a click on it selects the
  ## hero rather than using one of its items.
  let
    actor = run.world.actors[slot]
    class = actor.heroClass
    parts = panel.sheetPanels()
  sk.drawGoldPanel(panel, selected)
  # Portrait.
  let portrait = parts.portrait
  sk.drawWell(portrait, PlainWell)
  sk.drawSprite(HeroPortraitKeys[class], portrait.origin + vec2(2),
    portrait.size - vec2(4),
    if actor.alive: rgbx(255, 255, 255, 255) else: rgbx(110, 110, 118, 255))
  sk.drawBorder(portrait.origin, portrait.size, 1,
    if selected: TrimSelected else: TrimDark)
  # Name, player and gold.
  let
    name = parts.name
    className = ClassNames[class]
    classWidth = round(sk.getTextSize("Bold", className).x)
  sk.drawLabel(className, name.origin, name.size, Parchment, "Bold")
  var gold = ""
  gold.addAmount(actor.carriedValue.int)
  let goldWidth = round(sk.getTextSize("Small", gold).x)
  if actor.alive:
    sk.drawGlyph("gold", vec2(name.origin.x + name.size.x - goldWidth - 9,
      name.origin.y + name.size.y / 2), 14, Gold)
    sk.drawLabel(gold, name.origin, name.size, Gold, "Small", RightAlign)
  let player =
    if actor.alive: run.config.players[slot].displayName(slot)
    else: "Fallen"
  sk.drawLabel(
    sk.fittedLabel(player, name.size.x - classWidth - goldWidth - 36, "Small"),
    name.origin + vec2(classWidth + 6, 1),
    vec2(name.size.x - classWidth - goldWidth - 24, name.size.y),
    if actor.alive: Muted else: rgbx(220, 90, 80, 255), "Small"
  )
  # Meters.
  sk.drawBar(parts.hp.origin, parts.hp.size, max(actor.hp, 0'i16).float32,
    max(actor.maxHp, 1'i16).float32, healthColor(actor))
  writeRatio(hudScratch, max(actor.hp, 0'i16).int, actor.maxHp.int)
  sk.drawShadowLabel(hudScratch, parts.hp.origin, parts.hp.size,
    rgbx(255, 255, 255, 255), BarFont)
  if actor.maxMana > 0:
    sk.drawBar(parts.mana.origin, parts.mana.size, actor.mana.float32,
      actor.maxMana.float32, rgbx(52, 112, 222, 255))
    writeRatio(hudScratch, actor.mana.int, actor.maxMana.int)
    sk.drawShadowLabel(hudScratch, parts.mana.origin, parts.mana.size,
      rgbx(255, 255, 255, 255), BarFont)
  else:
    # The class draws on no mana: an empty track says so plainly.
    sk.drawBar(parts.mana.origin, parts.mana.size, 0, 1,
      rgbx(52, 112, 222, 255))
    sk.drawLabel("no mana", parts.mana.origin, parts.mana.size,
      rgbx(110, 112, 124, 255), BarFont, CenterAlign)
  # Gear.
  sk.drawLabel("MAIN HAND", parts.mainLabel.origin, parts.mainLabel.size,
    rgbx(206, 192, 160, 255), CaptionFont, CenterAlign)
  sk.drawLabel("OFF HAND", parts.offLabel.origin, parts.offLabel.size,
    rgbx(206, 192, 160, 255), CaptionFont, CenterAlign)
  let
    kinds = actor.carriedLoot
    carried = carriedSlots(kinds)
  var loot: array[EquipSlot, int]
  for equip in EquipSlot:
    loot[equip] = -1
  for bag in 0 ..< InventorySlots:
    if kinds[bag] >= 0:
      loot[carried[bag]] = bag
  result = true
  for equip in EquipSlot:
    let well = parts.gear[equip]
    if loot[equip] >= 0:
      let
        bag = loot[equip]
        ability = LootAbilities[LootKind(kinds[bag])]
      sk.drawWell(well, MagicWell)
      if ability != NoAbility:
        let
          size = min(well.size.x, well.size.y) - 6
          pos = well.origin + (well.size - vec2(size)) / 2
        sk.drawSprite(abilityIconKey(ability), pos, vec2(size))
        # Using an item neither checks nor charges mana, so its listed cost
        # never holds it back: the blue would mark a mana potion unusable
        # just when it is needed.
        sk.drawAbilityState(pos, size, ability, actor, renderAlpha, false)
        sk.drawBorder(pos, vec2(size), 1, WellColors[MagicWell].edge)
      if playerHero:
        if window.hudClicked(sk, well):
          queueUseItem(int32(slot), int32(bag))
          result = false
        elif not window.statsContains(sk.mousePos) and
            window.buttonReleased[MouseRight] and well.contains(sk.mousePos):
          queueDropItem(int32(slot), int32(bag))
    elif ClassGear[class][equip].len > 0:
      sk.drawWell(well, RowTints[equip])
      sk.drawGearIcon(well, ClassGear[class][equip])
    else:
      sk.drawWell(well, PlainWell)
      sk.drawLabel(SlotCaptions[equip], well.origin, well.size,
        rgbx(84, 80, 72, 255), CaptionFont, CenterAlign)
  # Skills.
  for index, well in parts.skills:
    sk.drawSkillIcon(well, HeroAbilities[class][index], actor, renderAlpha)
    if playerHero and well.size.x >= 48:
      sk.drawKeyPip(well, ActionKeys[index])
  if not actor.alive:
    let body = parts.mainLabel.origin.y - 4
    sk.drawRect(vec2(panel.origin.x + 6, body),
      vec2(panel.size.x - 12, panel.origin.y + panel.size.y - 6 - body),
      rgbx(8, 8, 10, 150))

## Frame

proc drawUi*(
    sk: Silky,
    window: Window,
    transport: var Player,
    cameraTarget: Vec3,
    cameraDistance: float32,
    primaryId: var int,
    selectedIds: var array[PartySize, bool],
    followSelection: var bool,
    actionCam: var ActionCam,
    focusPlayerHero: var bool,
    renderAlpha: float32
) =
  ## Draws every Silky HUD panel for the current frame.
  let table = currentStats()
  statsState.syncDirector(actionCam, table, window.tabHeld)
  let
    chrome = currentChrome(window)
    directed = actionCam.enabled and actionCam.locked
    detailSlot =
      if directed and actionCam.director.subject.owner in 0 ..< PartySize:
        int(actionCam.director.subject.owner)
      else:
        primaryId
    shownLevel =
      if directed:
        int(actionCam.director.subject.floor)
      else:
        int(run.viewLevel(selectedIds))
  var picked = 0
  for selected in selectedIds:
    if selected:
      inc picked
  sk.drawPlate(chrome.plate, shownLevel)
  sk.drawMap(window, chrome.map, shownLevel, selectedIds, cameraTarget,
    cameraDistance)
  for slot in 0 ..< PartySize:
    let
      panel = chrome.sheets[slot]
      # Lighting every sheet says nothing, so a whole-party selection
      # highlights none of them.
      selected =
        if directed: slot == detailSlot
        else: selectedIds[slot] and picked < PartySize
      playerHero = options.playerSlot > 0 and not run.replayMode and
        slot == options.playerSlot - 1
      selectable = sk.drawSheet(
        window, panel, slot, selected, playerHero, renderAlpha
      )
    if selectable and window.hudClicked(sk, panel):
      actionCam.takeManual()
      selectHeroSlot(
        primaryId,
        selectedIds,
        followSelection,
        slot,
        window.buttonDown[KeyLeftShift] or
          window.buttonDown[KeyRightShift]
      )
      if playerHero:
        focusPlayerHero = true
  transport.drawTransport(
    sk,
    window,
    chrome.layout.transportPanel,
    actionCam,
    followSelection,
    addr statsState.toggled
  )
  if run.hashCheck.mismatches > 0:
    sk.drawError(
      chrome.layout.size,
      &"REPLAY DIVERGED - {run.hashCheck.mismatches} mismatches, " &
        &"first at tick {run.hashCheck.firstTick}"
    )
  sk.drawDebugMenu(window)
  statsState.syncDirector(actionCam, table, window.tabHeld)

proc drawStatsOverlay*(sk: Silky, window: Window) =
  ## Presents readable statistics above the HUD at every window width.
  sk.drawStatsOverlay(
    window, currentLayout(window), statsState, currentStats(), run.history
  )
