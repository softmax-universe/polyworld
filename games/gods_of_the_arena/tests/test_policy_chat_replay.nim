## Actual Bassy chat reactions survive action playback without rerunning VMs.
import
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
doAssert tape.events.len >= 3
doAssert tape.events.len mod 3 == 0
doAssert tape.actions.len == tape.events.len div 3
for i in countup(0, tape.events.high, 3):
  let tick = tape.events[i].tick
  doAssert tick > 0 and tick <= 48
  doAssert tape.events[i].kind == PolicyReplayChat
  doAssert tape.events[i].target == -2
  doAssert tape.events[i].text == "all hello"
  doAssert tape.events[i + 1].target == -1
  doAssert tape.events[i + 1].text == "team hello"
  doAssert tape.events[i + 2].target == 0
  doAssert tape.events[i + 2].text == "move"
  doAssert tape.events[i + 1].tick == tick
  doAssert tape.events[i + 2].tick == tick
  doAssert tape.actions[i div 3].tick == tick
replay.replayPlayer = initReplayPlayer(tape)
replay.historyPlayback = true
for tick in 1 .. tape.hashes.len:
  replay.tickWorld(nil)
  doAssert replay.stateHash() == tape.hashes[tick - 1]
doAssert replay.hashCheck.mismatches == 0
doAssert replay.heroVms.len == 0 and replay.inboxes.len == 0
doAssert replay.visibleReplayChat().len == 0,
  "Private policy traffic stays in the tape without becoming human chat"
echo "PASS Bassy chat scopes, timestamps, reactions and replay hashes"
