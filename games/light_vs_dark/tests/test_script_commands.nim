## Real BASIC commands share the human validators, queues, and replay path.
import std/strformat
import bassy, polyworld/tapes
import trafficfixture, ../[bots, replays]

const Duration = TickRate * 120

proc fixture(): tuple[game: Game, worker: Unit, hall, enemyHall: int32] =
  ## Creates a funded match with one owned worker and real registered depots.
  let world = trafficFixture(0, "open").world
  result.game = newGame(world.map, Duration)
  result.game.world = world
  world.players[0].gold = 20000
  world.players[0].wood = 20000
  world.players[0].foodUsed = 0
  let id = world.spawnUnit(0, PeonUnit, tile2(20, 20))
  result.worker = world.units[world.unitIndex(id)]
  for building in world.buildings:
    if building.kind == TownHallBuilding:
      if building.owner == 0: result.hall = building.id
      else: result.enemyHall = building.id

proc execute(game: Game, source: string): seq[int32] =
  ## Compiles and runs the actual player host, collecting BASIC assertions.
  game.loadBots([source, ""])
  var values: seq[int32]
  game.brains[0].output = proc(event: PrintEvent) =
    ## Collects numeric results without coupling tests to runtime variables.
    if event.kind == ValuePrint: values.add event.value
  game.runBotDecisions()
  doAssert not game.brains[0].failed, game.brains[0].lastError
  values

proc allTrue(values: seq[int32]) =
  ## Requires every printed command acceptance or query assertion to succeed.
  doAssert values.len > 0
  for index, value in values:
    doAssert value != 0, &"BASIC assertion {index} returned {value}"

proc tree(world: World, x, y: int32): int32 =
  ## Adds a resource with its normal terrain blocker.
  result = world.map.tileIndex(x, y)
  world.treeWood[result] = WoodPerTree
  world.blocker[result] = TreeBlocker

proc complete(world: World, worker: Unit, kind: BuildingKind,
    x, y: int32): int32 =
  ## Registers a paid producer and completes its setup before the script runs.
  doAssert world.applyBuild(0, worker.id, kind.ord.int32, x, y)
  result = world.buildings[^1].id
  world.buildings[^1].state = BuildingComplete
  world.buildings[^1].hp = world.buildings[^1].maxHp
  doAssert world.applyCancel(0, worker.id)

block queuePayloadsDecimalsAndOwnership:
  let
    (game, worker, _, enemyHall) = fixture()
    world = game.world
    soldier = world.spawnUnit(0, SoldierUnit, tile2(18, 20))
    enemy = world.spawnUnit(1, SoldierUnit, tile2(22, 21))
    resource = world.tree(25, 25)
  world.diplomacy.pairs[world.diplomacy.pairIndex(0, 1)].state = AtWar
  world.rebuildVision()
  worker.carryWood = 7
  let opponent = world.units[world.unitIndex(enemy)]
  opponent.carryGold = 42
  opponent.orderQueue.add UnitOrder(kind: ActionMove, first: 30, second: 30)
  game.execute(&"""
print canPlace({FarmBuilding.ord}, 20, 20) = 0
print canPlaceFor({worker.id}, {FarmBuilding.ord}, 20, 20)
print canQueueBuild({worker.id}, {FarmBuilding.ord}, 26, 22)
print moveUnit({worker.id}, 21, 20)
print queueMove({worker.id}, 22.25, 20.25)
print queueHarvest({worker.id}, {resource}, 1)
print queueBuild({worker.id}, {FarmBuilding.ord}, 26, 22)
print queuedOrderCount({worker.id}) = 3
print queuedOrderKind({worker.id}, 0) = {ActionMove}
print queuedOrderFirst({worker.id}, 0) = 22
print queuedOrderSecond({worker.id}, 0) = 20
print queuedOrderX({worker.id}, 0) = 22.25
print queuedOrderY({worker.id}, 0) = 20.25
print queuedOrderKind({worker.id}, 1) = {ActionHarvest}
print queuedOrderFirst({worker.id}, 1) = {resource}
print queuedOrderX({worker.id}, 1) = -1
print queuedOrderKind({worker.id}, 2) = {ActionBuild}
print queuedOrderFirst({worker.id}, 2) = {FarmBuilding.ord}
print queuedOrderSecond({worker.id}, 2) = 26
print queuedOrderThird({worker.id}, 2) = 22
print queuedOrderX({worker.id}, 2) = 26
print queuedOrderY({worker.id}, 2) = 22
print carriedWood({worker.id}) = 7
print carriedGold({worker.id}) = 0
print attackMove({soldier}, 19.25, 20.25)
print queueAttackMove({soldier}, 23.25, 20.25)
print queueAttack({soldier}, {enemy})
print queuedOrderCount({soldier}) = 2
print queuedOrderKind({soldier}, 0) = {ActionAttackMove}
print queuedOrderKind({soldier}, 1) = {ActionAttack}
print queueMove({enemy}, 30, 30) = 0
print queueAttackMove({enemy}, 30, 30) = 0
print queueBuild({enemy}, {FarmBuilding.ord}, 30, 30) = 0
print canPlaceFor({enemy}, {FarmBuilding.ord}, 30, 30) = 0
print queuedOrderCount({enemy}) = 0
print queuedOrderKind({enemy}, 0) = 0
print queuedOrderFirst({enemy}, 0) = -1
print queuedOrderX({enemy}, 0) = -1
print queuedOrderThird({worker.id}, 99) = -1
print queuedOrderKind({worker.id}, -1) = 0
print carriedGold({enemy}) = 0
print trainingCount({enemyHall}) = 0
print trainingKind({enemyHall}, 0) = -1
print rallyKind({enemyHall}) = -1
print rallyX({enemyHall}) = -1
print researchKind({enemyHall}) = -1
print researchTicks({enemyHall}) = 0
print cancel({worker.id})
print queuedOrderCount({worker.id}) = 0
""").allTrue()
  doAssert world.units[world.unitIndex(soldier)].attackMove
  doAssert opponent.orderQueue.len == 1 and opponent.carryGold == 42
  doAssert worker.carryWood == 7 and worker.orderQueue.len == 0

block directAndQueuedDepositsUseTheChosenDepot:
  let
    (game, worker, hall, enemyHall) = fixture()
    world = game.world
    mill = world.complete(worker, LumberMillBuilding, 16, 15)
  worker.carryWood = WoodPerTrip
  game.execute(&"""
print deposit({worker.id}, {mill})
print cancel({worker.id})
print moveUnit({worker.id}, 21, 20)
print queueDeposit({worker.id}, {hall})
print queuedOrderCount({worker.id}) = 1
print queuedOrderKind({worker.id}, 0) = {ActionDeposit}
print queuedOrderFirst({worker.id}, 0) = {hall}
""").allTrue()
  for tick in 0 ..< TickRate * 30: world.tickWorld(nil)
  doAssert world.players[0].woodGathered == WoodPerTrip
  doAssert worker.carryWood == 0
  worker.carryGold = GoldPerTrip
  game.execute(&"""
print deposit({worker.id}, {mill}) = 0
print deposit({worker.id}, {enemyHall}) = 0
print deposit({worker.id}, {hall})
""").allTrue()
  doAssert worker.state == UnitToDropGold and worker.targetId == hall

block productionResearchAndResourceRallies:
  let
    (game, worker, hall, enemyHall) = fixture()
    world = game.world
    barracks = world.complete(worker, BarracksBuilding, 24, 12)
    smith = world.complete(worker, BlacksmithBuilding, 28, 12)
    mine = world.buildings[world.buildingIndex(FirstMineId)]
    resource = world.tree(25, 25)
    cost = researchStats(TemperedEdges, 1)
  game.execute(&"""
print canResearch({smith}, {TemperedEdges.ord})
print research({smith}, {TemperedEdges.ord})
print researchKind({smith}) = {TemperedEdges.ord}
print researchTicks({smith}) = {cost.ticks}
print researchLevel({TemperedEdges.ord}) = 0
print canResearch({smith}, {RunedPlating.ord}) = 0
print cancel({smith})
print researchKind({smith}) = -1
print researchTicks({smith}) = 0
print research({smith}, {TemperedEdges.ord})
print research({enemyHall}, {TemperedEdges.ord}) = 0
print setRally({hall}, 25, 25)
print rallyKind({hall}) = {RallyWood.ord}
print rallyX({hall}) = 25
print rallyY({hall}) = 25
print setRally({hall}, {mine.origin.x}, {mine.origin.y})
print rallyKind({hall}) = {RallyGold.ord}
print rallyX({hall}) = {mine.origin.x}
print rallyY({hall}) = {mine.origin.y}
print train({hall}, {PeonUnit.ord})
print train({hall}, {PeonUnit.ord})
print trainingCount({hall}) = 2
print trainingKind({hall}, 0) = {PeonUnit.ord}
print trainingKind({hall}, 1) = {PeonUnit.ord}
print trainingKind({hall}, 2) = -1
print trainingTicks({hall}) = {unitOf(0, PeonUnit).trainTicks}
print cancel({hall})
print trainingCount({hall}) = 1
""").allTrue()
  let before = world.units.len
  for tick in 0 ..< unitOf(0, PeonUnit).trainTicks: world.tickWorld(nil)
  doAssert world.units.len == before + 1
  doAssert world.units[^1].state == UnitToMine
  doAssert world.units[^1].sourceId == mine.id
  for tick in 0 ..< cost.ticks: world.tickWorld(nil)
  game.execute(&"print researchLevel({TemperedEdges.ord}) = 1").allTrue()
  doAssert world.buildings[world.buildingIndex(barracks)].queueLength == 0
  doAssert world.treeWood[resource] == WoodPerTree

block nearestTreeUsesDistanceAndStableTies:
  let (game, _, _, _) = fixture()
  discard game.world.tree(23, 23)
  let axial = game.world.tree(24, 20)
  game.execute(&"print nearestTree(20, 20) = {axial}").allTrue()
  let tied = game.world.tree(16, 20)
  doAssert tied < axial
  game.execute(&"""
print nearestTree(20, 20) = {tied}
print nearestTree(-1, 20) = -1
print nearestTree(20, -1) = -1
print nearestTree({game.world.map.side}, 20) = -1
print nearestTree(20, {game.world.map.side}) = -1
""").allTrue()

block waitingBuildWorkersAreNotIdle:
  let (game, worker, _, _) = fixture()
  game.world.players[0].gold = 0
  game.world.players[0].wood = 0
  doAssert game.world.applyBuild(0, worker.id, FarmBuilding.ord.int32,
    24, 20, append = true)
  let before = game.stateHash()
  game.execute(&"""
print obsIdle(obsIndexOf({worker.id})) = 0
print nearestOwnIdle({PeonUnit.ord}, 20, 20) = {NoEntity}
print queuedOrderCount({worker.id}) = 1
""").allTrue()
  doAssert game.stateHash() == before

block recordedScriptQueuesReplayEveryTick:
  let
    (game, worker, hall, _) = fixture()
    world = game.world
    soldier = world.spawnUnit(0, SoldierUnit, tile2(18, 18))
    initial = world.clone()
  var setup = Setup(mapSeed: world.map.seed, tickRate: TickRate.uint16,
    gridTiles: world.map.side.uint16, decisionTicks: DecisionTicks.uint16,
    maximumTicks: Duration.uint32, mapHash: 1, contentHash: contentHash())
  for player, origin in world.map.hallOrigin:
    setup.players.add ReplayPlayerSetup(id: player.int32,
      startX: origin.x.int32, startY: origin.y.int32)
  game.recorder = initReplayRecorder(setup)
  game.loadBots([&"""
if worldTick = {DecisionTicks} then
  accepted = moveUnit({worker.id}, 22.25, 20.25)
  accepted = queueBuild({worker.id}, {FarmBuilding.ord}, 24, 20)
  accepted = queueMove({worker.id}, 28.25, 20.25)
  accepted = attackMove({soldier}, 20.25, 18.25)
  accepted = queueAttackMove({soldier}, 26.25, 18.25)
  accepted = setRally({hall}, 58, 40)
  accepted = train({hall}, {PeonUnit.ord})
end if
""", ""])
  proc decide(w: World) =
    ## Runs the compiled script only through the normal decision callback.
    game.runBotDecisions()
  for tick in 0 ..< TickRate * 60:
    world.tickWorld(decide)
    game.recorder.recordHash(game.stateHash())
  doAssert not game.brains[0].failed, game.brains[0].lastError
  doAssert game.recorder.data.actions.len == 7
  doAssert world.buildingCount(0) == 2
  let
    data = decodeReplay(encodeReplay(game.recorder.data))
    playback = Game(world: initial)
    cursor = initReplayPlayer(data)
  proc replay(w: World) =
    ## Replays serialized accepted actions without rerunning the script.
    var action: ReplayAction
    while cursor.takeActionAt(w.tick.uint32, action):
      doAssert w.applyReplayAction(action)
  for hash in data.hashes:
    playback.world.tickWorld(replay)
    doAssert playback.stateHash() == hash
  doAssert cursor.finished

echo "BASIC commands: queues, resources, research, ownership and replay passed"
