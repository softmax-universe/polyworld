import
  std/[os, tempfiles],
  bassy,
  polyworld/cli,
  ../[bots, content, replays, sim]

const Candidate = """
decisions = decisions + 1
accepted = walkTo(objectiveLevel, objectiveX, objectiveY)
sent = sendChat(-2, "candidate")
"""

let directory = createTempDir("cta-resume-", "")
try:
  let path = directory / "candidate.bas"
  writeFile(path, Candidate)
  let game = newGame(2026, 12)
  game.loadBots([BotGroup(path: path, count: PartySize)])
  game.recorder = initReplayRecorder(game.world.setup)
  game.world.tick = 1
  game.historyPlayback = true
  let originalHash = game.stateHash()
  for slot in 0 ..< PartySize:
    game.runBotDecisions(slot.int32)
  doAssert game.stateHash() == originalHash
  doAssert game.recorder.data.actions.len == 0
  for slot, vm in game.heroVms:
    doAssert not vm.failed, vm.lastError
    doAssert vm.runtime.getGlobal("decisions") == 1
    doAssert vm.runtime.getGlobal("accepted") == 0
    doAssert game.inboxes[slot].count == 0

  game.historyPlayback = false
  for slot in 0 ..< PartySize:
    game.runBotDecisions(slot.int32)
  doAssert game.recorder.data.actions.len == PartySize
  doAssert game.stateHash() != originalHash
  for slot, vm in game.heroVms:
    doAssert vm.runtime.getGlobal("decisions") == 2
    doAssert game.inboxes[slot].count > 0
finally:
  removeDir(directory)

echo "Call to Adventure replay warm-up preserves world and policy memory"
