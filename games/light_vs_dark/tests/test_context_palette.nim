import std/[unittest, json]
import ../[shortcuts, content, controls, maps, sim]

suite "single contextual action palette":
  test "worker F and hall P work immediately without navigation":
    let w = newWorld(generateMap(DefaultSeed), TickRate * 60)
    w.players[0].gold = 10000
    w.players[0].wood = 10000
    w.players[0].foodCap = 100
    var state: ShortcutState
    check DefaultShortcuts[BuildFarmShortcut] == "F"
    let match = state.pressShortcut(DefaultShortcuts, 'F', 0)
    check match.action == BuildFarmShortcut.ord
    check w.performShortcut(0, [w.units[0].id], BuildFarmShortcut)
    check pendingBuild == FarmBuilding.ord
    pendingBuild = -1
    var hall = NoEntity
    for b in w.buildings:
      if b.owner == 0 and b.kind == TownHallBuilding: hall = b.id
    check state.pressShortcut(DefaultShortcuts, 'P', 0).action == TrainPeonShortcut.ord
    check w.performShortcut(0, [hall], TrainPeonShortcut)
    clearPlayerCommands()

  test "catalog follows selection and includes unavailable actions":
    let w = newWorld(generateMap(DefaultSeed), TickRate * 60)
    var hall = NoEntity
    for b in w.buildings:
      if b.owner == 0 and b.kind == TownHallBuilding: hall = b.id
    when declared(contextualActions):
      let worker = w.contextualActions(0, [w.units[0].id])
      check BuildFarmShortcut in worker
      check TrainPeonShortcut notin worker
      check w.contextualActions(0, [hall]) == {TrainPeonShortcut}
      check w.contextualActions(0, []) == {}
      w.buildings[w.buildingIndex(hall)].kind = BarracksBuilding
      let military = w.contextualActions(0, [hall])
      check TrainSoldierShortcut in military
      check TrainArcherShortcut in military
      check TrainPeonShortcut notin military
      var state: ShortcutState
      check state.pressShortcut(DefaultShortcuts, 'S', 0, actions = military).action == TrainSoldierShortcut.ord
    else:
      check false

  test "unfinished sites offer cancel only and completed buildings never demolish":
    let w = newWorld(generateMap(DefaultSeed), TickRate * 60)
    let id = w.buildings[0].id
    w.buildings[0].owner = 0
    w.buildings[0].state = BuildingUnderConstruction
    when declared(CancelSiteShortcut):
      check w.contextualActions(0, [id]) == {CancelSiteShortcut}
      check w.performShortcut(0, [id], CancelSiteShortcut)
      clearPlayerCommands()
      w.buildings[0].state = BuildingComplete
      check CancelSiteShortcut notin w.contextualActions(0, [id])
      check not w.performShortcut(0, [id], CancelSiteShortcut)
    else:
      check false

  test "legacy pairs migrate second key and report only contextual conflicts":
    var old = %*{"version": 1, "bindings": {"BuildFarmShortcut": "Q7", "TrainPeonShortcut": "X7"}}
    when declared(shortcutMigrationReport):
      old["bindings"]["BuildStablesShortcut"] = %"BS"
      let legacyStop = decodeShortcuts($old)
      check legacyStop[BuildStablesShortcut] == "U"
      check shortcutMigrationReport.len > 0
      old["bindings"].delete("BuildStablesShortcut")
      let b = decodeShortcuts($old)
      check b[BuildFarmShortcut] == "7"
      check b[TrainPeonShortcut] == "7"
      check shortcutMigrationReport.len == 0
      old["bindings"]["BuildBarracksShortcut"] = %"Z7"
      let fixed = decodeShortcuts($old)
      check fixed[BuildFarmShortcut] == "7"
      check fixed[BuildBarracksShortcut] == "B"
      check shortcutMigrationReport.len > 0
      check decodeShortcuts(encodeShortcuts(fixed)) == fixed
    else:
      check false
