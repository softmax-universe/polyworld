## LvD's player, team, and map controls; all menu chrome is shared.
import std/strutils
import presets
import polyworld/[rooms, roomclients]

const RosterColumns* = 2

proc confirmedPlayerName*(name: string): bool =
  ## Legacy placeholder settings are not a chosen identity. Inspect a trimmed
  ## copy only for this sentinel; legitimate names remain opaque UTF-8 bytes.
  name.len <= 64 and name.validName and name.strip.toLowerAscii != "player"

proc defaultGameName*(player: string): string =
  if player.confirmedPlayerName: player & "'s game" else: ""

proc canEditGameName*(snapshot: RoomMessage, self: uint32): bool =
  self != 0 and snapshot.room.len > 0 and snapshot.phase == Lobby and
    snapshot.participant == self

proc renameGame*(client: RoomClient, name: string): bool =
  if client == nil or not client.connected or not client.welcomed or
      not client.snapshot.canEditGameName(client.participant):
    return false
  if not name.validName:
    client.error = "Game name must contain visible text and no control characters"
    return false
  if name.len > 128:
    client.error = "Game name must be at most 128 UTF-8 bytes"
    return false
  if name == client.snapshot.name: return false
  client.error = ""
  # Reuse the authoritative settings verbatim: local map/roster drafts must
  # never become an accidental settings change when Enter submits the name.
  client.send(RoomMessage(kind: ResizeRoom, name: name,
    payload: client.snapshot.payload, number: uint32(client.snapshot.seats.len),
    tickRate: client.snapshot.tickRate, flag: client.snapshot.flag))
  return true

proc previewMap*(config: LvdConfig): MapData =
  config.validate()
  generateMap(config.seed, config.playerCount, config.mapSettings)

proc rosterColumn*(index: int): int = index mod RosterColumns

proc humanAfterRemoval*(human, removed: int): int =
  if human == removed: -1
  elif human > removed: human - 1
  else: human

when not defined(headless):
  import bumpy, chroma, pixie, silky, vmath, windy
  import polyworld/[chrome, menus, inputs]
  import polyworld/lobbies as sharedLobbies
  import content, factions, shortcutsettings
  export sharedLobbies

  type TeamPicker* = object
    seat*: int = -1
    page*: int
    anchor*: Vec2
    fresh: bool

  const LvdControlProfile* = block:
    var profile = ControlProfile(defaults: DefaultBindings)
    profile.defaults[SelectInput] = [MouseLeft, ButtonUnknown]
    profile.defaults[AttackMoveInput] = [KeyA, ButtonUnknown]
    profile.defaults[OrderInput] = [MouseRight, KeyD]
    profile.defaults[PanInput] = [MouseMiddle, ButtonUnknown]
    profile.defaults[CameraInput] = [KeyC, ButtonUnknown]
    profile.defaults[StopInput] = [KeyS, ButtonUnknown]
    profile.defaults[ShadingInput] = [KeyF5, ButtonUnknown]
    for action in LvdInputActions:
      if action in {AttackMoveInput, StopInput}: continue
      profile.actions.add ControlBinding(action: action, label: $action)
    profile.actions.add ControlBinding(action: AttackMoveInput, label: "Attack move / click destination")
    profile.actions.add ControlBinding(action: StopInput, label: "Stop selected")
    profile

  proc migrateLvdBindings*(bindings: var InputBindings) =
    ## Upgrade legacy defaults and free X for permanent cancellation.
    if bindings[StopInput] in [[KeyX, ButtonUnknown], [KeyS, KeyX]]:
      bindings[StopInput] = LvdControlProfile.defaults[StopInput]
    if bindings[ShadingInput] == [KeyT, ButtonUnknown]:
      bindings[ShadingInput] = LvdControlProfile.defaults[ShadingInput]
    if bindings[PanInput] == [MouseMiddle, KeyS]:
      bindings[PanInput] = LvdControlProfile.defaults[PanInput]
    if bindings[SelectInput] == [MouseLeft, KeyA] and
        bindings[AttackMoveInput] == [KeyA, ButtonUnknown]:
      bindings[SelectInput][1] = ButtonUnknown
    for action in InputAction:
      for slot in 0 .. 1:
        if bindings[action][slot] == KeyX:
          bindings[action][slot] = ButtonUnknown

  proc readLvdPreferences*(): Preferences =
    loadLvdShortcuts()
    result = readPreferences("Polyworld LvD")
    if getConfig("Polyworld LvD", "settings.json").len == 0:
      result.bindings = LvdControlProfile.defaults
    else:
      result.bindings.migrateLvdBindings()
    shortcutSettingsError.add currentShortcuts.reconcileShortcutInputs(
      result.bindings)


  proc lvdSettingsPanel*(sk: Silky, window: Window,
      preferences: var Preferences, app: string, origin: Vec2,
      title = "Settings", height = 440.0'f): bool =
    sk.settingsPanel(window, preferences, app, origin, title, height,
      LvdControlProfile, lvdShortcutExtension())

  proc lvdRosterPanel*(sk: Silky, layout: LobbyLayout, diplomacy = false) =
    sk.lobbyPanel(layout.left, vec2(layout.leftWidth, layout.panelHeight))
    sk.lobbyIcon("units", layout.left + vec2(24, 24), 36)
    sk.lobbyLabel("PLAYERS", layout.left + vec2(70, 22), 600, "LobbyHeading")
    sk.lobbyLabel(
      if diplomacy: "Each player commands an independent faction."
      else: "Right-click a team color to reassign that player.",
      layout.left + vec2(24, 76), layout.leftWidth - 48, tint = LobbyMuted
    )

  proc rosterCardSize*(layout: LobbyLayout): Vec2 =
    ## Match GotA's compact two-line seat dimensions.
    vec2((layout.leftWidth - 60) / RosterColumns.float32, 78)

  proc rosterCardPosition*(layout: LobbyLayout, index: int, scroll = 0.0'f): Vec2 =
    layout.left + vec2(20 + rosterColumn(index).float32 *
      (rosterCardSize(layout).x + 20),
      132 + (index div RosterColumns).float32 * 88 - scroll)

  proc rosterControlsPosition*(layout: LobbyLayout): Vec2 =
    layout.left + vec2(24, layout.panelHeight - 220)

  proc rosterViewport*(layout: LobbyLayout): Rect =
    ## Leave room for the fixed resize/fill controls and the right scrollbar.
    rect(rosterCardPosition(layout, 0),
      vec2(layout.leftWidth - 24, layout.panelHeight - 364))

  proc rosterCardHit*(layout: LobbyLayout, index: int, scroll: float32,
      mouse: Vec2): bool =
    ## Right-click picking uses exactly the visible roster clip, not hidden rows.
    let viewport = rosterViewport(layout)
    overlaps(mouse, rect(viewport.xy, viewport.wh - vec2(16, 0))) and
      overlaps(mouse, rect(rosterCardPosition(layout, index, scroll),
        rosterCardSize(layout)))

  proc rosterContentHeight*(count: int): float32 =
    max(0, ((count + RosterColumns - 1) div RosterColumns) * 88 - 10).float32

  proc rosterScrollPosition*(layout: LobbyLayout, count: int, scroll: float32): float32 =
    clamp(scroll, 0.0'f, max(0.0'f, rosterContentHeight(count) - rosterViewport(layout).h))

  proc rosterOwnsScroll*(layout: LobbyLayout, count: int, mouse: Vec2): bool =
    rosterContentHeight(count) > rosterViewport(layout).h and
      overlaps(mouse, rosterViewport(layout))

  proc pushRosterClip*(sk: Silky, layout: LobbyLayout) =
    let viewport = rosterViewport(layout)
    sk.pushClipRect(rect(viewport.xy, viewport.wh - vec2(16, 0)))

  proc beginLvdBattle*(sk: Silky, window: Window, ui: var LobbyUi,
    count: int, contextOpen = false): LobbyLayout =
    ## The nested roster consumes its wheel gesture, not the portrait page.
    let previousScroll = ui.scroll
    result = sk.beginLobby(window, ui, "BATTLE SETUP")
    let correction = vec2(0, ui.scroll - previousScroll)
    var previousLayout = result
    previousLayout.left += correction
    if window.scrollDelta.y != 0 and (contextOpen or ui.selectedSeat != -1 or
      rosterOwnsScroll(previousLayout, count, sk.mousePos)):
      ui.scroll = previousScroll
      result.origin += correction
      result.left += correction
      result.right += correction
      result.footer += correction
      result.primary += correction

  proc beginRoster*(sk: Silky, window: Window, layout: LobbyLayout,
    state: FrameState, count: int, enabled: bool) =
    let viewport = rosterViewport(layout)
    state.scrollPos = vec2(0, rosterScrollPosition(layout, count, state.scrollPos.y))
    if enabled:
      sk.frameScrollbars(window, state, viewport,
        vec2(viewport.w, rosterContentHeight(count)), vec2(1))
    sk.pushRosterClip(layout)

  proc rosterColor*(seed: int32, player: int): ColorRGBX =
    ## Use the exact seeded faction assignment used by runGraphics.
    let order = factionOrder(seed.int64)
    FactionColors[order[Faction(player mod FactionFiles.len)]]

  proc seatWellTint*(empty: bool, faction: ColorRGBX): ColorRGBX =
    if empty: rgbx(65, 65, 65, 255) else: faction

  proc teamControlsOrigin*(at: Vec2, gameName = false): Vec2 =
    ## Places team setup immediately below Max ticks in the main settings.
    at + vec2(22, (if gameName: 74'f32 else: 22'f32) + 318)

  proc diplomacyControlRect*(at: Vec2, width: float32): Rect =
    ## Fits the mode checkbox to the match settings column.
    rect(at, vec2(width, 40))

  proc teamSliderRect*(at: Vec2, width: float32): Rect =
    ## Keeps the team count and slider together beneath the mode checkbox.
    rect(at + vec2(138, 48), vec2(width - 138, 32))

  proc teamControls*(sk: Silky, window: Window, config: var LvdConfig,
      at: Vec2, width: float32, enabled: bool,
      occupied: openArray[int] = []): bool =
    ## Edits the match mode and balances teams only when the count changes.
    let
      mode = diplomacyControlRect(at, width)
      ink = if enabled: rgbx(240, 237, 225, 255) else: LobbyMuted
    if sk.interact(mode, enabled) == Released:
      config.diplomacySettings.enabled = not config.diplomacySettings.enabled
      if config.diplomacySettings.enabled:
        config.diplomacySettings.neutralStart = true
      result = true
    sk.drawSprite(
      if config.diplomacySettings.enabled: "check.on" else: "check.off",
      mode.xy + vec2(0, 4), vec2(32), ink
    )
    sk.lobbyLabel("Diplomacy mode", mode.xy + vec2(42, 0), mode.w - 42,
      "LobbyBold", ink)
    if "lvdTeamCount" in scrubberStates and
      (not enabled or config.diplomacySettings.enabled or
      not window.buttonDown[MouseLeft]):
        scrubberStates["lvdTeamCount"].dragging = false
    if config.diplomacySettings.enabled:
      sk.lobbyLabel("Players start neutral and can negotiate alliances.",
        at + vec2(0, 48), width, "Hud", LobbyMuted)
      return
    var count = config.resolvedTeamCount()
    sk.lobbyLabel($count & (if count == 1: " team" else: " teams"),
      at + vec2(0, 44), 132, "LobbyBold")
    let slider = teamSliderRect(at, width)
    if enabled and config.playerCount > 1:
      sk.pushLayout(slider.xy,
        vec2(slider.w + sk.theme.padding.float32 * 3, slider.h))
      scrubber("lvdTeamCount", count, 1, config.playerCount)
      sk.popLayout()
      if count != config.resolvedTeamCount():
        config.setTeamCount(count, occupied)
        result = true
    else:
      sk.draw9Patch("scrubber.body.9patch", sk.theme.scrubberPatch,
        slider.xy, slider.wh)
      let fraction = float32(count - 1) / max(1, config.playerCount - 1).float32
      sk.drawSprite("scrubber.handle",
        slider.xy + vec2(fraction * (slider.w - 24), 0), vec2(24, slider.h),
        LobbyMuted)

  proc teamBadgeRect*(layout: LobbyLayout, index: int, scroll: float32): Rect =
    ## Keeps the numbered team badge separate from the player chooser.
    rect(rosterCardPosition(layout, index, scroll) +
      vec2(rosterCardSize(layout).x - 120, 18), vec2(84, 42))

  proc teamBadgeHit*(layout: LobbyLayout, index: int, scroll: float32,
      mouse: Vec2): bool =
    ## Rejects clipped or scrolled-away team badges.
    rosterCardHit(layout, index, scroll, mouse) and
      overlaps(mouse, teamBadgeRect(layout, index, scroll))

  proc drawTeamBadge(sk: Silky, area: Rect, team: int, tint: ColorRGBX) =
    ## Pairs the team color with a readable number on a dark inset.
    sk.drawRect(area.xy, area.wh, tint)
    sk.drawRect(area.xy + vec2(2), area.wh - vec2(4), rgbx(27, 32, 41, 255))
    sk.drawLabel("Team " & $(team + 1), area.xy, area.wh,
      rgbx(245, 245, 245, 255), "LobbyBold", CenterAlign)

  proc seatButton*(sk: Silky, layout: LobbyLayout, index: int, scroll: float32,
    name, owner: string, human, empty, editable: bool, seed: int32,
    team = -1): bool =
    let
      size = rosterCardSize(layout)
      at = rosterCardPosition(layout, index, scroll)
      tint = rosterColor(seed, if team >= 0: team else: index)
      edge = if empty: rgbx(tint.r div 3, tint.g div 3, tint.b div 3, 255) else: tint
      ink = if empty: LobbyMuted else: tint
    result = sk.lobbyButton("", at, size.x, enabled = editable,
      height = size.y, tint = seatWellTint(empty, tint))
    # Explicit color edging remains readable even on the disabled theme patch.
    sk.drawRect(at, vec2(size.x, 2), edge)
    sk.drawRect(at + vec2(0, size.y - 2), vec2(size.x, 2), edge)
    sk.drawRect(at, vec2(2, size.y), edge)
    sk.drawRect(at + vec2(size.x - 2, 0), vec2(2, size.y), edge)
    sk.lobbyLabel($(index + 1), at + vec2(10, 19), 30, "LobbyBold", ink)
    sk.lobbyIcon(if empty: "cross" elif human: "character" else: "settings",
      at + vec2(44, 22), 32, ink)
    let nameWidth = size.x - (if team >= 0: 218 else: 130)
    sk.lobbyLabel(name, at + vec2(88, 6), nameWidth, "LobbyBold",
      if empty: LobbyMuted else: rgbx(240, 237, 225, 255))
    sk.lobbyLabel(owner, at + vec2(88, 37), nameWidth, tint = LobbyMuted)
    if team >= 0:
      sk.drawTeamBadge(teamBadgeRect(layout, index, scroll), team, tint)
    sk.lobbyIcon("chevron_down", at + vec2(size.x - 34, 25), 22)

  proc isOpen*(picker: TeamPicker): bool =
    ## Reports whether one player's assignment menu is open.
    picker.seat >= 0

  proc dismiss*(picker: var TeamPicker) =
    ## Clears the target and paging state together.
    picker = TeamPicker()

  proc openTeamPicker*(picker: var TeamPicker, seat: int, anchor: Vec2) =
    ## Opens a new assignment without reusing the previous target.
    picker = TeamPicker(seat: seat, anchor: anchor, fresh: true)

  proc teamPickerColumns(view: Vec2): int =
    ## Fits numbered choices without letting the popup exceed the viewport.
    max(1, min(4, int((view.x - 48) / 140)))

  proc teamPickerPageSize*(view: Vec2, count: int): int =
    ## Bounds even a full 64-team roster to a paged grid.
    let
      columns = teamPickerColumns(view)
      rows = max(1, min(8, int((view.y - 160) / 48)))
    columns * min(rows, max(1, (count + columns - 1) div columns))

  proc teamPickerBounds*(picker: TeamPicker, view: Vec2, count: int): Rect =
    ## Anchors the picker near the clicked badge and inside the screen.
    let
      columns = teamPickerColumns(view)
      rows = teamPickerPageSize(view, count) div columns
      size = vec2(min(620'f, view.x - 24), 126 + rows.float32 * 48)
    rect(vec2(clamp(picker.anchor.x, 12'f, max(12'f, view.x - size.x - 12)),
      clamp(picker.anchor.y, 12'f, max(12'f, view.y - size.y - 12))), size)

  proc teamPickerItemRect*(picker: TeamPicker, view: Vec2, count,
      team: int): Rect =
    ## Resolves one visible team's cell using the production page geometry.
    let
      panel = picker.teamPickerBounds(view, count)
      columns = teamPickerColumns(view)
      local = team mod teamPickerPageSize(view, count)
      width = (panel.w - 32) / columns.float32
    rect(panel.xy + vec2(16 + (local mod columns).float32 * width,
      60 + (local div columns).float32 * 48), vec2(width - 8, 40))

  proc drawTeamPicker*(sk: Silky, window: Window, picker: var TeamPicker,
      config: var LvdConfig): bool =
    ## Changes one assignment, leaving all other teams untouched.
    if not picker.isOpen:
      return
    if picker.seat >= config.playerCount or config.diplomacySettings.enabled:
      picker.dismiss()
      return
    let
      view = window.size.vec2 / sk.uiScale
      count = config.resolvedTeamCount()
      pageSize = teamPickerPageSize(view, count)
      pages = max(1, (count + pageSize - 1) div pageSize)
      panel = picker.teamPickerBounds(view, count)
    picker.page = clamp(picker.page, 0, pages - 1)
    if not picker.fresh and (window.buttonPressed[KeyEscape] or
      window.buttonPressed[MouseRight] or
      (window.buttonPressed[MouseLeft] and not overlaps(sk.mousePos, panel))):
        picker.dismiss()
        return
    picker.fresh = false
    sk.pushLayer(PopupsLayer)
    defer: sk.popLayer()
    discard sk.interact(rect(vec2(0), view), true)
    sk.lobbyPanel(panel.xy, panel.wh)
    sk.lobbyLabel("Assign player " & $(picker.seat + 1) & " to team",
      panel.xy + vec2(16, 8), panel.w - 80, "LobbyHeading")
    if sk.lobbyButton("X", panel.xy + vec2(panel.w - 52, 12), 36,
        height = 32):
      picker.dismiss()
      return
    for team in picker.page * pageSize ..< min(count, (picker.page + 1) * pageSize):
      let
        item = picker.teamPickerItemRect(view, count, team)
        tint = rosterColor(config.seed, team)
        selected = config.playerTeam(picker.seat) == team.int32
      if sk.lobbyButton("Team " & $(team + 1), item.xy, item.w,
          selected = selected, height = item.h, tint = tint):
        config.assignTeam(picker.seat, team.int32)
        picker.dismiss()
        return true
    let footer = panel.xy + vec2(16, panel.h - 52)
    if sk.lobbyButton("Previous", footer, 126, enabled = picker.page > 0):
      dec picker.page
    sk.drawLabel($(picker.page + 1) & " / " & $pages,
      footer + vec2(138, 0), vec2(panel.w - 308, 44), LobbyMuted,
      "LobbyBody", CenterAlign)
    if sk.lobbyButton("Next", panel.xy + vec2(panel.w - 150, panel.h - 52),
        134, enabled = picker.page + 1 < pages):
      inc picker.page

  var
    cachedPreview: MapData
    previewSeed: int32
    previewPlayers: int
    previewSettings: MapSettings
    previewError: string

  proc drawMapPreview(sk: Silky, config: LvdConfig, at: Vec2, width: float32) =
    if cachedPreview.side == 0 or previewSeed != config.seed or
      previewPlayers != config.playerCount or previewSettings != config.mapSettings:
      previewSeed = config.seed
      previewPlayers = config.playerCount
      previewSettings = config.mapSettings
      try:
        cachedPreview = previewMap(config)
        previewError = ""
      except CatchableError as error:
        previewError = error.msg
    if previewError.len > 0:
      sk.lobbyLabel(previewError, at, width, tint = LobbyRed)
      return
    let side = cachedPreview.side
    let step = max(1'i32, side div 64)
    let cell = 126.0'f / side.float32
    for y in countup(0'i32, side - 1, step):
      for x in countup(0'i32, side - 1, step):
        let i = int(y * side + x)
        let tint = if cachedPreview.treeWood[i] > 0: rgbx(36, 87, 49, 255)
          elif cachedPreview.passable[i] == 0: rgbx(77, 75, 83, 255)
          else: rgbx(123, 150, 82, 255)
        sk.drawRect(at + vec2(x.float32, y.float32) * cell,
          vec2(step.float32 * cell + 0.2'f), tint)
    for i, origin in cachedPreview.hallOrigin:
      let point = at + vec2(origin.x.float32, origin.y.float32) * cell
      let colorIndex =
        if config.diplomacySettings.enabled: i
        else: config.playerTeam(i).int
      sk.drawRect(point - vec2(2), vec2(5), rosterColor(config.seed, colorIndex))
    sk.lobbyLabel("Generated map", at + vec2(142, 8), width - 142, "LobbyBold")
    sk.lobbyLabel($side & " x " & $side & " tiles", at + vec2(142, 48), width - 142)
    sk.lobbyLabel(
      if config.diplomacySettings.enabled: $config.playerCount & " factions"
      else: $config.resolvedTeamCount() & " fixed teams",
      at + vec2(142, 88), width - 142
    )

  proc settingsFooter*(at: Vec2, height: float32): tuple[map, advanced: Vec2] =
    (at + vec2(22, height - 114), at + vec2(22, height - 66))

  proc configPanel*(sk: Silky, window: Window, ui: var LobbyUi,
    config: var LvdConfig, at: Vec2, width, height: float32,
    enabled: bool, showControls = true, gameName: ptr string = nil,
    occupied: openArray[int] = []): bool =
    let before = config
    sk.lobbyPanel(at, vec2(width, height))
    let p = at + vec2(22, if gameName != nil: 74 else: 22)
    let w = width - 44
    let page = if showControls: ui.configPage else: 0
    if page != 0 and "lvdTeamCount" in scrubberStates:
      scrubberStates["lvdTeamCount"].dragging = false
    sk.lobbyLabel("MATCH SETTINGS", p, w, "LobbyHeading")
    if gameName != nil:
      if enabled:
        sk.lobbyInput(window, "matchGameName", gameName[], at + vec2(22, 12), w)
      else:
        sk.lobbyLabel(gameName[], at + vec2(22, 12), w)
    if page == 0:
      sk.drawMapPreview(config, p + vec2(0, 64), w)
      if showControls:
        sk.lobbyNumber("Map seed", config.seed, p + vec2(0, 214), w,
          0'i32, int32.high - 1, 1'i32, enabled)
        sk.lobbyNumber("Max ticks", config.maxTicks, p + vec2(0, 266), w,
          TickRate, TickRate * 3600, TickRate * 60, enabled)
      else:
        sk.lobbyLabel("Map seed: " & $config.seed, p + vec2(0, 214), w)
        sk.lobbyLabel("Max ticks: " & $config.maxTicks, p + vec2(0, 266), w)
        sk.lobbyLabel("Layout: " & $config.mapSettings.layout,
          p + vec2(0, 418), w)
      discard sk.teamControls(window, config,
        teamControlsOrigin(at, gameName != nil), w, enabled, occupied)
    elif page == 1:
      sk.lobbyLabel("Layout", p + vec2(0, 64), 190)
      sk.lobbySelect(window, config.mapSettings.layout, [SpokeLayout, RandomLayout],
        p + vec2(196, 64), w - 196, enabled)
      sk.lobbyNumber("Map size", config.mapSettings.size, p + vec2(0, 116), w,
        32'i32, 4096'i32, 2'i32, enabled)
      sk.lobbyNumber("Expansions", config.mapSettings.expansions, p + vec2(0, 168), w,
        0'i32, 8'i32, 1'i32, enabled)
      sk.lobbyNumber("Spawn distance", config.mapSettings.minDistance,
        p + vec2(0, 220), w, 1'i32, 4096'i32, 1'i32, enabled)
    else:
      sk.lobbyNumber("War grace (s)", config.diplomacySettings.warGraceSeconds,
        p + vec2(0, 64), w, 1'i32, 300'i32, 1'i32, enabled)
      sk.lobbyNumber("Offer time (s)", config.diplomacySettings.offerSeconds,
        p + vec2(0, 116), w, 1'i32, 600'i32, 5'i32, enabled)
    if showControls:
      if sk.lobbyButton(if page == 1: "Back to match settings" else: "Map generation",
        settingsFooter(at, height).map, w, "terrain", enabled):
        ui.configPage = if page == 1: 0 else: 1
      if sk.lobbyButton(if page == 2: "Back to match settings" else: "Advanced settings",
        settingsFooter(at, height).advanced, w, "settings", enabled):
        ui.configPage = if page == 2: 0 else: 2
    result = config != before
