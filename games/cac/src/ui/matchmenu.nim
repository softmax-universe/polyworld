import
  std/tables,
  pixie, silky, vmath, windy,
  polyworld/[chrome, connections, inputs, lobbies, menus, rooms, roomclients,
    sounds],
  ../app, ../net/multiplayer, controls

const
  BattleMenuSize = vec2(520, 560)
  BattleMenuInset = vec2(32)
  BattleMenuWidth = 456'f
  BattleMenuGold = rgbx(215, 181, 112, 255)
  BattleMenuIvory = rgbx(244, 228, 192, 255)
  BattleMenuMuted = rgbx(178, 177, 161, 255)

type
  MatchMenuPage = enum
    MenuHidden, MenuBattle, MenuSettings
  MatchMenu* = object
    page, previousPage: MatchMenuPage
    origin: Vec2
    paused*: bool
    waitingToLeave: bool

proc visible*(menu: MatchMenu): bool =
  ## Reports whether the overlay owns gameplay input.
  menu.page != MenuHidden

proc handleEscape*(menu: var MatchMenu, window: Window,
    cancelingAction: bool) =
  ## Lets targeting consume Escape before opening the battle menu.
  if menu.waitingToLeave or not window.actionPressed(MenuInput):
    return
  case menu.page
  of MenuSettings:
    playSound(CancelSound)
    menu.page = MenuBattle
  of MenuBattle:
    playSound(CancelSound)
    menu.page = MenuHidden
  of MenuHidden:
    if not cancelingAction:
      menu.page = MenuBattle

proc beginFrame*(menu: var MatchMenu, app: App) =
  ## Starts one UI input frame for the battle or its active modal.
  let
    sk = app.sk
    window = app.window
  if menu.page != menu.previousPage:
    sk.resetInteractions()
    menu.previousPage = menu.page
  if not menu.visible:
    sk.beginUi(window, window.size)
    return
  menu.origin = sk.beginOverlay(window,
    if menu.page == MenuSettings: vec2(768, 488) else: BattleMenuSize)
  if menu.page == MenuSettings:
    menu.origin += vec2(24)

proc draw*(menu: var MatchMenu, app: App) =
  ## Draws only the active modal inside the current UI input frame.
  if not menu.visible:
    return
  let
    sk = app.sk
    window = app.window
    origin = menu.origin
    gameDefaultFont = sk.atlas.fonts["Default"]
    gameHeadingFont = sk.atlas.fonts["H1"]
    gameHudFont = sk.atlas.fonts["Hud"]
    gameSmallFont = sk.atlas.fonts["Small"]
  sk.atlas.fonts["Default"] = sk.atlas.fonts["MenuDefault"]
  sk.atlas.fonts["H1"] = sk.atlas.fonts["MenuHeading"]
  sk.atlas.fonts["Hud"] = sk.atlas.fonts["MenuHud"]
  sk.atlas.fonts["Small"] = sk.atlas.fonts["MenuSmall"]
  defer:
    sk.atlas.fonts["Default"] = gameDefaultFont
    sk.atlas.fonts["H1"] = gameHeadingFont
    sk.atlas.fonts["Hud"] = gameHudFont
    sk.atlas.fonts["Small"] = gameSmallFont
  if menu.waitingToLeave and (not app.network.client.connected or
      app.network.client.snapshot.phase in {Ended, Desynced, Lobby}):
    app.returnToMenu = true
    return
  if menu.page == MenuSettings:
    sk.lobbyPanel(origin - vec2(24), vec2(768, 488))
    if sk.settingsPanel(window, app.preferences, AppName, origin,
        controls = CacControlProfile):
      menu.page = MenuBattle
    return
  let
    network = app.network
    online = network != nil
    paused = if online: network.client.snapshot.flag else: menu.paused
    active = online and network.client.snapshot.phase in {Playing, Waiting}
    spectator = online and network.isSpectator
    canPause = not online or (active and not spectator)
    content = origin + BattleMenuInset
  sk.lobbyPanel(origin, BattleMenuSize)
  sk.drawLabel("CARDS AND CASTERS", content - vec2(0, 6),
    vec2(BattleMenuWidth, 24), BattleMenuGold, "Small", CenterAlign)
  sk.drawLabel("BATTLE MENU", content + vec2(0, 20),
    vec2(BattleMenuWidth, 42), BattleMenuIvory, "MenuDisplay", CenterAlign)
  sk.drawLabel(
    if menu.waitingToLeave: "Ending the match..."
    elif online and not network.client.connected: "Connection lost"
    elif paused: "Battle paused"
    elif online and not active: "Match finished"
    elif online and network.client.snapshot.phase == Waiting:
      "Waiting for players"
    elif spectator: "Spectating an online battle"
    elif online: "Online battle in progress"
    else: "Local battle in progress",
    content + vec2(0, 62), vec2(BattleMenuWidth, 28),
    BattleMenuMuted, "Default", CenterAlign)
  sk.drawRect(content + vec2(104, 94),
    vec2(BattleMenuWidth - 208, 1), rgbx(215, 181, 112, 90))
  if sk.lobbyButton("Resume", origin + vec2(32, 132), BattleMenuWidth,
      "play", enabled = not menu.waitingToLeave, height = 58,
      iconTint = BattleMenuGold):
    if paused:
      if online and canPause:
        network.client.send(RoomMessage(kind: PauseMatch,
          match: network.client.match, flag: false))
      elif not online:
        menu.paused = false
    menu.page = MenuHidden
  if sk.lobbyButton(if paused: "Unpause battle" else: "Pause battle",
      origin + vec2(32, 202), BattleMenuWidth,
      if paused: "play" else: "pause",
      enabled = canPause and not menu.waitingToLeave, height = 48):
    if online:
      network.client.send(RoomMessage(kind: PauseMatch,
        match: network.client.match, flag: not paused))
    else:
      menu.paused = not menu.paused
  if sk.lobbyButton("Settings", origin + vec2(32, 262), BattleMenuWidth,
      "settings", enabled = not menu.waitingToLeave, height = 48):
    menu.page = MenuSettings
  sk.drawRect(origin + vec2(32, 326), vec2(BattleMenuWidth, 1),
    rgbx(215, 181, 112, 60))
  let leaveText =
    if not online: "Return to main menu"
    elif spectator: "Leave match"
    elif active: "End match and return"
    elif network.client.snapshot.participant == network.client.participant:
      "Return room to lobby"
    else: "Back to multiplayer"
  if sk.lobbyButton(leaveText, origin + vec2(32, 338), BattleMenuWidth,
      "arrow_left", enabled = not menu.waitingToLeave, height = 48,
      tint = rgbx(218, 220, 220, 255)):
    if online:
      if spectator:
        network.client.send(RoomMessage(kind: LeaveRoom))
      elif active:
        network.abort("Ended the match from the battle menu.")
        menu.waitingToLeave = network.client.connected
      app.connection.pump()
    if not menu.waitingToLeave:
      app.returnToMenu = true
  sk.drawLabel(
    if menu.waitingToLeave:
      "Waiting for the server to confirm."
    elif active and not spectator:
      "Leaving ends the battle for every player."
    elif spectator: "Leaving will not interrupt the battle."
    elif online and not active: "Return to the lobby to set up another battle."
    elif paused: "Resume when you are ready to continue."
    else: "Use Pause battle to stop the game.",
    origin + vec2(32, 410), vec2(BattleMenuWidth, 28),
    BattleMenuMuted, "Default", CenterAlign)
  sk.drawLabel(menuShortcut() & " closes this menu",
    origin + vec2(32, 482), vec2(BattleMenuWidth, 24),
    BattleMenuGold, "Small", CenterAlign)
