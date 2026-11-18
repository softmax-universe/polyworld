## Current-frame HUD rectangles, composed from fixed rows and columns.
##
## Two columns frame the dungeon: the level plate over the Warrior's and
## the Mage's sheets on the left, the map over the Ranger's and the Druid's
## on the right. A sheet shrinks its wells to fit a short window; its text
## keeps its size.

import
  vmath,
  polyworld/[gameuis, stackpanels],
  gear

const
  ColumnWidth* = 312.0'f32
  ColumnGap* = 8.0'f32
  PanelPlate* = vec2(ColumnWidth, 146)
  PanelMap* = vec2(ColumnWidth, 146)
  SheetPad = 10.0'f32
  SheetLabel = 13.0'f32
    ## The MAIN HAND and OFF HAND captions.
  SheetHeader = 60.0'f32
  SheetGap = 7.0'f32
  GearRows = [76.0'f32, 50, 42]
    ## Heights of the three rows of equipment wells.
  SkillRow = 64.0'f32
  SheetFixed = SheetPad * 2 + SheetLabel
  SheetScaled = SheetHeader + GearRows[0] + GearRows[1] + GearRows[2] +
    SkillRow + SheetGap * 4
  SheetHeight* = SheetFixed + SheetScaled
    ## A sheet at full size.
  MinSheetScale = 0.6'f32

type
  PlatePanels* = object
    icon*, title*, progress*: GameUiPanel
    questIcon*, quest*: GameUiPanel
    status*: GameUiPanel

  SheetPanels* = object
    sheet*, portrait*, name*, hp*, mana*: GameUiPanel
    mainLabel*, offLabel*: GameUiPanel
    gear*: array[EquipSlot, GameUiPanel]
    skills*: array[4, GameUiPanel]

proc sheetHeight*(layout: GameUiLayout): float32 =
  ## Returns how tall each sheet can be so two fit under a top panel.
  let room = (layout.gameAreaSize.y - layout.margin * 2 - PanelPlate.y -
    ColumnGap * 2) / 2
  clamp(room, SheetFixed + SheetScaled * MinSheetScale, SheetHeight)

proc spread(
    row: GameUiPanel,
    widths: openArray[float32]
): seq[GameUiPanel] =
  ## Places wells of these widths across a row, the spare width shared out
  ## evenly between them.
  var total = 0'f32
  for width in widths:
    total += width
  let gap =
    if widths.len > 1: max(row.size.x - total, 0) / float32(widths.len - 1)
    else: 0
  var x = row.origin.x
  for width in widths:
    result.add GameUiPanel(
      origin: vec2(round(x), row.origin.y),
      size: vec2(width, row.size.y)
    )
    x += width + gap

proc platePanels*(panel: GameUiPanel): PlatePanels =
  ## Stacks the level title, the quest, and the status line.
  var rows = panel.stack(TopToBottom, vec2(14, 12))
  var title = rows.takeRow(46, 9).stack(LeftToRight)
  result.icon = title.take(vec2(36, 46), 10)
  var right = title.takeRest().stack(RightToLeft)
  result.progress = right.take(vec2(56, 30), 8)
  result.progress.origin.y += 8
  result.title = right.takeRest()
  var quest = rows.takeRow(30, 9).stack(LeftToRight)
  result.questIcon = quest.take(vec2(24, 30), 10)
  result.quest = quest.takeRest()
  result.status = rows.takeRow(24)

proc sheetPanels*(panel: GameUiPanel): SheetPanels =
  ## Lays out one hero sheet: portrait and meters, three rows of equipment,
  ## then the four skills, all shrunk alike when the sheet is short.
  let k = clamp(
    (panel.size.y - SheetFixed) / SheetScaled, MinSheetScale, 1
  )
  result.sheet = panel
  var rows = panel.stack(TopToBottom, vec2(SheetPad))
  let
    header = rows.takeRow(round(SheetHeader * k), round(SheetGap * k))
    portrait = round(SheetHeader * k)
  var columns = header.stack(LeftToRight)
  result.portrait = columns.take(vec2(portrait), 10)
  var info = columns.takeRest().stack(TopToBottom)
  let bar = round(18 * k)
  info.gap(max(header.size.y - 20 - bar * 2 - 4, 0) / 2)
  result.name = info.takeRow(20)
  result.hp = info.takeRow(bar, 4)
  result.mana = info.takeRow(bar)
  let labels = rows.takeRow(SheetLabel)
  var gearRows: array[3, GameUiPanel]
  for i, height in GearRows:
    gearRows[i] = rows.takeRow(round(height * k), round(SheetGap * k))
  let skillRow = rows.takeRow(round(SkillRow * k))
  let
    first = gearRows[0].spread([round(78 * k), round(84 * k), round(78 * k)])
    second = gearRows[1].spread([round(80 * k), round(80 * k), round(80 * k)])
    third = gearRows[2].spread(
      [round(76 * k), round(58 * k), round(58 * k), round(58 * k)])
  for slot in MainHandSlot .. OffHandSlot:
    result.gear[slot] = first[slot.ord]
  for slot in HelmetSlot .. BootsSlot:
    result.gear[slot] = second[slot.ord - HelmetSlot.ord]
  for slot in BeltSlot .. SecondRingSlot:
    result.gear[slot] = third[slot.ord - BeltSlot.ord]
  result.mainLabel = GameUiPanel(
    origin: vec2(first[0].origin.x - 8, labels.origin.y),
    size: vec2(first[0].size.x + 16, labels.size.y)
  )
  result.offLabel = GameUiPanel(
    origin: vec2(first[2].origin.x - 8, labels.origin.y),
    size: vec2(first[2].size.x + 16, labels.size.y)
  )
  let skill = round(SkillRow * k)
  for i, well in skillRow.spread([skill, skill, skill, skill]):
    result.skills[i] = well
