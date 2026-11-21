## Game-specific art and startup routing over the shared main menu.
proc opensMultiplayer*(room: string, configuredServer = ""): bool =
  ## Explicit server launches and room invites open the multiplayer menu.
  room.len > 0 or configuredServer.len > 0

when not defined(headless):
  import
    chroma, pixie, silky, vmath, windy,
    polyworld/[chrome, gameuis, menus, sounds],
    polyworld/homes as sharedHomes, assets
  export sharedHomes

  const
    HomeSize = vec2(1672, 941)
    DesktopLabels = ["Single Player", "Multiplayer", "Replays", "Settings", "Exit"]
    DesktopImages = [
      "button-single-player", "button-multiplayer", "button-settings",
      "button-settings", "button-exit"
    ]

  type LvdHomeAction* = enum
    LvdStayHome, LvdPlaySingle, LvdPlayMultiplayer, LvdOpenReplays,
    LvdOpenSettings, LvdExitGame

  proc drawLvdHome*(sk: Silky, window: Window, focus: var int): LvdHomeAction =
    ## Keeps LvD's compact branding and exposes the replay library on desktop.
    when defined(emscripten):
      case sharedHomes.drawHome(sk, window, focus, compact = true)
      of StayHome: LvdStayHome
      of PlaySingle: LvdPlaySingle
      of PlayMultiplayer: LvdPlayMultiplayer
      of OpenSettings: LvdOpenSettings
      of ExitGame: LvdExitGame
    else:
      sk.uiScale = selectedUiScale(max(0.1'f, min(
        window.size.x.float32 / 720,
        window.size.y.float32 / HomeSize.y
      )), 1080.0'f / HomeSize.y)
      sk.beginUi(window, window.size)
      sk.mousePos = window.mousePos.vec2 / sk.uiScale
      let
        view = window.size.vec2 / sk.uiScale
        origin = (view - HomeSize) * 0.5'f
      sk.drawHomeBackground(window)
      sk.drawSprite("home-shade", origin + vec2(386, 95), vec2(900, 850))
      sk.drawSprite("home-logo", origin + vec2(536, 105), vec2(600, 400))
      focus = clamp(focus, 0, DesktopLabels.high)
      if window.buttonPressed[KeyUp]:
        focus = (focus + DesktopLabels.len - 1) mod DesktopLabels.len
        playSound(SelectSound)
      if window.buttonPressed[KeyDown] or window.buttonPressed[KeyTab]:
        focus = (focus + 1) mod DesktopLabels.len
        playSound(SelectSound)
      for index, label in DesktopLabels:
        let
          at = origin + vec2(596, 490 + index.float32 * 80)
          size = vec2(480, 70)
          panel = GameUiPanel(origin: at, size: size)
          hovered = panel.contains(sk.mousePos)
        if hovered and window.mouseDelta != ivec2(0):
          focus = index
        sk.hoverSound(panel)
        let
          tint = if hovered or focus == index: 255'u8 else: 226'u8
          ink =
            if index == 0: rgbx(39, 24, 10, 255)
            else: rgbx(255, 242, 213, 255)
        sk.drawSprite("home-" & DesktopImages[index], at, size,
          rgbx(tint, tint, tint, 255))
        sk.drawLabel(label, at, size, ink, "H1", CenterAlign)
        if (hovered and window.buttonReleased[MouseLeft]) or
          (focus == index and window.buttonPressed[KeyEnter]):
            result = LvdHomeAction(index + 1)
            playSound(ClickSound)

  proc effectivePreferences*(stored: Preferences, queryServer,
    configuredServer: string): Preferences =
    ## Resolves preferences loaded at startup or after returning from a match.
    result = stored
    if queryServer.len > 0:
      result.server = queryServer
    elif configuredServer.len > 0:
      result.server = configuredServer

  proc addHomeAssets*(builder: AtlasBuilder) =
    ## Packs LvD artwork into the common menu atlas.
    sharedHomes.addHomeAssets(builder, assets.MenuRoot, assets.MenuImages)
