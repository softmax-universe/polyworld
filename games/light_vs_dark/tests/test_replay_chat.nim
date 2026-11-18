## Chat survives recording, bot reactions, playback, and timeline seeks.
import
  std/[strformat, unicode],
  jsony, polyworld/[mailboxes, tapes, rooms, roomclients],
  ../[bots, content, game, humancommunication, multiplayer, presets, replays, sim]

var config = defaultConfig(2)
config.maxTicks = 12
config.mapSettings = MapSettings(layout: RandomLayout, size: 90, expansions: 0)
let live = newLocalMatch(config, ["", ""])
var worker: Unit
for unit in live.world.units:
  if unit.owner == 1:
    worker = unit
    break
doAssert worker != nil
live.loadBots(["", &"""
while mailboxCount() > 0
  message$ = pullMailbox$()
  if message$ = "go 雪" then
    accepted = moveUnit({worker.id}, {worker.tile.x + 2}, {worker.tile.y})
    sent = sendChat(-2, "moving 🙂")
  end if
wend
"""])

var feed: HumanCommunication
doAssert feed.chatEnter(live, 0)
for rune in "go 雪".runes:
  doAssert feed.chatRune(rune)
doAssert feed.chatEnter(live, 0)
doAssert live.recorder.data.chats.len == 1
doAssert live.recorder.data.chats[0].tick == 0
doAssert feed.feed.len == 1
feed.syncChatFeed(live)
doAssert feed.feed.len == 1
let beginning = live.world.clone()
run = live
for tick in 1 .. config.maxTicks:
  advanceGame()
  if tick == 2:
    doAssert live.sendChat(0, 1, "private message") > 0
  feed.syncChatFeed(live)
doAssert not live.brains[1].failed, live.brains[1].lastError
doAssert live.recorder.data.actions.len == 1
doAssert live.recorder.data.actions[0].kind == ActionMove
doAssert live.recorder.data.chats.len == 3
doAssert feed.feed.len == 2
doAssert feed.feed[1].text == "moving 🙂"
doAssert live.inboxes[1].count == 0, "The bot consumed its messages"

let data = decodeReplay(encodeReplay(live.recorder.data))
doAssert data.chats == live.recorder.data.chats
doAssert data.chats[2].target == 1
doAssert data.chats[2].text == "private message"
let playback = newGame(
  live.world.map, config.maxTicks, data.header.setup.diplomacySettings
)
playback.replayMode = true
playback.historyPlayback = true
playback.replayData = data
playback.replayPlayer = initReplayPlayer(data)
run = playback
feed.syncChatFeed(playback)
doAssert feed.feed.len == 1 and feed.feed[0].text == "go 雪"
for tick in 1 .. data.hashes.len:
  advanceGame()
  feed.syncChatFeed(playback)
  feed.syncChatFeed(playback)
  doAssert playback.stateHash() == data.hashes[tick - 1]
  doAssert feed.feed.len == 2
doAssert playback.hashCheck.mismatches == 0
doAssert playback.brains[1] == nil, "Replay must not rerun chat-driven bots"
doAssert playback.inboxes[1] == nil, "Replay feed must not depend on mailboxes"

playback.world.restore(beginning)
playback.replayPlayer.syncCursor(0)
feed.syncChatFeed(playback)
doAssert feed.feed.len == 1, "Rewinding must hide future chat"
advanceGame()
feed.syncChatFeed(playback)
doAssert feed.feed.len == 2, "Playback must restore chat without duplicates"
doAssert not feed.chatEnter(playback, 0)
doAssert playback.sendChat(0, -2, "cannot edit replay") == 0

live.world.restore(beginning)
live.historyPlayback = true
feed.syncChatFeed(live)
doAssert feed.feed.len == 1, "Live history must also hide future chat"
doAssert not feed.chatEnter(live, 0)
doAssert live.sendChat(0, -2, "cannot edit history") == 0
echo "PASS saved Unicode chat, private messages, bot reactions, hashes and seeks"

let fresh = newLocalMatch(config, ["", ""])
feed.syncChatFeed(fresh)
doAssert feed.feed.len == 0
doAssert fresh.sendChat(0, -2, "first") > 0
feed.syncChatFeed(fresh)
doAssert fresh.sendChat(1, -2, "second") > 0
feed.syncChatFeed(fresh)
doAssert feed.feed.len == 2, "Paused same-tick messages must appear immediately"
doAssert fresh.recorder.data.chats[0].tick == 0
doAssert fresh.recorder.data.chats[1].tick == 0
echo "PASS same-tick chat and new-match feed reset"

block fullLocalTranscript:
  fresh.recorder.data.chats.setLen(MaxReplayChats)
  let
    beforeHash = fresh.stateHash()
    beforeCounts = [fresh.inboxes[0].count, fresh.inboxes[1].count]
  doAssert fresh.sendChat(0, -2, "cannot record") == 0
  doAssert fresh.recorder.data.chats.len == MaxReplayChats
  for i, count in beforeCounts:
    doAssert fresh.inboxes[i].count == count,
      "Rejected chat must not reach a mailbox"
  var rejected = false
  try:
    discard fresh.deliverChat(0, -2, "direct delivery cannot record")
  except ReplayError:
    rejected = true
  doAssert rejected, "Direct delivery must report exhausted recording capacity"
  for i, count in beforeCounts:
    doAssert fresh.inboxes[i].count == count,
      "Failed recording must happen before mailbox delivery"
  doAssert fresh.stateHash() == beforeHash
  doAssert fresh.chatSubmissions.len == 0
  echo "PASS full local transcript rejects chat before mailbox mutation"

block authoritativeBatchCapacity:
  var sparseConfig = defaultConfig(4)
  sparseConfig.maxTicks = 12
  sparseConfig.mapSettings = config.mapSettings
  let client = RoomClient(
    identity: lvdIdentity(), participant: 1, match: 1,
    began: true, welcomed: true, connected: true
  )
  client.snapshot = RoomMessage(
    kind: RoomState, revision: 2, phase: Playing,
    tickRate: uint32(TickRate), payload: sparseConfig.toJson(),
    seats: @[
      Seat(), Seat(owner: 1, name: "Human"),
      Seat(), Seat(owner: 2, name: "Human")
    ],
    participants: @[
      Participant(id: 1, name: "Alice"), Participant(id: 2, name: "Bob")
    ]
  )
  client.initialSnapshot = client.snapshot
  client.appliedSeats = client.snapshot.seats
  let session = prepareNetworkMatch(client, [])
  session.start(RoomMessage(
    kind: BeginMatch, match: 1, revision: 2,
    hash: setupHash(session.client.snapshot)
  ))
  session.game.recorder.data.chats.setLen(MaxReplayChats - 1)
  let
    beforeHash = session.game.networkHash()
    own = session.game.world.units[0]
    move = ReplayAction(
      kind: ActionMove, playerId: 0, entityId: own.id,
      first: int32(own.tile.x) + 1, second: int32(own.tile.y)
    )
    firstChat = ChatSubmission(player: 0, target: -2, text: "first")
    secondChat = ChatSubmission(player: 1, target: -2, text: "second")
    emptyChat = ChatSubmission(player: 0, target: -2, text: "")
    packet = RoomMessage(
      kind: TickPacket, seats: client.snapshot.seats, match: 1, tick: 1,
      commands: @[
        Command(participant: 1, seat: 1, payload: move.encodeSubmission()),
        Command(participant: 1, seat: 1, payload: emptyChat.encodeChat()),
        Command(participant: 1, seat: 1, payload: firstChat.encodeChat()),
        Command(participant: 2, seat: 3, payload: secondChat.encodeChat())
      ]
    )
  var rejected = false
  try:
    session.applyPacket(packet)
  except RoomsError:
    rejected = true
  doAssert rejected, "An overflowing chat batch must fail before delivery"
  doAssert session.game.networkHash() == beforeHash
  doAssert session.game.world.tick == 0
  doAssert session.game.networkActions.len == 0
  doAssert session.game.recorder.data.actions.len == 0
  doAssert session.game.recorder.data.hashes.len == 0
  doAssert session.game.recorder.data.chats.len == MaxReplayChats - 1
  for inbox in session.game.inboxes:
    doAssert inbox.count == 0, "No chat from a rejected batch may be delivered"
  let finalSlot = RoomMessage(
    kind: TickPacket, seats: client.snapshot.seats, match: 1, tick: 1,
    commands: @[
      Command(participant: 1, seat: 1, payload: emptyChat.encodeChat()),
      Command(participant: 2, seat: 3, payload: secondChat.encodeChat())
    ]
  )
  session.applyPacket(finalSlot)
  doAssert session.game.recorder.data.chats.len == MaxReplayChats
  doAssert session.game.recorder.data.chats[^1].text == "second"
  doAssert session.game.recorder.data.chats[^1].playerId == 1
  doAssert session.game.recorder.data.chats[^1].tick == 1
  for inbox in session.game.inboxes:
    doAssert inbox.count == 1
  doAssert session.game.sendChat(0, -2, "cannot enqueue") == 0
  doAssert session.game.chatSubmissions.len == 0
  echo "PASS chat batch capacity is atomic and empty messages use no slots"
