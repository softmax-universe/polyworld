## Headless bot matches, their replays, and replay playback.
import std/[os, random, sequtils, unittest]
import polyworld/mailboxes
import ../src/core/[sim, bots, match, replays]

const ArcherBot = staticRead("../players/archer.bas")

proc classesFor(seats: int, seed: int64): seq[HeroClass] =
  var rng = initRand(seed)
  for _ in 0 ..< seats:
    result.add rng.rand(HeroClass)

proc recordMatch(seats: int, seed: int32, sources: seq[string],
    maxTicks = 28_800'u32): (BotMatch, ReplayData) =
  let
    seated = classesFor(seats, seed).mapIt(precon(it))
    recorder = initReplayRecorder(matchSetup(seated, seed, maxTicks),
      GameConfig(seed: seed, maxTicks: maxTicks.int32,
        players: unnamedPlayers(seats)))
  var match = initBotMatch(seated, seed, loadBots(sources), maxTicks,
    recorder)
  match.run()
  (match, recorder.data)

proc replayHashes(data: ReplayData): GameState =
  ## Plays a replay back, checking every tick's hash.
  result = newGame(data.header.setup)
  var
    cursor = data.initReplayCursor()
    action: ReplayAction
    tick = 0'u32
  while data.takeReplayAction(cursor, tick, action):
    check result.applyAction(action)
    discard result.takeVisualEvents()
    check result.stateHash == data.hashes[action.tick.int - 1]
    tick = action.tick
  check cursor.actionIndex == data.actions.len

suite "bot matches":
  test "every roster size finishes with one winner and replays exactly":
    for seats in 2 .. MaxPlayers:
      let (played, data) = recordMatch(seats, int32(40 + seats),
        newSeq[string](seats).mapIt(ArcherBot))
      check played.outcome == MatchWon
      check played.scores.len == seats
      check played.scores[played.game.winner] == 1
      check data.actions.len == played.tick.int
      let replayed = data.replayHashes()
      check replayed.gameOver
      check replayed.winner == played.game.winner

  test "a replay survives the file round trip":
    let (_, data) = recordMatch(3, 7, @[ArcherBot, ArcherBot, ArcherBot])
    let path = getTempDir() / "cac-test.replay"
    saveReplay(path, data)
    let loaded = loadReplay(path)
    removeFile(path)
    check loaded.actions == data.actions
    check loaded.hashes == data.hashes
    check loaded.header.setup == data.header.setup
    discard loaded.replayHashes()

  test "scripts that only end their turn still finish by decking out":
    let (played, data) = recordMatch(2, 3, @["endTurn()\n", "endTurn()\n"])
    check played.outcome == MatchWon
    discard data.replayHashes()

  test "the tick limit ends a match as a timeout":
    let (played, data) = recordMatch(4, 5, newSeq[string](4).mapIt(ArcherBot),
      maxTicks = 12)
    check played.outcome == MatchTimedOut
    check played.scores == @[0, 0, 0, 0]
    check data.hashes.len == 12

  test "policy mail shares the saved action order without replaying the policy":
    const talking = """
sent = sendChat(enemyPlayer, "same message")
sent = sendChat(enemyPlayer, "same message")
endTurn()
end
"""
    let (played, data) = recordMatch(2, 3, @[talking, talking], maxTicks = 4)
    check played.outcome == MatchTimedOut
    check data.hashes.len == 4
    check data.actions.len == 12
    let decoded = data.encodeReplay().decodeReplay()
    check decoded.actions == data.actions
    check decoded.hashes == data.hashes
    for turn in 0 ..< 4:
      let index = turn * 3
      check decoded.actions[index].kind == ActionMailbox
      check decoded.actions[index + 1].kind == ActionMailbox
      check decoded.actions[index].text == "same message"
      check decoded.actions[index].tick == turn.uint32
      check decoded.actions[index + 1].tick == turn.uint32
      check decoded.actions[index + 2].kind == ActionEndTurn
      check decoded.actions[index + 2].tick == turn.uint32 + 1
    let liveCounts = bots.inboxes.mapIt(it.count)
    var
      game = newGame(decoded.header.setup)
      cursor = decoded.initReplayCursor()
      action: ReplayAction
      tick = 0'u32
    while decoded.takeReplayAction(cursor, tick, action):
      check game.applyAction(action)
      tick = action.tick
      check game.stateHash == decoded.hashes[tick.int - 1]
    check cursor.actionIndex == decoded.actions.len
    check cursor.inboxes.mapIt(it.count) == @[4, 4]
    check bots.inboxes.mapIt(it.count) == liveCounts
    decoded.applyReplayMailboxes(cursor, tick)
    check cursor.inboxes.mapIt(it.count) == @[4, 4]
    check game.stateHash == played.game.stateHash

  test "mailbox replay rejects invalid recipients, payloads, order and old versions":
    let (_, valid) = recordMatch(2, 3, @["endTurn()", "endTurn()"],
      maxTicks = 2)
    for invalid in [
      ReplayAction(kind: ActionMailbox, tick: 1, playerId: 0, target: -1,
        text: "invalid target"),
      ReplayAction(kind: ActionMailbox, tick: 1, playerId: 0, target: 2,
        text: "unknown player"),
      ReplayAction(kind: ActionMailbox, tick: 1, playerId: 2, target: -2,
        text: "unknown sender"),
      ReplayAction(kind: ActionMailbox, tick: 1, playerId: 0, target: -2),
      ReplayAction(kind: ActionMailbox, tick: 0, playerId: 0, target: -2,
        text: "wrong admission tick")]:
      var bad = valid
      bad.actions = @[valid.actions[0], invalid, valid.actions[1]]
      expect ReplayError:
        discard bad.encodeReplay()
    var old = valid
    old.header.formatVersion = ReplayFormatVersion - 1
    expect ReplayError:
      old.validate()
    let oldFile = encodeReplayFile(ReplayGame, ReplayGameVersion - 1, valid)
    expect ReplayError:
      discard oldFile.decodeReplay()

  test "accepted mail survives a decision that supplies no game action":
    const onlyMail = "sent = sendChat(-2, \"Before any action\")\nend\n"
    let (played, data) = recordMatch(2, 3, @[onlyMail, onlyMail], maxTicks = 4)
    check played.outcome == MatchFailed
    check data.hashes.len == 0
    check data.actions.len == 1
    let decoded = data.encodeReplay().decodeReplay()
    var
      cursor = decoded.initReplayCursor()
      action: ReplayAction
    check not decoded.takeReplayAction(cursor, 0, action)
    check cursor.actionIndex == 1
    check cursor.inboxes.mapIt(it.count) == @[1, 1]
    decoded.applyReplayMailboxes(cursor, 0)
    check cursor.inboxes.mapIt(it.count) == @[1, 1]
