## Main menu, local setup and shared Polyworld room lifecycle for CaC.
import
  std/[os, strutils, tables, uri],
  bumpy, chroma, pixie, silky, vmath, windy,
  polyworld/[renderer, chrome, connections, homes, lobbies, menus, policies,
    roomclients, rooms, sounds, viewers],
  app, core/[battlesetup, sessions, sim], net/[multiplayer, web], ui/controls,
  homes as cacHomes

when not defined(emscripten):
  import polyworld/displays, replaylibraries, replaymenus, replaysettings

const ClassChoices = [Archer, Warrior, Mage]

type
  FrontendKind* = enum
    ExitFrontend, LocalFrontend, NetworkFrontend, ReplayFrontend
  FrontendResult* = object
    kind*: FrontendKind
    seats*: seq[sim.Seat]
    humanSeat*: int
    network*: NetworkMatch
    botSources*, playerNames*: seq[string]
    seed*: int64
    replayPath*: string
  FrontendState = object
    initialized: bool
    setup: BattleSetup
    localPolicies, networkPolicies: seq[LocalPolicy]
    humanSeat: int
    roomName, roomNameDefault: string
    pendingInvite: string
    publicRoom: bool
    browsingReplays: bool
    when not defined(emscripten):
      replayBrowser: ReplayBrowserState

var frontendState: FrontendState

proc eligibleName(name: string): bool =
  ## Require an intentional player identity before joining a room.
  validName(name) and name.len <= 64 and
    name.strip().toLowerAscii() != "player"

proc defaultRoomName(name: string): string =
  ## Names new rooms after the chosen player identity.
  if eligibleName(name): name & "'s room" else: ""

proc bundledPolicies(appDir: string): seq[LocalPolicy] =
  ## Read the same bundled policies on native and browser builds.
  for index, file in DefaultBots:
    let path = appDir / "players" / file
    if fileExists(path):
      result.add LocalPolicy(
        name: ["Archer bot", "Warrior bot", "Mage bot", "Mixed bot"][index],
        bytes: readPolicyBytes(path))

proc policySources(policies: seq[LocalPolicy]): seq[string] =
  ## Pass sources only to local policy compilation, never to the relay.
  for policy in policies:
    result.add policy.bytes

proc localSelection(name: string): FrontendResult =
  ## Pack occupied lobby slots into the game's contiguous player order.
  frontendState.setup.validateBattleSetup()
  result.kind = LocalFrontend
  result.humanSeat = -1
  result.seed = frontendState.setup.seed.int64
  for index, heroClass in frontendState.setup.classes:
    if index == frontendState.humanSeat:
      result.humanSeat = result.seats.len
      result.playerNames.add name
      result.botSources.add ""
    elif frontendState.localPolicies[index].bytes.len > 0:
      result.playerNames.add frontendState.localPolicies[index].name
      result.botSources.add frontendState.localPolicies[index].bytes
    else:
      continue
    result.seats.add precon(heroClass)

proc removePlayerPicker(sk: Silky, window: Window,
    ui: var LobbyUi): SlotChoice =
  ## Lets the host release any guest slot without removing their other seats.
  sk.pushLayer(PopupsLayer)
  let
    view = window.size.vec2 / sk.uiScale
    at = (view - vec2(520, 220)) * 0.5'f
  discard sk.interact(rect(vec2(0), view), true)
  sk.drawRect(vec2(0), view, rgbx(0, 0, 0, 180))
  sk.lobbyPanel(at, vec2(520, 220))
  sk.lobbyLabel("Remove player from this slot?", at + vec2(24, 24), 472,
    "LobbyHeading")
  if sk.lobbyButton("Remove player", at + vec2(24, 132), 226, "minus"):
    result = SlotChoice(chosen: true, clear: true)
  if sk.lobbyButton("Cancel", at + vec2(270, 132), 226, "arrow_left") or
    window.buttonPressed[KeyEscape]:
      ui.selectedSeat = -1
  sk.popLayer()

proc runFrontend*(app: App, connection: var Connection,
    returnToLobby = false): FrontendResult =
  ## Keep the window and room alive while selecting the next playable battle.
  let
    window = app.window
    sk = app.sk
    bots = bundledPolicies(app.appDir)
    initialEntry = not frontendState.initialized
    gameDefaultFont = sk.atlas.fonts["Default"]
    gameHeadingFont = sk.atlas.fonts["H1"]
    gameHudFont = sk.atlas.fonts["Hud"]
    gameSmallFont = sk.atlas.fonts["Small"]
  # A press-activated battle menu may return while its pointer is still held.
  # Drain that input before installing the new screen's release-based buttons.
  window.onFrame = nil
  window.onButtonPress = nil
  while not window.closeRequested and (
    window.buttonDown[MouseLeft] or window.buttonReleased[MouseLeft] or
    window.buttonDown[MouseRight] or window.buttonReleased[MouseRight] or
    window.buttonDown[MouseMiddle] or window.buttonReleased[MouseMiddle]):
      connection.pump()
      pollEvents()
      waitForDisplay()
  # Shared settings need menu-sized fonts; the card HUD keeps larger originals.
  sk.atlas.fonts["Default"] = sk.atlas.fonts["MenuDefault"]
  sk.atlas.fonts["H1"] = sk.atlas.fonts["MenuHeading"]
  sk.atlas.fonts["Hud"] = sk.atlas.fonts["MenuHud"]
  sk.atlas.fonts["Small"] = sk.atlas.fonts["MenuSmall"]
  sk.resetInteractions()
  defer:
    sk.atlas.fonts["Default"] = gameDefaultFont
    sk.atlas.fonts["H1"] = gameHeadingFont
    sk.atlas.fonts["Hud"] = gameHudFont
    sk.atlas.fonts["Small"] = gameSmallFont
  template preferences: untyped = app.preferences
  if not frontendState.initialized:
    frontendState = FrontendState(initialized: true,
      setup: app.options.initialBattleSetup(),
      humanSeat: app.options.initialMenuHumanSeat(), publicRoom: true)
    frontendState.roomNameDefault = defaultRoomName(preferences.name)
    frontendState.roomName = frontendState.roomNameDefault
    when not defined(emscripten):
      frontendState.replayBrowser = initReplayBrowser(Library)
    frontendState.localPolicies.setLen(frontendState.setup.classes.len)
    var botIndex = 0
    for index in 0 ..< frontendState.localPolicies.len:
      if index == frontendState.humanSeat:
        continue
      if botIndex < app.options.botPaths.len:
        let path = app.options.botPaths[botIndex]
        frontendState.localPolicies[index] = LocalPolicy(
          name: path.extractFilename(), bytes: readPolicyBytes(path))
        inc botIndex
      elif bots.len > 0:
        frontendState.localPolicies[index] = bots[index mod bots.len]
  var
    activeConnection = connection
    page = if returnToLobby: LobbyMenu else: HomeMenu
    error = app.preferenceError
    prepared: NetworkMatch
    preparedRevision, viewedRevision: uint32
    viewedPayload, matchName, pendingPayload, pendingName: string
    configDirty, configPending, pendingResize: bool
    lobbyUi = LobbyUi()
    invite = inviteParameter("room")
    joinRequested: bool
    connectRequested: bool
    autoClaim: bool
    homeFocus: int
    playerName = preferences.name
    editingPlayer, localLaunchRequested: bool
    launchLocal, launchNetwork: bool
    launchReplay: bool
    selection: FrontendResult
  when not defined(emscripten):
    template replayBrowser: untyped = frontendState.replayBrowser
    var
      replayAction: ReplayBrowserResult
      retryReplaySave: bool
    replayBrowser.message = if app.replaySaveError.len > 0:
      app.replaySaveError else: error
    replayBrowser.refreshRequested = frontendState.browsingReplays

    proc drawReplayRetry() =
      ## Keeps failed exports available without discarding the completed match.
      if sk.drawReplaySaveRetry(app.unsavedReplays.len > 0):
        retryReplaySave = true

    if app.replaySaveError.len > 0:
      error = app.replaySaveError
  app.preferenceError = ""
  if initialEntry and not returnToLobby:
    let inviteServer = inviteParameter("server")
    if inviteServer.len > 0:
      preferences.server = inviteServer
    if app.options.serverAddress.len > 0:
      preferences.server = app.options.serverAddress
    if app.options.roomCode.len > 0:
      invite = app.options.roomCode
    # Links configure multiplayer, but entering it remains a menu action.
    frontendState.pendingInvite = invite
  if returnToLobby and activeConnection != nil:
    let client = activeConnection.client
    if client.snapshot.participant == client.participant and
      client.snapshot.phase in {rooms.Ended, Desynced}:
        client.send(RoomMessage(kind: ReturnLobby))
        client.error = ""
  var screenshotFrame: int
  when defined(takeScreenshot):
    # Capture fixtures change memory only; saved preferences remain untouched.
    preferences.name = "Player One"
    connectRequested = false
    joinRequested = false
    case getEnv("CAC_CAPTURE_PAGE", "home").toLowerAscii()
    of "home": page = HomeMenu
    of "single": page = SingleMenu
    of "settings": page = SettingsMenu
    of "multiplayer": page = MultiplayerMenu
    of "replays":
      when defined(emscripten):
        raise newException(MenusError, "The replay library is desktop-only")
      else:
        frontendState.browsingReplays = true
        replayBrowser.refreshRequested = true
    of "name":
      page = MultiplayerMenu
      preferences.name = ""
      playerName = ""
    else:
      raise newException(MenusError, "Unknown CAC_CAPTURE_PAGE")
  template presentMenuFrame() =
    ## Capture the rendered back buffer before swapping the hidden window.
    if captureFrame(window, screenshotFrame,
      (when defined(takeScreenshot):
        max(1, parseInt(getEnv("CAC_CAPTURE_FRAME", "20")))
      else: 30), app.appDir / "cac_menu.png"):
        when not defined(emscripten):
          window.closeRequested = true
    else:
      window.presentFrame(framePaceHz)
  while not window.closeRequested and not launchLocal and not launchNetwork and
      not launchReplay:
    when not defined(emscripten):
      window.updateWindowSettings()
      replayAction = ReplayBrowserResult()
      retryReplaySave = false
    let roomNameDefault = defaultRoomName(preferences.name)
    if frontendState.roomName == frontendState.roomNameDefault:
      frontendState.roomName = roomNameDefault
    frontendState.roomNameDefault = roomNameDefault
    if connectRequested and eligibleName(preferences.name):
      connectRequested = false
      try:
        preferences.server = serverUrl(preferences.server)
        preferences.savePreferences(AppName)
        activeConnection.close()
        activeConnection = connect(preferences.server, preferences.name,
          cacIdentity())
        prepared = nil
        preparedRevision = 0
        viewedRevision = 0
        viewedPayload = ""
        configDirty = false
        configPending = false
        pendingResize = false
        pendingPayload = ""
        pendingName = ""
        frontendState.networkPolicies.setLen(0)
        error = ""
      except CatchableError as problem:
        error = problem.msg
    if activeConnection != nil:
      activeConnection.pump()
      let client = activeConnection.client
      if client.welcomed and joinRequested and invite.len > 0 and
        client.snapshot.room.len == 0:
          client.send(RoomMessage(kind: JoinRoom, room: invite))
          joinRequested = false
          frontendState.pendingInvite = ""
      if client.snapshot.room.len == 0 and page == LobbyMenu:
        page = MultiplayerMenu
        prepared = nil
        preparedRevision = 0
        viewedRevision = 0
        viewedPayload = ""
        configDirty = false
        configPending = false
        pendingResize = false
        pendingPayload = ""
        pendingName = ""
        frontendState.networkPolicies.setLen(0)
      if client.snapshot.room.len > 0:
        page = LobbyMenu
        frontendState.publicRoom = client.snapshot.flag
        frontendState.networkPolicies.setLen(client.snapshot.seats.len)
        if viewedRevision != client.snapshot.revision:
          try:
            if configPending and client.snapshot.payload == pendingPayload and
              client.snapshot.name == pendingName:
                # Acknowledgements must preserve edits made while in flight.
                configDirty = frontendState.setup.encodeBattleSetup() !=
                  client.snapshot.payload or matchName != client.snapshot.name
                configPending = false
                pendingResize = false
                pendingPayload = ""
                pendingName = ""
                viewedPayload = client.snapshot.payload
            if viewedPayload != client.snapshot.payload:
              if configDirty and
                client.snapshot.participant == client.participant:
                  configDirty = frontendState.setup.encodeBattleSetup() !=
                    client.snapshot.payload or matchName != client.snapshot.name
              else:
                frontendState.setup = parseBattleSetup(client.snapshot.payload)
                configDirty = false
              viewedPayload = client.snapshot.payload
            if not configDirty and not configPending:
              matchName = client.snapshot.name
            viewedRevision = client.snapshot.revision
          except CatchableError as problem:
            error = problem.msg
        if autoClaim and client.snapshot.phase == rooms.Lobby:
          autoClaim = false
          if client.snapshot.humanSeatFor(client.participant) < 0:
            for index, seat in client.snapshot.seats:
              if seat.owner == 0:
                client.claimHumanSeat(index)
                break
      if client.events.len > 0:
        let event = client.events[0]
        client.events.delete(0)
        if event.kind == BeginMatch:
          try:
            if prepared == nil or preparedRevision != event.revision:
              prepared = prepareNetworkMatch(client,
                frontendState.networkPolicies.policySources())
            prepared.automaticBots = false
            prepared.start(event)
            selection = FrontendResult(kind: NetworkFrontend,
              network: prepared, humanSeat: prepared.humanSeat,
              playerNames: prepared.playerNames)
            launchNetwork = true
          except CatchableError as problem:
            error = problem.msg
            client.send(RoomMessage(kind: AbortMatch,
              match: event.match, detail: error))
      if client.error.len > 0:
        error = client.error
      if client.error.len > 0 or (configPending and not client.connected):
        if configPending and pendingResize and client.error.len > 0:
          let
            published = parseBattleSetup(client.snapshot.payload)
            surviving = frontendState.setup.classes.len
          frontendState.setup.resizeSetup(published.classes.len)
          for index in surviving ..< published.classes.len:
            frontendState.setup.classes[index] = published.classes[index]
          configDirty = frontendState.setup.encodeBattleSetup() !=
            client.snapshot.payload or matchName != client.snapshot.name
        configPending = false
        pendingResize = false
        pendingPayload = ""
        pendingName = ""
    if launchNetwork:
      break
    window.onButtonPress = proc(button: Button) =
      ## Reuse browser-style UI scaling shortcuts on every menu.
      discard window.scaleKey(button, preferences, sk.uiScale, AppName)
    window.onFrame = proc() =
      ## Render one menu state while the outer loop owns network pumping.
      app.beginCaptureFrame()
      # The arena's initialization and last battle leave 3D depth state active.
      prepareUi(sk)
      updateSounds()
      publishStatus(("Cards and Casters / " & $page).cstring)
      let needsName = not eligibleName(preferences.name)
      if editingPlayer or (page == MultiplayerMenu and needsName):
        sk.textStyle = "Default"
        discard sk.beginSettings(window)
        sk.drawHomeBackground(window)
        let
          view = window.size.vec2 / sk.uiScale
          at = (view - vec2(620, 260)) * 0.5'f
          valid = eligibleName(playerName)
        sk.drawRect(vec2(0), view, rgbx(0, 0, 0, 110))
        sk.lobbyPanel(at, vec2(620, 260))
        sk.drawLabel("Choose your player name", at + vec2(24, 20),
          vec2(572, 40), sk.theme.defaultTextColor, "H1")
        sk.menuInput(window, "newPlayerName", playerName,
          at + vec2(24, 80), 572, 44)
        if playerName.len > 0 and not valid:
          sk.drawLabel("Use 1–64 bytes and choose a name other than Player.",
            at + vec2(24, 128), vec2(572, 28), sk.theme.disabledTextColor)
        if sk.lobbyButton("Cancel", at + vec2(24, 188), 180) or
          window.buttonPressed[KeyEscape]:
            editingPlayer = false
            localLaunchRequested = false
            if page == MultiplayerMenu and needsName:
              page = HomeMenu
              connectRequested = false
        elif sk.lobbyButton("Continue", at + vec2(396, 188), 200,
          enabled = valid) or (valid and window.buttonPressed[KeyEnter]):
            try:
              var updated = preferences
              updated.name = playerName
              updated.savePreferences(AppName)
              preferences = updated
              editingPlayer = false
              if localLaunchRequested:
                launchLocal = true
                localLaunchRequested = false
              if activeConnection != nil and
                activeConnection.client.name != preferences.name:
                  activeConnection.client.name = preferences.name
                  activeConnection.reconnectAfter(0)
              error = ""
            except CatchableError as problem:
              error = problem.msg
        if error.len > 0:
          sk.menuLabel(error, at + vec2(0, 272), color = LobbyRed)
        sk.finishUi()
        presentMenuFrame()
        return
      when not defined(emscripten):
        if frontendState.browsingReplays:
          replayAction = sk.drawReplayBrowser(window, replayBrowser)
          sk.finishUi()
          presentMenuFrame()
          return
      if page == HomeMenu:
        case sk.drawCacHome(window, homeFocus)
        of CacStayHome: discard
        of CacPlaySingle:
          page = SingleMenu
          frontendState.localPolicies.setLen(frontendState.setup.classes.len)
          if frontendState.humanSeat >= frontendState.setup.classes.len:
            frontendState.humanSeat = -1
          lobbyUi = LobbyUi()
        of CacPlayMultiplayer:
          page = MultiplayerMenu
          connectRequested = preferences.server.strip().len > 0 and
            (activeConnection == nil or not activeConnection.client.connected)
          if frontendState.pendingInvite.len > 0:
            invite = frontendState.pendingInvite
            joinRequested = true
            autoClaim = true
          lobbyUi = LobbyUi()
        of CacOpenReplays:
          when not defined(emscripten):
            frontendState.browsingReplays = true
            replayBrowser.refreshRequested = true
            replayBrowser.message = ""
        of CacOpenSettings: page = SettingsMenu
        of CacExitGame:
          when not defined(emscripten):
            window.closeRequested = true
        if sk.playerButton(window, preferences.name):
          playerName = preferences.name
          editingPlayer = true
        if error.len > 0:
          sk.menuLabel(error, vec2(24, 24), color = LobbyRed)
        when not defined(emscripten):
          drawReplayRetry()
        sk.finishUi()
        presentMenuFrame()
        return
      var layout: LobbyLayout
      let origin =
        if page == SettingsMenu:
          sk.textStyle = "Default"
          sk.beginLobbySettings(window)
        else:
          layout = sk.beginLobby(window, lobbyUi,
            if page == MultiplayerMenu: "MULTIPLAYER" else: "BATTLE SETUP",
            page == MultiplayerMenu)
          layout.origin
      try:
        case page
        of HomeMenu: discard
        of MultiplayerMenu:
          let
            connected = activeConnection != nil and activeConnection.client.welcomed
            p = layout.origin + vec2(32, 144)
            totalWidth = if layout.compact: 936.0'f else: 1450.0'f
          sk.lobbyPanel(p, vec2(totalWidth, 74))
          sk.lobbyLabel("Server", p + vec2(20, 16), 90, "LobbyBold")
          let previousServer = preferences.server
          sk.lobbyInput(window, "server", preferences.server,
            p + vec2(112, 15), totalWidth - 470)
          if preferences.server != previousServer:
            preferences.savePreferences(AppName)
          if sk.lobbyButton(if connected: "Reconnect" else: "Connect",
            p + vec2(totalWidth - 340, 15), 160):
              connectRequested = true
          sk.lobbyIcon("status", p + vec2(totalWidth - 156, 23), 24,
            if connected: rgbx(130, 215, 110, 255) else: LobbyMuted)
          sk.lobbyLabel(if connected: "Connected" else: "Offline",
            p + vec2(totalWidth - 122, 16), 116)
          sk.lobbyPanel(layout.left, vec2(layout.leftWidth, layout.panelHeight))
          let list = layout.left + vec2(22)
          sk.lobbyIcon("units", list + vec2(0, 8), 38)
          sk.lobbyLabel("PUBLIC ROOMS", list + vec2(50, 0), 500,
            "LobbyHeading")
          sk.lobbyLabel("Rooms for this game version", list + vec2(50, 38),
            500, tint = LobbyMuted)
          if sk.lobbyButton("Refresh", list + vec2(layout.leftWidth - 204, 6),
            160, "loop", connected):
              activeConnection.client.send(RoomMessage(kind: ListRooms))
          sk.lobbyIcon("search", list + vec2(4, 94))
          sk.lobbyInput(window, "roomSearch", lobbyUi.search,
            list + vec2(44, 84), layout.leftWidth - 88)
          sk.lobbyLabel("ROOM", list + vec2(0, 136), 360, tint = LobbyMuted)
          sk.lobbyLabel("PLAYERS", list + vec2(390, 136), 130,
            tint = LobbyMuted)
          sk.lobbyLabel("STATUS", list + vec2(540, 136), 130,
            tint = LobbyMuted)
          var matches: seq[int]
          if connected:
            for i, room in activeConnection.client.listings:
              if lobbyUi.search.toLowerAscii() in room.name.toLowerAscii():
                matches.add i
          let
            rowsAt = list + vec2(0, 184)
            rowsSize = vec2(layout.leftWidth - 44, layout.panelHeight - 268)
            contentSize = vec2(rowsSize.x, matches.len.float32 * 68)
          if lobbyUi.roomScroll == nil:
            lobbyUi.roomScroll = FrameState()
          lobbyUi.roomListOverflow = contentSize.y > rowsSize.y
          sk.frameScrollbars(window, lobbyUi.roomScroll,
            rect(rowsAt, rowsSize), contentSize, vec2(1))
          sk.pushClipRect(rect(rowsAt, rowsSize - vec2(14, 0)))
          let rowsOrigin = rowsAt - lobbyUi.roomScroll.scrollPos
          for row in 0 ..< matches.len:
            let
              room = activeConnection.client.listings[matches[row]]
              point = rowsOrigin + vec2(0, row.float32 * 68)
              watching = room.phase != rooms.Lobby or room.occupied == room.seats
            sk.lobbyPanel(point, vec2(rowsSize.x - 16, 60), true)
            sk.lobbyLabel(room.name, point + vec2(12, 10), 365, "LobbyBold")
            sk.lobbyLabel($room.occupied & " / " & $room.seats,
              point + vec2(390, 10), 130)
            sk.lobbyIcon("status", point + vec2(540, 20), 20,
              if watching: LobbyMuted else: rgbx(130, 215, 110, 255))
            sk.lobbyLabel(if room.phase != rooms.Lobby: $room.phase
              elif watching: "Full" else: "Open", point + vec2(570, 10), 120)
            if sk.lobbyButton(if watching: "Watch" else: "Join",
              point + vec2(rowsSize.x - 156, 8), 128, "arrow_right"):
                activeConnection.client.send(RoomMessage(kind: JoinRoom, room: room.id))
                autoClaim = not watching
                lobbyUi.scroll = 0
          sk.popClipRect()
          if matches.len == 0:
            sk.lobbyLabel(if connected: "No rooms found. Create one to begin."
              elif error.len > 0: error
              else: activeConnection.status(),
              list + vec2(12, 200), layout.leftWidth - 68, tint = LobbyMuted)
            if not connected:
              sk.lobbyLabel("Plain server: ws://host:port/ws",
                list + vec2(12, 240), layout.leftWidth - 68, tint = LobbyMuted)
              sk.lobbyLabel("wss:// requires a server with TLS enabled.",
                list + vec2(12, 278), layout.leftWidth - 68, tint = LobbyMuted)
          sk.lobbyLabel($matches.len & " rooms",
            list + vec2(0, layout.panelHeight - 68), 300)
          sk.lobbyPanel(layout.right, vec2(layout.rightWidth, layout.panelHeight))
          let
            create = layout.right + vec2(22)
            width = layout.rightWidth - 44
          sk.lobbyIcon("cross", create + vec2(0, 8), 32)
          sk.lobbyLabel("CREATE ROOM", create + vec2(44, 0), width - 44,
            "LobbyHeading")
          sk.lobbyLabel("Room name", create + vec2(0, 52), width)
          sk.lobbyInput(window, "frontendState.roomName", frontendState.roomName,
            create + vec2(0, 96), width)
          sk.lobbyLabel("Visibility", create + vec2(0, 146), width)
          if sk.lobbyButton("Public", create + vec2(0, 190),
            width / 2 - 6, "globe", selected = frontendState.publicRoom):
              frontendState.publicRoom = true
          if sk.lobbyButton("Private", create + vec2(width / 2 + 6, 190),
            width / 2 - 6, "lock", selected = not frontendState.publicRoom):
              frontendState.publicRoom = false
          sk.lobbyLabel(if frontendState.publicRoom: "Listed in public rooms."
            else: "Only people with an invite can join.",
            create + vec2(0, 238), width, tint = LobbyMuted)
          if sk.lobbyButton("Create Room", create + vec2(0, 288), width,
            "cross", connected and frontendState.roomName.strip().len > 0):
              activeConnection.client.send(RoomMessage(
                kind: CreateRoom, name: frontendState.roomName, number: frontendState.setup.classes.len.uint32,
                tickRate: uint32(CacNetworkTickRate), flag: frontendState.publicRoom,
                payload: frontendState.setup.encodeBattleSetup()
              ))
              autoClaim = true
              lobbyUi.scroll = 0
          sk.lobbyIcon("link", create + vec2(0, 368))
          sk.lobbyLabel("JOIN BY INVITE", create + vec2(44, 360), width - 44,
            "LobbyHeading")
          sk.lobbyLabel("Invite link or room code", create + vec2(0, 410), width)
          sk.lobbyInput(window, "inviteRoom", invite,
            create + vec2(0, 456), width)
          if sk.lobbyButton("Join Room", create + vec2(0, layout.panelHeight - 72), width,
            "arrow_right", connected and invite.strip().len > 0):
              if invite.contains("?"):
                let parsed = parseUri(invite)
                for key, value in decodeQuery(parsed.query):
                  if key == "room":
                    invite = value
              joinRequested = true
              autoClaim = true
              lobbyUi.scroll = 0
          if sk.lobbyButton("Back", layout.footer, 190, "arrow_left"):
            activeConnection.close()
            activeConnection = nil
            error = ""
            page = HomeMenu
        of SingleMenu, LobbyMenu:
          let
            online = page == LobbyMenu
            client = if online: activeConnection.client else: nil
            snapshot = if online: client.snapshot else: RoomMessage()
            editable = not online or (client.connected and client.welcomed and
              snapshot.phase == rooms.Lobby)
            owner = not online or snapshot.participant == client.participant
            modal = lobbyUi.selectedSeat >= 0
            count = frontendState.setup.classes.len
            rosterPending = online and (count != snapshot.seats.len or
              (configPending and pendingResize))
          sk.lobbyPanel(layout.left, vec2(layout.leftWidth, layout.panelHeight))
          sk.lobbyIcon("units", layout.left + vec2(24, 26), 34)
          sk.lobbyLabel("PLAYERS", layout.left + vec2(70, 22), 400,
            "LobbyHeading")
          sk.lobbyLabel("CLASS / DECK", layout.left +
            vec2(layout.leftWidth - 240, 22), 210, "LobbyHeading")
          var
            emptyCount, ownCount, occupied: int
            selfReady: bool
          for index in 0 ..< count:
            let
              exists = not online or index < snapshot.seats.len
              seat = if online and exists: snapshot.seats[index]
                else: rooms.Seat()
              empty = if online: seat.owner == 0
                else: index != frontendState.humanSeat and
                  frontendState.localPolicies[index].bytes.len == 0
              mine = not online or seat.owner == client.participant
              human = if online: seat.kind == HumanSeat
                else: index == frontendState.humanSeat
              at = layout.left + vec2(22, 84 + index.float32 * 72)
              seatWidth = layout.leftWidth - 294
            var
              name = if empty: "Add player"
                elif human:
                  if eligibleName(preferences.name): preferences.name
                  else: "Choose name"
                elif online: seat.name
                else: frontendState.localPolicies[index].name
              controller = if not exists: "Updating room slots..."
                elif empty: "Empty slot" elif human: "HUMAN" else: "BOT"
            if empty:
              inc emptyCount
            else:
              inc occupied
            if online and not empty:
              for participant in snapshot.participants:
                if participant.id == seat.owner:
                  controller = participant.name &
                    (if participant.ready: " / Ready" else: " / Not ready")
                  if human:
                    name = participant.name
                  if mine:
                    selfReady = participant.ready
              if mine:
                inc ownCount
            if sk.lobbyButton("", at, seatWidth,
              enabled = editable and exists and
                (empty or mine or owner) and
                not modal and not rosterPending, height = 62):
                  lobbyUi.selectedSeat = index
            sk.lobbyLabel($(index + 1), at + vec2(10, 10), 32,
              "LobbyBold", LobbyMuted)
            sk.lobbyIcon(if empty: "cross" elif human: "character"
              else: "settings", at + vec2(44, 17), 28)
            sk.lobbyLabel(name, at + vec2(86, 0), seatWidth - 126,
              "LobbyBold", if empty: LobbyMuted else: rgbx(240, 237, 225, 255))
            sk.lobbyLabel(controller, at + vec2(86, 26), seatWidth - 126,
              tint = LobbyMuted)
            let previousClass = frontendState.setup.classes[index]
            sk.lobbySelect(window, frontendState.setup.classes[index],
              ClassChoices, at + vec2(seatWidth + 18, 8), 220,
              editable and owner and not modal)
            if previousClass != frontendState.setup.classes[index]:
              configDirty = online
          let fill = layout.left + vec2(22, layout.panelHeight - 98)
          if sk.lobbyButton("Fill empty slots with bots", fill, 340,
            "settings", editable and emptyCount > 0 and bots.len > 0 and
              not modal and not rosterPending):
                for index in 0 ..< count:
                  let bot = bots[frontendState.setup.classes[index].ord mod
                    bots.len]
                  if online:
                    if index < snapshot.seats.len and
                      snapshot.seats[index].owner == 0:
                        frontendState.networkPolicies[index] = bot
                        client.send(RoomMessage(kind: ClaimSeat,
                          seat: index.uint32, seatKind: BotSeat,
                          name: bot.name))
                  elif index != frontendState.humanSeat and
                    frontendState.localPolicies[index].bytes.len == 0:
                      frontendState.localPolicies[index] = bot
          sk.lobbyLabel(if online: snapshot.name & " / " & $snapshot.phase
            elif frontendState.humanSeat < 0: "Spectating bots"
            else: "Playing seat " & $(frontendState.humanSeat + 1),
            fill + vec2(0, 46), layout.leftWidth - 44, tint = LobbyMuted)
          sk.lobbyPanel(layout.right, vec2(layout.rightWidth, layout.panelHeight))
          let
            options = layout.right + vec2(22)
            width = layout.rightWidth - 44
            controls = owner and editable and not modal
          sk.lobbyLabel("BATTLE SETTINGS", options, width, "LobbyHeading")
          if online:
            sk.lobbyLabel("Room name", options + vec2(0, 56), width)
            let previousName = matchName
            if controls:
              sk.lobbyInput(window, "matchName", matchName,
                options + vec2(0, 100), width)
            else:
              sk.lobbyLabel(matchName, options + vec2(0, 100), width)
            if previousName != matchName:
              configDirty = true
          else:
            sk.lobbyLabel("Choose your hero and opponents.",
              options + vec2(0, 68), width, tint = LobbyMuted)
            sk.lobbyLabel("Each hero starts with a 40-card deck.",
              options + vec2(0, 108), width, tint = LobbyMuted)
          var slots = count
          sk.lobbyNumber("Player slots", slots, options + vec2(0, 176),
            width, 2, 7, 1, controls)
          if slots != count:
            frontendState.setup.resizeSetup(slots)
            if not online:
              frontendState.localPolicies.setLen(slots)
              if frontendState.humanSeat >= slots:
                frontendState.humanSeat = -1
            configDirty = online
          let previousSeed = frontendState.setup.seed
          sk.lobbyNumber("Seed", frontendState.setup.seed,
            options + vec2(0, 238), width, 0'i32, int32.high, 1'i32, controls)
          let previousLimit = frontendState.setup.maxActions
          if online:
            sk.lobbyNumber("Action limit", frontendState.setup.maxActions,
              options + vec2(0, 300), width, 1000'u32, 1_000_000'u32,
              1000'u32, controls)
          if previousSeed != frontendState.setup.seed or
            previousLimit != frontendState.setup.maxActions:
              configDirty = online
          sk.lobbyLabel(
            if online and not validName(matchName): "Enter a room name."
            elif online and matchName.len > 96: "Room name is too long."
            else: "Two to seven players. Empty slots sit out.",
            options + vec2(0, 382), width, tint = LobbyMuted)
          sk.lobbyLabel(if occupied <= 2: "Map: Tower Arena"
            else: "Map: Ring Arena",
            options + vec2(0, 422), width, tint = LobbyMuted)
          sk.lobbyLabel(if online: "Ready is optional. The host can start anytime."
            else: "Clear your human slot to watch the bots.",
            options + vec2(0, 462), width, tint = LobbyMuted)
          when not defined(emscripten):
            if sk.drawReplaySaveOption(
              window, options + vec2(0, 510),
              app.replayPreferences.saveReplay, not modal, width
            ):
              app.replayPreferences.saveReplayPreferences()
          if online:
            configDirty = frontendState.setup.encodeBattleSetup() !=
              snapshot.payload or matchName != snapshot.name
            if sk.lobbyButton("Copy invite", layout.footer + vec2(204, 0),
              200, "link", not modal):
                copyInvite(inviteBase() & "?server=" &
                  encodeUrl(preferences.server) & "&room=" &
                  encodeUrl(snapshot.room))
            if sk.lobbyButton(if selfReady: "Ready" else: "Ready up",
              layout.footer + vec2(420, 0), 190, "status",
              editable and ownCount > 0 and not modal,
              iconTint = readinessColor(selfReady)):
                client.error = ""
                error = ""
                client.send(RoomMessage(kind: ReadyStatus, flag: not selfReady))
            if owner:
              if sk.lobbyButton("Start Game", layout.primary, 250,
                "arrow_right", editable and not configDirty and
                  not configPending and
                  not modal and
                  occupied in MinBattlePlayers .. MaxBattlePlayers):
                    client.error = ""
                    error = ""
                    prepared = client.requestStart(
                      frontendState.networkPolicies.policySources())
                    preparedRevision = prepared.revision
            if sk.lobbyButton(if owner and
              snapshot.phase in {rooms.Ended, Desynced}: "Return to lobby"
              else: "Leave room", layout.footer, 190, "arrow_left", not modal):
                if owner and snapshot.phase in {rooms.Ended, Desynced}:
                  client.send(RoomMessage(kind: ReturnLobby))
                else:
                  client.send(RoomMessage(kind: LeaveRoom))
                  page = MultiplayerMenu
                  prepared = nil
                  preparedRevision = 0
                  viewedRevision = 0
                  viewedPayload = ""
                  configDirty = false
                  configPending = false
                  pendingResize = false
                  pendingPayload = ""
                  pendingName = ""
                  frontendState.networkPolicies.setLen(0)
                  lobbyUi = LobbyUi()
                client.error = ""
                error = ""
          else:
            if sk.lobbyButton("Back", layout.footer, 190, "arrow_left",
              not modal):
                page = HomeMenu
            if sk.lobbyButton("Start Game", layout.primary, 250,
              "arrow_right", occupied >= 2 and not modal):
                frontendState.setup.validateBattleSetup()
                if frontendState.humanSeat >= 0 and
                  not eligibleName(preferences.name):
                    editingPlayer = true
                    localLaunchRequested = true
                else:
                  launchLocal = true
          let selectedSeat = lobbyUi.selectedSeat
          let foreignSeat = online and selectedSeat in 0 ..< snapshot.seats.len and
            snapshot.seats[selectedSeat].owner notin [0'u32, client.participant]
          let choice =
            if foreignSeat: sk.removePlayerPicker(window, lobbyUi)
            elif selectedSeat >= 0: sk.seatPicker(window, lobbyUi, bots)
            else: SlotChoice()
          if choice.chosen:
            var selected = if choice.file: selectPolicy()
              elif choice.human or choice.clear: LocalPolicy()
              else: bots[choice.bot]
            if not choice.file or selected.bytes.len > 0:
              if selected.bytes.isPackage():
                selected.bytes = loadPolicy(selected.bytes).source
              if online:
                if selectedSeat notin 0 ..< snapshot.seats.len:
                  raise newException(MenusError, "This player slot has changed")
                if choice.human:
                  client.claimHumanSeat(selectedSeat,
                    snapshot.humanSeatFor(client.participant))
                  for index, seat in snapshot.seats:
                    if seat.owner == client.participant and
                      seat.kind == HumanSeat:
                        frontendState.networkPolicies[index] = LocalPolicy()
                else:
                  client.send(RoomMessage(
                    kind: if choice.clear: ReleaseSeat else: ClaimSeat,
                    seat: selectedSeat.uint32, seatKind: BotSeat,
                    name: selected.name))
                frontendState.networkPolicies[selectedSeat] = selected
              else:
                if choice.human:
                  if frontendState.humanSeat >= 0 and
                    frontendState.humanSeat != selectedSeat:
                      frontendState.localPolicies[frontendState.humanSeat] =
                        LocalPolicy()
                  frontendState.humanSeat = selectedSeat
                elif frontendState.humanSeat == selectedSeat:
                  frontendState.humanSeat = -1
                frontendState.localPolicies[selectedSeat] = selected
              lobbyUi.selectedSeat = -1
          if online and page == LobbyMenu and owner and editable and
            configDirty and not configPending and validName(matchName) and
            matchName.len <= 96:
              # Publish the latest edits once the previous update is confirmed.
              pendingPayload = frontendState.setup.encodeBattleSetup()
              pendingName = matchName
              pendingResize = frontendState.setup.classes.len !=
                snapshot.seats.len
              client.error = ""
              error = ""
              client.send(RoomMessage(
                kind: if pendingResize: ResizeRoom else: ConfigureRoom,
                name: pendingName,
                number: frontendState.setup.classes.len.uint32,
                tickRate: CacNetworkTickRate.uint32,
                flag: frontendState.publicRoom,
                payload: pendingPayload))
              configPending = true
        of SettingsMenu:
          let height = max(440.0'f,
            window.size.y.float32 / sk.uiScale - origin.y - 50)
          if sk.settingsPanel(window, preferences, AppName, origin, "", height,
            controls = CacControlProfile):
            page = HomeMenu
      except CatchableError as problem:
        error = problem.msg
      if page in {SingleMenu, MultiplayerMenu, LobbyMenu, SettingsMenu} and
        lobbyUi.selectedSeat == -1 and sk.playerButton(window, preferences.name,
          page != LobbyMenu or activeConnection.client.snapshot.phase ==
            rooms.Lobby):
              playerName = preferences.name
              editingPlayer = true
      if error.len > 0:
        sk.lobbyLabel(error, vec2(24, 0), 1400, tint = LobbyRed)
      when not defined(emscripten):
        drawReplayRetry()
      sk.textStyle = "Default"
      sk.finishUi()
      presentMenuFrame()
    pollEvents()
    waitForDisplay()
    when not defined(emscripten):
      if retryReplaySave:
        app.retryPendingReplays()
        error = app.replaySaveError
        replayBrowser.refreshRequested = true
      if frontendState.browsingReplays:
        let selected = replayBrowser.updateReplayBrowser(Library, replayAction)
        case selected.action
        of BackFromReplays:
          frontendState.browsingReplays = false
          sk.resetInteractions()
        of PlayReplay:
          selection = FrontendResult(kind: ReplayFrontend,
            replayPath: selected.path)
          launchReplay = true
        else:
          discard
  window.onFrame = nil
  window.onButtonPress = nil
  if launchLocal:
    selection = localSelection(preferences.name)
    activeConnection.close()
    activeConnection = nil
  elif not launchNetwork:
    activeConnection.close()
    activeConnection = nil
  connection = activeConnection
  result = selection
