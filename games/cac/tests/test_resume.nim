import ../src/core/[bots, match, replays, sim]

const
  SetupSource = """
if selectingClass then
  pickClass(1)
  deckCard("Warrior", 40)
  end
end if
"""
  OriginalSource = SetupSource & "endTurn()\n"
  ReplacementSource = SetupSource & """
calls = calls + 1
seenTurn = turnNumber
roll = random(1000)
sent = sendChat(enemyPlayer, "candidate")
if canPlay(0) then
  playCard(0)
else
  endTurn()
end if
"""

proc recording(): ReplayData =
  ## Records a legal match whose policies always end their turns.
  let
    bots = loadBots([OriginalSource, OriginalSource])
    seats = bots.setupBotSeats(19)
    recorder = initReplayRecorder(
      matchSetup(seats, 19, 8),
      GameConfig(seed: 19, maxTicks: 8, players: unnamedPlayers(2))
    )
  var game = initBotMatch(seats, 19, bots, 8, recorder)
  game.run()
  doAssert game.tick == 8
  recorder.data

proc resumed(data: ReplayData, step: uint32): BotMatch =
  ## Initializes selected policies while preserving the recorded match setup.
  let
    bots = loadBots([ReplacementSource, ReplacementSource])
    recorder = initReplayRecorder(data.header.setup, data.config)
  discard bots.setupBotSeats(data.header.setup.seed)
  result = initBotMatch(
    data.header.setup.seats,
    data.header.setup.seed,
    bots,
    data.header.setup.maximumTicks,
    recorder
  )
  result.warmup = data
  result.resumeStep = step

proc calls(game: BotMatch): int32 =
  ## Counts all selected policies' completed decision invocations.
  for bot in game.bots:
    result += bot.runtime.getGlobal("calls")

echo "CaC warms selected policies without changing the replay prefix"
block:
  let data = recording()
  var game = resumed(data, 4)
  for tick in 0 ..< 4:
    doAssert game.step()
    doAssert game.game.stateHash == data.hashes[tick]
    doAssert game.recorder.data.actions[tick] == data.actions[tick]
    doAssert game.calls == int32(tick + 1)
    for inbox in inboxes:
      doAssert inbox.count == 0
  for bot in game.bots:
    doAssert bot.runtime.getGlobal("calls") == 2
  let player = game.game.actingPlayer()
  doAssert game.step()
  doAssert game.calls == 5
  doAssert game.bots[player].runtime.getGlobal("calls") == 3
  doAssert game.recorder.data.actions[4].kind == ActionPlayCard
  doAssert data.actions[4].kind == ActionEndTurn
  doAssert game.game.stateHash != data.hashes[4]
  doAssert inboxes[game.game.nextPlayer(player)].count == 1
  var replayed = newGame(game.recorder.data.header.setup)
  for action in game.recorder.data.actions:
    doAssert replayed.applyAction(action)
    discard replayed.takeVisualEvents()
    doAssert replayed.stateHash == game.recorder.data.hashes[action.tick - 1]

echo "CaC supports immediate and full-prefix handoff boundaries"
block:
  let data = recording()
  var immediate = resumed(data, 0)
  doAssert immediate.step()
  doAssert immediate.calls == 1
  doAssert immediate.recorder.data.actions[0].kind == ActionPlayCard
  var complete = resumed(data, uint32(data.hashes.len))
  complete.run()
  doAssert complete.tick == uint32(data.hashes.len)
  doAssert complete.calls == int32(data.hashes.len)
  doAssert complete.recorder.data.hashes == data.hashes
  doAssert complete.recorder.data.actions == data.actions
  inc complete.maxTicks
  inc complete.recorder.data.header.setup.maximumTicks
  inc complete.recorder.data.config.maxTicks
  doAssert complete.step()
  doAssert complete.calls == int32(data.hashes.len + 1)
  doAssert complete.recorder.data.actions[^1].kind == ActionPlayCard
