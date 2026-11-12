import std/unittest
import ../games/light_vs_dark/[shortcuts, content, controls, maps, sim]

suite "LvD single contextual shortcuts":
  test "one key matches with repeat suppression and no hidden menu":
    var state: ShortcutState
    check state.pressShortcut(DefaultShortcuts, 'B', 0).action == BuildBarracksShortcut.ord
    check state.pressShortcut(DefaultShortcuts, 'B', 1).action == -1
    state.releaseShortcut('B')
    check state.pressShortcut(DefaultShortcuts, 'F', 3600).action == BuildFarmShortcut.ord
    state.releaseShortcut('F')
    check not state.pressShortcut(DefaultShortcuts, 'F', 3601, modified = true).consumed
    state.releaseShortcut('F')
    check not state.pressShortcut(DefaultShortcuts, 'F', 3602, gameplay = false).consumed
    state.resetShortcut()
    check not state.pressShortcut(DefaultShortcuts, 'B', 1, actions = {TrainPeonShortcut}).consumed
    check state.pressShortcut(DefaultShortcuts, 'P', 2, actions = {TrainPeonShortcut}).action == TrainPeonShortcut.ord
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
