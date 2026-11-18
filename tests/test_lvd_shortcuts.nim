import std/[json, unittest]
import ../games/light_vs_dark/[shortcuts, content, controls, maps, sim]

suite "LvD single contextual shortcuts":
  test "one key matches with repeat suppression and no hidden menu":
    var state: ShortcutState
    check state.pressShortcut(DefaultShortcuts, 'E', 0).action == BuildBarracksShortcut.ord
    check state.pressShortcut(DefaultShortcuts, 'E', 1).action == -1
    state.releaseShortcut('E')
    check state.pressShortcut(DefaultShortcuts, 'W', 3600).action == BuildFarmShortcut.ord
    state.releaseShortcut('W')
    check not state.pressShortcut(DefaultShortcuts, 'W', 3601, modified = true).consumed
    state.releaseShortcut('W')
    check not state.pressShortcut(DefaultShortcuts, 'W', 3602, gameplay = false).consumed
    state.resetShortcut()
    check not state.pressShortcut(DefaultShortcuts, 'E', 1, actions = {TrainPeonShortcut}).consumed
    check state.pressShortcut(DefaultShortcuts, 'Q', 2, actions = {TrainPeonShortcut}).action == TrainPeonShortcut.ord
  test "all actions match their single key in context":
    for action in ShortcutAction:
      var state: ShortcutState
      check DefaultShortcuts[action].len == 1
      check shortcutLabel(action).len > 0
      check state.pressShortcut(DefaultShortcuts, DefaultShortcuts[action][0], 0,
        actions = {action}).action == action.ord
  test "edits reject same-context collisions but allow different contexts":
    var bindings = DefaultShortcuts
    check bindings.setShortcut(BuildBarracksShortcut, "f").len > 0
    for invalid in ["", "BB", "B !", "Ctrl+B"]:
      check bindings.setShortcut(BuildBarracksShortcut, invalid).len > 0
    check bindings.setShortcut(BuildBarracksShortcut, "7") == ""
    check bindings.setShortcut(TrainPeonShortcut, "7") == ""
    check decodeShortcuts(encodeShortcuts(bindings)) == bindings
    check decodeShortcuts("") == DefaultShortcuts
    expect ValueError: discard decodeShortcuts("not json")
    bindings.resetShortcuts()
    check bindings == DefaultShortcuts


  test "default palettes avoid global actions and mixed producer collisions":
    for first in ShortcutAction:
      if first != CancelSiteShortcut:
        check DefaultShortcuts[first][0] notin ReservedShortcutKeys
      for second in ShortcutAction:
        if first < second and
            (first <= BuildBlacksmithShortcut) ==
            (second <= BuildBlacksmithShortcut):
          check DefaultShortcuts[first] != DefaultShortcuts[second]
    check DefaultShortcuts[CancelSiteShortcut] == "X"

  test "action keys stay reserved and cancel always remains X":
    var bindings = DefaultShortcuts
    for action in ShortcutAction:
      for key in ReservedShortcutKeys:
        if action != CancelSiteShortcut or key != 'X':
          check bindings.setShortcut(action, $key).len > 0
    check bindings.setShortcut(CancelSiteShortcut, "7").len > 0
    check bindings.setShortcut(CancelSiteShortcut, "X") == ""
    check bindings == DefaultShortcuts
    var invalid = bindings
    invalid[TrainPeonShortcut] = "A"
    expect ValueError: discard decodeShortcuts(encodeShortcuts(invalid))
    invalid = bindings
    invalid[CancelSiteShortcut] = "7"
    expect ValueError: discard decodeShortcuts(encodeShortcuts(invalid))
    invalid = bindings
    invalid[TrainPeonShortcut] = bindings[ResearchArrowsShortcut]
    expect ValueError: discard decodeShortcuts(encodeShortcuts(invalid))

  test "idle peon key is global rebindable and compatible with saved layouts":
    var bindings = DefaultShortcuts
    check bindings[IdlePeonShortcut] == "."
    check bindings.setShortcut(IdlePeonShortcut, "Q").len > 0
    check bindings.setShortcut(BuildFarmShortcut, ".").len > 0
    check bindings.setShortcut(TrainPeonShortcut, ".").len > 0
    check bindings.setShortcut(IdlePeonShortcut, ",") == ""
    check decodeShortcuts(encodeShortcuts(bindings)) == bindings
    var saved = parseJson(encodeShortcuts(bindings))
    saved["bindings"].delete($IdlePeonShortcut)
    saved["bindings"][$BuildBarracksShortcut] = %"7"
    let migrated = decodeShortcuts($saved)
    check migrated[IdlePeonShortcut] == "."
    check migrated[BuildBarracksShortcut] == "7"

suite "LvD shortcut migration":
  setup:
    let oldKeys = [
      "H", "F", "B", "L", "T", "U", "C", "K",
      "P", "S", "A", "M", "K", "C", "H", "E", "Q", "W", "R", "V", "X"
    ]
    var saved = newJObject()
    saved["version"] = %2
    saved["bindings"] = newJObject()
    for action in ShortcutAction.low .. CancelSiteShortcut:
      saved["bindings"][$action] = %oldKeys[action.ord]

  test "both older default formats become the current left-hand layout":
    check decodeShortcuts($saved) == DefaultShortcuts
    check shortcutMigrationReport.len > 0
    saved["version"] = %1
    for action in ShortcutAction.low .. CancelSiteShortcut:
      saved["bindings"][$action] = %("B " & oldKeys[action.ord])
    check decodeShortcuts($saved) == DefaultShortcuts

  test "valid custom bindings keep priority over new defaults":
    saved["bindings"][$BuildTownHallShortcut] = %"7"
    saved["bindings"][$TrainPeonShortcut] = %"W"
    let migrated = decodeShortcuts($saved)
    check migrated[BuildTownHallShortcut] == "7"
    check migrated[TrainPeonShortcut] == "W"
    check migrated[TrainSoldierShortcut] != "W"
    check decodeShortcuts(encodeShortcuts(migrated)) == migrated

  test "legacy reserved keys and custom cancel migrate to safe bindings":
    saved["bindings"][$BuildBarracksShortcut] = %"A"
    saved["bindings"][$TrainKnightShortcut] = %"X"
    saved["bindings"][$CancelSiteShortcut] = %"7"
    let migrated = decodeShortcuts($saved)
    check migrated[BuildBarracksShortcut] == "E"
    check migrated[TrainKnightShortcut] == "F"
    check migrated[CancelSiteShortcut] == "X"
    check shortcutMigrationReport.len > 0
    check decodeShortcuts(encodeShortcuts(migrated)) == migrated

  test "partial old files preserve edits and acquire current missing defaults":
    saved["bindings"] = %*{"BuildBarracksShortcut": "7"}
    let migrated = decodeShortcuts($saved)
    check migrated[BuildBarracksShortcut] == "7"
    check migrated[TrainPeonShortcut] == "Q"
    check migrated[CancelSiteShortcut] == "X"

suite "LvD shortcut commands":
  setup:
    clearPlayerCommands()
    let world = newWorld(generateMap(DefaultSeed), TickRate * 60)
    let game = Game(world: world)
    world.players[LightPlayer].gold = 10000
    world.players[LightPlayer].wood = 10000
    world.players[LightPlayer].foodCap = 100
  teardown:
    clearPlayerCommands()

  test "build arms only with eligible owned selected worker and real prerequisites":
    let worker = world.units[0].id
    require world.units[0].kind == PeonUnit
    require world.units[0].owner == LightPlayer
    check world.performShortcut(LightPlayer, [worker], BuildFarmShortcut)
    check pendingBuild == FarmBuilding.ord
    pendingBuild = -1
    for player in [-1'i32, DarkPlayer, world.players.len.int32]:
      check not world.performShortcut(player, [worker], BuildFarmShortcut)
    check not world.performShortcut(LightPlayer, [], BuildFarmShortcut)
    world.units[0].state = UnitInMine
    check not world.performShortcut(LightPlayer, [worker], BuildFarmShortcut)
    world.units[0].state = UnitDying
    check not world.performShortcut(LightPlayer, [worker], BuildFarmShortcut)
    world.units[0].state = UnitIdle
    world.units[0].hp = 0
    check not world.performShortcut(LightPlayer, [worker], BuildFarmShortcut)
    world.units[0].hp = 40
    world.players[LightPlayer].gold = 0
    check not world.performShortcut(LightPlayer, [worker], BuildFarmShortcut)
    check pendingBuild == -1

  test "train queues through controls and revalidates affordability at flush":
    var hall = NoEntity
    for building in world.buildings:
      if building.owner == LightPlayer and building.kind == TownHallBuilding:
        hall = building.id
    require hall != NoEntity
    let index = world.buildingIndex(hall)
    let before = world.players[LightPlayer].gold
    check world.performShortcut(LightPlayer, [hall], TrainPeonShortcut)
    check world.buildings[index].queueLength == 0
    check world.players[LightPlayer].gold == before
    game.flushPlayerCommands()
    check world.buildings[index].queueLength == 1
    check world.players[LightPlayer].gold == before - unitOf(LightPlayer, PeonUnit).gold
    check not world.performShortcut(DarkPlayer, [hall], TrainPeonShortcut)
    check not world.performShortcut(LightPlayer, [hall], TrainSoldierShortcut)
    check world.performShortcut(LightPlayer, [hall], TrainPeonShortcut)
    world.players[LightPlayer].gold = 0
    game.flushPlayerCommands()
    check world.buildings[index].queueLength == 1
    check not world.performShortcut(LightPlayer, [hall], TrainPeonShortcut)
