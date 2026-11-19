import ../src/core/[bots, match, replays, sim]

const
  SetupSource = """
if selectingClass then
  pickClass(1)
  deckCard("Warrior", 40)
  end
end if
"""
  ObserveSource = SetupSource & """
calls = calls + 1
seenTurn = turnNumber
roll = random(1000)
receivedThisTurn = 0
while mailboxCount() > 0
  message$ = pullMailbox$()
  received = received + 1
  receivedThisTurn = receivedThisTurn + 1
  lastSender = mailboxId()
wend
"""
  OriginalSource = ObserveSource & """
sent = sendChat(enemyPlayer, "original one")
sent = sendChat(enemyPlayer, "original two")
endTurn()
"""
  ReplacementSource = ObserveSource & """
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

proc total(game: BotMatch, name: string): int32 =
  ## Sums a private counter across the selected policies.
  for bot in game.bots:
    result += bot.runtime.getGlobal(name)

proc verify(data: ReplayData) =
  ## Replays the ordered mailbox and gameplay stream with every state hash.
  data.validate()
  var
    game = newGame(data.header.setup)
    cursor = data.initReplayCursor()
    action: ReplayAction
    tick = 0'u32
  while data.takeReplayAction(cursor, tick, action):
    doAssert game.applyAction(action)
    discard game.takeVisualEvents()
    tick = action.tick
    doAssert game.stateHash == data.hashes[tick.int - 1]
  doAssert tick.int == data.hashes.len
  doAssert cursor.actionIndex == data.actions.len

echo "CaC warms selected policies without changing the replay prefix"
block:
  let data = recording()
  var game = resumed(data, 4)
  for tick in 0 ..< 4:
    let
      player = game.game.actingPlayer()
      turn = game.game.turnNumber
    doAssert game.step()
    doAssert game.game.stateHash == data.hashes[tick]
    doAssert game.recorder.data.actions.len == (tick + 1) * 3
    doAssert game.recorder.data.actions == data.actions[0 ..< (tick + 1) * 3]
    doAssert game.total("calls") == int32(tick + 1)
    doAssert game.total("received") == int32(tick * 2)
    doAssert game.bots[player].runtime.getGlobal("seenTurn") == turn.int32
    doAssert game.bots[player].runtime.getGlobal("receivedThisTurn") ==
      int32(if tick == 0: 0 else: 2)
    doAssert inboxes[player].count == 0
    doAssert inboxes[game.game.actingPlayer()].count == 2
  for bot in game.bots:
    doAssert bot.runtime.getGlobal("calls") == 2
  let player = game.game.actingPlayer()
  doAssert game.step()
  doAssert game.total("calls") == 5
  doAssert game.total("received") == 8
  doAssert game.bots[player].runtime.getGlobal("calls") == 3
  doAssert game.recorder.data.actions.len == 14
  doAssert game.recorder.data.actions[^2].kind == ActionMailbox
  doAssert game.recorder.data.actions[^2].tick == 4
  doAssert game.recorder.data.actions[^2].text == "candidate"
  doAssert game.recorder.data.actions[^1].kind == ActionPlayCard
  doAssert data.actions[14].kind == ActionEndTurn
  doAssert game.game.stateHash != data.hashes[4]
  doAssert inboxes[game.game.nextPlayer(player)].count == 1
  game.recorder.data.verify()

echo "CaC supports immediate and full-prefix handoff boundaries"
block:
  let data = recording()
  var immediate = resumed(data, 0)
  doAssert immediate.step()
  doAssert immediate.total("calls") == 1
  doAssert immediate.total("received") == 0
  doAssert immediate.recorder.data.actions.len == 2
  doAssert immediate.recorder.data.actions[0].text == "candidate"
  doAssert immediate.recorder.data.actions[1].kind == ActionPlayCard
  var complete = resumed(data, uint32(data.hashes.len))
  complete.run()
  doAssert complete.tick == uint32(data.hashes.len)
  doAssert complete.total("calls") == int32(data.hashes.len)
  doAssert complete.total("received") == int32((data.hashes.len - 1) * 2)
  doAssert complete.recorder.data.hashes == data.hashes
  doAssert complete.recorder.data.actions == data.actions
  inc complete.maxTicks
  inc complete.recorder.data.header.setup.maximumTicks
  inc complete.recorder.data.config.maxTicks
  doAssert complete.step()
  doAssert complete.total("calls") == int32(data.hashes.len + 1)
  doAssert complete.recorder.data.actions[^2].text == "candidate"
  doAssert complete.recorder.data.actions[^1].kind == ActionPlayCard
  complete.recorder.data.verify()

echo "CaC leaves future decision messages outside the replay prefix"
block:
  var data = recording()
  data.actions.add ReplayAction(kind: ActionMailbox, tick: 8,
    playerId: 0, target: 1, text: "Future decision")
  data.validate()
  var complete = resumed(data, 8)
  complete.run()
  doAssert complete.recorder.data.actions == data.actions[0 ..< 24]
  complete.recorder.data.verify()
