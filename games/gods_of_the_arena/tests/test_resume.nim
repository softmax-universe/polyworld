import
  bassy,
  polyworld/[tapes, mailboxes],
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
resumed.warmingPolicies = true
resumed.applyReplayActions(0)
resumed.applyReplayActions(0)
for inbox in resumed.inboxes:
  doAssert inbox.count == 1
let firstHero = resumed.world.heroTurnStart
for tick in 1 .. 6:
  resumed.tickWorld(proc() = resumed.runBotDecisions())
  doAssert resumed.stateHash() == tape.hashes[tick - 1]
  for i, vm in resumed.heroVms:
    doAssert vm.runtime.getGlobal("initialReceived") == 1
    doAssert vm.runtime.getGlobal("candidateReceived") == 0
    if tick == 1:
      let earlierMessages = if i == firstHero: 0 else: 1
      doAssert vm.runtime.getGlobal("recordedReceived") == earlierMessages
      doAssert resumed.inboxes[i].count == 2 - earlierMessages
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
resumed.warmingPolicies = false
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
immediate.warmingPolicies = true
immediate.applyReplayActions(0)
immediate.recorder = ReplayRecorder(data: replayPrefix(tape, 0))
immediate.historyPlayback = false
immediate.replayMode = false
immediate.warmingPolicies = false
immediate.tickWorld(proc() = immediate.runBotDecisions())
for vm in immediate.heroVms:
  doAssert vm.runtime.getGlobal("count") == 1
  doAssert vm.runtime.getGlobal("initialReceived") == 1
  doAssert vm.runtime.getGlobal("recordedReceived") == 0
  doAssert vm.runtime.getGlobal("sent") == 2

const Feedback = """
count = count + 1
if worldTick = 1 then
  purchased = buyItem(8)
end if
accepted = walkTo(selfX + count, selfY)
if accepted then successes = successes + 1
sent = sendChat(-2, "recorded")
delivered = delivered + sent
while mailboxCount() > 0
  message$ = pullMailbox$()
  if message$ = "recorded" then received = received + 1
wend
"""

proc checkFeedback(mixed: bool) =
  ## Keeps unchanged policies' feedback identical even beside a replacement.
  const Names = ["count", "purchased", "successes", "delivered", "received"]
  let live = newGame(map, 240, 2, false, ReplayData(), drafting = false)
  live.loadBotSources([Feedback, Feedback])
  live.recorder = initReplayRecorder(live.currentSetup(6), map.preset)
  var expected: array[2, array[Names.len, int32]]
  for tick in 1 .. 6:
    live.tickWorld(proc() = live.runBotDecisions())
    if tick == 4:
      for slot, vm in live.heroVms:
        for i, name in Names:
          expected[slot][i] = vm.runtime.getGlobal(name)
  let
    recorded = live.recorder.data
    policyReplay = newGame(map, 240, 0, true, recorded)
  policyReplay.loadBotSources([if mixed: Candidate else: Feedback, Feedback])
  policyReplay.replayPlayer = initReplayPlayer(recorded)
  policyReplay.historyPlayback = true
  policyReplay.warmingPolicies = true
  for tick in 1 .. 4:
    policyReplay.tickWorld(proc() = policyReplay.runBotDecisions())
    doAssert policyReplay.stateHash() == recorded.hashes[tick - 1]
  for slot, vm in policyReplay.heroVms:
    doAssert not vm.failed, vm.lastError
    if not mixed or slot == 1:
      for i, name in Names:
        doAssert vm.runtime.getGlobal(name) == expected[slot][i], name
  if not mixed:
    policyReplay.recorder = ReplayRecorder(data: replayPrefix(recorded, 4))
    policyReplay.historyPlayback = false
    policyReplay.replayMode = false
    policyReplay.warmingPolicies = false
    for tick in 5 .. 6:
      policyReplay.tickWorld(proc() = policyReplay.runBotDecisions())
    doAssert policyReplay.recorder.data.actions == recorded.actions
    doAssert policyReplay.recorder.data.hashes == recorded.hashes

checkFeedback(false)
checkFeedback(true)

let full = newGame(map, 240, 2, false, ReplayData(), drafting = false)
full.loadBotSources(["stop", "stop"])
full.recorder = initReplayRecorder(full.currentSetup(1), map.preset)
for i in 0 ..< MaxMailboxMessages:
  doAssert full.inboxes[0].push(0, "full")
doAssert full.sendChat(0, 0, "retry") == 0
discard full.inboxes[0].pop()
doAssert full.sendChat(0, 0, "retry") == 1
full.replayPlayer = initReplayPlayer(full.recorder.data)
full.recorder = nil
full.warmingPolicies = true
doAssert full.sendChat(0, 0, "retry") == 0
doAssert full.replayPlayer.actionIndex == 1
discard full.inboxes[0].pop()
doAssert full.sendChat(0, 0, "retry") == 1
doAssert full.replayPlayer.actionIndex == 2

echo "PASS GOTA replay warm-up preserves policy feedback and ordered chat"
