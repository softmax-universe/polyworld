## Presentation-only human communication. Never drains simulation mailboxes.
import std/unicode
import polyworld/[mailboxes, rooms, tapes, configs]
import bots, content, sim, multiplayer, diplomacies, replays
export diplomacies

const MaxHumanChatLines* = 100

type
  HumanChatLine* = object
    player*: int32
    localNotice*: bool
    name*, text*: string
  HumanCommunication* = object
    typing*, diplomacyOpen*, blockedFrame*: bool
    draft*, status*: string
    feed*: seq[HumanChatLine]
    chatGame: Game
    chatTick: uint32
    chatIndex: int
    matchNoticeShown: bool
    diplomacyPage*: int

proc reset*(state: var HumanCommunication) =
  state = HumanCommunication()

proc blocksGameplay*(state: HumanCommunication): bool =
  state.typing or state.diplomacyOpen or state.blockedFrame

proc finishFrame*(state: var HumanCommunication) =
  state.blockedFrame = false

proc addLine(state: var HumanCommunication, game: Game, sender: int32, text: string) =
  if state.feed.len >= MaxHumanChatLines: state.feed.delete(0)
  state.feed.add HumanChatLine(player: sender,
    name: game.config.players[sender].displayName(int(sender)), text: text)

proc addMatchNotice(state: var HumanCommunication, game: Game, tick: uint32) =
  ## Derives the local warning from applied game time, including replay seeks.
  let trigger = int64(game.maximumTicks) - 180'i64 * TickRate
  if state.matchNoticeShown or trigger <= 0 or int64(tick) < trigger:
    return
  state.matchNoticeShown = true
  if state.feed.len >= MaxHumanChatLines:
    state.feed.delete(0)
  state.feed.add HumanChatLine(player: -1, name: "Match",
    text: "3 minutes remain", localNotice: true)

proc publicChat(chat: ReplayChat, players: int): bool =
  ## Keeps direct messages and invalid display text out of the public feed.
  chat.target == -2 and chat.playerId >= 0 and
    int(chat.playerId) < players and chat.text.len > 0 and
    validateUtf8(chat.text) == -1

proc syncChatFeed(
    state: var HumanCommunication,
    game: Game,
    chats: openArray[ReplayChat]
) =
  ## Restores visible history on rewind, otherwise appends newly due messages.
  let
    tick = uint32(max(0'i32, game.world.tick))
    players = game.config.players.len
    rebuild = state.chatGame != game or tick < state.chatTick or
      state.chatIndex > chats.len
    clearFeed = state.chatGame != nil or game.replayMode or game.historyPlayback
  state.chatGame = game
  state.chatTick = tick
  if rebuild:
    state.matchNoticeShown = false
    if clearFeed:
      state.feed.setLen(0)
    var
      first = 0
      last = chats.len
    while first < last:
      let middle = first + (last - first) div 2
      if chats[middle].tick <= tick:
        first = middle + 1
      else:
        last = middle
    state.chatIndex = first
    var remaining = MaxHumanChatLines
    while state.chatIndex > 0 and remaining > 0:
      dec state.chatIndex
      if chats[state.chatIndex].publicChat(players):
        dec remaining
  while state.chatIndex < chats.len and
    chats[state.chatIndex].tick <= tick:
      let chat = chats[state.chatIndex]
      inc state.chatIndex
      if chat.publicChat(players):
        state.addMatchNotice(game, chat.tick)
        state.addLine(game, chat.playerId, chat.text)
  state.addMatchNotice(game, tick)

proc syncChatFeed*(state: var HumanCommunication, game: Game) =
  ## Reads recorded chat at the displayed tick without consuming bot mailboxes.
  if game == nil or game.world == nil:
    return
  if game.recorder != nil:
    state.syncChatFeed(game, game.recorder.data.chats)
  else:
    state.syncChatFeed(game, game.replayData.chats)

proc chatRune*(state: var HumanCommunication, rune: Rune): bool =
  if not state.typing: return false
  result = true # Consume even rejected input; it must never become a hotkey.
  let value = int(rune)
  if value < 32 or value in 127 .. 159 or value > 0x10ffff or
      value in 0xd800 .. 0xdfff: return
  let encoded = rune.toUTF8()
  if state.draft.len + encoded.len <= MaxChatBytes:
    state.draft.add encoded

proc chatEnter*(state: var HumanCommunication, game: Game, player: int32): bool =
  if game == nil or game.replayMode or game.historyPlayback or
    player notin 0'i32 ..< int32(game.inboxes.len):
      return false
  state.blockedFrame = true
  if not state.typing:
    state.typing = true
    state.diplomacyOpen = false
    state.draft = ""
    state.status = ""
    return true
  if unicode.strip(state.draft).len == 0:
    state.typing = false
    state.draft = ""
    return true
  if game.sendChat(int(player), -2, state.draft) > 0:
    if not game.networked:
      if game.recorder != nil:
        state.syncChatFeed(game)
      else:
        state.addLine(game, player, state.draft)
    state.typing = false
    state.draft = ""
    state.status = ""
  else:
    state.status = "Chat queue full; try again."
  true

proc chatBackspace*(state: var HumanCommunication) =
  if not state.typing or state.draft.len == 0: return
  var index = state.draft.high
  while index > 0 and (ord(state.draft[index]) and 0xc0) == 0x80: dec index
  state.draft.setLen(index)

proc cancelCommunication*(state: var HumanCommunication): bool =
  result = state.typing or state.diplomacyOpen
  if result:
    state.typing = false
    state.diplomacyOpen = false
    state.draft = ""
    state.blockedFrame = true

proc diplomacyChoices*(game: Game, player, other: int32): set[DiplomacyCommand] =
  ## Validate against a detached copy; never change authoritative relations.
  if game == nil or game.replayMode or game.world == nil: return
  let world = game.world
  if player < 0 or other < 0 or player >= world.players.len or
      other >= world.players.len or player == other or
      world.players[player].defeated or world.players[other].defeated: return
  for command in DiplomacyCommand:
    var preview = world.diplomacy
    # Explicit copy keeps preview independent under every Nim memory manager.
    preview.pairs = @[]
    for pair in world.diplomacy.pairs: preview.pairs.add pair
    let relation = world.diplomacy.relation(player, other)
    if preview.apply(player, other, world.tick, command, relation.offerId):
      result.incl command

proc submitHumanDiplomacy*(game: Game, player, other: int32,
    command: DiplomacyCommand, offerId = 0'i32): bool =
  if command notin game.diplomacyChoices(player, other): return false
  if command in {AcceptOffer, DeclineOffer, WithdrawOffer} and
      offerId != game.world.diplomacy.relation(player, other).offerId: return false
  game.applyDiplomacy(player, other, command, offerId)

proc observeHumanPacket*(state: var HumanCommunication, session: NetworkMatch,
    packet: RoomMessage) =
  ## Observes the authoritative transcript after successful packet application.
  if session == nil or session.client == nil or session.game == nil or
    packet.kind != TickPacket or packet.match != session.client.match or
    packet.tick != uint32(session.game.world.tick):
      return
  state.syncChatFeed(session.game)
