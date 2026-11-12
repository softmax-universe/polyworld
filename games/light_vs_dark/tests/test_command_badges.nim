## Native HUD integration: every catalog entry has an always-visible key badge.
import std/[importutils, os]
from std/strutils import endsWith
import windy/internal
import opengl
import polyworld/viewers
import ../presets
include ../ui
privateAccess(Window)
privateAccess(TooltipHover)

let window = newWindow("LvD command key badges", ivec2(1280,900), visible = false)
window.makeContextCurrent()
loadExtensions()
pollEvents()
let atlas = newHudAtlas(4096)
let badges = loadUnitSymbols()
for kind in UnitKind:
  doAssert atlas.addImage(unitSymbolKey(kind), badges[kind])
let factionList = factionOrder(DefaultSeed.int64)
for player in 0'i32 ..< int32(min(factionList.len, FactionFiles.len)):
  for kind in BuildingKind:
    if kind == GoldMineBuilding and player != LightPlayer: continue
    doAssert atlas.addImage(buildingPortraitKey(player, kind),
      readImage(buildingPortraitPath(factionList[Faction(player)], kind)))
for key in TemporaryResearchIcons:
  doAssert atlas.addImage(key, readImage("../polyworld_art/icons/" & key & ".png"))
atlas.addDefaultFonts()
let sk = newSilky(window, atlas.atlasImage, atlas.atlas)
sk.applyThemePatches()
var config = defaultConfig(2)
config.maxTicks = TickRate * 600
config.mapSettings = MapSettings(layout: RandomLayout, size: 90, expansions: 0)
run = newLocalMatch(config, ["", ""])
options.playerSlot = 1
var primaryId = NoEntity
var selectedIds: seq[int32]
var transport = initPlayer(live = true, durationTicks = config.maxTicks, playing = true)
var viewMode = 1'i32
var follow = false
var director = initActionCam(subjectMode = true)
let colors = @[rgbx(230,100,100,255), rgbx(100,100,230,255)]
var framebuffer, texture: GLuint
glGenFramebuffers(1, framebuffer.addr)
glGenTextures(1, texture.addr)
glBindTexture(GL_TEXTURE_2D, texture)
glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.GLint, window.size.x, window.size.y,
  0, GL_RGBA, GL_UNSIGNED_BYTE, nil)
glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0)
doAssert glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE
proc frame(at: Vec2): Image =
  window.state.mousePos = ivec2((at.x * sk.uiScale).int32, (at.y * sk.uiScale).int32)
  glClearColor(0,0,0,1)
  glClear(GL_COLOR_BUFFER_BIT)
  sk.beginUi(window, window.size)
  drawUi(sk, window, transport, vec3(0), 45, viewMode, primaryId,
    selectedIds, follow, director, colors)
  sk.endUi()
  result = newImage(window.size.x, window.size.y)
  glReadPixels(0,0,window.size.x,window.size.y,GL_RGBA,GL_UNSIGNED_BYTE,result.data[0].addr)
  result.flipVertical()

let workerId = run.world.units[0].id
var producerIds: seq[int32]
for kind in UnitKind:
  var made = false
  run.world.players[0].gold = 100000
  run.world.players[0].wood = 100000
  for y in countup(3'i32, run.world.map.side - 6, 6):
    for x in countup(3'i32, run.world.map.side - 6, 6):
      if run.world.canPlace(FarmBuilding, x, y):
        doAssert run.world.applyBuild(0, workerId, FarmBuilding.ord.int32, x, y)
        let index = run.world.buildings.high
        run.world.buildings[index].kind = unitOf(0, kind).trainedAt
        run.world.buildings[index].state = BuildingComplete
        run.world.buildings[index].hp = 100
        producerIds.add run.world.buildings[index].id
        discard run.world.applyCancel(0, workerId)
        made = true
        break
    if made: break
  doAssert made
proc selectPane(pane: int) =
  selectedIds = if pane == 0: @[workerId] else: producerIds
  primaryId = selectedIds[0]
var build: BuildPanels
for scale in [0.5'f32, 1'f32, 1.25'f32, 2'f32]:
  uiScaleMode = CustomUiScale
  uiScalePercent = int(scale * 100)
  sk.uiScale = scale
  sk.beginUi(window, window.size)
  build = sk.beginFrame(currentLayout(window).panel(GameUiRegion.BottomRight, PanelBuild)).buildPanels()
  sk.endUi()
  for pane in 0 .. 1:
    selectPane(pane)
    let image = frame(vec2(300,100))
    for slot in build.slots.toOpenArray(0, 7):
      let at = slot.origin + vec2(2, if pane == 0: 2'f32 else: slot.size.y - 20)
      doAssert image[int((at.x+1)*scale), int((at.y+1)*scale)] ==
        rgbx(18,20,25,255), "Key backing scale=" & $scale & " pane=" & $pane & " at=" & $at & " selected=" & $selectedIds & " palette=" & $run.world.contextualActions(0, selectedIds)
      var ink = 0
      for y in int((at.y+2)*scale) ..< int((at.y+18)*scale):
        for x in int((at.x+2)*scale) ..< int((at.x+20)*scale):
          let pixel = image[x,y]
          # At half scale L's antialiased stem has only two >180 pixels
          # on current native GL/font dependencies; count midtone ink too.
          let inkThreshold = if scale == 0.5'f32: 140'u8 else: 180'u8
          if pixel.r > inkThreshold and pixel.g > inkThreshold and
              pixel.b > inkThreshold: inc ink
      doAssert ink >= 3, "Every command key must have readable glyph pixels"
    # Hover costs cannot obscure either key location, even for disabled slots.
    for slot in build.slots.toOpenArray(0, 7):
      resetHudTooltips()
      let hovered = frame(slot.origin + vec2(30))
      let keyPanel = commandKeyPanel(slot, pane == 1)
      for y in int((keyPanel.origin.y+1)*scale) ..< int((keyPanel.origin.y+17)*scale):
        for x in int((keyPanel.origin.x+1)*scale) ..< int((keyPanel.origin.x+21)*scale):
          doAssert hovered[x,y] == image[x,y], "Hover costs must not cover a key"
    resetHudTooltips()
    let output = getEnv("LVD_KEY_FIXTURE")
    if output.len > 0:
      image.writeFile(output & "-" & $scale & "-" & $pane & ".png")
  echo "PASS: native HUD badges scale ", scale
# Tooltip route follows the same edited bindings, without reloading the HUD.
selectPane(0)
let farmAt = build.slots[FarmBuilding.ord].origin + vec2(30)
discard frame(farmAt)
sleep(550)
discard frame(farmAt)
doAssert commandHover.visible
doAssert commandHover.card.subtitle == "Building / Shortcut: F"
resetHudTooltips()
let oldBindingImage = frame(vec2(300,100))
doAssert currentShortcuts.setShortcut(BuildFarmShortcut, "Z") == ""
let editedBindingImage = frame(vec2(300,100))
let farmKey = commandKeyPanel(build.slots[FarmBuilding.ord], false)
var changedPixels = 0
for y in int(farmKey.origin.y*sk.uiScale) ..< int((farmKey.origin.y+18)*sk.uiScale):
  for x in int(farmKey.origin.x*sk.uiScale) ..< int((farmKey.origin.x+22)*sk.uiScale):
    if oldBindingImage[x,y] != editedBindingImage[x,y]: inc changedPixels
doAssert changedPixels > 10, "Edited command key changes actual badge glyph pixels"
discard frame(farmAt)
doAssert not commandHover.visible, "Editing bindings retires any retained stale card"
sleep(550)
discard frame(farmAt)
doAssert commandHover.card.subtitle == "Building / Shortcut: Z"
# Every catalog tooltip carries its own full route, including Summon/Elemental.
for pane in 0 .. 1:
  selectPane(pane)
  for index, slot in build.slots.toOpenArray(0, 7):
    resetHudTooltips()
    let at = slot.origin + vec2(30)
    discard frame(at)
    sleep(510)
    discard frame(at)
    let action = if pane == 0: BuildingKind(index).shortcutAction
      else: UnitKind(index).shortcutAction
    doAssert commandHover.visible
    doAssert commandHover.card.subtitle.endsWith(
      " / Shortcut: " & currentShortcuts.shortcutRouteLabel(action))
glDeleteTextures(1, texture.addr)
glDeleteFramebuffers(1, framebuffer.addr)
window.close()
echo "PASS: all build/train command badges"
