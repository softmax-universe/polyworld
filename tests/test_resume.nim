## Exercises headless replay warm-up, takeover, and every BASIC game's runner.

import
  std/[monotimes, os, osproc, sequtils, streams, strutils, tempfiles, times]
import ../games/gods_of_the_arena/replays as gota
import ../games/call_to_adventure/replays as cta
import ../games/light_vs_dark/replays as lvd
import ../games/heartleaf/replays as heartleaf
import ../games/cac/src/core/replays as cac

const
  Root = currentSourcePath().parentDir.parentDir
  ExecutableSuffix =
    when ExeExt.len > 0:
      "." & ExeExt
    else:
      ""
  CacSetup = """if selectingClass then
  pickClass(1)
  deckCard("Warrior", 40)
  end
end if
"""

type ProcessWatch = object
  process: Process
  deadline: MonoTime
  exitCode: int
  timedOut: bool

proc watchProcess(watch: ptr ProcessWatch) {.thread.} =
  ## Enforces the deadline while the main thread drains subprocess output.
  while watch.process.running():
    if getMonoTime() >= watch.deadline:
      watch.timedOut = true
      watch.process.kill()
      break
    sleep(10)
  watch.exitCode = watch.process.waitForExit()

proc run(arguments: openArray[string], succeeds = true) =
  ## Runs the real CLI and includes its diagnostics when an assertion fails.
  let process = startProcess(
    arguments[0],
    workingDir = Root,
    args = arguments[1 .. ^1],
    options = {poUsePath, poStdErrToStdOut}
  )
  defer:
    process.close()
  let stream = process.outputStream
  var
    watch = ProcessWatch(
      process: process,
      deadline: getMonoTime() + initDuration(seconds = 180)
    )
    watcher: Thread[ptr ProcessWatch]
    output: string
  createThread(watcher, watchProcess, addr watch)
  try:
    output = stream.readAll()
  finally:
    joinThread(watcher)
  let diagnostic = quoteShellCommand(arguments) & "\n" & output
  doAssert not watch.timedOut, "Process exceeded 180 seconds: " & diagnostic
  doAssert (watch.exitCode == 0) == succeeds, diagnostic
  if succeeds:
    for failure in ["BASIC error", "script FAILED", "player_failure"]:
      doAssert failure notin output, diagnostic

proc build(source, target: string) =
  ## Compiles native headless code with an isolated cache.
  run([
    "nim", "c", "-d:release", "-d:headless", "-d:bassyNativeStrict",
    "--hints:off", "--nimcache:" & target & "-cache", "--out:" & target,
    source
  ])

proc chatPolicy(text: string): string =
  ## Keeps inboxes available and labels outgoing messages for CLI assertions.
  "while mailboxCount() > 0\n" &
    "  resumeMessage$ = pullMailbox$()\nwend\n" &
    "resumeSent = sendChat(-2, \"" & text & "\")\n"

proc isGameplay[A](action: A): bool =
  ## Separates actual policy decisions from mailbox and presentation actions.
  when A is gota.ReplayAction:
    gota.isGameplayAction(action)
  elif A is cta.ReplayAction:
    action.kind != cta.ActionChat
  elif A is lvd.ReplayAction:
    action.kind != lvd.ActionChat
  elif A is cac.ReplayAction:
    action.kind != cac.ActionMailbox
  else:
    true

proc prefixLength[T](data: T, cutoff: int): int =
  ## Stops CaC before messages emitted by the next policy decision.
  for action in data.actions:
    when T is cac.ReplayData:
      if cutoff == 0:
        return
      inc result
      if action.isGameplay() and action.tick == cutoff.uint32:
        return
    else:
      if action.tick > cutoff.uint32:
        return
      inc result

proc checkPrefix[T](recorded, resumed: T, cutoff: int) =
  ## Checks that warming replacement policies preserves the entire prefix.
  let count = recorded.prefixLength(cutoff)
  doAssert resumed.hashes[0 ..< cutoff] == recorded.hashes[0 ..< cutoff]
  doAssert resumed.prefixLength(cutoff) == count
  doAssert resumed.actions[0 ..< count] == recorded.actions[0 ..< count]

proc testGotaTakeover(
    executable, source, original, directory: string,
    recorded: gota.ReplayData
) =
  ## Warms real replacements, then lets both teams play to completion.
  let
    players = Root / "games/gods_of_the_arena/players"
    cutoff = recorded.hashes.len div 2
    heroes = recorded.header.setup.heroes
    seats = heroes.len
  for replaced in [seats div 2, seats]:
    var bots = @["--bot", players / "rusher.bas" & ":" & $replaced]
    if replaced < seats:
      bots.add ["--bot", original & ":" & $(seats - replaced)]
    let branch = directory / "gota-rusher-" & $replaced & ".replay"
    run(@[
      executable, "--replay", source, "--resume-step", $cutoff
    ] & bots & @["--record", branch])
    let
      resumed = gota.loadReplay(branch)
      live = resumed.actions.filterIt(it.tick > cutoff.uint32)
    checkPrefix(recorded, resumed, cutoff)
    doAssert resumed.header.setup.heroes == heroes
    doAssert resumed.hashes.len == recorded.hashes.len, "Match ended early"
    doAssert resumed.hashes[cutoff .. ^1] != recorded.hashes[cutoff .. ^1],
      "Replacement policies did not change the live world"
    for slot, hero in heroes:
      if slot < replaced:
        doAssert live.anyIt(it.heroId == hero.id and it.kind in {
          gota.ActionWalkTo, gota.ActionAttackTarget, gota.ActionAttackMove
        }), "Every replacement must move or attack after handoff"
      else:
        doAssert live.anyIt(it.heroId == hero.id),
          "The original policies must keep playing after handoff"
    doAssert live.len > 0
    doAssert live[0].tick == (cutoff + 1).uint32
    run([executable, "--replay", branch])
    echo "  base -> ", replaced, " rushers: replay through ", cutoff,
      ", live from ", cutoff + 1, " through ", resumed.hashes.len

proc testGame[T](
    name, entry: string,
    seats: int,
    duration: seq[string],
    load: proc(path: string): T,
    directory: string
) =
  ## Checks policy state, recorded prefixes, takeovers, and invalid inputs.
  echo "Testing ", name, " replay handoff"
  let
    gameDirectory = Root / "games" / entry.split('/')[0]
    focused = directory / name & "-state" & ExecutableSuffix
    prebuilt = getEnv("POLYWORLD_RESUME_BIN_DIR")
    original = directory / name & "-original.bas"
    candidate = directory / name & "-candidate.bas"
    source = directory / name & "-source.replay"
  build(gameDirectory / "tests/test_resume.nim", focused)
  run([focused])
  var executable = directory / name & ExecutableSuffix
  if prebuilt.len > 0:
    executable = prebuilt / name & ExecutableSuffix
  else:
    build(Root / "games" / entry, executable)
  if name == "cac":
    writeFile(original, CacSetup & chatPolicy("recorded") & "endTurn()\n")
    writeFile(candidate, CacSetup & chatPolicy("candidate") &
      "if canPlay(0) then\nplayCard(0)\nelse\nendTurn()\nend if\n")
  else:
    let baseline = readFile(gameDirectory / "players/base.bas")
    when T is heartleaf.ReplayData:
      writeFile(original, baseline)
      writeFile(candidate, "stop\n")
    else:
      let headerEnd = baseline.find('\n')
      writeFile(original, baseline[0 .. headerEnd] & chatPolicy("recorded") &
        baseline[headerEnd + 1 .. ^1])
      writeFile(candidate, chatPolicy("candidate") & "stop\n")
  run(@[executable, "--bot", original & ":" & $seats] & duration &
    @["--record", source])
  let
    recorded = load(source)
    length = recorded.hashes.len
    middle = length div 2
    bots = @["--bot", candidate & ":" & $seats]
  doAssert length > 2
  when T isnot heartleaf.ReplayData:
    doAssert recorded.actions.anyIt(it.text == "recorded")
  when T is gota.ReplayData:
    testGotaTakeover(executable, source, original, directory, recorded)
  for (cutoff, mixed) in [
    (0, false), (middle, false), (middle, true), (length, false)
  ]:
    let
      selected =
        if mixed:
          @["--bot", candidate, "--bot", original & ":" & $(seats - 1)]
        else:
          bots
      branch = directory / name & "-" & $cutoff & "-" & $mixed & ".replay"
    run(@[
      executable, "--replay", source, "--resume-step", $cutoff
    ] & selected & @["--record", branch])
    let resumed = load(branch)
    checkPrefix(recorded, resumed, cutoff)
    if cutoff == middle and not mixed:
      doAssert resumed.actions.filterIt(it.isGameplay()) !=
        recorded.actions.filterIt(it.isGameplay()), name
    when T isnot heartleaf.ReplayData:
      let live = resumed.actions[recorded.prefixLength(cutoff) .. ^1]
      if cutoff < length:
        doAssert live.anyIt(it.text == "candidate"), name
        if not mixed:
          doAssert live.allIt(it.text != "recorded"), name
      else:
        doAssert resumed.actions.allIt(it.text != "candidate"), name
    run([executable, "--replay", branch])
  for cutoff in [-1, length + 1]:
    run(@[
      executable, "--replay", source, "--resume-step", $cutoff
    ] & bots, succeeds = false)
  run([
    executable, "--replay", source, "--resume-step", $middle,
    "--bot", candidate & ":" & $(seats - 1)
  ], succeeds = false)
  run(@[executable, "--resume-step", $middle] & bots, succeeds = false)
  run([
    executable, "--replay", source, "--resume-step", $middle
  ], succeeds = false)
  echo "  verified prefix, takeover, replay, and boundaries (",
    length, " ticks)"

proc testResume() =
  ## Runs the same integration coverage for every BASIC-backed game.
  let
    started = getMonoTime()
    directory = createTempDir("polyworld-resume-", "")
  defer:
    removeDir(directory)
  testGame(
    "gota", "gods_of_the_arena/gota.nim", 10, @["--ticks", "1200"],
    gota.loadReplay, directory
  )
  testGame(
    "cta", "call_to_adventure/cta.nim", 4, @["--ticks", "120"],
    cta.loadReplay, directory
  )
  testGame(
    "lvd", "light_vs_dark/lvd.nim", 2, @["--ticks", "1200"],
    lvd.loadReplay, directory
  )
  testGame(
    "heartleaf", "heartleaf/heartleaf.nim", 9, @["--days", "1"],
    heartleaf.loadReplay, directory
  )
  testGame(
    "cac", "cac/src/cac.nim", 2, @["--ticks", "24"],
    cac.loadReplay, directory
  )
  echo "All BASIC games passed headless resume tests in ",
    formatFloat((getMonoTime() - started).inMilliseconds.float / 1000,
      ffDecimal, 1), "s"

testResume()
