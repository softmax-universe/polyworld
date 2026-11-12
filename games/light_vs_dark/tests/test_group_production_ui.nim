## Actual native HUD and keyboard callbacks, no browser/server.
import std/[importutils, macros]
import windy/internal
import ../presets
include ../graphics
privateAccess(Window)

macro production(name: static[string]): untyped =
  for node in parseStmt(staticRead("../graphics.nim")):
    if node.kind == nnkProcDef and node[0].repr == "runGraphics*":
      for child in node[^1]:
        if child.kind == nnkProcDef and child[0].repr == name: return child
        if child.kind == nnkAsgn and child[1].kind == nnkLambda and
            child[0].repr == "window." & name: return child
  error("Missing production routine: " & name)

proc main() =
  window = newWindow("LvD producer group HUD", ivec2(1280, 900), visible = false)
  window.makeContextCurrent()
  loadExtensions()
  let atlas = buildUiAtlas(factionOrder(DefaultSeed.int64))
  sk = newSilky(window, atlas.atlasImage, atlas.atlas)
  sk.applyThemePatches()
  defer: window.close()
  run = newLocalMatch(defaultConfig(2), ["", ""])
  run.networked = true
  options.playerSlot = 1
  resetHumanCommunication()
  clearPlayerCommands()
  var matchMenu = HiddenMatchMenu
  var actionCam = initActionCam(subjectMode = true)
  var preferences: Preferences
  var network: NetworkMatch
  var scene: CharacterScene
  production("playerMode")
  production("selectionTarget")
  production("clearSelection")
  production("selectAllUnits")
  production("onButtonPress")
  production("onButtonRelease")
  let w = run.world
  var hall: int32
  for b in w.buildings:
    if b.owner == 0 and b.kind == TownHallBuilding: hall = b.id
  w.players[0].gold = 20000
  w.players[0].wood = 20000
  w.players[0].foodCap = 100
  var barracks: seq[int32]
  for y in countup(10'i32, w.map.side - 10, 6):
    for x in countup(10'i32, w.map.side - 10, 6):
      if barracks.len < 3 and w.canPlace(BarracksBuilding, x, y):
        doAssert w.applyBuild(0, w.units[0].id, BarracksBuilding.ord.int32, x, y)
        w.buildings[^1].state = BuildingComplete
        w.buildings[^1].hp = w.buildings[^1].maxHp
        barracks.add w.buildings[^1].id
        discard w.applyCancel(0, w.units[0].id)
  doAssert barracks.len == 3
  selectedIds = @[hall] & barracks
  primaryId = hall
  let colors = @[rgbx(230,100,100,255), rgbx(100,100,230,255)]
  proc drawHud(at: Vec2, pressed: set[Button] = {}) =
    sk.uiScale = gameUiScale(window)
    window.state.mousePos = ivec2((at.x * sk.uiScale).int32, (at.y * sk.uiScale).int32)
    window.state.perFrame = PerFrame(buttonPressed: pressed)
    sk.beginUi(window, window.size)
    drawUi(sk, window, transport, cameraTarget, cameraDistance, viewMode,
      primaryId, selectedIds, followSelection, actionCam, colors)
    sk.endUi()
    window.state.perFrame = PerFrame()
  sk.beginUi(window, window.size)
  let build = sk.beginFrame(currentLayout(window).panel(GameUiRegion.BottomRight, PanelBuild)).buildPanels()
  sk.endUi()
  let before = run.stateHash()
  drawHud(build.slots[SoldierUnit.ord].origin + vec2(12), {MouseLeft})
  run.flushPlayerCommands()
  doAssert run.submissions.len == 1
  doAssert run.submissions[0].entityId == barracks[0], "Mixed HUD must route outside primary town hall"
  currentShortcuts = DefaultShortcuts
  inputBindings = LvdControlProfile.defaults
  shortcutState.resetShortcut()
  window.onButtonPress(KeyS)
  window.onButtonRelease(KeyS)
  run.flushPlayerCommands()
  doAssert run.submissions.len == 2
  doAssert run.submissions[1].entityId == barracks[1], "Keyboard must share HUD pending rotation"
  drawHud(build.slots[PeonUnit.ord].origin + vec2(12), {MouseLeft})
  run.flushPlayerCommands()
  doAssert run.submissions.len == 3 and run.submissions[2].entityId == hall
  doAssert run.stateHash() == before
  sk.beginUi(window, window.size)
  let panel = sk.beginFrame(currentLayout(window).panel(GameUiRegion.BottomLeft, PanelSelection)).selectionPanels(false)
  sk.endUi()
  drawHud(panel.units[0].origin + vec2(12), {MouseLeft})
  doAssert selectedIds == @[barracks[0]], "Building group portraits must dispatch selection"
  # Cancel unfinished sites through the same HUD and X key; no demolition.
  clearPlayerCommands()
  let site = barracks[0]
  w.buildings[w.buildingIndex(site)].state = BuildingUnderConstruction
  w.buildings[w.buildingIndex(site)].buildTicks = 50
  w.buildings[w.buildingIndex(site)].buildTotal = 100
  selectedIds = @[site]
  primaryId = site
  let cancelBefore = run.submissions.len
  drawHud(build.slots[0].origin + vec2(12), {MouseLeft})
  run.flushPlayerCommands()
  doAssert run.submissions.len == cancelBefore + 1
  doAssert run.submissions[^1].kind == ActionCancel
  doAssert run.submissions[^1].entityId == site
  let goldBefore = w.players[0].gold
  doAssert w.applyReplayAction(run.submissions[^1])
  doAssert w.players[0].gold == goldBefore + BuildingTable[BarracksBuilding].gold
  doAssert w.buildings[w.buildingIndex(site)].state == BuildingDying
  clearPlayerCommands()
  let site2 = barracks[1]
  w.buildings[w.buildingIndex(site2)].state = BuildingUnderConstruction
  selectedIds = @[site2, barracks[2]]
  primaryId = site2
  shortcutState.resetShortcut()
  let keyBefore = run.submissions.len
  window.onButtonPress(KeyX)
  window.onButtonRelease(KeyX)
  run.flushPlayerCommands()
  doAssert run.submissions.len == keyBefore + 1
  doAssert run.submissions[^1].entityId == site2
  doAssert w.buildings[w.buildingIndex(barracks[2])].state == BuildingComplete
  clearPlayerCommands()
  resetHumanCommunication()
  window.onButtonPress(KeyEnter)
  window.onButtonRelease(KeyEnter)
  let chatBefore = run.submissions.len
  window.onButtonPress(KeyX)
  window.onButtonRelease(KeyX)
  drawHud(build.slots[0].origin + vec2(12), {MouseLeft})
  run.flushPlayerCommands()
  doAssert run.submissions.len == chatBefore
  resetHumanCommunication()
  # Research keyboard uses the ordinary ActionResearch protocol too.
  clearPlayerCommands()
  let smith = barracks[2]
  w.buildings[w.buildingIndex(site2)].state = BuildingComplete
  w.buildings[w.buildingIndex(smith)].kind = BlacksmithBuilding
  w.buildings[w.buildingIndex(smith)].queueLength = 0
  selectedIds = @[smith]
  primaryId = smith
  shortcutState.resetShortcut()
  let researchBefore = run.submissions.len
  window.onButtonPress(KeyW)
  window.onButtonRelease(KeyW)
  run.flushPlayerCommands()
  doAssert run.submissions.len == researchBefore + 1
  doAssert run.submissions[^1].kind == ActionResearch
  doAssert run.submissions[^1].first == TemperedEdges.ord.int32
  doAssert w.buildings[w.buildingIndex(smith)].researchTicks == 0
  echo "PASS actual mixed-producer HUD + single S/X/W callbacks, cancel refund and chat, pending rotation and no local mutation"
main()
