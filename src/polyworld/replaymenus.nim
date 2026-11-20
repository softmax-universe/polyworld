import
  std/[strutils, times],
  bumpy, chroma, silky, vmath, windy,
  chrome, homes, lobbies, replaylibraries, sounds

const ReplayRowHeight* = 104.0'f

type
  ReplayBrowserAction* = enum
    StayReplayBrowser, BackFromReplays, ImportReplayFile, OpenReplayFolder,
    RefreshReplays, PlayReplay
  ReplayBrowserResult* = object
    action*: ReplayBrowserAction
    path*: string
  ReplayBrowserUi* = object
    scroll*: FrameState
    selectedPath*: string
  ReplayBrowserLayout* = object
    panel*, rows*: Rect
    back*, importButton*, folderButton*, refresh*: Rect

proc replayBrowserLayout*(view: Vec2): ReplayBrowserLayout =
  ## Keeps the list and controls within the current logical desktop viewport.
  let
    width = min(1240.0'f, max(480.0'f, view.x - 48))
    left = (view.x - width) / 2
    bottom = view.y - 30
  result.panel = rect(left, 132, width, max(260.0'f, bottom - 198))
  result.rows = rect(left + 20, 188, width - 40, result.panel.h - 76)
  result.back = rect(left, bottom - 44, 160, 44)
  result.importButton = rect(left, 76, 194, 44)
  result.folderButton = rect(left + 208, 76, 236, 44)
  result.refresh = rect(left + width - 154, 76, 154, 44)

proc folderButtonLabel*(): string =
  ## Names the desktop's file manager without exposing command syntax.
  when defined(macosx): "Open in Finder"
  elif defined(windows): "Open in File Explorer"
  else: "Open replay folder"

proc replayDetails(entry: ReplayEntry, tickRate: int): string =
  ## Shows recording time and version without pretending old files can play.
  result = entry.modified.local.format("yyyy-MM-dd  HH:mm") &
    "  |  Game v" & $entry.gameVersion
  if entry.playable:
    let seconds = entry.ticks div tickRate
    result.add("  |  " & $(seconds div 60) & ":" &
      align($(seconds mod 60), 2, '0'))

proc chooseReplay(ui: var ReplayBrowserUi, entries: openArray[ReplayEntry],
    direction: int): int =
  ## Moves keyboard focus between playable entries only.
  var current = if direction > 0: -1 else: entries.len
  for index, entry in entries:
    if entry.path == ui.selectedPath:
      current = index
      break
  var next = current + direction
  while next >= 0 and next < entries.len:
    if entries[next].playable:
      ui.selectedPath = entries[next].path
      return next
    next += direction
  -1

proc drawReplayBrowser*(
  sk: Silky, window: Window, ui: var ReplayBrowserUi,
  entries: openArray[ReplayEntry], folder: string,
  gameVersion: uint16, tickRate: int, message = ""
): ReplayBrowserResult =
  ## Draws the library and returns file actions for the frontend to perform.
  doAssert tickRate > 0
  let requestedScale = selectedUiScale(max(0.1'f, min(
    window.size.x.float32 / 1080, window.size.y.float32 / 800
  )), 1.35'f)
  sk.uiScale = min(requestedScale, max(0.1'f, min(
    window.size.x.float32 / 720, window.size.y.float32 / 600
  )))
  sk.beginUi(window, window.size)
  sk.textStyle = "LobbyBody"
  let
    view = window.size.vec2 / sk.uiScale
    layout = replayBrowserLayout(view)
    rowWidth = layout.rows.w - 16
  sk.drawHomeBackground(window)
  sk.drawLabel("REPLAYS", vec2(layout.panel.x, 14),
    vec2(layout.panel.w, 56), rgbx(240, 237, 225, 255), "LobbyTitle")
  if sk.lobbyButton("Import replay", layout.importButton.xy,
    layout.importButton.w):
      result.action = ImportReplayFile
  if sk.lobbyButton(folderButtonLabel(), layout.folderButton.xy,
    layout.folderButton.w):
      result.action = OpenReplayFolder
  if sk.lobbyButton("Refresh", layout.refresh.xy, layout.refresh.w, "loop"):
    result.action = RefreshReplays
  if sk.lobbyButton("Back", layout.back.xy, layout.back.w, "arrow_left") or
    window.buttonPressed[KeyEscape]:
      result.action = BackFromReplays
  sk.lobbyPanel(layout.panel.xy, layout.panel.wh)
  sk.lobbyLabel($entries.len & (if entries.len == 1: " replay" else: " replays") &
    "  |  Current game version " & $gameVersion,
    layout.panel.xy + vec2(20, 8), layout.panel.w - 40, "LobbyBold")
  if ui.scroll == nil:
    ui.scroll = FrameState()
  var selected = -1
  for index, entry in entries:
    if entry.playable and entry.path == ui.selectedPath:
      selected = index
      break
  if selected < 0:
    ui.selectedPath = ""
  let direction =
    if window.buttonPressed[KeyDown]: 1
    elif window.buttonPressed[KeyUp]: -1
    else: 0
  if direction != 0:
    let next = ui.chooseReplay(entries, direction)
    if next >= 0:
      selected = next
      let top = next.float32 * ReplayRowHeight
      ui.scroll.scrollPos.y = clamp(ui.scroll.scrollPos.y,
        top + ReplayRowHeight - layout.rows.h, top)
      playSound(SelectSound)
  sk.frameScrollbars(window, ui.scroll, layout.rows,
    vec2(layout.rows.w, entries.len.float32 * ReplayRowHeight), vec2(1))
  sk.pushClipRect(rect(layout.rows.xy, vec2(rowWidth, layout.rows.h)))
  for index, entry in entries:
    let
      at = layout.rows.xy +
        vec2(0, index.float32 * ReplayRowHeight - ui.scroll.scrollPos.y)
      size = vec2(rowWidth, ReplayRowHeight - 8)
      ink = if entry.playable: sk.theme.defaultTextColor else: LobbyMuted
      labelWidth = rowWidth - 180
    if at.y + size.y <= layout.rows.y or at.y >= layout.rows.y + layout.rows.h:
      continue
    sk.lobbyPanel(at, size, true)
    if index == selected:
      sk.drawRect(at + vec2(0, 2), vec2(4, size.y - 4), LobbyGreen)
    if sk.interact(rect(at, vec2(labelWidth + 20, size.y)),
      entry.playable) == Released:
        ui.selectedPath = entry.path
        selected = index
    sk.lobbyLabel(sk.fittedLabel(entry.name, labelWidth, "LobbyBold"),
      at + vec2(14, 0), labelWidth, "LobbyBold", ink)
    sk.lobbyLabel(replayDetails(entry, tickRate), at + vec2(14, 28), labelWidth,
      tint = LobbyMuted)
    let detail = if entry.playable: "Ready to watch" else: entry.problem
    sk.lobbyLabel(sk.fittedLabel(detail, labelWidth, "LobbyBody"),
      at + vec2(14, 56), labelWidth,
      tint = if entry.playable: LobbyGreen else: LobbyMuted)
    if sk.lobbyButton("Watch", at + vec2(rowWidth - 144, 26), 128,
      "arrow_right", entry.playable):
        result = ReplayBrowserResult(action: PlayReplay, path: entry.path)
  if entries.len == 0:
    sk.lobbyLabel("No saved replays yet.", layout.rows.xy + vec2(20, 38),
      rowWidth - 40, "LobbyHeading")
    sk.lobbyLabel("Enable Save replay in game setup, or import a replay file.",
      layout.rows.xy + vec2(20, 82), rowWidth - 40, tint = LobbyMuted)
  sk.popClipRect()
  if selected >= 0 and window.buttonPressed[KeyEnter]:
    result = ReplayBrowserResult(action: PlayReplay, path: entries[selected].path)
  let footer = layout.back.xy + vec2(180, 0)
  sk.lobbyLabel(sk.fittedLabel(
    if message.len > 0: message else: folder,
    layout.panel.w - 180, "LobbyBody"
  ), footer, layout.panel.w - 180,
    tint = if message.len > 0: sk.theme.defaultTextColor else: LobbyMuted)
