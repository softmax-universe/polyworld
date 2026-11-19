## A match between bot scripts with no window, one action per tick, as the
## Coworld server and the headless recorder play it. The browser replays
## the recorded actions through `applyAction`.
##
## Scripts select every voluntary action, including required choices and
## turn ends. A missing or failed decision stops the match without a fallback.
import sim, bots, replays
export replays.applyAction

type
  MatchOutcome* = enum
    MatchRunning, MatchWon, MatchDrawn, MatchTimedOut, MatchFailed

  BotMatch* = object
    game*: GameState
    bots*: seq[BotVm]  ## One per seat; A missing acting seat stops the match.
    tick*: uint32  ## Actions taken so far.
    maxTicks*: uint32
    recorder*: ReplayRecorder
    warmup*: ReplayData
    resumeStep*: uint32
    warmupCursor: ReplayCursor
    scriptError*: proc(player: int, message: string)
      ## Called when a seat fails to supply a legal action.
    failed*: bool  ## No valid explicit action was supplied.

proc initBotMatch*(seats: openArray[Seat], seed: int64,
    bots: seq[BotVm], maxTicks: uint32,
    recorder: ReplayRecorder = nil): BotMatch =
  ## Starts a deterministic match with explicit seat-owned policies.
  result = BotMatch(game: newGame(seats, seed, recordEvents = true),
    bots: bots, maxTicks: maxTicks, recorder: recorder)
  for bot in result.bots:
    bot.ensureSeed(seed)

proc initBotMatch*(classes: openArray[HeroClass], seed: int64,
    bots: seq[BotVm], maxTicks: uint32,
    recorder: ReplayRecorder = nil): BotMatch =
  ## Every seat with its class's precon.
  var seats: seq[Seat]
  for heroClass in classes:
    seats.add precon(heroClass)
  initBotMatch(seats, seed, bots, maxTicks, recorder)

proc outcome*(match: BotMatch): MatchOutcome =
  if match.failed:
    MatchFailed
  elif match.game.gameOver:
    if match.game.winner >= 0: MatchWon else: MatchDrawn
  elif match.maxTicks > 0 and match.tick >= match.maxTicks: MatchTimedOut
  else: MatchRunning

proc nextAction(match: var BotMatch): ReplayAction =
  ## Runs only the acting seat's script and returns its accepted action.
  let player = match.game.actingPlayer()
  let vm = if player < match.bots.len: match.bots[player] else: nil
  if vm != nil:
    let recorder = match.recorder
    let tick = match.tick
    vm.onSendChat = proc(sender, target: int,
        text: openArray[char]): int32 =
      result = bots.sendChat(sender, target, text)
      if result > 0:
        recorder.recordMailbox(tick, sender, target, text)
    try:
      if vm.runDecision(match.game) != BotFailed:
        return vm.action
    finally:
      vm.onSendChat = nil
  match.failed = true
  let message =
    if vm == nil: "No BASIC script for acting player " & $player
    else: vm.lastError
  if match.scriptError != nil:
    match.scriptError(player, message)

proc step*(match: var BotMatch): bool =
  ## Plays one tick. False once the match is over.
  if match.outcome != MatchRunning:
    return false
  var action: ReplayAction
  if match.tick < match.resumeStep:
    let
      vm = match.bots[match.game.actingPlayer()]
      first = match.warmupCursor.actionIndex
      cursor = addr match.warmupCursor
      data = match.warmup
      tick = match.tick
    cursor.inboxes = inboxes
    vm.watching = true
    vm.onSendChat = proc(sender, target: int,
        text: openArray[char]): int32 =
      if cursor.actionIndex >= data.actions.len:
        return
      let recorded = data.actions[cursor.actionIndex]
      if recorded.kind != ActionMailbox or recorded.tick != tick or
          recorded.playerId != sender or recorded.target != target or
          recorded.text.len != text.len:
        return
      for index, value in text:
        if recorded.text[index] != value:
          return
      result = cursor.inboxes.applyMailbox(recorded)
      if result > 0:
        inc cursor.actionIndex
    try:
      discard vm.runDecision(match.game, apply = false)
    finally:
      vm.watching = false
      vm.onSendChat = nil
    # Admit this decision's original messages, stopping at its game action.
    if not match.warmup.takeReplayAction(
      match.warmupCursor, match.tick, action
    ):
      raise newException(ReplayError, "Replay gameplay action is missing")
    for index in first ..< match.warmupCursor.actionIndex - 1:
      match.recorder.record(match.warmup.actions[index])
    if not match.game.applyAction(action):
      raise newException(ReplayError, "Replay action refused during warm-up")
  else:
    action = match.nextAction()
  if action.kind == 0:
    return false
  discard match.game.takeVisualEvents()
  inc match.tick
  action.tick = match.tick
  if match.tick <= match.resumeStep and
      match.game.stateHash != match.warmup.hashes[match.tick.int - 1]:
    raise newException(ReplayError, "Replay hash mismatch during warm-up")
  if match.recorder != nil:
    match.recorder.record(action)
    match.recorder.recordHash(match.game.stateHash)
  true

proc run*(match: var BotMatch) =
  ## Runs explicit decisions until completion, timeout, or player failure.
  while match.step():
    discard

proc scores*(match: BotMatch): seq[int] =
  ## 1 for the last player standing, 0 for everyone else.
  result = newSeq[int](match.game.playerCount)
  if match.outcome == MatchWon:
    result[match.game.winner] = 1

proc outcomeLabel*(match: BotMatch): string =
  case match.outcome
  of MatchWon: "winner_" & $match.game.winner
  of MatchDrawn: "draw"
  of MatchTimedOut: "timeout"
  of MatchRunning: "running"
  of MatchFailed: "player_failure"
