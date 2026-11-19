import
  bassy,
  polyworld/tapes,
  ../[bots, maps, replays, sim]

const
  Original = """
count = count + 1
if worldTick = 1 then
  sent = sendChat(-2, "recorded")
end if
"""
  Candidate = """
count = count + 1
seenTick = worldTick
accepted = walkTo(selfX + 1, selfY)
sent = sendChat(-2, "candidate")
while mailboxCount() > 0
  message$ = pullMailbox$()
  if message$ = "initial" then initialReceived = initialReceived + 1
  if message$ = "recorded" then recordedReceived = recordedReceived + 1
  if message$ = "candidate" then candidateReceived = candidateReceived + 1
wend
"""

let
  map = generateMap(2026)
  original = newGame(map, 240, 2, false, ReplayData(), drafting = false)
original.loadBotSources([Original, Original])
original.recorder = initReplayRecorder(original.currentSetup(12), map.preset)
discard original.deliverChat(0, -2, "initial")
for tick in 1 .. 12:
  original.tickWorld(proc() = original.runBotDecisions())
let
  tape = original.recorder.data
  resumed = newGame(map, 240, 0, true, tape)
resumed.loadBotSources([Candidate, Candidate])
resumed.replayPlayer = initReplayPlayer(tape)
resumed.historyPlayback = true
resumed.watchingPolicies = true
resumed.applyReplayActions(0)
resumed.applyReplayActions(0)
for inbox in resumed.inboxes:
  doAssert inbox.count == 1
for tick in 1 .. 6:
  resumed.tickWorld(proc() = resumed.runBotDecisions())
  doAssert resumed.stateHash() == tape.hashes[tick - 1]
  for i, vm in resumed.heroVms:
    doAssert vm.runtime.getGlobal("initialReceived") == 1
    doAssert vm.runtime.getGlobal("candidateReceived") == 0
    if tick == 1:
      doAssert vm.runtime.getGlobal("recordedReceived") == 0
      doAssert resumed.inboxes[i].count == 2
    else:
      doAssert vm.runtime.getGlobal("recordedReceived") == 2
      doAssert resumed.inboxes[i].count == 0
for vm in resumed.heroVms:
  doAssert not vm.failed, vm.lastError
  doAssert vm.runtime.getGlobal("count") == 6
  doAssert vm.runtime.getGlobal("accepted") == 0
  doAssert vm.runtime.getGlobal("sent") == 0
resumed.recorder = initReplayRecorder(resumed.currentSetup(12), map.preset)
resumed.historyPlayback = false
resumed.replayMode = false
resumed.watchingPolicies = false
resumed.tickWorld(proc() = resumed.runBotDecisions())
doAssert resumed.recorder.data.actions.len == 4
var chatCount = 0
for action in resumed.recorder.data.actions:
  doAssert action.tick == 7
  if action.kind == ActionPolicyChat:
    inc chatCount
    doAssert action.text == "candidate"
doAssert chatCount == 2
for vm in resumed.heroVms:
  doAssert vm.runtime.getGlobal("count") == 7
  doAssert vm.runtime.getGlobal("seenTick") == 7
  doAssert vm.runtime.getGlobal("sent") == 2
  doAssert vm.runtime.getGlobal("candidateReceived") > 0

let immediate = newGame(map, 240, 0, true, tape)
immediate.loadBotSources([Candidate, Candidate])
immediate.replayPlayer = initReplayPlayer(tape)
immediate.historyPlayback = true
immediate.watchingPolicies = true
immediate.applyReplayActions(0)
immediate.recorder = ReplayRecorder(data: replayPrefix(tape, 0))
immediate.historyPlayback = false
immediate.replayMode = false
immediate.watchingPolicies = false
immediate.tickWorld(proc() = immediate.runBotDecisions())
for vm in immediate.heroVms:
  doAssert vm.runtime.getGlobal("count") == 1
  doAssert vm.runtime.getGlobal("initialReceived") == 1
  doAssert vm.runtime.getGlobal("recordedReceived") == 0
  doAssert vm.runtime.getGlobal("sent") == 2

echo "PASS GOTA replay warm-up preserves VM state and ordered chat at handoff"
