## Exercises the production team controls in a hidden offscreen GL window.

import
  std/[importutils, os],
  opengl, pixie, silky, vmath, windy, windy/internal,
  polyworld/viewers,
  ../[homes, lobbies, presets]

privateAccess(Window)

let window = newWindow("LvD team setup regression", ivec2(1514, 970),
  visible = false)
window.makeContextCurrent()
loadExtensions()
pollEvents()
doAssert not window.visible

let builder = newHudAtlas(4096)
builder.addDefaultFonts()
builder.addLobbyFonts()
builder.addHomeAssets()
let sk = newSilky(window, builder.atlasImage, builder.atlas)
sk.applyThemePatches()

var framebuffer, colorTexture: GLuint
glGenFramebuffers(1, framebuffer.addr)
glGenTextures(1, colorTexture.addr)
glBindTexture(GL_TEXTURE_2D, colorTexture)
glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.GLint, window.size.x, window.size.y,
  0, GL_RGBA, GL_UNSIGNED_BYTE, nil)
glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
  GL_TEXTURE_2D, colorTexture, 0)
doAssert glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE

var
  config = defaultConfig(8)
  ui = LobbyUi(selectedBot: "Base bot")
  picker: TeamPicker
  layout: LobbyLayout
  editable = true
  online = false
  matchName = "Andrew's game"
  hoveredSeat = -1

config.setTeamCount(4)
for i in 0 ..< config.playerCount:
  config.players[i].name = ["Andrew", "Morgan", "River", "Sam",
    "Avery", "Casey", "Jordan", "Taylor"][i]

proc frame(point: Vec2, pressed = false, released = false,
    right = false, escape = false): bool =
  ## Drives normal pointer frames while keeping the native window hidden.
  window.state.perFrame = PerFrame()
  window.state.buttonDown = {}
  window.state.mousePos = point.ivec2
  if pressed:
    window.state.perFrame.buttonPressed.incl MouseLeft
    window.state.buttonDown.incl MouseLeft
  if released:
    window.state.perFrame.buttonReleased.incl MouseLeft
  if right:
    window.state.perFrame.buttonPressed.incl MouseRight
    window.state.buttonDown.incl MouseRight
  if escape:
    window.state.perFrame.buttonPressed.incl KeyEscape
  doAssert not window.visible
  layout = sk.beginLvdBattle(window, ui, config.playerCount, picker.isOpen)
  sk.lvdRosterPanel(layout, config.diplomacySettings.enabled)
  sk.pushRosterClip(layout)
  for i in 0 ..< config.playerCount:
    discard sk.seatButton(layout, i, 0, config.players[i].name,
      if i == 0: "HUMAN" else: "BOT", i == 0, false,
      editable and not picker.isOpen, config.seed,
      if config.diplomacySettings.enabled: -1 else: config.playerTeam(i).int)
    if right and editable and not picker.isOpen and
        not config.diplomacySettings.enabled and
        teamBadgeHit(layout, i, 0, sk.mousePos):
      hoveredSeat = i
      picker.openTeamPicker(i, sk.mousePos)
  sk.popClipRect()
  result = sk.configPanel(window, ui, config, layout.right,
    layout.rightWidth, layout.panelHeight, editable and not picker.isOpen,
    showControls = not online or editable,
    gameName = if online: addr matchName else: nil)
  let
    controls = rosterControlsPosition(layout)
    active = editable and not picker.isOpen
    fill = layout.left + vec2(22, layout.panelHeight - 164)
  discard sk.lobbyButton("Add player", controls, 210, "cross", active)
  discard sk.lobbyButton("Remove last", controls + vec2(222, 0),
    210, "minus", active)
  sk.lobbyLabel($config.playerCount & " players", controls + vec2(454, 0), 180)
  sk.lobbyLabel("Fill empty slots", fill, 210, "LobbyBold")
  sk.lobbySelect(window, ui.selectedBot, ["Base bot"],
    fill + vec2(216, 0), 216, active)
  discard sk.lobbyButton("Fill 0 slots", fill + vec2(444, 0), 198,
    "cross", false)
  discard sk.lobbyButton("Shuffle players", fill + vec2(654, 0),
    layout.leftWidth - 698, "shuffle", active)
  sk.lobbyLabel("Fill keeps assigned humans and bots. Clear a slot to replace it.",
    fill + vec2(0, 54), layout.leftWidth - 44, tint = LobbyMuted)
  sk.lobbyLabel("Playing seat 1", layout.left + vec2(22, layout.panelHeight - 74),
    800, tint = LobbyMuted)
  discard sk.lobbyButton("Back", layout.footer, 190, "arrow_left", active)
  discard sk.lobbyButton("Start Game", layout.primary, 250, "arrow_right",
    active, tint = LobbyGreen)
  if picker.isOpen:
    result = sk.drawTeamPicker(window, picker, config) or result
  sk.endUi()

proc click(point: Vec2): bool =
  ## Uses the same hover, press, and release sequence as an actual click.
  discard frame(point)
  discard frame(point, pressed = true)
  frame(point, released = true)

proc capture(path: string): Image =
  ## Saves pixels from the explicit framebuffer without displaying a window.
  doAssert not window.visible
  result = newImage(window.size.x, window.size.y)
  glReadPixels(0, 0, window.size.x, window.size.y, GL_RGBA,
    GL_UNSIGNED_BYTE, result.data[0].addr)
  result.flipVertical()
  createDir(path.parentDir)
  result.writeFile(path)
  echo "Hidden team setup fixture: ", path

discard frame(vec2(0))
let
  controlAt = teamControlsOrigin(layout.right)
  mode = diplomacyControlRect(controlAt, layout.rightWidth - 44)
  modePoint = mode.xy + mode.wh / 2
  originalTeams = @(config.diplomacySettings.teams)

echo "Testing diplomacy toggles preserve configured teams"
discard click(modePoint)
doAssert config.diplomacySettings.enabled
doAssert config.diplomacySettings.neutralStart
doAssert config.diplomacySettings.teams == originalTeams
discard click(modePoint)
doAssert not config.diplomacySettings.enabled
doAssert config.diplomacySettings.teams == originalTeams
doAssert config.resolvedTeamCount() == 4

echo "Testing the team slider balances the roster and reaches both endpoints"
let
  slider = teamSliderRect(controlAt, layout.rightWidth - 44)
  handle = sk.getImageSize("scrubber.handle")
  trackStart = slider.x + handle.x / 2
  trackWidth = slider.w - handle.x
  sliderY = slider.y + handle.y / 2
discard click(vec2(trackStart, sliderY))
doAssert config.resolvedTeamCount() == 1
discard click(vec2(trackStart + trackWidth, sliderY))
doAssert config.resolvedTeamCount() == 8
discard click(vec2(trackStart + trackWidth * 3.25'f / 7, sliderY))
doAssert config.resolvedTeamCount() == 4
var counts: array[4, int]
for player in 0 ..< config.playerCount:
  inc counts[config.playerTeam(player)]
doAssert counts == [2, 2, 2, 2]

echo "Testing guests cannot alter mode or team count"
editable = false
online = true
let readonly = config
discard click(modePoint + vec2(0, 52))
discard click(vec2(trackStart, sliderY + 52))
doAssert config == readonly
discard frame(vec2(0))
discard capture(getCurrentDir() / "output/lvd-team-guest-setup.png")
online = false
editable = true

echo "Testing a permission change cannot leave the team slider dragging"
discard frame(vec2(trackStart + trackWidth * 3.25'f / 7, sliderY))
discard frame(vec2(trackStart + trackWidth * 3.25'f / 7, sliderY), pressed = true)
let beforeMissedRelease = @(config.diplomacySettings.teams)
editable = false
discard frame(vec2(trackStart + trackWidth, sliderY))
editable = true
discard frame(vec2(trackStart, sliderY))
doAssert config.resolvedTeamCount() == 4
doAssert config.diplomacySettings.teams == beforeMissedRelease

echo "Testing right-click assignment changes only the chosen player"
let
  badge = teamBadgeRect(layout, 0, 0)
  badgePoint = badge.xy + badge.wh / 2
  beforeAssignment = @(config.diplomacySettings.teams)
  chosenTeam = (config.playerTeam(0).int + 1) mod 4
discard frame(badgePoint)
discard frame(badgePoint, right = true)
doAssert picker.isOpen and picker.seat == 0
doAssert hoveredSeat == 0
let pickerPath = getCurrentDir() / "output/lvd-team-picker.png"
discard capture(pickerPath)
let item = picker.teamPickerItemRect(window.size.vec2 / sk.uiScale,
  config.resolvedTeamCount(), chosenTeam)
discard click(item.xy + item.wh / 2)
doAssert not picker.isOpen
doAssert config.playerTeam(0) == chosenTeam.int32
for player in 1 ..< config.playerCount:
  doAssert config.playerTeam(player) == beforeAssignment[player]

echo "Testing outside clicks and Escape dismiss without changing assignments"
let manualTeams = @(config.diplomacySettings.teams)
discard frame(badgePoint, right = true)
doAssert picker.isOpen
discard frame(vec2(12), pressed = true)
doAssert not picker.isOpen
discard frame(vec2(12), released = true)
discard frame(badgePoint, right = true)
doAssert picker.isOpen
discard frame(badgePoint, escape = true)
doAssert not picker.isOpen
doAssert config.diplomacySettings.teams == manualTeams

echo "Testing hidden badges cannot open a team picker"
let hiddenBadge = teamBadgeRect(layout, 63, 0)
doAssert not teamBadgeHit(layout, 63, 0, hiddenBadge.xy + hiddenBadge.wh / 2)

echo "Testing every team remains reachable in a full 64-team picker"
for view in [vec2(1514, 970), vec2(500, 400), vec2(320, 240)]:
  var bounded: TeamPicker
  bounded.openTeamPicker(0, view - vec2(1))
  let
    pageSize = teamPickerPageSize(view, 64)
    bounds = bounded.teamPickerBounds(view, 64)
  doAssert pageSize > 0
  doAssert bounds.x >= 0 and bounds.y >= 0
  doAssert bounds.x + bounds.w <= view.x
  doAssert bounds.y + bounds.h <= view.y
  for team in 0 ..< 64:
    bounded.page = team div pageSize
    let cell = bounded.teamPickerItemRect(view, 64, team)
    doAssert cell.x >= bounds.x and cell.y >= bounds.y
    doAssert cell.x + cell.w <= bounds.x + bounds.w
    doAssert cell.y + cell.h <= bounds.y + bounds.h
let smallConfig = config
config = LvdConfig(
  playerCount: 64,
  players: unnamedPlayers(64),
  mapSettings: MapSettings(
    layout: RandomLayout, size: 48, expansions: 0, minDistance: 8
  )
)
config.normalizeTeams()
config.validate()
discard frame(badgePoint)
discard frame(badgePoint, right = true)
doAssert picker.isOpen
let largeBounds = picker.teamPickerBounds(window.size.vec2 / sk.uiScale, 64)
discard click(largeBounds.xy + vec2(largeBounds.w - 80, largeBounds.h - 30))
doAssert picker.isOpen and picker.page == 1
let lastTeam = picker.teamPickerItemRect(window.size.vec2 / sk.uiScale, 64, 63)
discard click(lastTeam.xy + lastTeam.wh / 2)
doAssert not picker.isOpen
doAssert config.playerTeam(0) == 63
doAssert config.resolvedTeamCount() == 64
config = smallConfig

config.setTeamCount(4)
discard frame(vec2(0))
let
  output = getEnv("LVD_TEAM_SETUP_FIXTURE",
    getCurrentDir() / "output/lvd-team-setup.png")
  fixedImage = capture(output)
for player in 0 ..< config.playerCount:
  let area = teamBadgeRect(layout, player, 0)
  doAssert fixedImage[area.x.int, (area.y + area.h / 2).int] ==
    rosterColor(config.seed, config.playerTeam(player).int)

discard click(modePoint)
doAssert config.diplomacySettings.enabled
discard frame(vec2(0))
discard capture(getCurrentDir() / "output/lvd-diplomacy-setup.png")

glDeleteTextures(1, colorTexture.addr)
glDeleteFramebuffers(1, framebuffer.addr)
window.close()
echo "Hidden team controls and reassignment passed"
