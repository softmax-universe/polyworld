import std/unittest
import ../[content, sim, controls, shortcuts, maps, replays]

proc fixture(): Game =
  clearPlayerCommands()
  result = Game(world: newWorld(generateMap(DefaultSeed), TickRate * 60), networked: true)
  result.recorder = initReplayRecorder(Setup(gridTiles: result.world.map.side.uint16,
    maximumTicks: (TickRate * 60).uint32, decisionTicks: DecisionTicks.uint16,
    players: @[ReplayPlayerSetup(id: 0), ReplayPlayerSetup(id: 1)]))
  let w = result.world
  w.buildings.setLen(0)
  w.buildingSlot.setLen(w.map.mines.len + 3)
  for i in 0 .. 2:
    w.buildings.add Building(id: FirstBuildingId + i.int32, owner: 0,
      kind: BarracksBuilding, state: BuildingComplete, hp: 100,
      footprint: BuildingTable[BarracksBuilding].footprint, origin: tile2(20 + i.int32 * 5, 20))
    w.buildingSlot[w.map.mines.len + i] = i.int32
  w.players[0].gold = 10000
  w.players[0].wood = 10000
  w.players[0].foodCap = 100

let selected = @[FirstBuildingId, FirstBuildingId + 1, FirstBuildingId + 2]
suite "selected producer command routing":
  test "2/2/1 chooses one then rapid clicks balance pending loads without mutation":
    let g = fixture()
    for i, count in [2, 2, 1]:
      for n in 0 ..< count: require g.world.applyTrain(0, selected[i], SoldierUnit.ord.int32)
    let before = g.stateHash()
    for n in 0 ..< 4:
      require g.world.performShortcut(0, selected, TrainSoldierShortcut)
    g.flushPlayerCommands()
    check g.stateHash() == before
    require g.submissions.len == 4
    check g.submissions[0].entityId == selected[2]
    check g.submissions[1].entityId == selected[0]
    check g.submissions[2].entityId == selected[1]
    check g.submissions[3].entityId == selected[2]

  test "network-flushed pending trains reserve all capacity and budget":
    let g = fixture()
    g.world.players[0].gold = unitOf(0, SoldierUnit).gold * 2
    require g.world.performShortcut(0, selected, TrainSoldierShortcut)
    g.flushPlayerCommands()
    require g.world.performShortcut(0, selected, TrainSoldierShortcut)
    g.flushPlayerCommands()
    check not g.world.performShortcut(0, selected, TrainSoldierShortcut)
    require g.submissions.len == 2
    check g.submissions[0].entityId == selected[0]
    check g.submissions[1].entityId == selected[1]
    clearPlayerCommands()
    g.world.players[0].gold = 10000
    for n in 0 ..< QueueSlots * selected.len:
      require g.world.performShortcut(0, selected, TrainSoldierShortcut)
      g.flushPlayerCommands()
    check not g.world.performShortcut(0, selected, TrainSoldierShortcut)
    for id in selected:
      var count = 0
      for action in g.submissions[2 .. ^1]:
        if action.entityId == id: inc count
      check count == QueueSlots

  test "food and wood reservations, dead or foreign producers, local acceptance":
    let g = fixture()
    g.world.players[0].foodCap = g.world.players[0].foodUsed + unitOf(0, SoldierUnit).food
    require g.world.queueSelectedTrain(0, selected, SoldierUnit)
    check not g.world.queueSelectedTrain(0, selected, SoldierUnit)
    clearPlayerCommands()
    g.world.players[0].foodCap = 100
    g.world.players[0].wood = 0
    check not g.world.queueSelectedTrain(0, selected, CatapultUnit)
    g.world.players[0].wood = 10000
    g.world.buildings[0].hp = 0
    g.world.buildings[1].owner = 1
    g.world.buildings[2].state = BuildingUnderConstruction
    check not g.world.queueSelectedTrain(0, selected, SoldierUnit)
    g.world.buildings[2].state = BuildingComplete
    g.networked = false
    let gold = g.world.players[0].gold
    require g.world.queueSelectedTrain(0, selected, SoldierUnit)
    check g.world.selectedTrainingCount(0, selected, SoldierUnit) == 1
    g.flushPlayerCommands()
    check g.world.players[0].gold == gold - unitOf(0, SoldierUnit).gold
    check g.world.buildings[2].queueLength == 1
    check g.world.selectedTrainingCount(0, selected, SoldierUnit) == 1
    check g.submissions.len == 0

  test "authority rejection retires reservation and selection changes do not discard it":
    let g = fixture()
    g.world.players[0].gold = unitOf(0, SoldierUnit).gold
    require g.world.queueSelectedTrain(0, @[selected[0]], SoldierUnit)
    g.flushPlayerCommands()
    check not g.world.queueSelectedTrain(0, @[selected[1]], SoldierUnit)
    let action = g.submissions[0]
    g.world.buildings[0].state = BuildingUnderConstruction
    check not g.world.applyReplayAction(action)
    g.world.retireProductionReservation(action)
    require g.world.queueSelectedTrain(0, @[selected[1]], SoldierUnit)
