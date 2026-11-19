## CaC's action-only replay format, on Polyworld's shared tape.
##
## A replay holds the match setup (seed, classes and decks), the public match
## config, every accepted game action and mailbox message in their original
## order, and one canonical state hash per
## tick. A tick is one action: a card played, an attack, a discard or
## trigger answered, or a turn ended. It never stores bot source or the
## players' private output.

import std/json
import polyworld/[tapes, mailboxes]
import sim, sessions

export tapes

const
  ## The game's old short name (Archers Warriors Mages). Every saved replay,
  ## hosted Coworld episodes included, stores it and loading checks it, so
  ## it stays "awm" after the rename to Cards and Casters.
  ReplayGame* = "awm"
  ReplayFormatVersion* = 2'u16
  ## This client supports only this gameplay version. Bump it when rules
  ## change. Older replays use their archived client.
  ReplayGameVersion* = 5'u16

  MaxReplayActions* = 1_000_000
  MaxReplayHashes* = 1_000_000
  MaxPlayers* = 7

  ActionPlayCard* = 1'u8
  ActionAttack* = 2'u8
  ActionEndTurn* = 3'u8
  ActionResolveTrigger* = 4'u8
  ActionToss* = 5'u8
  ActionGameKindHigh* = ActionToss
  ActionMailbox* = 6'u8
  ActionDuration* = 7'u8
  ActionKindHigh* = ActionDuration

type
  ReplayChoice* = object
    ## A Choice in a flat, portable form.
    kind*: uint8  ## ChoiceKind's ordinal.
    owner*, creatureId*: int32
    option*: int32  ## Which branch of a `choose` rule the player picked.

  ReplayDeckCard* = object
    name*: string
    copies*: int32

  Setup* = object
    seed*: int32
    classes*: seq[uint8]  ## One HeroClass ordinal per seat, in seat order.
    decks*: seq[seq[ReplayDeckCard]]
      ## One per seat, in seat order; empty when the seat had no legal deck.
    maximumTicks*: uint32

  ReplayAction* = object
    tick*: uint32
      ## Game action: the tick it completes, from 1. Mailbox: the number of
      ## game actions already completed, including zero before the first.
    playerId*: int32  ## The seat that acted.
    kind*: uint8
    handIndex*: int32  ## PlayCard: the hand card. Duration: the new tick cap.
    attacker*: int32  ## Attack: the minion's id.
    choices*: seq[ReplayChoice]
      ## PlayCard and ResolveTrigger: one per target. Attack: the target.
    indices*: seq[int32]  ## Toss: the hand cards discarded.
    target*: int32  ## Mailbox: -2 for everyone, otherwise the recipient seat.
    text*: string  ## Mailbox only; private VM source/output is never recorded.

  ReplayHeader* = TapeHeader[Setup]
  ReplayData* = ActionTape[Setup, ReplayAction]
  ReplayRecorder* = TapeRecorder[Setup, ReplayAction]

  ReplayCursor* = object
    ## Replay consumes the public stream without running private bot programs.
    actionIndex*: int
    inboxes*: seq[Mailbox]
    maximumTicks*: uint32

proc fail(message: string) {.noreturn.} =
  raise newException(ReplayError, message)

proc validateMailbox(action: ReplayAction, players: int) =
  ## Checks the sender, recipient, and bounded message payload.
  if action.kind != ActionMailbox or action.playerId < 0 or
      action.playerId.int >= players or action.target < -2 or
      action.target == -1 or action.target >= players.int32 or
      action.text.len == 0 or action.text.len > MaxChatBytes:
    fail("replay mailbox message is invalid")

proc applyMailbox*(inboxes: openArray[Mailbox], action: ReplayAction): int32 =
  ## Delivers one recorded message once, independently of gameplay state.
  action.validateMailbox(inboxes.len)
  let id = if action.target == -2: -2'i32 else: action.playerId
  for recipient, inbox in inboxes:
    if action.target == -2 or recipient == action.target.int:
      if inbox.push(id, action.text):
        inc result

proc initReplayCursor*(data: ReplayData): ReplayCursor =
  ## Starts with independent inboxes; rewinds create a fresh cursor.
  result.maximumTicks = data.header.setup.maximumTicks
  for _ in data.header.setup.classes:
    result.inboxes.add newMailbox()

proc applyReplayMailboxes*(data: ReplayData, cursor: var ReplayCursor,
    tick: uint32) =
  ## Consumes only messages after the gameplay actions already applied.
  while cursor.actionIndex < data.actions.len:
    let action = data.actions[cursor.actionIndex]
    if action.kind != ActionMailbox or action.tick > tick:
      break
    discard cursor.inboxes.applyMailbox(action)
    inc cursor.actionIndex

proc takeReplayAction*(data: ReplayData, cursor: var ReplayCursor,
    tick: uint32, action: var ReplayAction): bool =
  ## Selects the next game action without sorting equal-tick messages.
  data.applyReplayMailboxes(cursor, tick)
  if cursor.actionIndex == data.actions.len:
    return false
  if data.actions[cursor.actionIndex].kind == ActionDuration:
    let duration = data.actions[cursor.actionIndex]
    if duration.tick != tick + 1:
      fail("replay cursor skipped a duration change")
    cursor.maximumTicks = uint32(duration.handIndex)
    inc cursor.actionIndex
    if cursor.actionIndex == data.actions.len:
      fail("replay duration change has no following game action")
  action = data.actions[cursor.actionIndex]
  if action.kind > ActionGameKindHigh or action.tick != tick + 1:
    fail("replay cursor skipped a game action")
  inc cursor.actionIndex
  true

proc toReplay*(choice: Choice): ReplayChoice =
  result = ReplayChoice(kind: choice.kind.ord.uint8, owner: choice.owner.int32)
  if choice.kind == CreatureChoice:
    result.creatureId = choice.creatureId.int32
  if choice.kind == OptionChoice:
    result.option = choice.option.int32

proc toChoice*(choice: ReplayChoice): Choice =
  if choice.kind > ChoiceKind.high.ord.uint8:
    fail("replay choice kind is invalid")
  case ChoiceKind(choice.kind)
  of CanceledChoice: Canceled
  of NoTargetChoice: NoTarget
  of HeroChoice: heroChoice(choice.owner.int)
  of CreatureChoice: creatureChoice(choice.owner.int, choice.creatureId.int)
  of OptionChoice: optionChoice(choice.option.int)

proc toReplay*(choices: openArray[Choice]): seq[ReplayChoice] =
  for choice in choices:
    result.add choice.toReplay

proc toChoices*(choices: openArray[ReplayChoice]): seq[Choice] =
  for choice in choices:
    result.add choice.toChoice

proc applyAction*(game: var GameState, action: ReplayAction): bool =
  ## Applies one recorded action. False when the game refuses it.
  case action.kind
  of ActionPlayCard:
    game.playCard(action.handIndex.int, action.choices.toChoices)
  of ActionAttack:
    action.choices.len == 1 and
      game.attack(action.attacker.int, action.choices[0].toChoice)
  of ActionEndTurn:
    if game.waitingChoice or game.gameOver:
      false
    else:
      game.finishTurn()
      true
  of ActionResolveTrigger:
    game.resolvePendingTrigger(action.choices.toChoices)
  of ActionToss:
    var indices: seq[int]
    for index in action.indices:
      indices.add index.int
    game.resolvePendingToss(indices)
  else:
    false

proc heroClasses*(setup: Setup): seq[HeroClass] =
  for value in setup.classes:
    if value > HeroClass.high.ord.uint8:
      fail("replay setup names an unknown class")
    result.add HeroClass(value)

proc matchSetup*(seats: openArray[Seat], seed: int32,
    maxTicks: uint32): Setup =
  ## The setup that deals these seats again.
  result = Setup(seed: seed, maximumTicks: maxTicks)
  for seat in seats:
    result.classes.add seat.heroClass.ord.uint8
    var deck: seq[ReplayDeckCard]
    for (name, copies) in seat.deck:
      deck.add ReplayDeckCard(name: name, copies: copies.int32)
    result.decks.add deck

proc seats*(setup: Setup): seq[Seat] =
  ## The recorded seats, for `newGame`.
  let classes = setup.heroClasses()
  if setup.decks.len != classes.len:
    fail("replay setup needs one deck per player")
  for player, heroClass in classes:
    var seat = Seat(heroClass: heroClass)
    for card in setup.decks[player]:
      try:
        discard baseCardNamed(card.name)
      except ValueError:
        fail("replay deck names an unknown card")
      if card.copies < 1:
        fail("replay deck lists a card without copies")
      seat.deck.add (card.name, card.copies.int)
    result.add seat

proc newGame*(setup: Setup): GameState =
  ## The recorded match before its first action.
  newGame(setup.seats, setup.seed.int64)

proc initReplayRecorder*(setup: Setup, config: GameConfig): ReplayRecorder =
  ## An in-memory recorder for one match; `config` is its public record.
  result = initTapeRecorder[Setup, ReplayAction](setup,
    ReplayFormatVersion, ReplayGameVersion)
  result.data.config = config

proc record*(recorder: ReplayRecorder, action: ReplayAction) =
  ## Appends one accepted action and checks it names a real seat.
  if recorder == nil:
    return
  if action.kind == 0 or action.kind > ActionKindHigh:
    fail("replay action kind is invalid")
  if action.playerId < 0 or
      action.playerId.int >= recorder.data.header.setup.classes.len:
    fail("replay action names an unknown player")
  if action.kind == ActionMailbox:
    action.validateMailbox(recorder.data.header.setup.classes.len)
    if action.tick != recorder.data.hashes.len.uint32:
      fail("replay mailbox message is not at the current game tick")
  elif action.kind == ActionDuration:
    if action.tick != recorder.data.hashes.len.uint32 + 1 or
      action.handIndex < int32(action.tick) or
      action.handIndex > MaxReplayHashes:
        fail("replay duration change is invalid")
    recorder.data.config.maxTicks = action.handIndex
  recorder.data.actions.appendAction(action, MaxReplayActions)

proc recordDuration*(recorder: ReplayRecorder, tick, maximumTicks: uint32) =
  ## Changes the cap immediately before the named gameplay action.
  recorder.record(ReplayAction(kind: ActionDuration, tick: tick,
    handIndex: int32(maximumTicks)))

proc durationAt*(data: ReplayData, tick: uint32): uint32 =
  ## Returns the match cap after all gameplay actions through this tick.
  result = data.header.setup.maximumTicks
  for action in data.actions:
    if action.tick > tick:
      break
    if action.kind == ActionDuration:
      result = uint32(action.handIndex)

proc recordMailbox*(recorder: ReplayRecorder, tick: uint32,
    sender, target: int, text: openArray[char]) =
  ## Appends mail at its admission point; messages do not consume game turns.
  if recorder == nil:
    return
  var message = newString(text.len)
  for index, value in text:
    message[index] = value
  recorder.record(ReplayAction(kind: ActionMailbox, tick: tick,
    playerId: sender.int32, target: target.int32, text: message))

proc recordHash*(recorder: ReplayRecorder, hash: uint64) =
  ## Appends one tick hash using the current recorded duration.
  if recorder != nil:
    recorder.data.hashes.appendHash(hash,
      uint32(recorder.data.config.maxTicks), MaxReplayHashes)

proc validate*(data: ReplayData) =
  ## Rejects a replay this build can't play back exactly.
  data.header.requireTapeVersion(ReplayFormatVersion, ReplayGameVersion)
  let setup = data.header.setup
  if setup.classes.len notin 2 .. MaxPlayers:
    fail("replay setup has an unsupported player count")
  discard setup.seats()
  data.config.validateConfig(setup.classes.len)
  if data.hashes.len > MaxReplayHashes or data.actions.len > MaxReplayActions:
    fail("replay is too long")
  var
    tick = 0'u32
    maximumTicks = setup.maximumTicks
    pendingDuration = false
  for action in data.actions:
    if action.kind == 0 or action.kind > ActionKindHigh:
      fail("replay action kind is invalid")
    if action.playerId < 0 or action.playerId.int >= setup.classes.len:
      fail("replay action names an unknown player")
    if action.kind == ActionMailbox:
      action.validateMailbox(setup.classes.len)
      if action.tick != tick or pendingDuration:
        fail("replay mailbox message is not at its admission tick")
    elif action.kind == ActionDuration:
      if pendingDuration or action.tick != tick + 1 or
        action.handIndex < int32(action.tick) or
        action.handIndex > MaxReplayHashes or
        (maximumTicks > 0 and tick > maximumTicks):
          fail("replay duration change is invalid")
      maximumTicks = uint32(action.handIndex)
      pendingDuration = true
    else:
      if action.tick != tick + 1:
        fail("replay game actions are not one per tick")
      tick = action.tick
      pendingDuration = false
      if maximumTicks > 0 and tick > maximumTicks:
        fail("replay is longer than its tick limit")
  if pendingDuration:
    fail("replay duration change has no following game action")
  if data.config.maxTicks.uint32 != maximumTicks:
    fail("replay duration disagrees with its configuration")
  if tick.uint64 != data.hashes.len.uint64:
    fail("replay actions and hashes do not match")

proc encodeReplay*(data: ReplayData): string =
  ## Validates and encodes the game's ordered command tape.
  data.validate()
  encodeReplayFile(ReplayGame, ReplayGameVersion, data,
    DefaultMaxReplayBytes)

proc decodeReplay*(bytes: string): ReplayData =
  ## Decodes and validates a current-version game recording.
  result = decodeReplayFile(ReplayGame, ReplayGameVersion, bytes, ReplayData,
    DefaultMaxReplayBytes)
  result.validate()

proc saveReplay*(path: string, data: ReplayData) =
  data.validate()
  saveReplayFile(path, ReplayGame, ReplayGameVersion, data,
    DefaultMaxReplayBytes)

proc loadReplay*(path: string): ReplayData =
  if path.len == 0:
    fail("replay input path is empty")
  readFile(path).decodeReplay()

proc stateHash*(game: GameState): uint64 =
  ## FNV-1a over the game's canonical JSON, without the pending visual
  ## events (only a presentation drains those). The same on every
  ## platform, so a browser replay can check the native recording.
  var node = gameToJson(game)
  node.delete("visualEvents")
  result = 0xcbf29ce484222325'u64
  for character in $node:
    result = (result xor character.ord.uint64) * 0x100000001b3'u64
