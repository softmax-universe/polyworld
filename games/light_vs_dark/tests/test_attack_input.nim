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
  let hooks = GraphicsHooks()
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
    attackPressedButtons = {}
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
      updateWorldSelection(vp)
      updatePlayerOrder(vp, focused = focused)

  proc pointAtUnit(id: int32) =
    ## Places the cursor on the rendered body used by production picking.
    let unit = run.world.units[run.world.unitIndex(id)]
    pointAt(screenPosition(renderPoint(unit) +
      vec3(0, UnitHeights[unit.kind] * 0.5'f, 0), vp))

  proc leftClick() =
    ## Drives an ordinary primary press and release through the real callbacks.
    inputFrame({MouseLeft})
    inputFrame(released = {MouseLeft})
    run.flushPlayerCommands()

  proc rightClick() =
    inputFrame({MouseRight})
    inputFrame(released = {MouseRight})
    run.flushPlayerCommands()

  proc depotFixture(kind: BuildingKind): int32 =
    ## Places a visible owned depot and selects one peon for real right clicks.
    fixture()
    let half = run.world.map.side div 2
    result = run.world.spawnUnit(0, PeonUnit, tile2(half-5, half))
    selectedIds = @[result]
    primaryId = result
    run.world.buildings.add Building(id: FirstBuildingId, owner: 0,
      kind: kind, hp: 500, state: BuildingComplete,
      footprint: BuildingTable[kind].footprint,
      origin: tile2(half+2, half-1))
    run.world.buildingSlot.setLen(run.world.map.mines.len + 1)
    run.world.buildingSlot[run.world.map.mines.len] = 0
    let size = BuildingTable[kind].footprint
    pointAtTile(tile2(half+2+size.width div 2, half-1+size.depth div 2))

  suite "LvD right-click resource delivery":
    test "town hall accepts either cargo and mill accepts wood":
      for kind in [TownHallBuilding, LumberMillBuilding]:
        for wood in [false, true]:
          if kind == LumberMillBuilding and not wood: continue
          for append in [false, true]:
            let peon = depotFixture(kind)
            let unit = run.world.units[run.world.unitIndex(peon)]
            if wood: unit.carryWood = 13
            else: unit.carryGold = 17
            if append: inputFrame({KeyLeftShift})
            let before = run.stateHash()
            rightClick()
            require run.submissions.len == 1
            let action = run.submissions[0]
            check action.kind == ActionDeposit
            check action.entityId == peon
            check action.first == FirstBuildingId
            check action.append == append
            check selectedIds == @[peon]
            check run.stateHash() == before
            check targetFlash.kind == HarvestEntityFlash
            check targetFlash.target == FirstBuildingId

    test "gold at a lumber mill stays carried and never queues delivery":
      let peon = depotFixture(LumberMillBuilding)
      let unit = run.world.units[run.world.unitIndex(peon)]
      unit.carryGold = 17
      rightClick()
      require run.submissions.len == 1
      check run.submissions[0].kind == ActionMove
      check unit.carryGold == 17

    test "mixed selection sends only wood carriers to a mill":
      let woodPeon = depotFixture(LumberMillBuilding)
      run.world.units[run.world.unitIndex(woodPeon)].carryWood = 13
      let half = run.world.map.side div 2
      let goldPeon = run.world.spawnUnit(0, PeonUnit, tile2(half-5, half+2))
      let emptyPeon = run.world.spawnUnit(0, PeonUnit, tile2(half-5, half+3))
      run.world.units[run.world.unitIndex(goldPeon)].carryGold = 17
      selectedIds = @[woodPeon, goldPeon, emptyPeon, soldier]
      rightClick()
      require run.submissions.len == 1
      check run.submissions[0].kind == ActionDeposit
      check run.submissions[0].entityId == woodPeon

    test "cancelling a blueprint at a depot still means movement":
      let peon = depotFixture(TownHallBuilding)
      run.world.units[run.world.unitIndex(peon)].carryGold = 17
      pendingBuild = FarmBuilding.ord.int32
      rightClick()
      check pendingBuild == -1
      require run.submissions.len == 1
      check run.submissions[0].kind == ActionMove

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

    test "tapped A left ground orders on press once and preserves selection":
      fixture()
      inputFrame({KeyA})
      inputFrame(released = {KeyA})
      let before = run.stateHash()
      inputFrame({MouseLeft})
      run.flushPlayerCommands()
      require run.submissions.len == 1
      check run.submissions[0].kind == ActionAttackMove
      check run.submissions[0].entityId == soldier
      check selectedIds == @[soldier]
      check primaryId == soldier
      check not attackMoveArmed
      check not selectionStarted
      check not lineGesture.active
      check run.stateHash() == before
      inputFrame(released = {MouseLeft})
      run.flushPlayerCommands()
      check run.submissions.len == 1
      check selectedIds == @[soldier]
      pointAtUnit(other)
      leftClick()
      check selectedIds == @[other]
      check run.submissions.len == 1

    test "held A left drag and double click never start selection or a line":
      fixture()
      inputFrame({KeyA})
      inputFrame({MouseLeft})
      run.flushPlayerCommands()
      require run.submissions.len == 1
      check attackMoveArmed
      pointAtUnit(other)
      for i in 0 .. 2:
        inputFrame()
        check not selectionStarted
        check not lineGesture.active
      inputFrame(released = {MouseLeft})
      run.flushPlayerCommands()
      check run.submissions.len == 1
      check selectedIds == @[soldier]
      pointAtTile(target)
      inputFrame({MouseLeft, DoubleClick, KeyLeftShift})
      inputFrame(released = {MouseLeft, DoubleClick})
      run.flushPlayerCommands()
      require run.submissions.len == 2
      for action in run.submissions:
        check action.kind == ActionAttackMove
        check action.entityId == soldier
      check not run.submissions[0].append
      check run.submissions[1].append
      check selectedIds == @[soldier]
      inputFrame(released = {KeyA, KeyLeftShift})
      check not attackMoveArmed
      rightClick()
      require run.submissions.len == 3
      check run.submissions[2].kind == ActionMove

    test "armed left target attacks enemies without selecting friendlies":
      for owner in [0'i32, 1'i32]:
        fixture()
        let unit = run.world.units[run.world.unitIndex(other)]
        unit.owner = owner
        for stamp in run.world.visibleStamp[0].mitems:
          stamp = run.world.visionGeneration[0]
        inputFrame({KeyA})
        inputFrame(released = {KeyA})
        pointAtUnit(other)
        require pickEntity(vp) == other
        let before = run.stateHash()
        leftClick()
        check selectedIds == @[soldier]
        check primaryId == soldier
        check run.stateHash() == before
        if owner == 1:
          require run.submissions.len == 1
          check run.submissions[0].kind == ActionAttack
          check run.submissions[0].entityId == soldier
          check run.submissions[0].first == other
          check not attackMoveArmed
        else:
          check run.submissions.len == 0
          check attackMoveArmed

    test "armed minimap left click orders without panning or dragging":
      fixture()
      inputFrame({KeyA})
      inputFrame(released = {KeyA})
      let
        area = attackMinimapArea(currentLayout(window))
        relative = vec2(target.x.float32 + 0.5'f,
          target.y.float32 + 0.5'f) / run.world.map.side.float32
      pointAt((area.origin + area.size * relative) * sk.uiScale)
      let mini = attackMinimapTile(currentLayout(window), sk.mousePos,
        run.world.map.side)
      require mini != NoTile
      require run.world.terrainOpen(mini.x.int32, mini.y.int32)
      let beforeCamera = cameraTarget
      inputFrame({MouseLeft})
      run.flushPlayerCommands()
      require run.submissions.len == 1
      check run.submissions[0].kind == ActionAttackMove
      check run.submissions[0].first == mini.x.int32
      check run.submissions[0].second == mini.y.int32
      check not minimapPanning
      check cameraTarget == beforeCamera
      pointAt((area.origin + area.size * 0.75'f) * sk.uiScale)
      inputFrame()
      inputFrame(released = {MouseLeft})
      run.flushPlayerCommands()
      check run.submissions.len == 1
      check selectedIds == @[soldier]
      check not minimapPanning
      check cameraTarget == beforeCamera

    test "unarmed left click double click box and minimap keep normal behavior":
      fixture()
      pointAtUnit(other)
      leftClick()
      check selectedIds == @[other]
      inputFrame({MouseLeft, DoubleClick})
      inputFrame(released = {MouseLeft, DoubleClick})
      check selectedIds.len == 2
      check primaryId == other
      selectEntity(other)
      pointAt(vec2(450, 250))
      inputFrame({MouseLeft})
      pointAt(vec2(850, 650))
      inputFrame()
      inputFrame(released = {MouseLeft})
      check selectedIds.len == 2
      let area = attackMinimapArea(currentLayout(window))
      pointAt((area.origin + area.size * 0.75'f) * sk.uiScale)
      let beforeCamera = cameraTarget
      inputFrame({MouseLeft})
      check minimapPanning
      check cameraTarget != beforeCamera
      inputFrame(released = {MouseLeft})
      check not attackMoveArmed
      run.flushPlayerCommands()
      check run.submissions.len == 0

    test "selection changes cancel held A until release and a fresh press":
      for change in 0 .. 6:
        fixture()
        if change == 4:
          selectedIds.add other
        inputFrame({KeyA})
        require attackMoveArmed
        case change
        of 0:
          selectEntity(other)
        of 1:
          clearSelection()
        of 2:
          selectAllUnits()
        of 3:
          selectBox(@[other], false)
        of 4:
          run.world.units[run.world.unitIndex(soldier)].state = UnitDying
          pruneSelection()
        of 5:
          inputFrame({KeyLeftControl, KeyA})
          inputFrame(released = {KeyLeftControl})
        else:
          selectedIds = @[other]
          primaryId = other
        inputFrame()
        check not attackMoveArmed
        inputFrame({KeyA})
        check not attackMoveArmed
        inputFrame(released = {KeyA})
        check not attackMoveArmed
        if selectedIds.len == 0:
          selectEntity(other)
        inputFrame({KeyA})
        check attackMoveArmed

    test "empty A cannot arm a unit selected while the key is still held":
      fixture()
      clearSelection()
      inputFrame({KeyA})
      check not attackMoveArmed
      pointAtUnit(other)
      leftClick()
      check selectedIds == @[other]
      check not attackMoveArmed
      inputFrame({KeyA})
      check not attackMoveArmed
      inputFrame(released = {KeyA})
      check not attackMoveArmed
      inputFrame({KeyA})
      check attackMoveArmed
      check run.submissions.len == 0

    test "A cannot arm a selection containing only buildings or enemies":
      discard depotFixture(TownHallBuilding)
      selectEntity(FirstBuildingId)
      inputFrame({KeyA})
      check not attackMoveArmed
      fixture()
      run.world.units[run.world.unitIndex(other)].owner = 1
      selectEntity(other)
      inputFrame({KeyA})
      check not attackMoveArmed

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
