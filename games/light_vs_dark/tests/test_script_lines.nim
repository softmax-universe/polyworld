## Actual BASIC line orders share human formation geometry and replay actions.
import
  bassy,
  trafficfixture, ../[bots, linemoves, replays]

proc fixture(): tuple[game: Game, ids: seq[int32], enemy: int32] =
  ## Makes a funded, open match with a mixed group and an enemy to reject.
  let world = trafficFixture(0, "open").world
  result.game = newGame(world.map, TickRate * 60)
  result.game.world = world
  for index in 0 ..< 11:
    result.ids.add world.spawnUnit(0,
      (if index == 10: PeonUnit else: SoldierUnit),
      tile2(25 + index.int32 mod 4, 25 + index.int32 div 4))
  result.enemy = world.spawnUnit(1, SoldierUnit, tile2(50, 50))
  world.tick = DecisionTicks
  result.game.recorder = initReplayRecorder(Setup(
    players: @[ReplayPlayerSetup(id: 0), ReplayPlayerSetup(id: 1)]))

proc lineScript(ids: seq[int32]): string =
  ## Stages decimal tile-center coordinates on a short line requiring rows.
  result = "ok = lineStart()\n"
  for id in ids: result.add "ok = lineAddUnit(" & $id & ")\n"
  result.add "ok = lineAddPoint(35.25, 35)\n"
  result.add "ok = lineAddPoint(37.25, 35)\n"

proc execute(game: Game, source: string): seq[int32] =
  ## Runs a real player VM and captures integer results from its host calls.
  game.loadBots([source, ""])
  var values: seq[int32]
  game.brains[0].output = proc(event: PrintEvent) =
    ## Captures BASIC output without querying host callbacks directly.
    if event.kind == ValuePrint: values.add event.value
  game.runBotDecisions()
  doAssert not game.brains[0].failed, game.brains[0].lastError
  values

block plainLinesMatchHumanRowsAndRecordedActions:
  let
    (game, ids, enemy) = fixture()
    expected = game.world.planLineMove(0, ids,
      [linePoint(35.75, 35.5), linePoint(37.75, 35.5)])
    before = game.world.clone()
    source = lineScript(ids) &
      "print lineAddUnit(" & $ids[0] & ")\n" &
      "print lineAddUnit(" & $enemy & ")\n" &
      "print lineMove(0, 0)\nprint lineMove(0, 0)\n"
  doAssert expected.len == ids.len
  let values = game.execute(source)
  doAssert values == @[0'i32, 0, ids.len.int32, 0], $values
  doAssert game.recorder.data.actions.len == ids.len
  var rows: seq[int16]
  for i, target in expected:
    let action = game.recorder.data.actions[i]
    doAssert action.kind == ActionMove and not action.append
    doAssert action.entityId == target.unitId
    doAssert action.first == target.tile.x.int32
    doAssert action.second == target.tile.y.int32
    doAssert action.offset == target.offset
    if target.tile.y notin rows: rows.add target.tile.y
    doAssert before.applyReplayAction(action)
  doAssert rows.len > 1
  doAssert Game(world: before).stateHash() == game.stateHash()
  doAssert game.world.units[game.world.unitIndex(enemy)].state == UnitIdle

block attackLinesAppendAndKeepPeonsAsMovers:
  let (game, ids, _) = fixture()
  for id in ids: doAssert game.world.applyMove(0, id, 22, 22)
  let source = lineScript(ids) & "print lineMove(1, 1)\n"
  doAssert game.execute(source) == @[ids.len.int32]
  for i, id in ids:
    let
      unit = game.world.units[game.world.unitIndex(id)]
      kind = if unit.kind == PeonUnit: ActionMove else: ActionAttackMove
    doAssert unit.goal == tile2(22, 22)
    doAssert unit.orderQueue.len == 1 and unit.orderQueue[0].kind == kind
    doAssert game.recorder.data.actions[i].kind == kind
    doAssert game.recorder.data.actions[i].append

block stagingResetAndInvalidStrokeNeverIssuePartialOrders:
  let (game, ids, _) = fixture()
  let before = game.stateHash()
  var source = lineScript(ids)
  source.add "print lineStart()\nprint lineMove(0, 0)\n"
  source.add "print lineAddUnit(" & $ids[0] & ")\n"
  source.add lineScript(ids)
  source.add "print lineAddPoint(-1, 20)\nprint lineMove(0, 0)\n"
  doAssert game.execute(source) == @[1'i32, 0, 0, 0, 0]
  doAssert game.recorder.data.actions.len == 0
  doAssert game.stateHash() == before

echo "Script lines: rows, decimals, ownership, append and replay parity passed"
