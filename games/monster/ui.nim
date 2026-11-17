import
  std/[strutils, times, unicode],
  bumpy, chroma, pixie, silky, vmath,
  polyworld/[gameuis, rtscameras],
  common, minimaps, hudlayouts, hudassets, selections

export hudlayouts

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
    selection*: Selection
    scale*: float32 = 1
    typing*: bool
    input*: string
    scroll*: float32
    focusRequested*: bool
    minimapPanning*: bool
    voiceEnabled*, voiceConnected*, voiceConnecting*: bool
    voiceListening*, voiceSpeaking*, voiceMuted*: bool
    voiceStatus*, voiceError*: string
    voiceToggleRequested*, voiceMuteRequested*, voiceReconnectRequested*: bool
    cursor: int
    selected: bool
    inputScroll: float32
    messageCount: int
    historyWidth, historyTotal: float32
    historyLines: seq[seq[string]]
    historyHeights: seq[float32]
    localError: string
    historyFrame*: FrameState
    utilityFrame*: FrameState
    utilitySelection: Selection

proc initChatUi*(): ChatUi {.raises: [].} =
  ## Begins with the creature's conversation ready for typing.
  ChatUi(scale: 1, typing: true, historyFrame: FrameState(),
    utilityFrame: FrameState())

proc select*(ui: var ChatUi, world: World, picked: Selection): bool =
  ## Inspects a picked entity without issuing orders or changing the draft.
  if picked.kind == NoSelection:
    return false
  let selected = world.resolveSelection(picked)
  if selected != ui.selection:
    ui.utilityFrame = FrameState()
    ui.utilitySelection = selected
  ui.selection = selected
  true

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
  when defined(silkyTesting):
    sk.beginWidget("label", text = text,
      rect = rect(origin.x, origin.y, size.x, size.y))
  discard sk.drawText(
    font, text, origin, tint,
    maxWidth = size.x, maxHeight = size.y,
    hAlign = align, vAlign = MiddleAlign
  )
  when defined(silkyTesting):
    sk.endWidget()

proc mouseOverUi*(ui: ChatUi, window: Window): bool =
  ## Reserves the panels and an active minimap drag from world gestures.
  let
    scale = max(0.1'f, ui.scale)
    boxes = chatLayout(window.size.vec2 / scale)
    mouse = window.mousePos.vec2 / scale
  ui.minimapPanning or
    (not ui.historyFrame.isNil and ui.historyFrame.scrollingY) or
    (not ui.utilityFrame.isNil and ui.utilityFrame.scrollingY) or
    boxes.frame.contains(mouse)

proc updateMinimapCamera*(
  ui: var ChatUi,
  window: Window,
  world: World,
  cameraTarget: var Vec3,
  following: var bool
) =
  ## Navigates the map by dragging, or follows Moss when its icon is clicked.
  let
    scale = max(0.1'f, ui.scale)
    panel = chatLayout(window.size.vec2 / scale).minimap
    area = panel.minimapArea()
    mouse = window.mousePos.vec2 / scale
  if window.buttonPressed[MouseLeft] and area.contains(mouse):
    if creatureHit(mouse, panel, world):
      ui.minimapPanning = false
      discard ui.select(world, Selection())
      ui.focusRequested = true
    else:
      ui.minimapPanning = true
      following = false
  if not window.buttonDown[MouseLeft]:
    ui.minimapPanning = false
  if ui.minimapPanning:
    let point = minimapWorldPoint(mouse, area.origin, area.size, MapHalf)
    cameraTarget = vec3(point.x, 0, point.y)

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
  enabled = true
): bool =
  ## Activates the carved button without painting over its illustrated rim.
  let
    hit = GameUiPanel(origin: panel.origin - vec2(8, 7),
      size: panel.size + vec2(16, 14))
    over = hit.contains(window.mousePos.vec2 / sk.uiScale)
    font = if panel.size.y >= 17: "Hud" else: "Small"
  if over and enabled:
    sk.drawRect(panel.origin, panel.size, rgbx(110, 91, 51, 90))
  sk.drawLabel(text, panel.origin, panel.size, Ink, font, CenterAlign)
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
  ## Keeps editable text and its caret inside the artwork's narrow input well.
  let
    font = if panel.size.y >= 17: "Hud" else: "Small"
    origin = panel.origin + vec2(3, 0)
    width = max(1'f, panel.size.x - 6)
    caret = sk.getTextSize(font, ui.input[0 ..< ui.cursor]).x
  ui.inputScroll = max(0'f, min(ui.inputScroll, caret))
  if caret - ui.inputScroll > width - 4:
    ui.inputScroll = caret - width + 4
  sk.pushClipRect(rect(origin, vec2(width, panel.size.y)))
  if ui.selected and ui.input.len > 0:
    sk.drawRect(origin - vec2(ui.inputScroll, 0),
      vec2(sk.getTextSize(font, ui.input).x, panel.size.y),
      rgbx(85, 107, 137, 150))
  let value = if ui.input.len == 0: "Talk to Moss..." else: ui.input
  discard sk.drawText(font, value,
    origin - vec2(ui.inputScroll, 0), Ink,
    maxWidth = max(width, sk.getTextSize(font, value).x),
    maxHeight = panel.size.y, clip = false, vAlign = MiddleAlign)
  if ui.typing and (epochTime() * 2).int mod 2 == 0:
    sk.drawRect(origin + vec2(caret - ui.inputScroll, 1),
      vec2(1, max(1'f, panel.size.y - 2)), Ink)
  sk.popClipRect()

proc drawHistory(
  sk: Silky,
  window: Window,
  panel, scrollbar: GameUiPanel,
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
        text =
          case message.role
          of PlayerMessage: "You: " & message.text
          of CreatureMessage: "Moss: " & message.text
          else: message.text
        wrapped = sk.textLines(text, panel.size.x - 4, font)
        height = wrapped.len.float32 * 22 + 8
      ui.historyLines.add wrapped
      ui.historyHeights.add height
      ui.historyTotal += height
  let
    total = ui.historyTotal
    frameRect = rect(panel.origin,
      vec2(scrollbar.origin.x + scrollbar.size.x - panel.origin.x,
        panel.size.y))
  if ui.historyFrame.isNil:
    ui.historyFrame = FrameState()
  ui.historyFrame.scrollPos = vec2(0, ui.scroll)
  sk.frameScrollbars(window, ui.historyFrame, frameRect,
    vec2(frameRect.w, total), vec2(1, -1))
  ui.scroll = ui.historyFrame.scrollPos.y
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
        let top = y
        for j, line in ui.historyLines[i]:
          discard sk.drawText(
            font, line, vec2(panel.origin.x, top + j.float32 * 22),
            Ink,
            clip = false
          )
    y += ui.historyHeights[i]
  sk.popClipRect()

proc voiceButton(
  sk: Silky,
  window: Window,
  panel: GameUiPanel,
  text: string,
  enabled = true
): bool =
  ## Reserves an exact voice-control hit area without overlapping the input.
  let over = panel.contains(window.mousePos.vec2 / sk.uiScale)
  sk.plate(panel,
    if over and enabled: rgbx(110, 91, 51, 130)
    else: rgbx(0, 0, 0, 150))
  sk.drawLabel(text, panel.origin, panel.size, Ink, "Hud", CenterAlign)
  enabled and over and window.buttonPressed[MouseLeft]

proc drawVoice(
  sk: Silky,
  window: Window,
  ui: var ChatUi,
  history: var GameUiPanel
) =
  ## Places voice controls beneath the transcript while keeping its draft intact.
  if not ui.voiceEnabled:
    return
  let
    height = min(30'f, history.size.y)
    origin = history.origin + vec2(0, history.size.y - height)
    talk = GameUiPanel(origin: origin, size: vec2(66, height))
    mute = GameUiPanel(origin: origin + vec2(72, 0), size: vec2(88, height))
  history.size.y = max(0'f, history.size.y - height - 6)
  if sk.voiceButton(window, talk,
    if ui.voiceListening: "Finish" else: "Talk",
    ui.voiceConnected or ui.voiceListening):
      ui.voiceToggleRequested = true
  if sk.voiceButton(window, mute,
    if ui.voiceMuted: "Voice off" else: "Voice on"):
      ui.voiceMuteRequested = true
  var statusX = 168'f
  if not ui.voiceConnected and not ui.voiceConnecting:
    let retry = GameUiPanel(origin: origin + vec2(statusX, 0),
      size: vec2(58, height))
    if sk.voiceButton(window, retry, "Retry"):
      ui.voiceReconnectRequested = true
    statusX += 66
  let status =
    if ui.voiceStatus.len > 0: ui.voiceStatus
    elif ui.voiceConnecting: "Connecting voice..."
    elif ui.voiceListening: "Listening..."
    elif ui.voiceSpeaking: "Moss is speaking..."
    elif ui.voiceConnected: "Ready"
    else: "Voice disconnected"
  sk.drawLabel(status, origin + vec2(statusX, 0),
    vec2(max(0'f, history.size.x - statusX), height), Ink)

proc drawUi*(
  sk: Silky,
  window: Window,
  world: World,
  ui: var ChatUi,
  messages: openArray[Message],
  pending: bool,
  available: bool,
  failure: string,
  cameraTarget = vec3(0),
  cameraDistance = 34'f,
  following = true
): string =
  ## Draws the creature's conversation and returns a newly submitted message.
  let
    size = window.size.vec2 / sk.uiScale
    boxes = chatLayout(size)
  ui.cursor = clamp(ui.cursor, 0, ui.input.len)
  var submit = ui.keyboard(window)
  let inputHit = GameUiPanel(origin: boxes.input.origin - vec2(6, 7),
    size: boxes.input.size + vec2(12, 14))
  if window.buttonPressed[MouseLeft] and
    inputHit.contains(window.mousePos.vec2 / sk.uiScale):
      ui.typing = true
      ui.cursor = ui.input.len
      ui.selected = false
  sk.drawRect(boxes.frame.origin + vec2(460, 110) * boxes.artScale,
    vec2(1115, 545) * boxes.artScale, rgbx(0, 0, 0, 205))
  sk.drawRect(boxes.frame.origin + vec2(1575, 160) * boxes.artScale,
    vec2(435, 480) * boxes.artScale, rgbx(0, 0, 0, 205))
  sk.drawMinimap(boxes.minimap, world, cameraTarget, cameraDistance,
    size.x / max(1'f, size.y), following)
  sk.drawHudFrame(boxes.frame)
  ui.selection = world.resolveSelection(ui.selection)
  if ui.utilityFrame.isNil or ui.utilitySelection != ui.selection:
    ui.utilityFrame = FrameState()
    ui.utilitySelection = ui.selection
  sk.drawSelectionStats(window, world, boxes, ui.selection, ui.utilityFrame)
  sk.drawInput(boxes.input, ui)
  let stopping = ui.input.isStopCommand()
  submit = sk.button(window, boxes.send, "Send",
    stopping or (available and not pending)) or submit
  if submit and ui.input.strip().len > 0:
    if not available and not stopping:
      ui.localError = "Connect the creature before sending a message."
    elif pending and not stopping:
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
  let error =
    if failure.len > 0: failure
    elif ui.localError.len > 0: ui.localError
    else: ui.voiceError
  var history = boxes.history
  sk.drawVoice(window, ui, history)
  if error.len > 0:
    let
      height = min(62'f, history.size.y)
      box = GameUiPanel(
        origin: history.origin + vec2(0, history.size.y - height),
        size: vec2(history.size.x, height)
      )
    history.size.y = max(0'f, history.size.y - height - 10)
    sk.plate(box, rgbx(0, 0, 0, 190))
    discard sk.drawText("Hud", error, box.origin + vec2(8, 3), Ink,
      maxWidth = box.size.x - 16, maxHeight = box.size.y - 6,
      wordWrap = true)
  if history.size.y > 0:
    sk.drawHistory(window, history, boxes.scrollbar, ui, messages)
