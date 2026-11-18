## Exercise real debug tab input at the game's native and compact UI scales.
import
  std/[importutils, tables],
  opengl, silky, vmath, windy/internal,
  polyworld/[assets, chrome, viewers]
import ../[posteffects, replays]
include ../ui

privateAccess(Window)

let window = newWindow("GotA debug menu input", ivec2(1280, 800), visible = false)
window.makeContextCurrent()
loadExtensions()
let builder = newHudAtlas(2048)
builder.addDefaultFonts()
builder.addFont(DefaultFontPath, "HeroVersus", 24.0)
let sk = newSilky(window, builder.atlasImage, builder.atlas)
sk.applyThemePatches()
run = newGame(generateMap(7), 100000, 10, false, ReplayData(),
  drafting = false, activeSeats = @[0])
run.networked = true
run.replayData.config.players.setLen(1)
run.replayData.config.maxTicks = 10000
options.playerSlot = 0
var
  postDraws, waterDraws: int
  fullHud = false
  renderIndex = 0
  ao = ArenaOcclusion
  transport = initPlayer(live = true, durationTicks = 1000, playing = true)
  primaryId = run.world.heroes[0].id
  selectedIds = @[primaryId]
  followSelection, focusPlayerHero, attackMoveArmed: bool
  director = initActionCam()
let tabs = @[
  DebugTab(label: "Post-processing", draw: proc(sk: Silky, window: Window) =
    ## Record that the selected game-owned panel ran.
    inc postDraws
    sk.drawPostProcessing(window, ao)
  ),
  DebugTab(label: "Water", draw: proc(sk: Silky, window: Window) =
    ## Record that the second game-owned panel ran.
    inc waterDraws
    text "Water controls"
  )
]

proc render(point = vec2(-100), pressed = false, down = false,
    released = false) =
  ## Change underlying HUD controls each frame while routing real debug input.
  inc renderIndex
  options.playerSlot = if fullHud and renderIndex mod 2 == 0: 1 else: 0
  window.state.perFrame = PerFrame()
  window.state.buttonDown = {}
  if pressed: window.state.perFrame.buttonPressed.incl MouseLeft
  if down: window.state.buttonDown.incl MouseLeft
  if released: window.state.perFrame.buttonReleased.incl MouseLeft
  glClearColor(0.03, 0.04, 0.06, 1)
  glClear(GL_COLOR_BUFFER_BIT)
  sk.beginUi(window, window.size)
  sk.mousePos = point
  if fullHud:
    sk.drawUi(window, transport, vec3(0), 80, 0, primaryId, selectedIds,
      followSelection, director, focusPlayerHero, attackMoveArmed,
      false, extraTabs = tabs)
  else:
    sk.drawDebugMenu(window, extraTabs = tabs)
  sk.endUi()

for configuration in [(0.5'f, false), (1.0'f, false), (0.5'f, true), (1.0'f, true)]:
  let scale = configuration[0]
  fullHud = configuration[1]
  sk.uiScale = scale
  debugMenuOpen = true
  debugTab = 0
  subWindowStates.clear()
  render()
  render()
  # These are the visible tab centers in the default debug window.
  let post = vec2(450, 132)
  render(post, pressed = true, down = true)
  render(post, down = true)
  render(post, released = true)
  doAssert debugTab == 2, "Post-processing click failed at scale " & $scale
  doAssert postDraws > 0
  let enabled = vec2(390, 218)
  render(enabled)
  ao.enabled = true
  render(enabled, pressed = true, down = true)
  render(enabled, down = true)
  render(enabled, released = true)
  doAssert not ao.enabled, "AO off click failed at scale " & $scale
  render(enabled, pressed = true, down = true)
  render(enabled, released = true)
  doAssert ao.enabled, "AO on click failed at scale " & $scale
  let water = vec2(590, 132)
  render(water, pressed = true, down = true)
  render(water, released = true)
  doAssert debugTab == 3, "Water click failed at scale " & $scale
  doAssert waterDraws > 0
  render(vec2(440, 92), pressed = true, released = true)
  doAssert debugTab == 0
window.close()
echo "PASS tabs and AO toggles across changing HUD controls at both UI scales"
