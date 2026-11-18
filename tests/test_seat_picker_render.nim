## Exercises the production seat picker through native pointer input.
import
  std/importutils,
  bumpy, opengl, silky, vmath, windy, windy/internal,
  polyworld/[lobbies, menus, viewers]

privateAccess(Window)

let window = newWindow("Seat picker", ivec2(1000, 800), visible = false)
window.makeContextCurrent()
loadExtensions()
let builder = newHudAtlas(2048)
builder.addDefaultFonts()
builder.addLobbyFonts()
let sk = newSilky(window, builder.atlasImage, builder.atlas)
sk.applyThemePatches()
sk.textStyle = "LobbyBody"
var
  ui = LobbyUi(selectedSeat: 0)
  drawFill: bool
  fillEnabled = true
  fillAt = vec2(270, 705)
  bots = @[
    LocalPolicy(name: "Base bot"),
    LocalPolicy(name: "Rusher"),
    LocalPolicy(name: "Puller"),
    LocalPolicy(name: "Jev"),
    LocalPolicy(name: "Khors"),
    LocalPolicy(name: "Lane Sustain"),
    LocalPolicy(name: "Red Kite"),
    LocalPolicy(name: "Black Kite"),
    LocalPolicy(name: "Co-gas")
  ]

proc frame(point: Vec2, pressed = false, released = false,
    escape = false): SlotChoice =
  ## Sends one frame of pointer input to the real modal and dropdown.
  window.state.perFrame = PerFrame()
  window.state.buttonDown = {}
  if pressed:
    window.state.perFrame.buttonPressed = {MouseLeft}
    window.state.buttonDown = {MouseLeft}
  if released:
    window.state.perFrame.buttonReleased = {MouseLeft}
  if escape:
    window.state.perFrame.buttonPressed = {KeyEscape}
  sk.beginUi(window, window.size)
  sk.mousePos = point
  if drawFill:
    var names: seq[string]
    for bot in bots:
      names.add bot.name
    sk.lobbyBotSelect(window, ui.selectedBot, names, ui.fillBotMenu,
      fillAt, 216, fillEnabled)
    if sk.lobbyButton("Fill empty slots", fillAt + vec2(228, 0), 198,
      enabled = fillEnabled and bots.len > 0):
        result.chosen = true
  else:
    result = sk.seatPicker(window, ui, bots)
  sk.endUi()

proc click(point: Vec2): SlotChoice =
  ## Warms the immediate-mode hit target before pressing and releasing.
  discard frame(point)
  discard frame(point, pressed = true)
  result = frame(point, released = true)

let
  at = (window.size.vec2 - vec2(520, 480)) / 2
  selector = at + vec2(40, 174)
  add = at + vec2(40, 230)
  rowHeight = sk.atlas.fonts["LobbyBody"].lineHeight +
    sk.theme.padding.float32 * 2
  seatPopup = lobbyBotPopup(at + vec2(24, 164), vec2(472, rowHeight),
    window.size.vec2, bots.len)

echo "Testing late policies are selectable without activating covered buttons"
for i in 5 ..< bots.len:
  let row = seatPopup.xy + vec2(16, rowHeight * (i.float32 + 0.5'f))
  doAssert not click(selector).chosen
  doAssert not click(row).chosen
  doAssert ui.selectedSeatBot == bots[i].name
  doAssert ui.selectedBot == "Base bot"
  doAssert ui.selectedSeat == 0
  let selected = click(add)
  doAssert selected.chosen and selected.bot == i
  doAssert not selected.human and not selected.clear and not selected.file

echo "Testing human, local file, clear, and cancel choices"
doAssert click(at + vec2(40, 82)).human
doAssert click(at + vec2(40, 334)).file
doAssert click(at + vec2(40, 386)).clear
doAssert not click(at + vec2(280, 386)).chosen
doAssert ui.selectedSeat == -1

echo "Testing Escape closes the dropdown when dismissing the picker"
ui.selectedSeat = 1
discard click(selector)
discard frame(selector, escape = true)
doAssert ui.selectedSeat == -1
ui.selectedSeat = 1
doAssert click(add).chosen

echo "Testing the compact fill dropdown opens above and exposes late policies"
drawFill = true
let
  fillSelector = fillAt + vec2(10)
  popup = lobbyBotPopup(fillAt, vec2(216, rowHeight),
    window.size.vec2, bots.len)
doAssert popup.y >= 0 and popup.y + popup.h <= fillAt.y
doAssert popup.x >= 0 and popup.x + popup.w <= window.size.x.float32
for i in 5 ..< bots.len:
  let row = popup.xy + vec2(10, rowHeight * (i.float32 + 0.5'f))
  doAssert not click(fillSelector).chosen
  doAssert ui.fillBotMenu.open
  doAssert not click(row).chosen
  doAssert ui.selectedBot == bots[i].name
  doAssert not ui.fillBotMenu.open
  doAssert click(fillAt + vec2(238, 10)).chosen

echo "Testing disabled and empty fill dropdowns close without selection"
discard click(fillSelector)
doAssert ui.fillBotMenu.open
fillEnabled = false
discard frame(fillSelector)
doAssert not ui.fillBotMenu.open
doAssert not click(fillSelector).chosen
doAssert ui.selectedBot == bots[^1].name
fillEnabled = true
discard click(fillSelector)
discard frame(fillSelector, escape = true)
doAssert not ui.fillBotMenu.open
let savedBots = bots
bots.setLen(0)
doAssert not click(fillSelector).chosen
doAssert not ui.fillBotMenu.open
bots = savedBots
drawFill = false

echo "Testing changed and empty policy catalogs"
ui.selectedSeat = 1
bots.setLen(1)
discard frame(at)
doAssert ui.selectedSeatBot == "Base bot"
doAssert click(add).bot == 0
bots.setLen(0)
doAssert not click(add).chosen
doAssert click(at + vec2(40, 334)).file
window.close()
echo "Seat picker dropdown and existing choices passed"
