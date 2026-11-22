import
  bumpy, chroma, pixie, silky, vmath, windy,
  polyworld/[chrome, gameuis, homes, sounds]

type CacHomeAction* = enum
  CacStayHome, CacPlaySingle, CacPlayMultiplayer, CacOpenReplays,
  CacOpenSettings, CacExitGame

proc drawCacHome*(sk: Silky, window: Window, focus: var int): CacHomeAction =
  ## Draws CaC's illustrated menu with a desktop-only replay library entry.
  sk.uiScale = selectedUiScale(max(0.1'f, min(
    window.size.x.float32 / 760, window.size.y.float32 / 940
  )), 1080.0'f / 940)
  sk.beginUi(window, window.size)
  sk.textStyle = "LobbyBody"
  sk.drawHomeBackground(window)
  let
    view = window.size.vec2 / sk.uiScale
    center = view * 0.5'f
    at = center - vec2(270, 280)
    labels =
      when defined(emscripten):
        ["Single Player", "Multiplayer", "Settings"]
      else:
        ["Single Player", "Multiplayer", "Replays", "Settings", "Exit"]
    count = labels.len
  sk.drawSprite("home-shade", center - vec2(500, 440), vec2(1000, 880))
  sk.drawLabel("CARDS AND CASTERS", at - vec2(80, 21), vec2(700, 80),
    rgbx(8, 16, 25, 230), "HomeTitle", CenterAlign)
  sk.drawLabel("CARDS AND CASTERS", at - vec2(80, 24), vec2(700, 80),
    rgbx(245, 225, 181, 255), "HomeTitle", CenterAlign)
  focus = clamp(focus, 0, count - 1)
  if window.buttonPressed[KeyUp]:
    focus = (focus + count - 1) mod count
    playSound(SelectSound)
  if window.buttonPressed[KeyDown] or window.buttonPressed[KeyTab]:
    focus = (focus + 1) mod count
    playSound(SelectSound)
  for index in 0 ..< count:
    let
      point = at + vec2(30, 142 + index.float32 * 80)
      size = vec2(480, 76)
      interaction = sk.interact(rect(point, size), true)
      hovered = interaction in {Hovered, Pressed, Held, Released}
    if hovered and window.mouseDelta != ivec2(0):
      focus = index
    sk.hoverSound(GameUiPanel(origin: point, size: size))
    let
      active = hovered or focus == index
      pressed = interaction in {Pressed, Held}
      tint = if pressed: 205'u8 elif active: 255'u8 else: 218'u8
      inset = if pressed: vec2(2, 1) else: vec2(0)
      ink = if active: rgbx(255, 240, 202, 255)
        else: rgbx(225, 221, 200, 255)
      skin = if index == 0: "home-button-primary" else: "home-button-secondary"
    sk.drawSprite(skin, point + inset, size - inset * 2,
      rgbx(tint, tint, tint, 255))
    sk.drawLabel(labels[index], point + vec2(0, 2), size,
      rgbx(6, 15, 20, 235), "HomeButton", CenterAlign)
    sk.drawLabel(labels[index], point, size, ink, "HomeButton", CenterAlign)
    if interaction == Released or
      (focus == index and window.buttonPressed[KeyEnter]):
        when defined(emscripten):
          result = [CacPlaySingle, CacPlayMultiplayer, CacOpenSettings][index]
        else:
          result = CacHomeAction(index + 1)
        playSound(ClickSound)
