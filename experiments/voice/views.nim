import
  std/[math, times, unicode],
  bumpy, chroma, pixie, silky, vmath

const
  Background* = rgbx(17, 23, 26, 255)
  Panel = rgbx(25, 33, 36, 255)
  Card = rgbx(33, 43, 46, 255)
  Border = rgbx(53, 67, 70, 255)
  Ink = rgbx(229, 236, 232, 255)
  Muted = rgbx(145, 163, 160, 255)
  Accent = rgbx(164, 224, 199, 255)
  Warm = rgbx(246, 178, 134, 255)
  Danger = rgbx(255, 151, 145, 255)
  DraftId = "voice-draft"

type
  UiAction* = enum
    ConnectAction, DisconnectAction, BeginTalkAction, EndTalkAction,
    ConversationAction, RepliesAction, SubmitAction, InterruptAction,
    ClearAction, CopyAction, InputDeviceAction, OutputDeviceAction,
    RefreshDevicesAction
  TranscriptLine* = object
    user*: bool
    text*: string
  TextLayout = object
    text: string
    width, height: float32
    state: TextBoxState
  VoiceView* = ref object
    window*: Window
    sk*: Silky
    model*, status*, error*, draft*: string
    connected*, connecting*, listening*, speaking*, responding*: bool
    handsFree*, speakReplies*, demo*: bool
    conversationRequested*, permissionPending*: bool
    level*: float32
    latencyMs*: int
    inputDevices*, outputDevices*: seq[string]
    inputDevice*, outputDevice*: int
    lines*: seq[TranscriptLine]
    layouts: seq[TextLayout]
    errorLayout: TextLayout
    lastLineCount: int
    scroll: float32
    follow: bool = true
    holding, mouseHolding, keyHolding: bool
    deviceMenu, deviceScroll: int
    pickerConsumesInput: bool

proc label(sk: Silky, text: string, x, y: float32,
    color = Ink, font = "Default") =
  ## Draws a label in the experiment's font palette.
  discard sk.drawText(font, text, vec2(x, y), color)

proc panel(sk: Silky, area: Rect, color: ColorRGBX, radius = 12.0'f) =
  ## Draws a rounded solid panel from the atlas white tile.
  sk.drawRoundedImage(WhiteTileKey, area.xy, area.wh, radius, color)

proc disc(sk: Silky, center: Vec2, radius: float32, color: ColorRGBX) =
  ## Draws a circle using the rounded white tile.
  sk.panel(rect(center - vec2(radius), vec2(radius * 2)), color, radius)

proc button(view: VoiceView, title: string, area: Rect,
    active = false, enabled = true): bool =
  ## Draws a button and reports one enabled pointer press.
  let
    sk = view.sk
    hover = sk.mousePos.overlaps(area) and enabled and
      not view.pickerConsumesInput
    color =
      if active and enabled: Accent
      elif hover: Border
      else: Card
    textColor =
      if not enabled: Muted
      elif active: Background
      else: Ink
  sk.panel(area, color, 8)
  discard sk.drawText(
    "Default", title, area.xy, textColor, area.w, area.h,
    hAlign = CenterAlign, vAlign = MiddleAlign
  )
  hover and sk.buttonPressed[MouseLeft]

proc textFocused(view: VoiceView): bool =
  ## Reports whether space belongs to the editable text field.
  DraftId in textBoxStates and textBoxStates[DraftId].focused

proc clearDraft*(view: VoiceView) =
  ## Clears both the draft and the text editor's retained content.
  view.draft.setLen(0)
  if DraftId in textBoxStates:
    textBoxStates[DraftId].setText("")

proc buildAtlas*(fontPath: string): AtlasBuilder =
  ## Builds an atlas from the bundled font and generated swatches.
  result = newAtlasBuilder(2048, 2)
  let typeface = readTypeface(fontPath)
  var glyphs = AsciiGlyphs
  for code in 160 .. 255:
    glyphs.add($Rune(code))
  for glyph in ["’", "‘", "“", "”", "—", "–", "…"]:
    glyphs.add(glyph)
  for (name, size) in [("Small", 12.0'f), ("Default", 16.0'f),
      ("Heading", 25.0'f), ("Title", 36.0'f)]:
    result.addFont(typeface, name, size, glyphs, pixelScale = 2)
  for name in ["textbox.9patch", "textbox.disabled.9patch",
      "textbox.error.9patch", "scrollbar.9patch", "scrollbar.track.9patch"]:
    let image = newImage(16, 16)
    image.fill(Border)
    for y in 1 ..< 15:
      for x in 1 ..< 15:
        image[x, y] = Card
    if not result.addImage(name, image):
      raise newException(ValueError, "Voice UI atlas is full")

proc drawOrb(view: VoiceView, area: Rect) =
  ## Visualizes microphone level and animates reply activity.
  let
    sk = view.sk
    center = vec2(area.x + area.w / 2, area.y + 94)
    active = view.listening or view.speaking or view.responding or
      view.conversationRequested
    pulse = (sin(epochTime() * 2.5) * 0.5 + 0.5).float32
    inputSignal = clamp(
      (20 * log10(max(view.level, 0.000001'f)) + 60) / 50, 0.0'f, 1.0'f
    )
    tint = (if view.listening: Warm else: Accent)
  sk.disc(center, 78, Background)
  sk.disc(center, 69 + (if active: pulse * 3 else: 0), Border)
  sk.disc(center, 66, Panel)
  for i in 0 ..< 25:
    let
      distance = abs(i.float32 - 12) / 12
      envelope = 1 - distance * distance
      signal =
        if view.listening and view.speaking:
          max(inputSignal, 0.3'f + pulse * 0.35'f)
        elif view.listening: inputSignal
        elif view.speaking: 0.3'f + pulse * 0.35'f
        elif view.responding: 0.15'f + pulse * 0.15'f
        else: 0.05'f
      ripple = 0.6'f + 0.4'f * sin(i.float32 * 1.7'f +
        (epochTime() mod 100).float32 * 4)
      height = 4 + envelope * signal * (24 + 34 * ripple)
    sk.panel(
      rect(center.x - 60 + i.float32 * 5, center.y - height / 2, 3, height),
      (if active: tint else: Muted), 1.5
    )
  let
    title =
      if view.permissionPending: "Microphone permission"
      elif view.listening and view.speaking: "Speaking and listening"
      elif view.listening: "Listening"
      elif view.speaking: "Speaking"
      elif view.responding: "Thinking"
      elif view.connecting: "Connecting"
      elif view.connected: "Ready when you are"
      else: "Let's talk"
    subtitle =
      if view.permissionPending: "Allow access in the system prompt"
      elif view.conversationRequested and view.listening:
        if view.speaking: "Speak any time to interrupt"
        else: "Microphone on. Just talk naturally."
      elif view.conversationRequested: "Starting your conversation"
      elif view.listening: "Your microphone is on"
      elif view.speaking: "Press Stop to interrupt"
      elif view.responding: "Waiting for a reply"
      elif view.connected: "Start a conversation, or hold to talk"
      else: "Press Start conversation to begin"
  discard sk.drawText(
    "Heading", title, vec2(area.x, area.y + 190), Ink,
    area.w, 38, hAlign = CenterAlign
  )
  discard sk.drawText(
    "Small", subtitle, vec2(area.x, area.y + 233), Muted,
    area.w, 24, hAlign = CenterAlign
  )

proc drawToggle(view: VoiceView, title, hint: string,
    area: Rect, enabled: bool): bool =
  ## Draws a settings row with a two-state switch.
  let sk = view.sk
  if sk.mousePos.overlaps(area):
    sk.panel(area, Card, 8)
  sk.label(title, area.x + 12, area.y + 10)
  sk.label(hint, area.x + 12, area.y + 35, Muted, "Small")
  let pos = vec2(area.x + area.w - 52, area.y + 17)
  sk.panel(rect(pos, vec2(36, 20)), (if enabled: Accent else: Border), 10)
  sk.disc(
    pos + vec2((if enabled: 26 else: 10), 10), 7,
    (if enabled: Background else: Muted)
  )
  sk.mousePos.overlaps(area) and sk.buttonPressed[MouseLeft] and
    not view.pickerConsumesInput

proc drawTranscript(view: VoiceView, area: Rect) =
  ## Lays out conversation cards with user-controlled scrolling.
  let sk = view.sk
  sk.panel(area, Panel)
  sk.pushClipRect(rect(area.x + 8, area.y + 8, area.w - 16, area.h - 16))
  defer: sk.popClipRect()
  if view.lines.len == 0:
    sk.label(
      "A conversation starts here.", area.x + 30, area.y + 32,
      Ink, "Heading"
    )
    discard sk.drawText(
      "Default",
      "Speak naturally, or type a message below. Your words and the " &
      "bot's replies appear here as they arrive.",
      vec2(area.x + 30, area.y + 84), Muted, area.w - 60, wordWrap = true
    )
    sk.label("TRY ASKING", area.x + 30, area.y + 178, Accent, "Small")
    sk.label("What should we build in Polyworld?", area.x + 30, area.y + 207)
    sk.label("Give me a tiny game idea.", area.x + 30, area.y + 238)
    return
  view.layouts.setLen(view.lines.len)
  var total = 24.0'f
  for i, line in view.lines:
    let width = area.w - 76
    var layout = addr view.layouts[i]
    if layout.state == nil:
      layout.state = TextBoxState(wordWrap: true)
    if layout.text != line.text or layout.width != width:
      layout.text = line.text
      layout.width = width
      layout.state.setText(if line.text.len == 0: "..." else: line.text)
      layout.state.computeLayout(sk.atlas.fonts["Default"], width)
      layout.height = max(24.0'f, layout.state.innerHeight)
    total += layout.height + 64
  let maxScroll = max(0.0'f, total - area.h)
  if sk.mousePos.overlaps(area) and view.window.scrollDelta.y != 0 and
    not view.pickerConsumesInput:
    view.scroll -= view.window.scrollDelta.y * 12
    view.scroll = clamp(view.scroll, 0.0'f, maxScroll)
    view.follow = view.scroll >= maxScroll - 8
  if view.follow:
    view.scroll = maxScroll
  view.scroll = clamp(view.scroll, 0.0'f, maxScroll)
  var y = area.y + 12 - view.scroll
  for i, line in view.lines:
    let height = view.layouts[i].height + 52
    if y + height >= area.y and y <= area.y + area.h:
      sk.panel(
        rect(area.x + 12, y, area.w - 24, height),
        (if line.user: Card else: Background), 8
      )
      sk.label(
        (if line.user: "YOU" else: "VOICE"), area.x + 26, y + 12,
        (if line.user: Warm else: Accent), "Small"
      )
      discard sk.drawText(
        "Default", (if line.text.len > 0: line.text else: "..."),
        vec2(area.x + 26, y + 34), Ink, area.w - 76, wordWrap = true
      )
    y += height + 12
  if maxScroll > 0:
    let
      track = area.h - 24
      thumb = max(24.0'f, track * area.h / total)
      offset = (track - thumb) * view.scroll / maxScroll
    sk.panel(
      rect(area.x + area.w - 8, area.y + 12 + offset, 3, thumb),
      Muted, 1.5
    )

proc devicesEnabled(view: VoiceView): bool =
  ## Allows route changes only while no audio or connection is active.
  not (view.listening or view.conversationRequested or view.connecting or
    view.speaking or view.responding)

proc deviceArea(area: Rect, output: bool): Rect =
  ## Places two equally sized device selectors beside the refresh button.
  let width = (area.w - 108) / 2
  rect(area.x + (if output: width + 12 else: 0), area.y + 24, width, 36)

proc devicePopup(view: VoiceView, area: Rect): Rect =
  ## Keeps a bounded device menu inside the conversation panel width.
  let
    output = view.deviceMenu == 2
    control = deviceArea(area, output)
    count = if output: view.outputDevices.len else: view.inputDevices.len
    width = min(area.w, max(control.w, 310.0'f))
  rect(min(control.x, area.x + area.w - width), control.y + control.h + 4,
    width, min(7, count).float32 * 34 + 8)

proc updateDevices(view: VoiceView, area: Rect): seq[UiAction] =
  ## Consumes menu input before any underlying conversation controls see it.
  let sk = view.sk
  view.pickerConsumesInput = view.deviceMenu != 0
  if not view.devicesEnabled() or not view.window.focused:
    view.deviceMenu = 0
    return
  if view.deviceMenu != 0:
    let
      popup = view.devicePopup(area)
      count =
        if view.deviceMenu == 2: view.outputDevices.len
        else: view.inputDevices.len
    if view.window.buttonPressed[KeyEscape]:
      view.deviceMenu = 0
      return
    if sk.mousePos.overlaps(popup) and view.window.scrollDelta.y != 0:
      view.deviceScroll = clamp(
        view.deviceScroll - int(view.window.scrollDelta.y),
        0, max(0, count - 7)
      )
    if sk.buttonPressed[MouseLeft] and sk.mousePos.overlaps(popup):
      let row = int((sk.mousePos.y - popup.y - 4) / 34)
      let selected = row + view.deviceScroll
      if sk.mousePos.y >= popup.y + 4 and row >= 0 and row < 7 and
        selected >= 0 and selected < count:
          if view.deviceMenu == 1:
            view.inputDevice = selected
            result.add(InputDeviceAction)
          else:
            view.outputDevice = selected
            result.add(OutputDeviceAction)
      view.deviceMenu = 0
      return
  if sk.buttonPressed[MouseLeft]:
    for output in [false, true]:
      let count = if output: view.outputDevices.len else: view.inputDevices.len
      if sk.mousePos.overlaps(deviceArea(area, output)) and count > 0:
        let menu = if output: 2 else: 1
        view.deviceMenu = if view.deviceMenu == menu: 0 else: menu
        view.deviceScroll = 0
        view.pickerConsumesInput = true
        return
    if view.deviceMenu != 0:
      view.deviceMenu = 0

proc drawDevices(view: VoiceView, area: Rect): bool =
  ## Draws the currently selected microphone and speaker even while disabled.
  let
    sk = view.sk
    enabled = view.devicesEnabled()
  for output in [false, true]:
    let
      control = deviceArea(area, output)
      names = if output: view.outputDevices else: view.inputDevices
      selected = if output: view.outputDevice else: view.inputDevice
      name =
        if selected >= 0 and selected < names.len: names[selected]
        else: "System default"
    sk.label((if output: "SOUND OUT" else: "SOUND IN"),
      control.x, area.y + 2, Accent, "Small")
    sk.panel(control, (if enabled: Card else: Panel), 8)
    sk.pushClipRect(rect(control.x + 10, control.y, control.w - 36, control.h))
    discard sk.drawText("Small", name, vec2(control.x + 10, control.y),
      (if enabled: Ink else: Muted), control.w - 36, control.h,
      vAlign = MiddleAlign)
    sk.popClipRect()
    sk.label("v", control.x + control.w - 22, control.y + 9, Muted)
  result = view.button("Refresh",
    rect(area.x + area.w - 84, area.y + 24, 84, 36), enabled = enabled)
  sk.label(
    (if enabled: "Choose the microphone and speaker for this conversation."
      else: "Stop conversation or playback to change devices."),
    area.x, area.y + 68, Muted, "Small"
  )

proc drawDevicePopup(view: VoiceView, area: Rect) =
  ## Draws the device menu after other controls so rows stay visible.
  if view.deviceMenu == 0:
    return
  let
    sk = view.sk
    popup = view.devicePopup(area)
    names =
      if view.deviceMenu == 2: view.outputDevices else: view.inputDevices
    selected =
      if view.deviceMenu == 2: view.outputDevice else: view.inputDevice
  sk.panel(rect(popup.x - 1, popup.y - 1, popup.w + 2, popup.h + 2), Border, 9)
  sk.panel(popup, Card, 8)
  for row in 0 ..< min(7, names.len - view.deviceScroll):
    let
      index = view.deviceScroll + row
      entry = rect(popup.x + 4, popup.y + 4 + row.float32 * 34,
        popup.w - 8, 34)
    if index == selected or sk.mousePos.overlaps(entry):
      sk.panel(entry, Border, 5)
    sk.pushClipRect(rect(entry.x + 10, entry.y, entry.w - 20, entry.h))
    discard sk.drawText("Small", names[index], vec2(entry.x + 10, entry.y),
      (if index == selected: Accent else: Ink), entry.w - 20, entry.h,
      vAlign = MiddleAlign)
    sk.popClipRect()

proc draw*(view: VoiceView): seq[UiAction] =
  ## Draws one frame and emits explicit actions for the app loop.
  let
    sk = view.sk
    width = sk.size.x
    height = sk.size.y
    side = rect(24, 98, 288, height - 154)
    mainX = 336.0'f
    mainWidth = width - mainX - 24
    devicesArea = rect(mainX, 146, mainWidth, 88)
    conversationArea = rect(side.x + 20, side.y + 278, side.w - 40, 48)
    talkArea = rect(side.x + 20, side.y + 373, side.w - 40, 48)
  result.add(view.updateDevices(devicesArea))
  if view.lines.len == 0 and view.lastLineCount > 0:
    view.follow = true
    view.scroll = 0
  view.lastLineCount = view.lines.len
  sk.clearScreen(Background)
  sk.label("POLYWORLD  /  EXPERIMENTS", 24, 20, Muted, "Small")
  sk.label("Voice", 24, 39, Ink, "Title")
  sk.disc(vec2(144, 66), 4, Accent)
  sk.label("A small space to talk.", 158, 54, Muted)
  let connectTitle =
    if view.connecting: "Cancel"
    elif view.connected: "Disconnect"
    else: "Connect"
  if view.button(
    connectTitle, rect(width - 152, 32, 128, 40),
    not view.connected and not view.connecting
  ):
    result.add(
      if view.connected or view.connecting: DisconnectAction
      else: ConnectAction
    )
  sk.panel(side, Panel)
  sk.label("VOICE 01", side.x + 20, side.y + 17, Accent, "Small")
  sk.label(
    (if view.demo: "PREVIEW" else: "REALTIME"),
    side.x + side.w - 78, side.y + 17, Muted, "Small"
  )
  view.drawOrb(rect(side.x, side.y + 17, side.w, 260))
  let conversationPressed = view.button(
    (if view.conversationRequested: "Stop conversation"
      else: "Start conversation"),
    conversationArea, active = true
  )
  if conversationPressed:
    result.add(ConversationAction)
  discard sk.drawText(
    "Small", "Just talk. Interrupt whenever you like.",
    vec2(side.x, side.y + 336), Muted, side.w, 22, hAlign = CenterAlign
  )
  let
    manualEnabled = view.connected and not view.conversationRequested and
      not conversationPressed and not view.pickerConsumesInput
    talkTitle =
      if view.listening and not view.conversationRequested: "Release to send"
      else: "Hold to talk"
  let talkPressed = view.button(
    talkTitle, talkArea, view.listening and manualEnabled, manualEnabled
  )
  if view.conversationRequested or conversationPressed:
    view.holding = false
    view.mouseHolding = false
    view.keyHolding = false
  else:
    if talkPressed:
      view.mouseHolding = true
    if manualEnabled and view.window.focused and
      not view.textFocused() and sk.buttonPressed[KeySpace]:
        view.keyHolding = true
    if not sk.buttonDown[MouseLeft] or not view.window.focused:
      view.mouseHolding = false
    if not sk.buttonDown[KeySpace] or not view.window.focused or
      view.textFocused():
        view.keyHolding = false
    let held = manualEnabled and view.window.focused and
      (view.mouseHolding or view.keyHolding)
    if held and not view.holding:
      result.add(BeginTalkAction)
    elif not held and view.holding:
      result.add(EndTalkAction)
    view.holding = held
  discard sk.drawText(
    "Small", "Or hold SPACE outside the text field",
    vec2(side.x, side.y + 423), Muted, side.w, 18, hAlign = CenterAlign
  )
  if view.drawToggle(
    "Spoken replies", "Text always stays visible",
    rect(side.x + 8, side.y + 441, side.w - 16, 64), view.speakReplies
  ):
    result.add(RepliesAction)
  if view.button(
    "Stop reply", rect(side.x + 20, side.y + 525, side.w - 40, 36),
    enabled = view.speaking or view.responding
  ):
    result.add(InterruptAction)
  sk.label("Conversation", mainX, 102, Ink, "Heading")
  if view.button(
    "Copy", rect(width - 168, 99, 64, 30), enabled = view.lines.len > 0
  ):
    result.add(CopyAction)
  if view.button(
    "New", rect(width - 96, 99, 72, 30), enabled = not view.connecting
  ):
    view.follow = true
    view.scroll = 0
    result.add(ClearAction)
  if view.drawDevices(devicesArea):
    result.add(RefreshDevicesAction)
  var errorHeight = 0.0'f
  if view.error.len > 0:
    if view.errorLayout.state == nil:
      view.errorLayout.state = TextBoxState(wordWrap: true)
    if view.errorLayout.text != view.error or
      view.errorLayout.width != mainWidth - 32:
        view.errorLayout.text = view.error
        view.errorLayout.width = mainWidth - 32
        view.errorLayout.state.setText(view.error)
        view.errorLayout.state.computeLayout(
          sk.atlas.fonts["Default"], mainWidth - 32
        )
        view.errorLayout.height = view.errorLayout.state.innerHeight
    errorHeight = view.errorLayout.height + 48
    let errorY = height - 149 - errorHeight
    sk.panel(
      rect(mainX, errorY, mainWidth, errorHeight),
      rgbx(53, 35, 36, 255), 8
    )
    sk.label("NEEDS ATTENTION", mainX + 16, errorY + 10, Danger, "Small")
    discard sk.drawText(
      "Default", view.error, vec2(mainX + 16, errorY + 31), Ink,
      mainWidth - 32, wordWrap = true
    )
    errorHeight += 12
  view.drawTranscript(rect(mainX, 248, mainWidth, height - 397 - errorHeight))
  let composeY = height - 133
  if view.pickerConsumesInput:
    sk.panel(rect(mainX, composeY, mainWidth - 92, 48), Card, 8)
    sk.pushClipRect(rect(mainX + 10, composeY, mainWidth - 112, 48))
    sk.label(view.draft, mainX + 10, composeY + 12)
    sk.popClipRect()
  else:
    sk.pushLayout(vec2(mainX, composeY), vec2(mainWidth - 92, 48))
    sk.textBox(
      view.window, DraftId, view.draft, mainWidth - 92, 48,
      wrapWords = false, singleLine = true, submitOnEnter = true
    )
    sk.popLayout()
  if view.draft.len == 0 and not view.textFocused():
    sk.label("Type a message...", mainX + 10, composeY + 12, Muted)
  let submitted = DraftId in textBoxStates and
    textBoxStates[DraftId].submitted
  let canSubmit = view.connected and view.draft.strip.len > 0 and
    (not view.conversationRequested or view.listening) and
    not view.pickerConsumesInput
  if view.button(
    "Send", rect(width - 104, composeY, 80, 48), active = true,
    enabled = canSubmit
  ) or (submitted and canSubmit):
    result.add(SubmitAction)
  sk.label("ENTER to send  /  ESC to stop", mainX, height - 75, Muted, "Small")
  if sk.buttonPressed[KeyEscape] and not view.pickerConsumesInput:
    result.add(InterruptAction)
  sk.drawRect(vec2(24, height - 44), vec2(width - 48, 1), Border)
  let status =
    if view.error.len > 0: "See the message above to continue."
    else: view.status
  discard sk.drawText(
    "Small", status, vec2(24, height - 30),
    (if view.error.len > 0: Danger else: Muted), width - 380, 24
  )
  let suffix = if view.latencyMs > 0: "  /  " & $view.latencyMs & " ms" else: ""
  discard sk.drawText(
    "Small", view.model & suffix, vec2(width - 350, height - 30),
    Muted, 326, 24, hAlign = RightAlign
  )
  view.drawDevicePopup(devicesArea)
