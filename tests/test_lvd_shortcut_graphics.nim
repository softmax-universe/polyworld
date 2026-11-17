## Executes the actual graphics key callback, not a duplicate dispatcher.
import std/[unittest, macros, importutils]
import windy/internal
include ../games/light_vs_dark/graphics
privateAccess(Window)

macro keyHandler(name: static[string]): untyped =
  ## Extracts production callbacks for invisible-window testing.
  let source = parseStmt(staticRead("../games/light_vs_dark/graphics.nim"))
  for node in source:
    if node.kind == nnkProcDef and node[0].repr == "runGraphics*":
      for child in node[^1]:
        if child.kind == nnkAsgn and child[0].repr == "window." & name and
            child[1].kind == nnkLambda:
          return child
  error("missing production key handler")

suite "LvD production shortcut routing":
  test "left-hand commands preserve actions, cancellation and text input":
    window = newWindow("LvD shortcuts", ivec2(1600, 1000), visible = false)
    defer:
      window.close()
      window = nil
      run = nil
      clearPlayerCommands()
    sk = Silky(uiScale: 1)
    options.playerSlot = 1
    run = newGame(generateMap(DefaultSeed), TickRate * 60)
    run.world.players[0].gold = 10000
    run.world.players[0].wood = 10000
    run.world.players[0].foodCap = 100
    var
      matchMenu = HiddenMatchMenu
      preferences = Preferences()
      network: NetworkMatch
      scene: CharacterScene
      actionCam = initActionCam(subjectMode = true)
    proc playerMode(): bool = options.playerSlot > 0 and not run.replayMode
    let hooks = GraphicsHooks()
    keyHandler("onButtonPress")
    keyHandler("onButtonRelease")
    inputBindings = LvdControlProfile.defaults
    bindingCapture = false
    currentShortcuts = DefaultShortcuts
    resetHumanCommunication()
    selectedIds = @[run.world.units[0].id]
    window.onButtonPress(KeyE)
    check pendingBuild == BarracksBuilding.ord
    pendingBuild = -1
    window.onButtonPress(KeyE)
    check pendingBuild == -1 # repeat suppression
    shortcutState.releaseShortcut('E')
    window.onButtonPress(KeyW)
    check pendingBuild == FarmBuilding.ord
    pendingBuild = -1
    shortcutState.resetShortcut()
    var hall = NoEntity
    for building in run.world.buildings:
      if building.owner == 0 and building.kind == TownHallBuilding: hall = building.id
    selectedIds = @[hall]
    window.onButtonPress(KeyQ)
    run.flushPlayerCommands()
    check run.world.buildings[run.world.buildingIndex(hall)].queueLength == 1
    shortcutState.resetShortcut()
    selectedIds = @[run.world.spawnUnit(0, SoldierUnit, tile2(30, 30))]
    window.onButtonPress(KeyA)
    check attackMoveArmed
    attackMoveArmed = false
    shortcutState.resetShortcut()
    matchMenu = MatchSettings
    window.onButtonPress(KeyE)
    shortcutState.releaseShortcut('E')
    window.onButtonPress(KeyE)
    check pendingBuild == -1
    matchMenu = HiddenMatchMenu
    shortcutState.resetShortcut()
    let priorSelection = selectedIds
    selectedIds = @[hall]
    window.state.buttonDown = {KeyLeftSuper}
    window.onButtonPress(KeyQ)
    window.onButtonRelease(KeyQ)
    window.state.buttonDown = {}
    selectedIds = priorSelection
    run.flushPlayerCommands()
    check run.world.buildings[run.world.buildingIndex(hall)].queueLength == 1

    # W trains, whereas S stops current and queued moves.
    shortcutState.resetShortcut()
    let soldier = selectedIds[0]
    let worker = run.world.units[0].id
    let barracks = hall
    run.world.buildings[run.world.buildingIndex(hall)].kind = BarracksBuilding
    selectedIds = @[barracks]
    for id in [soldier, worker]:
      require run.world.applyMove(0, id, 40, 40)
      require run.world.applyMove(0, id, 41, 40, append = true)
    window.onButtonPress(KeyW)
    run.flushPlayerCommands()
    check run.world.buildings[run.world.buildingIndex(barracks)].queueLength == 2
    for id in [soldier, worker]:
      check run.world.units[run.world.unitIndex(id)].state == UnitMoving
      check run.world.units[run.world.unitIndex(id)].orderQueue.len == 1
    shortcutState.resetShortcut()
    selectedIds = @[soldier, worker]
    window.onButtonPress(KeyS)
    run.flushPlayerCommands()
    for id in [soldier, worker]:
      check run.world.units[run.world.unitIndex(id)].state == UnitIdle
      check run.world.units[run.world.unitIndex(id)].orderQueue.len == 0
    shortcutState.resetShortcut()
    selectedIds = @[worker]
    window.onButtonPress(KeyA)
    check attackMoveArmed
    window.onButtonPress(KeyEscape)
    check not attackMoveArmed
    check matchMenu == HiddenMatchMenu
    shortcutState.resetShortcut()
    inputBindings[AttackMoveInput] = [KeyW, ButtonUnknown]
    window.onButtonPress(KeyA)
    check not attackMoveArmed
    window.onButtonPress(KeyW)
    check attackMoveArmed
    inputBindings[StopInput] = [KeyJ, ButtonUnknown]
    window.onButtonPress(KeyJ)
    check not attackMoveArmed
    inputBindings = LvdControlProfile.defaults

    # E trains an Archer without stealing attack move from A.
    shortcutState.resetShortcut()
    run.world.buildings.add Building(owner: 0, kind: LumberMillBuilding,
      state: BuildingComplete, hp: 100)
    require run.world.canTrain(barracks, ArcherUnit)
    selectedIds = @[barracks]
    window.onButtonPress(KeyE)
    run.flushPlayerCommands()
    check not attackMoveArmed
    check run.world.buildings[run.world.buildingIndex(barracks)].queueLength == 3

    # Text and modal owners precede both persistent menu and combat dispatch.
    resetHumanCommunication()
    shortcutState.resetShortcut()
    selectedIds = @[soldier]
    window.onButtonPress(KeyEnter)
    require humanCommunicationBlocksGameplay()
    for key in [KeyE, KeyT, KeyA]: window.onButtonPress(key)
    check not attackMoveArmed
    check pendingBuild == -1
    resetHumanCommunication()
    matchMenu = MatchSettings
    window.onButtonPress(KeyA)
    check not attackMoveArmed
    matchMenu = HiddenMatchMenu
    bindingCapture = true
    window.onButtonPress(KeyA)
    check not attackMoveArmed
    bindingCapture = false

    # X abandons previews without clearing the worker's actual orders.
    resetHumanCommunication()
    window.runeInputEnabled = false
    shortcutState.resetShortcut()
    pendingBuild = -1
    cancelGameplayGestures()
    selectedIds = @[worker]
    require run.world.applyMove(0, worker, 40, 40)
    for intent in 0 .. 2:
      case intent
      of 0:
        window.onButtonPress(KeyW)
        window.onButtonRelease(KeyW)
        require pendingBuild == FarmBuilding.ord
      of 1:
        window.onButtonPress(KeyA)
        require attackMoveArmed
      else:
        lineGesture = LineGesture(active: true, dragging: true)
        rightOrderStarted = true
      window.onButtonPress(KeyX)
      window.onButtonRelease(KeyX)
      run.flushPlayerCommands()
      check pendingBuild == -1
      check not attackMoveArmed
      check attackHeldButtons == {}
      check not lineGesture.active
      check not rightOrderStarted
      check matchMenu == HiddenMatchMenu
      check run.world.units[run.world.unitIndex(worker)].state == UnitMoving
      window.onButtonRelease(KeyA)

    # Holding X removes one queued unit, even with malformed custom bindings.
    selectedIds = @[barracks]
    let index = run.world.buildingIndex(barracks)
    require run.world.buildings[index].queueLength == 3
    inputBindings[AttackMoveInput] = [KeyX, ButtonUnknown]
    currentShortcuts[TrainSoldierShortcut] = "X"
    for i in 0 .. 4: window.onButtonPress(KeyX)
    run.flushPlayerCommands()
    check run.world.buildings[index].queueLength == 2
    window.onButtonRelease(KeyX)
    window.onButtonPress(KeyX)
    window.onButtonRelease(KeyX)
    run.flushPlayerCommands()
    check run.world.buildings[index].queueLength == 1
    inputBindings = LvdControlProfile.defaults
    currentShortcuts = DefaultShortcuts

    # Mixed selection cancels construction and stops units with the same X.
    run.world.buildings[index].state = BuildingUnderConstruction
    selectedIds = @[worker, barracks]
    window.onButtonPress(KeyX)
    window.onButtonRelease(KeyX)
    run.flushPlayerCommands()
    check run.world.buildings[index].state == BuildingDying
    check run.world.units[run.world.unitIndex(worker)].state == UnitIdle

    # X closes menus, but remains a letter in text fields.
    matchMenu = MatchSettings
    window.onButtonPress(KeyX)
    window.onButtonRelease(KeyX)
    check matchMenu == PauseMenu
    window.onButtonPress(KeyX)
    window.onButtonRelease(KeyX)
    check matchMenu == HiddenMatchMenu
    window.onButtonPress(KeyEnter)
    window.onButtonRelease(KeyEnter)
    require humanCommunicationTyping()
    window.onButtonPress(KeyX)
    window.onButtonRelease(KeyX)
    check humanCommunicationTyping()
    window.onButtonPress(KeyEscape)
    window.onButtonRelease(KeyEscape)
    finishHumanCommunicationFrame()
    check not window.visible
