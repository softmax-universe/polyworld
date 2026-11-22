## Actual Bassy chat reactions survive action playback without rerunning VMs.
import
  std/os,
  bassy,
  polyworld/tapes,
  ../[bots, content, maps, replays, sim]

const Policy = """
sentAll = sendChat(-2, "all hello")
sentTeam = sendChat(-1, "team hello")
sentDirect = sendChat(mailboxSelf(), "move")
while mailboxCount() > 0
  message$ = pullMailbox$()
  if message$ = "move" then
    reacted = reacted + 1
    accepted = walkTo(selfX + 1, selfY)
  end if
wend
"""

let
  map = generateMap(2026)
  game = newGame(map, 10 * TickRate, 2, false, ReplayData(),
    drafting = false)
game.loadBotSources([Policy])
game.recorder = initReplayRecorder(game.currentSetup(48), map.preset)
for tick in 1 .. 48:
  game.tickWorld(proc() = game.runBotDecisions())
doAssert not game.heroVms[0].failed, game.heroVms[0].lastError
doAssert game.heroVms[0].runtime.getGlobal("reacted") > 0
let
  tape = decodeReplay(encodeReplay(game.recorder.data))
  replay = newGame(map, 10 * TickRate, 0, true, tape)
doAssert tape.actions.len >= 4 and tape.actions.len mod 4 == 0
let sender = tape.header.setup.heroes[0].id
for i in countup(0, tape.actions.high, 4):
  let tick = tape.actions[i].tick
  doAssert tick > 0 and tick <= 48
  for offset in 0 .. 2:
    let action = tape.actions[i + offset]
    doAssert action.kind == ActionPolicyChat and action.isChatAction()
    doAssert not action.isGameplayAction()
    doAssert action.heroId == sender and action.tick == tick
  doAssert tape.actions[i].first == -2
  doAssert tape.actions[i].text == "all hello"
  doAssert tape.actions[i + 1].first == -1
  doAssert tape.actions[i + 1].text == "team hello"
  doAssert tape.actions[i + 2].first == 0
  doAssert tape.actions[i + 2].text == "move"
  let reaction = tape.actions[i + 3]
  doAssert reaction.kind == ActionWalkTo and reaction.isGameplayAction()
  doAssert reaction.heroId == sender and reaction.tick == tick,
    "Policy reactions must follow their input messages in the same action stream"
replay.replayPlayer = initReplayPlayer(tape)
replay.historyPlayback = true
for tick in 1 .. tape.hashes.len:
  replay.tickWorld(nil)
  doAssert replay.stateHash() == tape.hashes[tick - 1]
doAssert replay.hashCheck.mismatches == 0
doAssert replay.replayCommandCount() == tape.actions.len div 4,
  "Replay command totals count reactions and exclude policy messages"
doAssert replay.heroVms.len == 0 and replay.inboxes.len == 0,
  "Historical playback follows recorded reactions without re-executing private policy state"
doAssert replay.visibleReplayChat().len == 0,
  "Private policy traffic stays in the tape without becoming human chat"
echo "PASS canonical Bassy chat order, recorded reactions, private-state isolation and replay hashes"

block startupCommandsAtTickZero:
  let startup = newGame(map, 10 * TickRate, 2, false, ReplayData(),
    drafting = false)
  startup.loadBotSources([])
  startup.recorder = initReplayRecorder(startup.currentSetup(8), map.preset)
  let hero = startup.world.heroes[0].id
  doAssert startup.sendChat(0, -2, "initial") == 2
  startup.recorder.record(ReplayAction(tick: 0, heroId: hero,
    kind: ActionHumanChat, first: -2, text: "Initial hello"))
  startup.recorder.record(ReplayAction(tick: 0,
    kind: ActionSystemNotice, first: -2, text: "Initial notice"))
  for tick in 1 .. 8:
    if tick == 2:
      startup.recorder.record(ReplayAction(tick: 2, heroId: hero,
        kind: ActionHumanChat, first: -2, text: "Later hello"))
    startup.tickWorld(proc() = startup.runBotDecisions())
  let path = getTempDir() / ("gota-tick-zero-" & $getCurrentProcessId() & ".replay")
  saveReplay(path, startup.recorder.data)
  defer: removeFile(path)
  let saved = loadReplay(path)
  doAssert saved.actions == startup.recorder.data.actions
  doAssert saved.actions.len == 4 and saved.actions[0].kind == ActionPolicyChat
  doAssert saved.actions[0].text == "initial"
  for index in 0 .. 2: doAssert saved.actions[index].tick == 0
  let playback = newGame(map, 10 * TickRate, 0, true, saved)
  let initial = playback.world.clone()
  playback.historyPlayback = true
  playback.replayPlayer = initReplayPlayer(saved)
  let initialMessages = playback.visibleReplayChat()
  doAssert initialMessages.len == 2
  doAssert initialMessages[0].ordinal == 1 and initialMessages[1].ordinal == 2
  doAssert initialMessages[1].system
  for tick in 1 .. saved.hashes.len:
    playback.tickWorld(nil)
    doAssert playback.stateHash() == saved.hashes[tick - 1]
    doAssert playback.replayPlayer.actionIndex == (if tick == 1: 3 else: 4),
      "Startup inputs must be consumed before ordinary tick commands"
  doAssert playback.hashCheck.mismatches == 0
  doAssert playback.heroVms.len == 0 and playback.inboxes.len == 0
  doAssert playback.visibleReplayChat().len == 3
  doAssert playback.replayCommandCount() == 0, "Startup chat is not gameplay APM"
  # A seek to the saved initial world skips the already-consumed tick-zero group.
  # Chat remains a view of the original ordered tape, never a duplicate append.
  playback.world.restore(initial)
  playback.replayPlayer.syncCursor(0)
  doAssert playback.visibleReplayChat() == initialMessages
  for tick in 1 .. saved.hashes.len:
    playback.tickWorld(nil)
    doAssert playback.stateHash() == saved.hashes[tick - 1]
  doAssert playback.hashCheck.mismatches == 0
  doAssert playback.visibleReplayChat().len == 3
  doAssert playback.replayPlayer.data.actions == saved.actions
  doAssert playback.heroVms.len == 0 and playback.inboxes.len == 0
  echo "PASS tick-zero canonical chat save/load, replay cursor, hashes and seek"
