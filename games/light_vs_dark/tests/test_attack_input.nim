## Real production keyboard, camera, selection and order callbacks; no browser.
import std/[unittest, macros, importutils]
import windy/internal
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
  window = newWindow("LvD attack input contract", ivec2(1600, 1000), visible = false)
  window.makeContextCurrent()
  loadExtensions()
  sk = Silky(uiScale: gameUiScale(window))
  defer:
    window.close()
    window = nil
    run = nil
    clearPlayerCommands()
  var
    matchMenu = HiddenMatchMenu
    actionCam = initActionCam(subjectMode = true)
    preferences: Preferences
    network: NetworkMatch
    scene: CharacterScene
    buildingArt: BuildingArt
    grove: Grove
    scenery: seq[GrovePlacement]
    clickMarks = initClickMarks(orderMarkSettings(false))
    attackClickMarks = initClickMarks(orderMarkSettings(true))
  defer:
    clickMarks.closeClickMarks()
    attackClickMarks.closeClickMarks()
  production("playerMode")
  production("selectionTarget")
  production("selectedCount")
  production("selectEntity")
  production("clearSelection")
  production("selectAllUnits")
  production("pruneSelection")
  production("selectedCenter")
  production("selectedRadius")
  production("screenPosition")
  production("pickEntity")
  production("structureAtTile")
  production("insideBox")
  production("boxedUnits")
  production("selectBox")
  production("updateCamera")
  production("updateWorldSelection")
  production("buildGhostOrigin")
  production("queuePendingBuild")
  production("clickTilePoint")
  production("issueSelectedMove")
  production("updatePlayerOrder")
  production("onButtonPress")
  production("onButtonRelease")
  let vp = perspective(45'f32, 1.6, 0.1, 1000) *
    lookAt(vec3(0, 22, 18), vec3(0), vec3(0, 1, 0))
  var soldier, other: int32
  var target: Tile2

  proc pointAt(point: Vec2) =
    window.state.mousePos = ivec2(point.x.int32, point.y.int32)
    sk.mousePos = window.mousePos.vec2 / sk.uiScale

  proc pointAtTile(tile: Tile2) =
    pointAt(screenPosition(clickTilePoint(tile.x.int32, tile.y.int32), vp))

  proc fixture() =
    clearPlayerCommands()
    cancelGameplayGestures()
    attackMoveArmed = false
    pendingBuild = -1
    resetHumanCommunication()
    shortcutState.resetShortcut()
    inputBindings = LvdControlProfile.defaults
    customBindingsEnabled = true
    mouseKeyAliasesEnabled = false
    bindingCapture = false
    matchMenu = HiddenMatchMenu
    options.playerSlot = 1
    viewMode = 0
    run = Game(world: newWorld(generateMap(DefaultSeed), TickRate * 60))
    run.world.buildings.setLen(0)
    run.world.units.setLen(0)
    run.networked = true
    run.recorder = initReplayRecorder(Setup(gridTiles: run.world.map.side.uint16,
      maximumTicks: (TickRate*60).uint32, decisionTicks: DecisionTicks.uint16,
      players: @[ReplayPlayerSetup(id: 0), ReplayPlayerSetup(id: 1)]))
    transport = initPlayer(live = true, durationTicks = TickRate * 60, playing = true)
    cameraTarget = vec3(0)
    followSelection = false
    actionCam.takeManual()
    window.state.buttonDown = {}
    window.state.perFrame = PerFrame()
    let half = run.world.map.side div 2
    soldier = run.world.spawnUnit(0, SoldierUnit, tile2(half-4, half))
    other = run.world.spawnUnit(0, SoldierUnit, tile2(half-4, half+2))
    selectedIds = @[soldier]
    primaryId = soldier
    target = tile2(half+4, half)
    pointAtTile(target)

  proc inputFrame(pressed: set[Button] = {}; released: set[Button] = {}, focused = true) =
    window.state.buttonDown = (window.state.buttonDown + pressed) - released
    window.state.perFrame = PerFrame(buttonPressed: pressed, buttonReleased: released)
    for button in pressed: window.onButtonPress(button)
    for button in released: window.onButtonRelease(button)
    updateCamera(0, focused = focused)
    if focused and matchMenu == HiddenMatchMenu and not humanCommunicationBlocksGameplay() and
        not bindingCapture:
      updatePlayerOrder(vp, focused = focused)
      updateWorldSelection(vp)

  proc rightClick() =
    inputFrame({MouseRight})
    inputFrame(released = {MouseRight})
    run.flushPlayerCommands()

  suite "LvD production attack input contract":
    test "tap A then right ground attacks once; following right click moves":
      fixture()
      require run.world.hasSelectedMilitary(0, selectedIds)
      require AttackMoveInput.matches(KeyA)
      inputFrame({KeyA})
      require attackMoveArmed
      inputFrame(released = {KeyA})
      require attackMoveArmed
      for i in 0 .. 100: inputFrame()
      check attackMoveArmed
      rightClick()
      require run.submissions.len == 1
      check run.submissions[0].kind == ActionAttackMove
      check not attackMoveArmed
      rightClick()
      require run.submissions.len == 2
      check run.submissions[1].kind == ActionMove

    test "held A repeats Shift orders; release after consumption never re-arms":
      fixture()
      inputFrame({KeyA})
      rightClick()
      check attackMoveArmed
      inputFrame({KeyLeftShift})
      rightClick()
      require run.submissions.len == 2
      for action in run.submissions: check action.kind == ActionAttackMove
      check not run.submissions[0].append
      check run.submissions[1].append
      inputFrame(released = {KeyA, KeyLeftShift})
      check not attackMoveArmed
      rightClick()
      require run.submissions.len == 3
      check run.submissions[2].kind == ActionMove

    test "armed left click double click box and minimap remain selection and navigation":
      fixture()
      inputFrame({KeyA})
      inputFrame(released = {KeyA})
      pointAt(screenPosition(renderPoint(run.world.units[run.world.unitIndex(other)]) +
        vec3(0, UnitHeights[SoldierUnit] * 0.5'f32, 0), vp))
      inputFrame({MouseLeft})
      inputFrame(released = {MouseLeft})
      check selectedIds == @[other]
      check attackMoveArmed
      inputFrame({MouseLeft, DoubleClick})
      inputFrame(released = {MouseLeft, DoubleClick})
      check selectedIds.len == 2
      check primaryId == other
      selectedIds = @[other]
      pointAt(vec2(450, 250))
      inputFrame({MouseLeft})
      pointAt(vec2(850, 650))
      inputFrame()
      inputFrame(released = {MouseLeft})
      check selectedIds.len == 2
      let area = attackMinimapArea(currentLayout(window))
      pointAt((area.origin + area.size * 0.75'f32) * sk.uiScale)
      let beforeCamera = cameraTarget
      inputFrame({MouseLeft})
      check minimapPanning
      check cameraTarget != beforeCamera
      inputFrame(released = {MouseLeft})
      check attackMoveArmed
      run.flushPlayerCommands()
      check run.submissions.len == 0
  suite "LvD multiple building selection":
    test "box and on-screen owned building double click retain group through release":
      fixture()
      run.world.units.setLen(0)
      let half = run.world.map.side div 2
      for i in 0 .. 3:
        run.world.buildings.add Building(id: FirstBuildingId + i.int32,
          owner: (if i == 2: 1'i32 else: 0'i32), kind: BarracksBuilding,
          hp: 100, state: BuildingComplete, footprint: BuildingTable[BarracksBuilding].footprint,
          origin: tile2(half + (if i == 3: 35 else: i * 4 - 4), half))
      run.world.buildingSlot.setLen(run.world.map.mines.len + 4)
      for i in 0 .. 3: run.world.buildingSlot[run.world.map.mines.len + i] = i.int32
      selectedIds.setLen(0)
      primaryId = NoEntity
      viewMode = 0
      pointAt(vec2(250, 200))
      inputFrame({MouseLeft})
      pointAt(vec2(1100, 700))
      inputFrame(released = {MouseLeft})
      check selectedIds == @[FirstBuildingId, FirstBuildingId + 1]
      pointAt(screenPosition(buildingCentre(run.world.buildings[0]) + vec3(0, 1.4, 0), vp))
      inputFrame({MouseLeft, DoubleClick})
      inputFrame(released = {MouseLeft, DoubleClick})
      check selectedIds == @[FirstBuildingId, FirstBuildingId + 1]
      # Shift click toggles one building without collapsing the other.
      pointAt(screenPosition(buildingCentre(run.world.buildings[1]) + vec3(0, 1.4, 0), vp))
      inputFrame({KeyLeftShift, MouseLeft})
      inputFrame(released = {MouseLeft, KeyLeftShift})
      check selectedIds == @[FirstBuildingId]
      inputFrame({KeyLeftShift, MouseLeft})
      inputFrame(released = {MouseLeft, KeyLeftShift})
      check selectedIds == @[FirstBuildingId, FirstBuildingId + 1]
      pointAtTile(tile2(half - 7, half - 5))
      let before = run.stateHash()
      rightClick()
      require run.submissions.len == 2
      for i, action in run.submissions:
        check action.kind == ActionSetRally
        check action.entityId == selectedIds[i]
      check run.stateHash() == before
      let worker = run.world.spawnUnit(0, PeonUnit, tile2(half-8, half))
      selectedIds.add worker
      require issueSelectedMove(0, half-7, half-5)
      run.flushPlayerCommands()
      check run.submissions.len == 5

main()
