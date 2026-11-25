from polyworld/renderer import beginGameUi
import
  chroma, pixie, silky, vmath, windy,
  polyworld/[chrome, gameuis, sounds]
import polyworld/homes as sharedHomes
import assets

export sharedHomes except MenuImages

const
  HomeSize = vec2(1672, 941)
  DesktopLabels = ["Single Player", "Multiplayer", "Replays", "Settings", "Exit"]
  DesktopImages = [
    "button-single-player", "button-multiplayer", "button-settings",
    "button-settings", "button-exit"
  ]

type GotaHomeAction* = enum
  GotaStayHome, GotaPlaySingle, GotaPlayMultiplayer, GotaOpenReplays,
  GotaOpenSettings, GotaExitGame

proc addHomeAssets*(builder: AtlasBuilder) =
  ## Keeps GotA asset selection behind its existing frontend API.
  sharedHomes.addHomeAssets(builder, MenuRoot, assets.MenuImages)

proc drawGotaHome*(sk: Silky, window: Window, focus: var int): GotaHomeAction =
  ## Adds the desktop replay library while preserving the shared browser menu.
  when defined(emscripten):
    case sharedHomes.drawHome(sk, window, focus)
    of StayHome: GotaStayHome
    of PlaySingle: GotaPlaySingle
    of PlayMultiplayer: GotaPlayMultiplayer
    of OpenSettings: GotaOpenSettings
    of ExitGame: GotaExitGame
  else:
    sk.uiScale = selectedUiScale(max(0.1'f, min(
      window.size.x.float32 / 720,
      window.size.y.float32 / HomeSize.y
    )), 1080.0'f / HomeSize.y)
    sk.beginGameUi(window, window.size)
    sk.mousePos = window.mousePos.vec2 / sk.uiScale
    let
      view = window.size.vec2 / sk.uiScale
      origin = (view - HomeSize) * 0.5'f
    sk.drawHomeBackground(window)
    sk.drawSprite("home-shade", origin + vec2(386, 95), vec2(900, 850))
    sk.drawSprite("home-logo", origin + vec2(536, 30), vec2(600, 400))
    sk.drawLabel("Polyworld", origin + vec2(536, 437), vec2(600, 36),
      rgbx(222, 222, 218, 255), "Bold", CenterAlign)
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
          result = GotaHomeAction(index + 1)
          playSound(ClickSound)
