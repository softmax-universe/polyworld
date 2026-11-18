## Native regression: execute production graphics handlers, not copied input logic.
import std/[unittest, macros, importutils, strutils]
import windy/internal
include ../graphics
privateAccess(Window)

proc renameDirector(node: NimNode): NimNode {.compileTime.} =
  ## Supplies local camera and explicit focus to hidden-window callbacks.
  if node.kind == nnkIdent and node.strVal == "actionCam": return ident("director")
  if node.kind == nnkDotExpr and node.repr == "window.focused":
    return ident("fixtureFocused")
  result = copyNimNode(node)
  for child in node: result.add renameDirector(child)

macro productionRoutine(name: static[string]): untyped =
  for node in parseStmt(staticRead("../graphics.nim")):
    if node.kind == nnkProcDef and node[0].repr == "runGraphics*":
      for child in node[^1]:
        if child.kind == nnkProcDef and child[0].repr == name: return renameDirector(child)
        if name == "buttonHandler" and child.kind == nnkAsgn and
            child[0].repr == "window.onButtonPress" and child[1].kind == nnkLambda:
          return renameDirector(child)
  error("Missing production routine: " & name)

macro productionOrderPass(): untyped =
  proc search(node: NimNode): NimNode =
    if node.kind == nnkIfStmt and node[0][0].repr.contains("matchMenu == HiddenMatchMenu") and
        node[0][0].repr.contains("humanCommunicationBlocksGameplay()") and
        node.repr.contains("updateWorldSelection(viewProjection)"):
      return node
    for child in node:
      let found = search(child)
      if found != nil: return found
  result = renameDirector(search(parseStmt(staticRead("../graphics.nim"))))
  if result == nil: error("Missing production frame input gate")

proc main() =
  window = newWindow("LvD building placement regression", ivec2(1600, 1000), visible = false)
  window.makeContextCurrent()
  loadExtensions()
  pollEvents()
  doAssert not window.visible
  sk = Silky(uiScale: gameUiScale(window))
  options.playerSlot = 1
  viewMode = 0
  var
    matchMenu = HiddenMatchMenu
    fixtureFocused = true
    director = initActionCam(subjectMode = true)
    preferences: Preferences
    network: NetworkMatch
    scene: CharacterScene
    buildingArt: BuildingArt
    grove: Grove
    scenery: seq[GrovePlacement]
    clickMarks = initClickMarks(orderMarkSettings(false))
    attackClickMarks = initClickMarks(orderMarkSettings(true))
  let hooks = GraphicsHooks()
  director.takeManual()
  productionRoutine("playerMode")
  productionRoutine("selectionTarget")
  productionRoutine("selectedCount")
  productionRoutine("selectEntity")
  productionRoutine("clearSelection")
  productionRoutine("selectAllUnits")
  productionRoutine("pruneSelection")
  productionRoutine("selectedCenter")
  productionRoutine("selectedRadius")
  productionRoutine("screenPosition")
  productionRoutine("pickEntity")
  productionRoutine("pickSelectionEntity")
  productionRoutine("structureAtTile")
  productionRoutine("insideBox")
  productionRoutine("boxedUnits")
  productionRoutine("selectBox")
  productionRoutine("updateCamera")
  productionRoutine("updateWorldSelection")
  productionRoutine("buildGhostOrigin")
  productionRoutine("queuePendingBuild")
  productionRoutine("clickTilePoint")
  productionRoutine("issueSelectedMove")
  productionRoutine("updatePlayerOrder")
  productionRoutine("buttonHandler")
  let viewProjection = perspective(45'f32, 1.6, 0.1, 1000) *
    lookAt(vec3(0, 22, 18), vec3(0), vec3(0, 1, 0))
  var worker: int32
  var origin: (int32, int32)
  var targetMouse: Vec2

  proc pointAt(point: Vec2) =
    window.state.mousePos = ivec2(point.x.int32, point.y.int32)
    sk.mousePos = window.mousePos.vec2 / sk.uiScale

  proc fixture() =
    run = Game(world: newWorld(generateMap(DefaultSeed), TickRate * 60))
    run.inboxes.setLen(run.world.players.len)
    run.networked = true
    run.recorder = initReplayRecorder(Setup(gridTiles: run.world.map.side.uint16,
      maximumTicks: (TickRate*60).uint32, decisionTicks: DecisionTicks.uint16,
      players: @[ReplayPlayerSetup(id: 0), ReplayPlayerSetup(id: 1)]))
    run.world.buildings.setLen(0)
    clearPlayerCommands()
    cancelGameplayGestures()
    resetHumanCommunication()
    matchMenu = HiddenMatchMenu
    bindingCapture = false
    cameraTarget = vec3(0)
    followSelection = false
    window.state.buttonDown = {}
    window.state.perFrame = PerFrame()
    let half = run.world.map.side div 2
    worker = run.world.spawnUnit(0, PeonUnit, tile2(half-8, half))
    selectedIds = @[worker]
    primaryId = worker
    pendingBuild = FarmBuilding.ord.int32
    var found = false
    for y in half-8 .. half+8:
      for x in half-8 .. half+8:
        if not run.world.canPlace(FarmBuilding, x, y): continue
        let size = BuildingTable[FarmBuilding].footprint
        pointAt(screenPosition(clickTilePoint(x + size.width div 2,
          y + size.depth div 2), viewProjection))
        if mouseOverUi(window, sk.mousePos): continue
        if buildGhostOrigin(viewProjection) != (x, y): continue
        origin = (x, y)
        targetMouse = window.mousePos.vec2
        found = true
        break
      if found: break
    doAssert found, "Fixture needs a visible valid build footprint"

  proc inputFrame(pressed: set[Button] = {}; released: set[Button] = {}) =
    window.state.buttonDown = (window.state.buttonDown + pressed) - released
    window.state.perFrame = PerFrame(buttonPressed: pressed, buttonReleased: released)
    updateCamera(0)
    productionOrderPass()

  suite "LvD production building placement input":
    test "left world press queues one build and release never changes selection":
      fixture()
      let before = run.stateHash()
      inputFrame({MouseLeft})
      inputFrame(released = {MouseLeft})
      check selectedIds == @[worker]
      check primaryId == worker
      check not selectionStarted
      run.flushPlayerCommands()
      require run.submissions.len == 1
      let action = run.submissions[0]
      check action.kind == ActionBuild
      check action.entityId == worker
      check action.first == FarmBuilding.ord.int32
      check action.second == origin[0]
      check action.third == origin[1]
      check not action.append
      check pendingBuild == -1
      check run.stateHash() == before # Submission must not mutate simulation.

    test "Shift placements append on the same peon and retain the blueprint":
      fixture()
      run.world.players[0].gold = 0
      run.world.players[0].wood = 0
      let other = run.world.spawnUnit(0, PeonUnit,
        tile2(run.world.map.side div 2 + 8, run.world.map.side div 2))
      selectedIds.add other
      let firstOrigin = origin
      window.state.buttonDown.incl KeyLeftShift
      inputFrame({MouseLeft})
      inputFrame(released = {MouseLeft})
      run.flushPlayerCommands()
      require run.submissions.len == 1
      check run.submissions[0].kind == ActionBuild
      check run.submissions[0].entityId == worker
      check run.submissions[0].append
      check pendingBuild == FarmBuilding.ord.int32
      check selectedIds == @[worker, other]
      require run.world.applyBuild(0, worker, FarmBuilding.ord.int32,
        firstOrigin[0], firstOrigin[1], append = true)
      let half = run.world.map.side div 2
      var found = false
      for y in half - 8 .. half + 8:
        for x in half - 8 .. half + 8:
          if not run.world.canQueueBuild(0, worker, FarmBuilding.ord.int32,
              x, y):
            continue
          let size = BuildingTable[FarmBuilding].footprint
          pointAt(screenPosition(clickTilePoint(x + size.width div 2,
            y + size.depth div 2), viewProjection))
          if mouseOverUi(window, sk.mousePos) or
              buildGhostOrigin(viewProjection) != (x, y):
            continue
          origin = (x, y)
          found = true
          break
        if found: break
      require found
      let before = run.stateHash()
      inputFrame({MouseLeft})
      inputFrame(released = {MouseLeft})
      run.flushPlayerCommands()
      require run.submissions.len == 2
      let action = run.submissions[1]
      check action.kind == ActionBuild
      check action.entityId == worker
      check action.first == FarmBuilding.ord.int32
      check action.second == origin[0]
      check action.third == origin[1]
      check action.append
      check pendingBuild == FarmBuilding.ord.int32
      check selectedIds == @[worker, other]
      check not selectionStarted
      check run.stateHash() == before
      inputFrame(released = {KeyLeftShift})
      inputFrame({MouseLeft})
      inputFrame(released = {MouseLeft})
      run.flushPlayerCommands()
      require run.submissions.len == 3
      check not run.submissions[2].append
      check run.submissions[2].entityId == worker
      check pendingBuild == -1

    test "Shift right click appends work at an existing unfinished building":
      for append in [false, true]:
        fixture()
        run.world.players[0].gold = 5000
        run.world.players[0].wood = 5000
        require run.world.applyBuild(0, worker, FarmBuilding.ord.int32,
          origin[0], origin[1])
        pendingBuild = -1
        if append: window.state.buttonDown.incl KeyLeftShift
        let before = run.stateHash()
        inputFrame({MouseRight})
        inputFrame(released = {MouseRight})
        run.flushPlayerCommands()
        require run.submissions.len == 1
        check run.submissions[0].kind == ActionBuild
        check run.submissions[0].entityId == worker
        check run.submissions[0].append == append
        check run.stateHash() == before

    test "worker entering a mine cancels blueprint before the next input pass":
      fixture()
      run.world = newWorld(generateMap(DefaultSeed), TickRate * 60)
      let unit = run.world.units[0]
      worker = unit.id
      selectedIds = @[worker]
      primaryId = worker
      require run.world.applyHarvest(unit.owner, worker, run.world.buildings[0].id, 0)
      pendingBuild = FarmBuilding.ord.int32
      inputFrame()
      check pendingBuild == FarmBuilding.ord.int32
      for tick in 0 ..< TickRate * 60:
        run.world.tickWorld(nil)
        if unit.state == UnitInMine: break
      require unit.state == UnitInMine
      let before = run.stateHash()
      inputFrame()
      check pendingBuild == -1
      check not selectionStarted
      check not rightOrderStarted
      check not lineGesture.active
      check run.stateHash() == before
      window.state.perFrame = PerFrame(buttonPressed: {MouseLeft})
      updatePlayerOrder(viewProjection)
      run.flushPlayerCommands()
      check run.submissions.len == 0
      check unit.state == UnitInMine

    test "invalid footprint keeps blueprint without selecting or attacking":
      fixture()
      discard run.world.spawnUnit(1, SoldierUnit, tile2(origin[0], origin[1]))
      attackMoveArmed = true
      inputFrame({MouseLeft})
      pointAt(targetMouse + vec2(80, 20))
      inputFrame(released = {MouseLeft})
      run.flushPlayerCommands()
      check run.submissions.len == 0
      check pendingBuild == FarmBuilding.ord.int32
      check selectedIds == @[worker]
      check not selectionStarted

    test "HUD choice press and release cannot place on underlying world":
      fixture()
      let area = currentLayout(window).panel(GameUiRegion.BottomRight, PanelBuild)
      pointAt((area.origin + vec2(20)) * sk.uiScale)
      require mouseOverUi(window, sk.mousePos)
      pendingBuild = -1
      inputFrame({MouseLeft})
      # The real HUD sets this AFTER the world input pass.
      pendingBuild = FarmBuilding.ord.int32
      inputFrame()
      pointAt(targetMouse)
      inputFrame(released = {MouseLeft})
      run.flushPlayerCommands()
      check run.submissions.len == 0
      check pendingBuild == FarmBuilding.ord.int32
      inputFrame({MouseLeft})
      inputFrame(released = {MouseLeft})
      run.flushPlayerCommands()
      check run.submissions.len == 1

    test "HUD minimap and outside-window presses never place":
      for at in [vec2(-2, 400), vec2(1601, 400),
          attackMinimapArea(currentLayout(window)).origin * sk.uiScale + vec2(20)]:
        fixture()
        pointAt(at)
        inputFrame({MouseLeft})
        inputFrame(released = {MouseLeft})
        run.flushPlayerCommands()
        check run.submissions.len == 0
        check pendingBuild == FarmBuilding.ord.int32
        check selectedIds == @[worker]

    test "right click cancels blueprint and moves with normal Shift queuing":
      for append in [false, true]:
        fixture()
        let before = run.stateHash()
        let size = BuildingTable[FarmBuilding].footprint
        attackMoveArmed = true
        if append: window.state.buttonDown.incl KeyLeftShift
        inputFrame({MouseRight})
        check pendingBuild == -1
        check not attackMoveArmed
        run.flushPlayerCommands()
        check run.submissions.len == 0
        inputFrame(released = {MouseRight})
        run.flushPlayerCommands()
        require run.submissions.len == 1
        let action = run.submissions[0]
        check action.kind == ActionMove
        check action.entityId == worker
        check action.first == origin[0] + size.width div 2
        check action.second == origin[1] + size.depth div 2
        check action.append == append
        check selectedIds == @[worker]
        check not selectionStarted
        check run.stateHash() == before

    test "right click on an invalid blueprint moves instead of attacking":
      fixture()
      let size = BuildingTable[FarmBuilding].footprint
      let destination = tile2(origin[0] + size.width div 2,
        origin[1] + size.depth div 2)
      discard run.world.spawnUnit(1, SoldierUnit, destination)
      require not run.world.canPlace(FarmBuilding, origin[0], origin[1])
      inputFrame({MouseRight})
      inputFrame(released = {MouseRight})
      run.flushPlayerCommands()
      require run.submissions.len == 1
      check run.submissions[0].kind == ActionMove
      check pendingBuild == -1

    test "right drag cancels blueprint and retains formation orders":
      fixture()
      inputFrame({MouseRight})
      check pendingBuild == -1
      pointAt(targetMouse + vec2(100, 0))
      inputFrame()
      require lineGesture.dragging
      inputFrame(released = {MouseRight})
      run.flushPlayerCommands()
      require run.submissions.len == 1
      check run.submissions[0].kind == ActionMove

    test "cancellation over an existing site moves instead of resuming building":
      fixture()
      run.world.players[0].gold = 5000
      run.world.players[0].wood = 5000
      let unit = run.world.units[run.world.unitIndex(worker)]
      run.world.place(unit, tile2(origin[0], origin[1]))
      require run.world.applyBuild(0, worker, FarmBuilding.ord.int32,
        origin[0], origin[1])
      require unit.state == UnitBuilding
      inputFrame({MouseRight})
      inputFrame(released = {MouseRight})
      run.flushPlayerCommands()
      require run.submissions.len == 1
      check run.submissions[0].kind == ActionMove
      check pendingBuild == -1

    test "simultaneous buttons cancel instead of placing":
      fixture()
      inputFrame({MouseLeft, MouseRight})
      inputFrame(released = {MouseLeft, MouseRight})
      run.flushPlayerCommands()
      require run.submissions.len == 1
      check run.submissions[0].kind == ActionMove
      check selectedIds == @[worker]

    test "right release outside the window cannot place or order":
      fixture()
      inputFrame({MouseRight})
      pointAt(vec2(-2, 400))
      inputFrame(released = {MouseRight})
      run.flushPlayerCommands()
      check pendingBuild == -1
      check run.submissions.len == 0

    test "right minimap click cancels blueprint and moves without placing":
      fixture()
      let area = attackMinimapArea(currentLayout(window))
      pointAt((area.origin + area.size * 0.5'f32) * sk.uiScale)
      let tile = attackMinimapTile(currentLayout(window), sk.mousePos,
        run.world.map.side)
      require tile != NoTile
      require run.world.terrainOpen(tile.x.int32, tile.y.int32)
      inputFrame({MouseRight})
      check pendingBuild == -1
      inputFrame(released = {MouseRight})
      run.flushPlayerCommands()
      require run.submissions.len == 1
      check run.submissions[0].kind == ActionMove
      check run.submissions[0].first == tile.x.int32
      check run.submissions[0].second == tile.y.int32

    test "HUD right click cancels without issuing a world order":
      fixture()
      let area = currentLayout(window).panel(GameUiRegion.BottomRight, PanelBuild)
      pointAt((area.origin + vec2(20)) * sk.uiScale)
      inputFrame({MouseRight})
      inputFrame(released = {MouseRight})
      run.flushPlayerCommands()
      check pendingBuild == -1
      check run.submissions.len == 0

    test "blueprint chosen during a held right button cannot place on release":
      fixture()
      pendingBuild = -1
      inputFrame({MouseRight})
      pendingBuild = FarmBuilding.ord.int32
      inputFrame(released = {MouseRight})
      run.flushPlayerCommands()
      check pendingBuild == FarmBuilding.ord.int32
      check run.submissions.len == 0

    test "Escape cancels blueprint without an order":
      fixture()
      window.onButtonPress(KeyEscape)
      check pendingBuild == -1
      check matchMenu == HiddenMatchMenu
      run.flushPlayerCommands()
      check run.submissions.len == 0

    test "menus chat and consumed shortcut edges cannot place":
      for page in [PauseMenu, MatchSettings]:
        fixture()
        matchMenu = page
        inputFrame({MouseLeft})
        inputFrame(released = {MouseLeft})
        run.flushPlayerCommands()
        check run.submissions.len == 0
      fixture()
      window.onButtonPress(KeyEnter)
      inputFrame({MouseLeft})
      inputFrame(released = {MouseLeft})
      run.flushPlayerCommands()
      check run.submissions.len == 0
      fixture()
      bindingCapture = true
      inputFrame({MouseLeft})
      inputFrame(released = {MouseLeft})
      run.flushPlayerCommands()
      check run.submissions.len == 0
      fixture()
      let saved = inputBindings
      customBindingsEnabled = true
      inputBindings[SelectInput] = [KeyB, ButtonUnknown]
      inputBindings = maskShortcutBindings(inputBindings, {KeyB})
      inputFrame({KeyB})
      inputFrame(released = {KeyB})
      run.flushPlayerCommands()
      check run.submissions.len == 0
      inputBindings = saved
      customBindingsEnabled = false

    test "another available selected worker retains blueprint and receives build":
      fixture()
      let other = run.world.spawnUnit(0, PeonUnit,
        tile2(run.world.map.side div 2 + 8, run.world.map.side div 2))
      selectedIds.add other
      run.world.units[run.world.unitIndex(worker)].state = UnitInMine
      inputFrame()
      check pendingBuild == FarmBuilding.ord.int32
      inputFrame({MouseLeft})
      inputFrame(released = {MouseLeft})
      run.flushPlayerCommands()
      require run.submissions.len == 1
      check run.submissions[0].entityId == other

    test "dead missing or non-owned workers clear only pending presentation":
      for unavailable in 0..3:
        fixture()
        let unit = run.world.units[run.world.unitIndex(worker)]
        case unavailable
        of 0: unit.hp = 0
        of 1: unit.state = UnitDying
        of 2: unit.owner = 1
        else: selectedIds = @[NoEntity]
        let before = run.stateHash()
        inputFrame()
        check pendingBuild == -1
        check run.stateHash() == before
        run.flushPlayerCommands()
        check run.submissions.len == 0

    test "placement can use its assigned worker inside the footprint":
      fixture()
      run.world.place(run.world.units[run.world.unitIndex(worker)], tile2(origin[0], origin[1]))
      require not run.world.canPlace(FarmBuilding, origin[0], origin[1])
      require run.world.canPlace(0, FarmBuilding, origin[0], origin[1], worker)
      let before = run.stateHash()
      inputFrame({MouseLeft})
      inputFrame(released = {MouseLeft})
      run.flushPlayerCommands()
      require run.submissions.len == 1
      check run.submissions[0].kind == ActionBuild
      check run.submissions[0].entityId == worker
      check run.stateHash() == before

    test "construction render pose follows active site without changing simulation":
      fixture()
      run.world.players[0].gold = 5000
      run.world.players[0].wood = 5000
      let unit = run.world.units[run.world.unitIndex(worker)]
      run.world.place(unit, tile2(origin[0], origin[1]))
      require run.world.applyBuild(0, worker, FarmBuilding.ord.int32, origin[0], origin[1])
      require unit.state == UnitBuilding
      let site = run.world.buildings[run.world.buildingIndex(unit.targetId)]
      let x = site.origin.x.float32 + site.footprint.width.float32 * 0.5'f32 - mapHalf()
      let z = site.origin.y.float32 + site.footprint.depth.float32 * 0.62'f32 - mapHalf()
      let before = run.stateHash()
      check renderPoint(unit) == vec3(x, surfaceHeight(x, z) + 0.09'f32, z)
      check abs(renderFacing(unit) - 3.14159265'f32) < 0.0001
      check renderAnimation(unit) == AttackAnimation
      captureUnitPoses()
      check previousUnitPositions[worker] == unitWorldPoint(unit)
      check run.stateHash() == before

    test "single-key builds and chat isolation":
      fixture()
      shortcutState.resetShortcut()
      currentShortcuts = DefaultShortcuts
      window.onButtonPress(KeyE)
      check pendingBuild == BarracksBuilding.ord.int32
      shortcutState.releaseShortcut('E')
      window.onButtonPress(KeyEscape)
      check pendingBuild == -1
      window.onButtonPress(KeyEnter)
      window.onButtonPress(KeyW)
      check pendingBuild == -1
      resetHumanCommunication()

    test "custom single key trains without navigation":
      fixture()
      run.world = newWorld(generateMap(DefaultSeed), TickRate * 60)
      run.world.players[0].gold = 5000
      run.world.players[0].wood = 5000
      run.world.players[0].foodCap = 100
      for structure in run.world.buildings:
        if structure.owner == 0 and structure.kind == TownHallBuilding:
          selectedIds = @[structure.id]
          primaryId = structure.id
          break
      pendingBuild = -1
      shortcutState.resetShortcut()
      currentShortcuts = DefaultShortcuts
      check currentShortcuts.setShortcut(TrainPeonShortcut, "7") == ""
      window.onButtonPress(Key7)
      shortcutState.releaseShortcut('7')
      run.flushPlayerCommands()
      require run.submissions.len == 1
      check run.submissions[0].kind == ActionTrain
      check run.submissions[0].first == PeonUnit.ord.int32
      window.state.buttonDown = {KeyLeftControl}
      window.onButtonPress(Key7)
      run.flushPlayerCommands()
      check run.submissions.len == 1
      window.state.buttonDown = {}
      currentShortcuts = DefaultShortcuts

  clickMarks.closeClickMarks()
  attackClickMarks.closeClickMarks()
  window.close()
  window = nil
  run = nil

main()
