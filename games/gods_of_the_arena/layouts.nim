## Current-frame HUD rectangles, composed from fixed rows and columns.

import
  std/math,
  vmath,
  polyworld/[gameuis, stackpanels],
  content, shopcatalog

const
  PanelScore* = vec2(298, 104)
  PanelHeroes* = vec2(1090, 142)
  PanelClock* = vec2(128, 86)
  PanelMinimap* = vec2(256, 256)
  PanelDetails* = vec2(859, 242)
  PanelInventory* = vec2(252, 243)
  PanelDraft = vec2(1048, 632)
  HeroCardSize = vec2(100, 126)
  HeroGap = 4.0'f
  HeroTeamGap = 34.0'f

proc heroTeamWidth(count: int): float32 =
  ## No cards means no reserved team width or inter-card gaps.
  HeroCardSize.x * count.float32 + HeroGap * max(count - 1, 0).float32

proc heroRibbonSize*(redCount, blueCount: int): Vec2 =
  ## Keeps the original ten-hero dimensions, shrinking to occupied cards.
  vec2(24 + heroTeamWidth(redCount) + HeroTeamGap +
    heroTeamWidth(blueCount), PanelHeroes.y)

type
  ClockPanels* = object
    icon*, caption*, time*: GameUiPanel

  HeroPanels* = object
    portrait*, name*, hp*, mana*: GameUiPanel

  DetailsPanels* = object
    portrait*, name*, class*, stats*: GameUiPanel
    hp*, mana*, xp*: GameUiPanel
    abilities*: array[6, GameUiPanel]

  InventoryPanels* = object
    title*, shop*, contents*, gold*: GameUiPanel
    slots*: array[6, GameUiPanel]

  ShopPanels* = object
    panel*, heading*, catalog*, footer*, tooltipGutter*: GameUiPanel
    groups*: array[ShopGroup, GameUiPanel]
    cards*: array[Item.high.ord, GameUiPanel]
    compact*: bool

  DraftPanels* = object
    panel*, title*, status*, footer*, selection*, role*, confirm*: GameUiPanel
    deadline*: GameUiPanel
    heroes*: array[10, GameUiPanel]

proc draftScale*(size: Vec2): float32 =
  ## Enlarges the picker by half while fitting within the window.
  min(
    1.5'f,
    min((size.x - 48) / PanelDraft.x, (size.y - 48) / PanelDraft.y)
  )

proc draftPanels*(size: Vec2): DraftPanels =
  ## Centers a compact five-column hero grid beneath the current picker.
  const
    Gap = 12.0'f
    CardHeight = 224.0'f
    HeaderHeight = 96.0'f
    FooterHeight = 76.0'f
  let
    width = min(PanelDraft.x, size.x - 48)
    cardWidth = floor((width - Gap * 4) / 5)
    gridWidth = cardWidth * 5 + Gap * 4
    gridHeight = CardHeight * 2 + Gap
  result.panel.size = vec2(
    gridWidth, HeaderHeight + gridHeight + FooterHeight
  )
  result.panel.origin = floor((size - result.panel.size) / 2)
  var rows = result.panel.stack(TopToBottom)
  result.title = rows.takeRow(44, 4)
  result.status = rows.takeRow(28, 4)
  result.deadline = rows.takeRow(8, 8)
  result.deadline.origin.x += floor((result.deadline.size.x - 320) / 2)
  result.deadline.size.x = 320
  let grid = rows.takeRow(gridHeight, 20)
  grid.stackGrid(vec2(cardWidth, CardHeight), 5, vec2(Gap), result.heroes)
  result.footer = rows.takeRest()
  var footer = result.footer.stack(RightToLeft)
  result.confirm = footer.takeColumn(240, 24)
  var selected = footer.takeRest().stack(TopToBottom)
  result.selection = selected.takeRow(30, 2)
  result.role = selected.takeRest()

proc scorePanel*(layout: GameUiLayout,
    heroSize = PanelHeroes): GameUiPanel =
  ## Moves the score below the occupied hero roster on collision.
  let heroes = layout.panel(GameUiRegion.TopCenter, heroSize)
  result = layout.panel(GameUiRegion.TopLeft, PanelScore)
  if result.overlaps(heroes, 48):
    result.origin.y = heroes.origin.y + heroes.size.y + 48

proc inspectionPanel*(layout: GameUiLayout,
    score, heroes: GameUiPanel): GameUiPanel =
  ## Keep inspection on the left, below both top plates; death stays centered.
  GameUiPanel(origin: vec2(score.origin.x,
    max(score.origin.y + score.size.y,
      heroes.origin.y + heroes.size.y) + 12), size: vec2(298, 116))

proc clockPanels*(panel: GameUiPanel): ClockPanels =
  ## Stacks the clock's icon and caption above its centered time.
  var rows = panel.stack(TopToBottom, vec2(4, 12))
  var heading = rows.takeRow(20, 7).stack(LeftToRight)
  heading.gap(12)
  result.icon = heading.take(vec2(22, 20), 4)
  result.caption = heading.take(vec2(72, 20))
  result.time = rows.takeRow(40)

proc heroPanels*(panel: GameUiPanel, redCount = 5,
    blueCount = 5): array[10, HeroPanels] =
  ## Packs occupied cards on either side; array halves retain team identity.
  let counts = [redCount, blueCount]
  var teams = panel.stack(LeftToRight, vec2(12, 5))
  for team in 0 ..< 2:
    var cards = teams.takeColumn(heroTeamWidth(counts[team]),
      HeroTeamGap).stack(LeftToRight)
    for slot in 0 ..< counts[team]:
      var card = cards.take(HeroCardSize, HeroGap).stack(TopToBottom)
      let i = team * 5 + slot
      card.indent = 14
      result[i].portrait = card.take(vec2(72), 3)
      card.indent = 0
      result[i].name = card.takeRow(18)
      result[i].hp = card.takeRow(16, 1)
      result[i].mana = card.takeRow(16)

proc heroVersusPanel*(panel: GameUiPanel, redCount: int): GameUiPanel =
  ## Centers VS in the team divider, even when the teams are unequal.
  GameUiPanel(origin: panel.origin +
    vec2(12 + heroTeamWidth(redCount) + (HeroTeamGap - 26) / 2, 57),
    size: vec2(26, 28))

proc detailsPanels*(panel: GameUiPanel): DetailsPanels =
  ## Gives the portrait, identity, meters, and ability groups their own stacks.
  var rows = panel.stack(TopToBottom, vec2(32, 20))
  rows.gap(12)
  var columns = rows.takeRest().stack(LeftToRight)
  result.portrait = columns.take(vec2(150), 12)
  var identity = columns.takeColumn(96, 10).stack(TopToBottom)
  identity.gap(4)
  result.name = identity.takeRow(28)
  result.class = identity.takeRow(20, 2)
  result.stats = identity.takeRow(54)
  var meters = columns.takeColumn(526).stack(TopToBottom)
  meters.gap(4)
  result.hp = meters.takeRow(28, 10)
  result.mana = meters.takeRow(28, 10)
  result.xp = meters.takeRow(28, 10)
  var groups = meters.takeRow(72).stack(LeftToRight)
  var abilities = groups.takeColumn(72 * 4 + 18 * 3, 22).stack(LeftToRight)
  for i in 0 ..< 4:
    result.abilities[i] = abilities.take(vec2(72), 18)
  var items = groups.takeRest().stack(LeftToRight)
  for i in 4 ..< 6:
    result.abilities[i] = items.take(vec2(72), 18)

proc inventoryPanels*(panel: GameUiPanel): InventoryPanels =
  ## Stacks the clickable title, two inventory rows, and currency footer.
  var rows = panel.stack(TopToBottom, vec2(14, 10))
  var heading = rows.takeRow(28, 12).stack(LeftToRight)
  result.title = heading.takeColumn(112, 4)
  result.shop = heading.takeRest()
  result.contents = rows.takeRow(72 * 2 + 5, 1)
  result.gold = rows.takeRow(31)
  stackGrid(result.contents, vec2(72), 3, vec2(4, 5), result.slots)

proc shopPanels*(size: Vec2): ShopPanels =
  ## Centered icon shop; its right-hand gutter is never a purchase target.
  result.panel.size = min(size - vec2(32), vec2(1200, 744))
  result.panel.origin = floor((size - result.panel.size) / 2)
  result.compact = result.panel.size.x < 1100 or result.panel.size.y < 720
  let at = result.panel.origin + vec2(20)
  let width = result.panel.size.x - 40
  result.heading = GameUiPanel(origin: at, size: vec2(width, 48))
  result.catalog = GameUiPanel(origin: at + vec2(0, 60),
    size: vec2(width - 400, result.panel.size.y - 220))
  result.tooltipGutter = GameUiPanel(
    origin: vec2(result.catalog.origin.x + result.catalog.size.x + 12,
      result.catalog.origin.y),
    size: vec2(388, result.catalog.size.y))
  result.footer = GameUiPanel(origin: at + vec2(0, result.panel.size.y - 144),
    size: vec2(width, 104))
  # Four small functional groups across the top; equipment and utility below.
  # The equipment group wraps left-to-right before advancing to its next row.
  let cell = vec2(80, 96)
  let pitch = vec2(88, 102)
  let topWidth = result.catalog.size.x / 4
  for group in ShopHealing..ShopRanged:
    result.groups[group] = GameUiPanel(
      origin: result.catalog.origin + vec2(group.ord.float32 * topWidth, 0),
      size: vec2(topWidth - 8, 24))
  result.groups[ShopEquipment] = GameUiPanel(
    origin: result.catalog.origin + vec2(0, 136),
    size: vec2(result.catalog.size.x - 184, 24))
  result.groups[ShopUtility] = GameUiPanel(
    origin: result.catalog.origin + vec2(result.catalog.size.x - 176, 136),
    size: vec2(176, 24))
  var counts: array[ShopGroup, int]
  for i, item in sortedShopItems():
    let group = item.shopGroup
    let columns = if group == ShopEquipment:
        max(1, int(result.groups[group].size.x / pitch.x))
      else: 2
    let n = counts[group]
    result.cards[i] = GameUiPanel(origin: result.groups[group].origin +
      vec2((n mod columns).float32 * pitch.x,
        26 + (n div columns).float32 * pitch.y), size: cell)
    inc counts[group]
