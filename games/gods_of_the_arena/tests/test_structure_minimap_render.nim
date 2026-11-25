## Checks the production minimap's fixed structures through fog and destruction.
import std/os
import opengl
import polyworld/viewers
import ../replays
include ../ui

const
  Width = 1160
  Height = 660

let window = newWindow("GotA structure minimap", ivec2(Width, Height),
  visible = false)
window.makeContextCurrent()
loadExtensions()
pollEvents()
let builder = newHudAtlas(2048)
builder.addDefaultFonts()
let sk = newSilky(window, builder.atlasImage, builder.atlas)
sk.applyThemePatches()
sk.uiScale = 1
run = newGame(generateMap(7), 100000, 10, false, ReplayData(),
  drafting = false)
let
  left = GameUiPanel(origin: vec2(28, 90), size: vec2(512))
  right = GameUiPanel(origin: vec2(620, 90), size: vec2(512))
  viewMode = int32(RedTeam.ord + 1)
var hiddenTower = -1
var hiddenBarracks = -1
for i, building in run.world.buildings:
  if not visibleInView(viewMode, building.team, building.position):
    if building.kind == TowerBuilding and hiddenTower < 0:
      hiddenTower = i
    elif building.kind == BarracksBuilding and hiddenBarracks < 0:
      hiddenBarracks = i
doAssert hiddenTower >= 0 and hiddenBarracks >= 0
var framebuffer, texture: GLuint
glGenFramebuffers(1, framebuffer.addr)
glGenTextures(1, texture.addr)
glBindTexture(GL_TEXTURE_2D, texture)
glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.GLint, Width, Height,
  0, GL_RGBA, GL_UNSIGNED_BYTE, nil)
glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
  GL_TEXTURE_2D, texture, 0)
doAssert glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE

proc drawMap(panel: GameUiPanel, structures: bool,
    selectedIds: openArray[int32]) =
  ## Calls the same terrain, fog and structure renderers as the live HUD.
  let area = panel.minimapMap()
  sk.drawMinimapTerrain(panel)
  sk.pushClipRect(rect(area.origin, area.size))
  sk.drawMinimapFog(area, viewMode)
  if structures:
    sk.drawMinimapStructures(panel, viewMode, selectedIds)
  sk.popClipRect()

proc readFrame(): Image =
  ## Reads the actual native framebuffer into a reusable screenshot.
  result = newImage(Width, Height)
  glReadPixels(0, 0, Width, Height, GL_RGBA, GL_UNSIGNED_BYTE,
    result.data[0].addr)
  result.flipVertical()

proc render(structures = true, selectedIds: seq[int32] = @[]): Image =
  ## Produces a stable isolated map for comparing fog and status behavior.
  sk.beginUi(window, window.size)
  glClearColor(0.035, 0.045, 0.065, 1)
  glClear(GL_COLOR_BUFFER_BIT)
  drawMap(left, structures, selectedIds)
  doAssert not sk.mouseConsumed
  sk.endUi()
  readFrame()

proc changedAt(before, after: Image, point: Vec2): int =
  ## Counts changed pixels around a structure's actual projected location.
  for y in max(0, point.y.int - 10) .. min(Height - 1, point.y.int + 10):
    for x in max(0, point.x.int - 10) .. min(Width - 1, point.x.int + 10):
      if before[x, y] != after[x, y]:
        inc result

let
  empty = render(false)
  intact = render()
  towerHp = run.world.buildings[hiddenTower].hp
  barracksHp = run.world.buildings[hiddenBarracks].hp
for i in [hiddenTower, hiddenBarracks]:
  let point = minimapPosition(renderPoint(run.world.buildings[i].position), left)
  doAssert changedAt(empty, intact, point) > 20,
    "Both unseen towers and barracks must be drawn from the start."
  run.world.buildings[i].hp = 1
doAssert render().data == intact.data,
  "Hidden damage must not change the structure's minimap appearance."
doAssert render(selectedIds = @[run.world.buildings[hiddenTower].id]).data ==
  intact.data, "Hidden structures must not acquire a selection highlight."
for i in [hiddenTower, hiddenBarracks]:
  run.world.buildings[i].hp = 0
let destroyed = render()
for i in [hiddenTower, hiddenBarracks]:
  let point = minimapPosition(renderPoint(run.world.buildings[i].position), left)
  doAssert changedAt(intact, destroyed, point) > 10,
    "Destruction must change the marker while still under fog."
  doAssert changedAt(empty, destroyed, point) > 10,
    "Destroyed structure sites must retain a visible marker."

run.world.buildings[hiddenTower].hp = towerHp
run.world.buildings[hiddenBarracks].hp = barracksHp
sk.beginUi(window, window.size)
glClearColor(0.035, 0.045, 0.065, 1)
glClear(GL_COLOR_BUFFER_BIT)
sk.drawLabel("MATCH START", vec2(28, 20), vec2(512, 44),
  rgbx(236, 240, 246, 255), "H1", CenterAlign)
sk.drawLabel("DESTROYED IN FOG", vec2(620, 20), vec2(512, 44),
  rgbx(236, 240, 246, 255), "H1", CenterAlign)
drawMap(left, true, [])
for i in [hiddenTower, hiddenBarracks]:
  run.world.buildings[i].hp = 0
drawMap(right, true, [])
sk.drawLabel("Gray: known structures outside team vision", vec2(28, 610),
  vec2(512, 28), rgbx(178, 187, 201, 255), "Default", CenterAlign)
sk.drawLabel("Crossed out: destroyed tower or barracks", vec2(620, 610),
  vec2(512, 28), rgbx(178, 187, 201, 255), "Default", CenterAlign)
sk.endUi()
let output = getEnv("GOTA_STRUCTURE_MINIMAP_FIXTURE",
  getCurrentDir() / "output/gota-structures-minimap.png")
createDir(output.parentDir)
readFrame().writeFile(output)
glDeleteTextures(1, texture.addr)
glDeleteFramebuffers(1, framebuffer.addr)
window.close()
echo "PASS minimap structures: unseen towers/barracks, destruction, hidden HP."
