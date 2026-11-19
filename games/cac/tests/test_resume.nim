import polyworld/mailboxes
import ../core/[bots, match, replays, sim]

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
  SendResultSource = SetupSource & """
previous = sent
sent = sendChat(enemyPlayer, "x")
if previous > 0 and canPlay(0) then
  playCard(0)
else
  endTurn()
end if
"""
  SelfReadSource = SetupSource & """
previous = received
sent = sendChat(selfPlayer, "x")
received = mailboxCount()
message$ = pullMailbox$()
if previous > 0 and canPlay(0) then
  playCard(0)
else
  endTurn()
end if
"""
  FullMailboxSource = SetupSource & """
previous = accepted
if initialized = 0 then
  for i = 1 to """ & $MaxMailboxMessages & """

    sent = sendChat(selfPlayer, "x")
  next
  initialized = 1
end if
rejected = sendChat(selfPlayer, "x")
message$ = pullMailbox$()
accepted = sendChat(selfPlayer, "x")
if previous > 0 and canPlay(0) then
  playCard(0)
else
  endTurn()
end if
"""
  MageSource = staticRead("../players/mage.bas")

proc recording(source = OriginalSource, maxTicks = 8'u32): ReplayData =
  ## Records a legal match with the same policy in both seats.
  let
    bots = loadBots([source, source])
    seats = bots.setupBotSeats(19)
    recorder = initReplayRecorder(
      matchSetup(seats, 19, maxTicks),
      GameConfig(seed: 19, maxTicks: maxTicks.int32,
        players: unnamedPlayers(2))
    )
  var game = initBotMatch(seats, 19, bots, maxTicks, recorder)
  game.run()
  doAssert game.outcome in {MatchWon, MatchDrawn, MatchTimedOut}
  recorder.data

proc resumed(data: ReplayData, step: uint32,
    source = ReplacementSource, maximum = 0'u32): BotMatch =
  ## Initializes selected policies while preserving the recorded match setup.
  let
    bots = loadBots([source, source])
    recorder = initReplayRecorder(data.header.setup, data.config)
    maxTicks = data.header.setup.maximumTicks
  recorder.data.config.maxTicks = maxTicks.int32
  discard bots.setupBotSeats(data.header.setup.seed)
  result = initBotMatch(
    data.header.setup.seats,
    data.header.setup.seed,
    bots,
    maxTicks,
    recorder
  )
  result.replayData = data
  result.resumeStep = step
  result.resumeMaximumTicks = maximum

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
  complete.resumeMaximumTicks = complete.maxTicks + 1
  doAssert complete.step()
  doAssert complete.total("calls") == int32(data.hashes.len + 1)
  doAssert complete.recorder.data.actions[^3].text == "candidate"
  doAssert complete.recorder.data.actions[^2].kind == ActionDuration
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

echo "CaC supports longer and unchanged explicit durations"
for cutoff in [0'u32, 4, 8]:
  for maximum in [8'u32, 12]:
    let data = recording()
    var game = resumed(data, cutoff, OriginalSource, maximum)
    game.run()
    doAssert game.tick == maximum
    doAssert game.outcome == MatchTimedOut
    doAssert game.recorder.data.hashes[0 ..< data.hashes.len] == data.hashes
    let count = data.actions.actionIndexAfter(cutoff)
    for index in 0 ..< count:
      if data.actions[index].kind != ActionMailbox or
        data.actions[index].tick < cutoff:
          doAssert game.recorder.data.actions[index] == data.actions[index]
    game.recorder.data.verify()

echo "CaC nested branches retain only past duration changes"
block:
  let data = recording()
  var extended = resumed(data, 4, OriginalSource, 12)
  extended.run()
  let branch = extended.recorder.data
  doAssert branch.header.setup.maximumTicks == 8
  doAssert branch.config.maxTicks == 12
  doAssert branch.durationAt(4) == 8
  doAssert branch.durationAt(5) == 12
  for cutoff in [2'u32, 4, 5, 10, 12]:
    var nested = resumed(branch, cutoff, OriginalSource)
    nested.run()
    let expected = if cutoff <= 4: data else: branch
    doAssert nested.recorder.data.actions == expected.actions
    doAssert nested.recorder.data.hashes == expected.hashes
    nested.recorder.data.verify()

echo "CaC rejects malformed duration controls"
block:
  let data = recording()
  var extended = resumed(data, 4, OriginalSource, 12)
  extended.run()
  let branch = extended.recorder.data
  var control = -1
  for index, action in branch.actions:
    if action.kind == ActionDuration:
      control = index
  doAssert control >= 0
  for variant in 0 .. 3:
    var invalid = branch
    case variant
    of 0:
      invalid.actions[control].handIndex = 4
    of 1:
      invalid.actions[control].tick = 4
    of 2:
      invalid.actions.insert(invalid.actions[control], control)
    else:
      invalid.config.maxTicks = 8
    var rejected = false
    try:
      invalid.validate()
    except ReplayError:
      rejected = true
    doAssert rejected

echo "CaC preserves unchanged policies that read their own chat effects"
for source in [SendResultSource, SelfReadSource, FullMailboxSource]:
  let data = recording(source)
  var game = resumed(data, 2, source)
  game.run()
  doAssert game.tick == uint32(data.hashes.len)
  doAssert game.recorder.data.actions == data.actions
  doAssert game.recorder.data.hashes == data.hashes
  doAssert game.game.stateHash == data.hashes[^1]
  if source == FullMailboxSource:
    for bot in game.bots:
      doAssert bot.runtime.getGlobal("rejected") == 0
      doAssert bot.runtime.getGlobal("accepted") == 1
  game.recorder.data.verify()

echo "CaC reproduces a complete Mage match after a halfway handoff"
block:
  let data = recording(MageSource, 2_000)
  doAssert data.hashes.len > 2
  var game = resumed(data, uint32(data.hashes.len div 2), MageSource)
  game.run()
  doAssert game.outcome == MatchWon
  doAssert game.tick == uint32(data.hashes.len)
  doAssert game.recorder.data.actions == data.actions
  doAssert game.recorder.data.hashes == data.hashes
  doAssert game.game.stateHash == data.hashes[^1]
  game.recorder.data.verify()
  var extended = resumed(data, data.hashes.len.uint32, MageSource, 3_000)
  extended.run()
  doAssert extended.outcome == MatchWon
  doAssert extended.tick == data.hashes.len.uint32,
    "Extending time must preserve a decided match"
  doAssert extended.recorder.data.hashes == data.hashes
  doAssert extended.recorder.data.actions == data.actions
  extended.recorder.data.verify()
