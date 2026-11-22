## BASIC policies stay isolated, bounded, private, and replayable.

import
  std/[os, strutils, tempfiles],
  bassy,
  polyworld/cli,
  ../[bots, game, maps, replays, sim]

const
  MoveSource = """
calls = calls + 1
lastSlot = selfSlot
accepted = setInput(8)
end
"""
  ReplaySource = """
calls = calls + 1
direction = randomInt(2)
if direction = 0 then
  accepted = setInput(8)
else
  accepted = setInput(4)
end if
end
"""

proc botOptions(seed = 17): Options =
  ## Builds one deterministic all-bot game without graphics.
  Options(seed: seed, players: MinPlayers, ticks: 10000, player: -1, speed: 1)

proc enterPlaying(game: Game) =
  ## Skips the reveal without consuming policy decisions.
  for i in 0 ..< RoleRevealTicks:
    game.world.step([], [])
  doAssert game.world.phase == Playing

proc enterVoting(game: Game) =
  ## Starts a real meeting with every player's chat cooldown available.
  game.enterPlaying()
  game.world.startVote(VoteCalledUnknown, 0, 0, 0)
  while game.world.phase == MeetingCall:
    game.world.step([], [])
  doAssert game.world.phase == Voting

proc allSources(source: string): seq[string] =
  ## Assigns the same source to independently initialized policy runtimes.
  for slot in 0 ..< MinPlayers:
    result.add source

echo "Testing custom BASIC controls and independent persistent globals"
block:
  let directory = createTempDir("crewrift-bots-", "")
  defer:
    removeDir(directory)
  let
    path = directory / "move.bas"
    defaultPath = directory / "base.bas"
  writeFile(path, MoveSource)
  writeFile(defaultPath, DefaultBotSource)
  for arguments in [
    @["--spectate", "--bot", path & ":8"],
    @["--spectate", "--bot:" & path & ":8"],
    @["--spectate", "--bot=" & path & ":8"]
  ]:
    let parsed = parseOptions(arguments)
    doAssert parsed.botGroups == @[BotGroup(path: path, count: 8)]
  var options = botOptions()
  options.botGroups = @[
    BotGroup(path: path, count: 2),
    BotGroup(path: defaultPath, count: MinPlayers - 2)
  ]
  let game = newGame(options)
  game.enterPlaying()
  let start = game.world.players[0].x
  for i in 0 ..< 10:
    game.advance(record = true)
  for slot in 0 .. 1:
    doAssert game.bots[slot].runtime.getGlobal("calls") == 10
    doAssert game.bots[slot].runtime.getGlobal("lastSlot") == slot.int32
    doAssert game.previous[slot] == InputState(right: true)
    doAssert game.rosterName(slot).endsWith("(move.bas)")
    doAssert not game.bots[slot].failed
  doAssert game.world.players[0].x > start
  doAssert game.bots[0].runtime != game.bots[1].runtime
  doAssert game.rosterName(2).endsWith("(base.bas)")
  options.player = 2
  options.name = "Human"
  options.botGroups[0].count = 3
  options.botGroups[1].count = MinPlayers - 4
  let human = newGame(options)
  doAssert human.bots[2].runtime == nil
  doAssert human.rosterName(2).endsWith("(Human)")
  for slot in [0, 1, 3]:
    doAssert human.rosterName(slot).endsWith("(move.bas)")

echo "Testing BASIC loading failures are reported before play"
block:
  let directory = createTempDir("crewrift-invalid-bots-", "")
  defer:
    removeDir(directory)
  let path = directory / "broken.bas"
  var options = botOptions()
  options.botGroups = @[BotGroup(path: path, count: MinPlayers)]
  for source in ["", "if then"]:
    if source.len > 0:
      writeFile(path, source)
    var rejected = false
    try:
      discard newGame(options)
    except CrewriftError as error:
      rejected = error.msg.len > 0
    doAssert rejected, "Missing or malformed BASIC must fail during loading."
  writeFile(path, MoveSource)
  options.botGroups[0].count = MinPlayers + 1
  var rejected = false
  try:
    discard newGame(options)
  except CrewriftError:
    rejected = true
  doAssert rejected, "A bot specification cannot overfill the roster."

echo "Testing policy RNG and globals reconstruct across live rewinds"
block:
  let directory = createTempDir("crewrift-bot-replays-", "")
  defer:
    removeDir(directory)
  let
    path = directory / "random.bas"
    replayPath = directory / "match.json"
  writeFile(path, ReplaySource)
  var options = botOptions()
  options.botGroups = @[BotGroup(path: path, count: MinPlayers)]
  let
    game = newGame(options)
    baseline = newGame(options)
  for frame in 0 ..< 180:
    game.advance(record = true)
    baseline.advance(record = true)
  doAssert game.recording.frames == baseline.recording.frames
  let
    calls = game.bots[0].runtime.getGlobal("calls")
    rng = game.bots[0].rng
    worldRng = game.world.rng
  removeFile(path)
  game.rewind()
  for frame in 0 ..< 180:
    game.advance(record = true)
  doAssert game.bots[0].runtime.getGlobal("calls") == calls
  doAssert game.bots[0].rng == rng
  doAssert game.world.rng == worldRng
  for frame in 0 ..< 80:
    game.advance(record = true)
    baseline.advance(record = true)
  doAssert game.recording.frames == baseline.recording.frames
  doAssert game.world.gameHash() == baseline.world.gameHash()
  saveReplay(replayPath, game.recording)
  options.replay = replayPath
  let playback = newGame(options)
  for bot in playback.bots:
    doAssert bot.runtime == nil
  while not playback.finished():
    playback.advance()
  doAssert playback.world.gameHash() == game.world.gameHash()
  doAssert playback.world.rng == game.world.rng
  playback.rewind()
  while not playback.finished():
    playback.advance()
  doAssert playback.world.gameHash() == game.world.gameHash()

echo "Testing BASIC chat and votes use the ordered replay action stream"
block:
  let game = newGame(botOptions())
  game.enterVoting()
  game.world.players[2].alive = false
  var sources = allSources("end")
  sources[0] = """
sent = sendChat(-2, "Crew ready.")
chosen = voteFor(playerTotal)
end
"""
  sources[1] = """
unsupported = sendChat(0, "Private message.")
sent = sendChat(-2, "Check the Bridge.")
chosen = voteFor(0)
end
"""
  sources[3] = "chosen = voteFor(2)\nend"
  game.bots = initBots(sources, game.world.config.seed)
  game.advance(record = true)
  let actions = game.recording.frames[0].actions
  doAssert actions[0].kind == InputAction and actions[0].slot == 0
  doAssert actions[1] == ReplayAction(
    kind: VoteAction, slot: 0, choice: MinPlayers
  )
  doAssert actions[2] == ReplayAction(
    kind: ChatAction, slot: 0, text: "Crew ready."
  )
  doAssert actions[3].kind == InputAction and actions[3].slot == 1
  doAssert actions[4] == ReplayAction(kind: VoteAction, slot: 1, choice: 0)
  doAssert actions[5] == ReplayAction(
    kind: ChatAction, slot: 1, text: "Check the Bridge."
  )
  doAssert game.world.voteState.votes[0] == -2
  doAssert game.world.voteState.votes[1] == 0
  doAssert game.world.chatMessages.len == 2
  doAssert game.bots[1].runtime.getGlobal("unsupported") == 0
  doAssert game.bots[3].runtime.getGlobal("chosen") == 0
  doAssert game.world.voteState.votes[3] == -1
  game.advance(record = true)
  doAssert game.bots[0].runtime.getGlobal("chosen") == 0
  for action in game.recording.frames[1].actions:
    doAssert action.kind == InputAction

echo "Testing BASIC budget exhaustion cancels queued decisions"
block:
  let game = newGame(botOptions())
  game.enterVoting()
  var sources = allSources("end")
  sources[0] = """
accepted = setInput(32)
accepted = voteFor(1)
accepted = sendChat(-2, "This must not escape.")
while 1
  spins = spins + 1
wend
"""
  sources[1] = "calls = calls + 1\nend"
  game.bots = initBots(sources, game.world.config.seed)
  game.advance(record = true)
  doAssert game.bots[0].failed and game.bots[0].lastError.len > 0
  doAssert game.previous[0] == InputState()
  doAssert game.world.voteState.votes[0] == -1
  doAssert game.world.chatMessages.len == 0
  doAssert game.bots[0].chat.len == 0 and game.bots[0].choice == -1
  for action in game.recording.frames[0].actions:
    doAssert action.kind == InputAction
  let work = game.bots[0].lastWork
  game.advance()
  doAssert game.bots[0].lastWork == work
  doAssert game.bots[1].runtime.getGlobal("calls") == 2

echo "Testing visibility and role information are scoped to the caller"
block:
  let game = newGame(botOptions())
  game.enterPlaying()
  var
    crew = -1
    imposters: seq[int]
  for slot, player in game.world.players:
    if player.role == Imposter:
      imposters.add slot
    elif crew < 0:
      crew = slot
  doAssert imposters.len == 2 and crew >= 0
  let origin = game.world.taskPoint(0)
  game.world.players[crew].x = origin.x
  game.world.players[crew].y = origin.y
  var hidden = MapPoint(x: -1, y: -1)
  for task in 0 ..< game.world.tasks.len:
    let point = game.world.taskPoint(task)
    if not game.world.visibleFrom(crew, point.x, point.y):
      hidden = point
      break
  doAssert hidden.x >= 0
  let target = imposters[0]
  game.world.players[target].x = hidden.x
  game.world.players[target].y = hidden.y
  game.world.bodies = @[Body(
    x: hidden.x, y: hidden.y, slotId: target,
    color: game.world.players[target].color,
    killerSlot: imposters[1], killTick: game.world.tickCount
  )]
  let source = "target = " & $target & "\nother = " & $imposters[1] & "\n" & """
own = myRole
role = playerRole(target)
teammate = playerRole(other)
visible = playerVisible(target)
alive = playerAlive(target)
seenX = playerX(target)
seenY = playerY(target)
bodies = bodyTotal
end
"""
  var
    policies = initBots(allSources(source), game.world.config.seed)
    nav: Navigator
  discard policies[crew].decideBot(nav, game.world, crew, InputState())
  let runtime = policies[crew].runtime
  doAssert not policies[crew].failed
  doAssert runtime.getGlobal("own") == Crewmate.ord.int32
  doAssert runtime.getGlobal("role") == -1
  doAssert runtime.getGlobal("teammate") == -1
  doAssert runtime.getGlobal("visible") == 0
  doAssert runtime.getGlobal("alive") == -1
  doAssert runtime.getGlobal("seenX") == -1
  doAssert runtime.getGlobal("seenY") == -1
  doAssert runtime.getGlobal("bodies") == 0
  game.world.players[target].x = origin.x
  game.world.players[target].y = origin.y
  game.world.bodies[0].x = origin.x
  game.world.bodies[0].y = origin.y
  discard policies[crew].decideBot(nav, game.world, crew, InputState())
  doAssert runtime.getGlobal("visible") != 0
  doAssert runtime.getGlobal("seenX") == origin.x.int32
  doAssert runtime.getGlobal("role") == -1
  doAssert runtime.getGlobal("bodies") == 1
  game.world.players[target].alive = false
  discard policies[crew].decideBot(nav, game.world, crew, InputState())
  doAssert runtime.getGlobal("visible") == 0
  doAssert runtime.getGlobal("alive") == -1
  doAssert runtime.getGlobal("seenX") == -1
  doAssert runtime.getGlobal("seenY") == -1
  discard policies[target].decideBot(nav, game.world, target, InputState())
  doAssert policies[target].runtime.getGlobal("teammate") == Imposter.ord.int32

echo "Testing invalid BASIC host arguments stay within the API boundary"
block:
  let game = newGame(botOptions())
  game.enterPlaying()
  let source = """
missingPlayer = playerX(-1)
farPlayer = playerY(2147483647)
missingTask = taskX(-1)
farTask = taskY(2147483647)
missingBody = bodyId(-1)
farBody = bodyAge(2147483647)
missingAssignment = assignedTask(-1)
missingChat$ = chatText$(2147483647)
badInput = setInput(128)
badMove = moveTo(2147483647, 2147483647)
badVote = voteFor(2147483647)
badChat = sendChat(-2, "No meeting is open.")
end
"""
  var
    policies = initBots(allSources(source), game.world.config.seed)
    nav: Navigator
  let input = policies[0].decideBot(nav, game.world, 0, InputState())
  doAssert not policies[0].failed
  doAssert input == InputState()
  doAssert policies[0].chat.len == 0 and policies[0].choice == -1
  for name in ["missingPlayer", "farPlayer", "missingTask", "farTask",
      "missingBody", "farBody", "missingAssignment"]:
    doAssert policies[0].runtime.getGlobal(name) == -1
  for name in ["badInput", "badMove", "badVote", "badChat"]:
    doAssert policies[0].runtime.getGlobal(name) == 0
  doAssert policies[0].runtime.getStringGlobal("missingChat$") == ""

echo "Testing route searches are bounded while cached routes remain reusable"
block:
  let game = newGame(botOptions())
  game.enterPlaying()
  let
    firstGoal = game.world.taskPoint(0)
    secondGoal = game.world.taskPoint(1)
    source = """
calls = calls + 1
if calls = 1 then
  first = moveTo(taskX(0), taskY(0))
  second = moveTo(taskX(1), taskY(1))
  cached = moveTo(taskX(0), taskY(0))
else
  later = moveTo(taskX(1), taskY(1))
end if
end
"""
  doAssert firstGoal != secondGoal
  game.bots = initBots(allSources(source), game.world.config.seed)
  game.advance()
  let runtime = game.bots[0].runtime
  doAssert not game.bots[0].failed
  doAssert runtime.getGlobal("first") == 1
  doAssert runtime.getGlobal("second") == 0
  doAssert runtime.getGlobal("cached") == 1
  doAssert game.bots[0].hasGoal and game.bots[0].goal == firstGoal
  game.advance()
  doAssert not game.bots[0].failed
  doAssert runtime.getGlobal("later") == 1
  doAssert game.bots[0].goal == secondGoal

echo "Testing maximum integer seeds preserve deterministic private RNG"
block:
  let game = newGame(botOptions())
  var
    first = initBots(["roll = randomInt(2147483647)\nend"], int.high)
    second = initBots(["roll = randomInt(2147483647)\nend"], int.high)
    nav: Navigator
  for decision in 0 ..< 8:
    discard first[0].decideBot(nav, game.world, 0, InputState())
    discard second[0].decideBot(nav, game.world, 0, InputState())
    doAssert not first[0].failed and not second[0].failed
    let roll = first[0].runtime.getGlobal("roll")
    doAssert roll >= 0 and roll < int32.high
    doAssert roll == second[0].runtime.getGlobal("roll")
    doAssert first[0].rng == second[0].rng

echo "Crewrift BASIC policy checks passed"
