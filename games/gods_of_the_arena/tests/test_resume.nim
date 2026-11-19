import bassy
import polyworld/tapes
import ../[bots, maps, replays, sim]

const Original = """
count = count + 1
if worldTick = 1 then
  sent = sendChat(-2, "recorded")
end if
"""
const Candidate = """
count = count + 1
seenTick = worldTick
accepted = walkTo(selfX + 1, selfY)
sent = sendChat(-2, "candidate")
while mailboxCount() > 0
  message$ = pullMailbox$()
  received = received + 1
wend
"""
let map = generateMap(2026)
let original = newGame(map, 240, 2, false, ReplayData(), drafting = false)
original.loadBotSources([Original, Original])
original.recorder = initReplayRecorder(original.currentSetup(12), map.preset)
for tick in 1 .. 12:
  original.tickWorld(proc() = original.runBotDecisions())
let tape = original.recorder.data
let resumed = newGame(map, 240, 0, true, tape)
resumed.loadBotSources([Candidate, Candidate])
resumed.replayPlayer = initReplayPlayer(tape)
resumed.historyPlayback = true
resumed.watchingPolicies = true
for tick in 1 .. 6:
  resumed.replayMailboxes(uint32(tick - 1))
  resumed.tickWorld(proc() = resumed.runBotDecisions())
  resumed.replayMailboxes(tick.uint32)
  doAssert resumed.stateHash() == tape.hashes[tick - 1]
  if tick == 1:
    doAssert resumed.heroVms[0].runtime.getGlobal("received") == 0
for vm in resumed.heroVms:
  doAssert not vm.failed, vm.lastError
  doAssert vm.runtime.getGlobal("count") == 6
  doAssert vm.runtime.getGlobal("accepted") == 0
  doAssert vm.runtime.getGlobal("received") == 2
resumed.recorder = initReplayRecorder(resumed.currentSetup(12), map.preset)
resumed.historyPlayback = false
resumed.replayMode = false
resumed.watchingPolicies = false
resumed.tickWorld(proc() = resumed.runBotDecisions())
doAssert resumed.recorder.data.actions.len == 2
for action in resumed.recorder.data.actions:
  doAssert action.tick == 7
for vm in resumed.heroVms:
  doAssert vm.runtime.getGlobal("count") == 7
  doAssert vm.runtime.getGlobal("seenTick") == 7
echo "PASS GOTA warm-up preserves tape hashes, builds VM state, receives replay messages, and hands off at K+1"
