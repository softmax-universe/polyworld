import
  std/[strutils, times, unicode],
  bumpy, chroma, pixie, silky, vmath,
  polyworld/gameuis,
  common, resources

when defined(silkyTesting):
  import silky/testwindow
else:
  import windy

const
  InputLimit = 2000
  Ink = rgbx(255, 255, 255, 255)
  Panel = rgbx(0, 0, 0, 160)
  Line = rgbx(55, 55, 55, 55)

type
  ChatUi* = object
    scale*: float32 = 1
    typing*: bool
    input*: string
    scroll*: float32
    focusRequested*: bool
    cursor: int
    selected: bool
    inputScroll: float32
    messageCount: int
    historyWidth, historyTotal: float32
    historyLines: seq[seq[string]]
    historyHeights: seq[float32]
    localError: string
  ChatLayout = object
    panel, history, input, send, focus, stats, village: GameUiPanel

proc initChatUi*(): ChatUi {.raises: [].} =
  ## Begins with the creature's conversation ready for typing.
  ChatUi(scale: 1, typing: true)

proc restoreInput*(ui: var ChatUi, text: string) =
  ## Restores an unsent message with its caret ready for a retry.
  ui.input = text
  ui.cursor = text.len
  ui.typing = true
  ui.selected = false
  ui.localError.setLen(0)

proc drawLabel(
  sk: Silky,
  text: string,
  origin, size: Vec2,
  tint: ColorRGBX,
  font = "Hud",
  align = LeftAlign
) =
  ## Places a clipped label within an explicit UI rectangle.
  discard sk.drawText(
    font, text, origin, tint,
    maxWidth = size.x, maxHeight = size.y,
    hAlign = align, vAlign = MiddleAlign
  )

proc layout(size: Vec2): ChatLayout {.raises: [].} =
  ## Keeps the conversation centered with clear space above for the creature.
  let
    width = min(760'f, max(280'f, size.x - 32))
    height = min(310'f, max(220'f, size.y * 0.35'f))
    origin = vec2((size.x - width) / 2, max(140'f, size.y - height - 20))
  result.panel = GameUiPanel(origin: origin, size: vec2(width, height))
  result.history = GameUiPanel(
    origin: origin + vec2(24, 18),
    size: vec2(width - 48, height - 98)
  )
  result.input = GameUiPanel(
    origin: origin + vec2(18, height - 66),
    size: vec2(width - 126, 44)
  )
  result.send = GameUiPanel(
    origin: origin + vec2(width - 96, height - 66),
    size: vec2(78, 44)
  )
  result.stats = GameUiPanel(
    origin: vec2(size.x - 320, 20), size: vec2(300, 126)
  )
  result.focus = GameUiPanel(
    origin: vec2(size.x - 172, 158), size: vec2(152, 30)
  )
  if size.x >= 960 and result.panel.origin.y >= 430:
    result.village = GameUiPanel(origin: vec2(20, 20), size: vec2(286, 390))

proc mouseOverUi*(ui: ChatUi, window: Window): bool =
  ## Prevents camera gestures from stealing conversation and button input.
  let
    scale = max(0.1'f, ui.scale)
    boxes = layout(window.size.vec2 / scale)
    mouse = window.mousePos.vec2 / scale
  boxes.panel.contains(mouse) or boxes.focus.contains(mouse) or
    boxes.stats.contains(mouse) or boxes.village.contains(mouse)

proc previousRune(text: string, cursor: int): int {.raises: [].} =
  ## Moves to the previous UTF-8 boundary without cutting a character.
  result = max(0, cursor - 1)
  while result > 0 and (ord(text[result]) and 0xc0) == 0x80:
    dec result

proc nextRune(text: string, cursor: int): int {.raises: [].} =
  ## Moves to the next UTF-8 boundary in the input field.
  result = min(text.len, cursor + 1)
  while result < text.len and (ord(text[result]) and 0xc0) == 0x80:
    inc result

proc printable(rune: Rune): bool {.raises: [].} =
  ## Excludes controls and directional overrides from the single-line input.
  let value = rune.int
  value >= 32 and value <= 0x10ffff and value notin 0x7f .. 0x9f and
    value notin 0xd800 .. 0xdfff and value notin 0xfdd0 .. 0xfdef and
    (value and 0xffff) notin [0xfffe, 0xffff] and
    value notin 0x202a .. 0x202e and value notin 0x2066 .. 0x2069

proc insert(ui: var ChatUi, text: string) =
  ## Inserts bounded text at the caret and preserves UTF-8 boundaries.
  if text.validateUtf8() != -1:
    ui.localError = "That text is not valid UTF-8."
    return
  var cleaned: string
  for rune in text.runes:
    if rune.int in [9, 10, 13]:
      cleaned.add ' '
    elif rune.printable():
      cleaned.add rune.toUTF8()
  let retained = if ui.selected: 0 else: ui.input.len
  if retained + cleaned.len > InputLimit:
    ui.localError = "Please keep each message under 2,000 bytes."
    return
  if ui.selected:
    ui.input.setLen(0)
    ui.cursor = 0
    ui.selected = false
  ui.cursor = clamp(ui.cursor, 0, ui.input.len)
  ui.input = ui.input[0 ..< ui.cursor] & cleaned &
    ui.input[ui.cursor ..< ui.input.len]
  ui.cursor += cleaned.len
  ui.localError.setLen(0)

proc installInput*(window: Window, ui: ptr ChatUi) =
  ## Routes native committed text to Monster while preserving other handlers.
  let
    previousText = window.onTextInput
    previous = window.onRune
  window.onTextInput = proc(text: string) =
    ## Receives native typing, composed text, and platform paste events.
    if ui[].typing:
      ui[].insert(text)
    elif previousText != nil:
      previousText(text)
  window.onRune = proc(rune: Rune) =
    ## Receives legacy rune events on platforms without committed text.
    if ui[].typing:
      ui[].insert(rune.toUTF8())
    elif previous != nil:
      previous(rune)
  window.runeInputEnabled = ui[].typing

proc syncInput*(window: Window, ui: ChatUi) =
  ## Restores Monster's focus after Silky finishes its own input frame.
  window.runeInputEnabled = ui.typing

proc textLines(
  sk: Silky,
  text: string,
  width: float32,
  font: string
): seq[string] =
  ## Wraps transcript text using actual font widths and safe rune boundaries.
  for paragraph in text.splitLines():
    var line: string
    for word in strutils.splitWhitespace(paragraph):
      let candidate = if line.len == 0: word else: line & " " & word
      if sk.getTextSize(font, candidate).x <= width:
        line = candidate
        continue
      if line.len > 0:
        result.add line
        line.setLen(0)
      for rune in word.runes:
        let value = rune.toUTF8()
        if line.len > 0 and sk.getTextSize(font, line & value).x > width:
          result.add line
          line.setLen(0)
        line.add value
    result.add line
  if result.len == 0:
    result.add ""

proc outline(sk: Silky, panel: GameUiPanel, tint = Line) =
  ## Draws only the edges so the interior retains its transparency.
  sk.drawRect(panel.origin, vec2(panel.size.x, 1), tint)
  sk.drawRect(panel.origin + vec2(0, panel.size.y - 1),
    vec2(panel.size.x, 1), tint)
  sk.drawRect(panel.origin + vec2(0, 1),
    vec2(1, panel.size.y - 2), tint)
  sk.drawRect(panel.origin + vec2(panel.size.x - 1, 1),
    vec2(1, panel.size.y - 2), tint)

proc plate(sk: Silky, panel: GameUiPanel, fill = Panel) =
  ## Draws a translucent black plate with a fine neutral outline.
  sk.drawRect(panel.origin, panel.size, fill)
  sk.outline(panel)

proc button(
  sk: Silky,
  window: Window,
  panel: GameUiPanel,
  text: string,
  enabled = true,
  accent = false
): bool =
  ## Draws and activates one explicit panel button.
  let over = panel.contains(window.mousePos.vec2 / sk.uiScale)
  sk.drawRect(
    panel.origin,
    panel.size,
    if not enabled: rgbx(0, 0, 0, 80)
    elif over: rgbx(0, 0, 0, 200)
    else: Panel
  )
  sk.outline(panel,
    if enabled and accent: rgbx(150, 150, 150, 150) else: Line)
  sk.drawLabel(
    text, panel.origin, panel.size, Ink, "Hud", CenterAlign
  )
  enabled and over and window.buttonPressed[MouseLeft]

proc keyboard(ui: var ChatUi, window: Window): bool =
  ## Applies focus, editing, clipboard shortcuts, and message submission.
  if window.buttonPressed[KeyEscape]:
    ui.typing = not ui.typing
    ui.selected = false
  if window.buttonPressed[KeyEnter]:
    if ui.typing:
      result = true
    else:
      ui.typing = true
      ui.cursor = ui.input.len
  if not ui.typing:
    return
  let command = window.buttonDown[KeyLeftControl] or
    window.buttonDown[KeyRightControl] or
    window.buttonDown[KeyLeftSuper] or window.buttonDown[KeyRightSuper]
  if command and window.buttonPressed[KeyA]:
    ui.selected = true
  if command and window.buttonPressed[KeyC] and ui.selected:
    setClipboardString(ui.input)
  if command and window.buttonPressed[KeyX] and ui.selected:
    setClipboardString(ui.input)
    ui.input.setLen(0)
    ui.cursor = 0
    ui.selected = false
  if command and window.buttonPressed[KeyV]:
    ui.insert(getClipboardString())
  if window.buttonPressed[KeyBackspace]:
    if ui.selected:
      ui.input.setLen(0)
      ui.cursor = 0
      ui.selected = false
    elif ui.cursor > 0:
      let previous = previousRune(ui.input, ui.cursor)
      ui.input = ui.input[0 ..< previous] &
        ui.input[ui.cursor ..< ui.input.len]
      ui.cursor = previous
  if window.buttonPressed[KeyDelete]:
    if ui.selected:
      ui.input.setLen(0)
      ui.cursor = 0
      ui.selected = false
    elif ui.cursor < ui.input.len:
      let next = nextRune(ui.input, ui.cursor)
      ui.input = ui.input[0 ..< ui.cursor] &
        ui.input[next ..< ui.input.len]
  if window.buttonPressed[KeyLeft]:
    ui.cursor = previousRune(ui.input, ui.cursor)
    ui.selected = false
  if window.buttonPressed[KeyRight]:
    ui.cursor = nextRune(ui.input, ui.cursor)
    ui.selected = false
  if window.buttonPressed[KeyHome]:
    ui.cursor = 0
    ui.selected = false
  if window.buttonPressed[KeyEnd]:
    ui.cursor = ui.input.len
    ui.selected = false

proc drawInput(sk: Silky, panel: GameUiPanel, ui: var ChatUi) =
  ## Keeps the caret visible while clipping long text to the editor bounds.
  sk.drawRect(panel.origin, panel.size, rgbx(0, 0, 0, 80))
  sk.outline(panel, if ui.typing: Ink else: Line)
  let
    origin = panel.origin + vec2(12, 12)
    width = panel.size.x - 24
    caret = sk.getTextSize("Default", ui.input[0 ..< ui.cursor]).x
  ui.inputScroll = max(0'f, min(ui.inputScroll, caret))
  if caret - ui.inputScroll > width - 4:
    ui.inputScroll = caret - width + 4
  sk.pushClipRect(rect(origin - vec2(0, 3), vec2(width, 29)))
  if ui.selected and ui.input.len > 0:
    sk.drawRect(
      origin - vec2(ui.inputScroll, 2),
      vec2(sk.getTextSize("Default", ui.input).x, 25),
      rgbx(55, 55, 55, 55)
    )
  if ui.input.len == 0:
    discard sk.drawText(
      "Default", "Tell me where to go, or teach me something...",
      origin, Ink, maxWidth = width, maxHeight = 28
    )
  else:
    discard sk.drawText(
      "Default", ui.input, origin - vec2(ui.inputScroll, 0), Ink,
      clip = false
    )
  if ui.typing and (epochTime() * 2).int mod 2 == 0:
    sk.drawRect(origin + vec2(caret - ui.inputScroll, 0), vec2(1, 20), Ink)
  sk.popClipRect()

proc drawHistory(
  sk: Silky,
  window: Window,
  panel: GameUiPanel,
  ui: var ChatUi,
  messages: openArray[Message]
) =
  ## Draws a scrollable transcript with different voices and real outcomes.
  if messages.len != ui.messageCount or panel.size.x != ui.historyWidth:
    if messages.len != ui.messageCount:
      ui.scroll = 0
    ui.messageCount = messages.len
    ui.historyWidth = panel.size.x
    ui.historyTotal = 0
    ui.historyLines.setLen(0)
    ui.historyHeights.setLen(0)
    for message in messages:
      if message.role == FeedbackMessage:
        ui.historyLines.add newSeq[string]()
        ui.historyHeights.add 0'f
        continue
      let
        font = if message.role == EventMessage: "Hud" else: "Default"
        wrapped = sk.textLines(message.text, panel.size.x - 18, font)
        height = wrapped.len.float32 * 22 +
          (if message.role == EventMessage: 8'f else: 28'f)
      ui.historyLines.add wrapped
      ui.historyHeights.add height
      ui.historyTotal += height
  let total = ui.historyTotal
  if panel.contains(window.mousePos.vec2 / sk.uiScale):
    ui.scroll += window.scrollDelta.y * 2 / sk.uiScale
  ui.scroll = clamp(ui.scroll, 0'f, max(0'f, total - panel.size.y))
  var y = panel.origin.y + min(0'f, panel.size.y - total) + ui.scroll
  sk.pushClipRect(rect(panel.origin, panel.size))
  if messages.len == 0:
    discard sk.drawText(
      "Default", "A small creature. A world to discover. Your voice to guide it.",
      panel.origin + vec2(0, 12), Ink,
      maxWidth = panel.size.x - 12, maxHeight = 60, wordWrap = true
    )
    discard sk.drawText(
      "Hud", "Try: Walk to the village.  Or: Gather wild berries for the villagers.",
      panel.origin + vec2(0, 68), Ink,
      maxWidth = panel.size.x - 12, maxHeight = 50, wordWrap = true
    )
  for i, message in messages:
    if message.role == FeedbackMessage:
      continue
    if y + ui.historyHeights[i] >= panel.origin.y and
      y < panel.origin.y + panel.size.y:
        let font = if message.role == EventMessage: "Hud" else: "Default"
        if message.role != EventMessage:
          discard sk.drawText(
            "Small", if message.role == PlayerMessage: "YOU" else: "CREATURE",
            vec2(panel.origin.x, y), Ink
          )
        let top = y + (if message.role == EventMessage: 0'f else: 19'f)
        for j, line in ui.historyLines[i]:
          discard sk.drawText(
            font, line, vec2(panel.origin.x, top + j.float32 * 22),
            Ink,
            clip = false
          )
    y += ui.historyHeights[i]
  sk.popClipRect()
  if total > panel.size.y:
    let
      thumb = max(16'f, panel.size.y * panel.size.y / total)
      fraction = 1 - ui.scroll / max(1'f, total - panel.size.y)
    sk.drawRect(
      panel.origin + vec2(panel.size.x - 3, fraction * (panel.size.y - thumb)),
      vec2(2, thumb), rgbx(160, 160, 160, 160)
    )

proc drawVillage(sk: Silky, panel: GameUiPanel, world: World) =
  ## Shows communal supplies, household needs, and residents' current work.
  if panel.size.x <= 0:
    return
  sk.plate(panel)
  let origin = panel.origin + vec2(14, 10)
  sk.drawLabel("VILLAGE HALL", origin, vec2(258, 18), Ink, "Small")
  let supplies = [
    "Berries " & $world.stock[BerriesResource] & "   Grain " &
      $world.stock[GrainResource] & "   Fish " & $world.stock[FishResource],
    "Pine " & $world.stock[SoftwoodResource] & "   Oak " &
      $world.stock[HardwoodResource] & "   Stone " & $world.stock[StoneResource]
  ]
  for i, text in supplies:
    sk.drawLabel(text, origin + vec2(0, (25 + i * 22).float32),
      vec2(258, 20), Ink, "Small")
  var y = 80'f
  for household in world.households:
    sk.drawLabel(household.name, origin + vec2(0, y),
      vec2(258, 18), Ink, "Small")
    sk.drawLabel("Food " & $household.stock.foodTotal() &
      "   Warmth " & $int(household.fuel) & "%   Home " &
      $int(household.integrity) & "%", origin + vec2(0, y + 18),
      vec2(258, 18), Ink, "Small")
    y += 42
  y += 8
  for villager in world.villagers:
    sk.drawLabel(villager.name & ": " & villager.activity,
      origin + vec2(0, y), vec2(258, 20), Ink, "Small")
    y += 23

proc drawUi*(
  sk: Silky,
  window: Window,
  world: World,
  ui: var ChatUi,
  messages: openArray[Message],
  pending: bool,
  available: bool,
  failure: string
): string =
  ## Draws the creature's conversation and returns a newly submitted message.
  let
    size = window.size.vec2 / sk.uiScale
    boxes = layout(size)
  ui.cursor = clamp(ui.cursor, 0, ui.input.len)
  var submit = ui.keyboard(window)
  if window.buttonPressed[MouseLeft] and
    boxes.input.contains(window.mousePos.vec2 / sk.uiScale):
      ui.typing = true
      ui.cursor = ui.input.len
      ui.selected = false
  let stats = boxes.stats
  sk.plate(stats)
  sk.drawLabel("YOUR CREATURE", stats.origin + vec2(16, 10),
    vec2(268, 18), Ink, "Small")
  sk.drawLabel("Energy " & $int(world.creature.energy) & "%",
    stats.origin + vec2(16, 31), vec2(128, 24), Ink)
  sk.drawLabel("Carrying " & $world.creature.cargo.total() & "/6",
    stats.origin + vec2(151, 31), vec2(133, 24), Ink)
  sk.drawLabel(world.creature.cargo.inventoryText(),
    stats.origin + vec2(16, 61), vec2(268, 20), Ink, "Small")
  sk.drawLabel(world.status,
    stats.origin + vec2(16, 91), vec2(268, 20), Ink, "Small")
  sk.drawVillage(boxes.village, world)
  if sk.button(window, boxes.focus, "Find my creature"):
    ui.focusRequested = true
  sk.plate(boxes.panel)
  sk.drawHistory(window, boxes.history, ui, messages)
  sk.drawInput(boxes.input, ui)
  submit = sk.button(window, boxes.send, "Send",
    available and not pending, accent = true) or submit
  if submit and ui.input.strip().len > 0:
    if not available:
      ui.localError = "Connect the creature before sending a message."
    elif pending:
      ui.localError = "Your creature is still thinking. Your next message is ready."
    else:
      result = ui.input.strip()
      ui.input.setLen(0)
      ui.cursor = 0
      ui.selected = false
      ui.scroll = 0
      ui.inputScroll = 0
      ui.localError.setLen(0)
      ui.typing = true
  let error = if failure.len > 0: failure else: ui.localError
  if error.len > 0:
    let box = GameUiPanel(
      origin: boxes.panel.origin - vec2(0, 62),
      size: vec2(boxes.panel.size.x, 52)
    )
    sk.plate(box, rgbx(0, 0, 0, 190))
    discard sk.drawText("Hud", error, box.origin + vec2(14, 9), Ink,
      maxWidth = box.size.x - 28, maxHeight = 36, wordWrap = true)
