import
  std/[strutils, times],
  bumpy, chroma, pixie, silky, vmath, windy,
  chrome, homes, lobbies, replaylibraries, sounds, tapes

const ReplayRowHeight* = 104.0'f

type
  ReplayLengthDisplay* = enum
    ReplayDuration, ReplayActionCount
  ReplayBrowserAction* = enum
    StayReplayBrowser, BackFromReplays, ImportReplayFile, OpenReplayFolder,
    RefreshReplays, PlayReplay
  ReplayBrowserResult* = object
    action*: ReplayBrowserAction
    path*: string
  ReplayBrowserUi* = object
    scroll*: FrameState
    selectedPath*: string
  ReplayBrowserState* = object
    ui*: ReplayBrowserUi
    entries*: seq[ReplayEntry]
    folder*, message*: string
    refreshRequested*: bool
  ReplayBrowserStyle* = object
    title*: string = "REPLAYS"
    titleColor*: ColorRGBX = rgbx(240, 237, 225, 255)
    accentColor*: ColorRGBX = LobbyGreen
    mutedColor*: ColorRGBX = LobbyMuted
    centerTitle*: bool
    navigationIcons*: bool = true
    background*: proc(sk: Silky, window: Window)
  ReplayBrowserLayout* = object
    panel*, rows*: Rect
    back*, importButton*, folderButton*, refresh*: Rect

proc initReplayBrowser*(
  library: ReplayLibrary, message = "", directory = ""
): ReplayBrowserState =
  ## Initializes the desktop library without performing filesystem operations.
  result.folder = if directory.len > 0: directory else: library.replayDirectory()
  result.message = message
  result.refreshRequested = true

proc refreshReplayBrowser*(
  browser: var ReplayBrowserState, library: ReplayLibrary
) =
  ## Reloads the current folder after an import, save, or explicit refresh.
  browser.refreshRequested = false
  browser.folder = library.ensureReplayDirectory(browser.folder)
  browser.entries = library.listReplays(browser.folder)

proc importBrowserReplay*(
  browser: var ReplayBrowserState, library: ReplayLibrary, source: string
) =
  ## Imports a selected file and focuses it without changing its source.
  if source.len == 0:
    return
  browser.ui.selectedPath = library.importReplay(source, browser.folder)
  browser.refreshRequested = true
  browser.message = "Replay imported."

when not defined(emscripten):
  proc updateReplayBrowser*(
    browser: var ReplayBrowserState, library: ReplayLibrary,
    action: ReplayBrowserResult
  ): ReplayBrowserResult =
    ## Performs desktop file actions after event polling and validates playback.
    try:
      case action.action
      of StayReplayBrowser:
        discard
      of BackFromReplays:
        browser.message = ""
        return action
      of RefreshReplays:
        browser.refreshRequested = true
        browser.message = ""
      of OpenReplayFolder:
        openUrl(library.ensureReplayDirectory(browser.folder))
      of ImportReplayFile:
        let source = openFileDialog("Import replay", @[
          FileDialogFilter(name: "Polyworld replay", extensions: "replay")
        ], defaultPath = library.ensureReplayDirectory(browser.folder))
        browser.importBrowserReplay(library, source)
      of PlayReplay:
        let entry = library.inspectReplay(action.path)
        if not entry.playable:
          raise newException(ReplayError, entry.problem)
        result = ReplayBrowserResult(action: PlayReplay, path: entry.path)
      if browser.refreshRequested:
        browser.refreshReplayBrowser(library)
    except CatchableError as error:
      browser.message = error.msg
      result = ReplayBrowserResult()

proc replayBrowserLayout*(view: Vec2, folderWidth = 236.0'f): ReplayBrowserLayout =
  ## Keeps the list and controls within the current logical desktop viewport.
  let
    width = min(1240.0'f, max(480.0'f, view.x - 48))
    left = (view.x - width) / 2
    bottom = view.y - 30
  result.panel = rect(left, 132, width, max(260.0'f, bottom - 198))
  result.rows = rect(left + 20, 188, width - 40, result.panel.h - 76)
  result.back = rect(left, bottom - 44, 160, 44)
  result.importButton = rect(left, 76, 194, 44)
  result.refresh = rect(left + width - 154, 76, 154, 44)
  result.folderButton = rect(left + 208, 76,
    min(max(236.0'f, folderWidth), result.refresh.x - left - 220), 44)

proc folderButtonLabel*(): string =
  ## Names the desktop's file manager without exposing command syntax.
  when defined(macosx): "Open in Finder"
  elif defined(windows): "Open in File Explorer"
  else: "Open replay folder"

proc drawReplaySaveOption*(
  sk: Silky, window: Window, at: Vec2, saveReplay: var bool,
  enabled = true, width = 280.0'f
): bool =
  ## Draws the common recording preference and reports changes for persistence.
  let previous = saveReplay
  sk.at = at
  if enabled:
    checkBox "Save replay", saveReplay
  else:
    sk.lobbyLabel("Save replay: " & (if saveReplay: "On" else: "Off"),
      at, width, tint = LobbyMuted)
  previous != saveReplay

proc drawReplaySaveRetry*(sk: Silky, pending: bool): bool =
  ## Keeps the retry action in the same place on each game's desktop menu.
  pending and sk.lobbyButton("Retry saving replay", vec2(24, 64), 280)

proc replayDetails(entry: ReplayEntry, tickRate: int,
    lengthDisplay: ReplayLengthDisplay): string =
  ## Shows a recording's version and supported time or action-count measure.
  result = entry.modified.local.format("yyyy-MM-dd  HH:mm") &
    "  |  Game v" & $entry.gameVersion
  if entry.playable:
    case lengthDisplay
    of ReplayDuration:
      let seconds = entry.ticks div tickRate
      result.add("  |  " & $(seconds div 60) & ":" &
        align($(seconds mod 60), 2, '0'))
    of ReplayActionCount:
      result.add("  |  " & $entry.ticks &
        (if entry.ticks == 1: " action" else: " actions"))

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
  gameVersion: uint16, tickRate: int, message = "",
  lengthDisplay = ReplayDuration, style = ReplayBrowserStyle()
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
    layout = replayBrowserLayout(view,
      sk.getTextSize("LobbyBody", folderButtonLabel()).x + 20)
    rowWidth = layout.rows.w - 16
  if style.background != nil:
    style.background(sk, window)
  else:
    sk.drawHomeBackground(window)
  sk.drawLabel(style.title, vec2(layout.panel.x, 14),
    vec2(layout.panel.w, 56), style.titleColor, "LobbyTitle",
    if style.centerTitle: CenterAlign else: LeftAlign)
  if sk.lobbyButton("Import replay", layout.importButton.xy,
    layout.importButton.w):
      result.action = ImportReplayFile
  if sk.lobbyButton(folderButtonLabel(), layout.folderButton.xy,
    layout.folderButton.w):
      result.action = OpenReplayFolder
  if sk.lobbyButton("Refresh", layout.refresh.xy, layout.refresh.w,
    if style.navigationIcons: "loop" else: ""):
    result.action = RefreshReplays
  if sk.lobbyButton("Back", layout.back.xy, layout.back.w,
    if style.navigationIcons: "arrow_left" else: "") or
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
      ink = if entry.playable: sk.theme.defaultTextColor else: style.mutedColor
      labelWidth = rowWidth - 180
    if at.y + size.y <= layout.rows.y or at.y >= layout.rows.y + layout.rows.h:
      continue
    sk.lobbyPanel(at, size, true)
    if index == selected:
      sk.drawRect(at + vec2(0, 2), vec2(4, size.y - 4), style.accentColor)
    if sk.interact(rect(at, vec2(labelWidth + 20, size.y)),
      entry.playable) == Released:
        ui.selectedPath = entry.path
        selected = index
    sk.lobbyLabel(sk.fittedLabel(entry.name, labelWidth, "LobbyBold"),
      at + vec2(14, 0), labelWidth, "LobbyBold", ink)
    sk.lobbyLabel(replayDetails(entry, tickRate, lengthDisplay),
      at + vec2(14, 28), labelWidth, tint = style.mutedColor)
    let detail = if entry.playable: "Ready to watch" else: entry.problem
    sk.lobbyLabel(sk.fittedLabel(detail, labelWidth, "LobbyBody"),
      at + vec2(14, 56), labelWidth,
      tint = if entry.playable: style.accentColor else: style.mutedColor)
    if sk.lobbyButton("Watch", at + vec2(rowWidth - 144, 26), 128,
      (if style.navigationIcons: "arrow_right" else: ""), entry.playable):
        result = ReplayBrowserResult(action: PlayReplay, path: entry.path)
  if entries.len == 0:
    sk.lobbyLabel("No saved replays yet.", layout.rows.xy + vec2(20, 38),
      rowWidth - 40, "LobbyHeading")
    sk.lobbyLabel("Enable Save replay in game setup, or import a replay file.",
      layout.rows.xy + vec2(20, 82), rowWidth - 40, tint = style.mutedColor)
  sk.popClipRect()
  if selected >= 0 and window.buttonPressed[KeyEnter]:
    result = ReplayBrowserResult(action: PlayReplay, path: entries[selected].path)
  let footer = layout.back.xy + vec2(180, 0)
  sk.lobbyLabel(sk.fittedLabel(
    if message.len > 0: message else: folder,
    layout.panel.w - 180, "LobbyBody"
  ), footer, layout.panel.w - 180,
    tint = if message.len > 0: sk.theme.defaultTextColor else: style.mutedColor)

proc drawReplayBrowser*(
  sk: Silky, window: Window, browser: var ReplayBrowserState,
  gameVersion: uint16, tickRate: int, lengthDisplay = ReplayDuration,
  style = ReplayBrowserStyle()
): ReplayBrowserResult =
  ## Renders the same controller state for every desktop replay library.
  sk.drawReplayBrowser(window, browser.ui, browser.entries, browser.folder,
    gameVersion, tickRate, browser.message, lengthDisplay, style)
