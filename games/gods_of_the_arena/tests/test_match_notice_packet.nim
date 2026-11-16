## Recorded server event consumption; empty ticks must not fabricate notices.
import std/importutils
import polyworld/[rooms, roomclients]
import ../[chats, content, maps, relaynotice, multiplayer, replays, sim]
privateAccess(NetworkMatch)

proc fixture(limit = 182 * TickRate): NetworkMatch =
  let game = newGame(generateMap(2026), 10 * TickRate, 2, false,
    ReplayData(), drafting = false)
  game.recorder = initReplayRecorder(currentSetup(game, uint32(limit)))
  game.recorder.data.config.maxTicks = limit
  game.networked = true
  game.world.camps.setLen(0)
  result = NetworkMatch(client: RoomClient(), game: game,
    started: true, match: 1, spectator: true)

let first = fixture()
let second = fixture()
proc packetAt(tick: uint32): RoomMessage =
  result = RoomMessage(kind: TickPacket, match: 1, tick: tick)
  if tick == 2 * TickRate.uint32:
    result.commands.add Command(participant: 0, seat: ServerNoticeSeat,
      sequence: 1, payload: noticePayload())

var beforeCrossing: World
for tick in 1'u32 .. 3'u32 * TickRate.uint32:
  let packet = packetAt(tick)
  first.applyPacket(packet, localPlayback = true)
  if tick == 2 * TickRate.uint32 - 1:
    beforeCrossing = first.game.world.clone()
  if tick < 2 * TickRate.uint32:
    doAssert first.humanChat.len == 0
  else:
    doAssert first.humanChat.len == 1
  second.applyPacket(packet, localPlayback = true)
  doAssert first.humanChat == second.humanChat
for session in [first, second]:
  doAssert session.humanChat[0].text == ThreeMinuteNotice
  doAssert session.humanChat[0].tick == 2 * TickRate.uint32
  doAssert session.humanChat[0].system and session.humanChat[0].sender.len == 0
  doAssert session.client.outgoing.len == 0, "No forged outgoing command"
# Seek back across threshold with the independently retained chat/cursor.
first.game.world.restore(beforeCrossing)
first.applyPacket(packetAt(2 * TickRate.uint32), localPlayback = true)
doAssert first.humanChat.len == 1
let reconnect = fixture()
for tick in 1'u32 .. 3'u32 * TickRate.uint32:
  reconnect.applyPacket(packetAt(tick), localPlayback = true)
doAssert reconnect.humanChat == second.humanChat, "Reconnect history reconstructs identical notice"
let shortMatch = fixture(180 * TickRate)
shortMatch.applyPacket(RoomMessage(kind: TickPacket, match: 1, tick: 1), localPlayback = true)
doAssert shortMatch.humanChat.len == 0
# Even when the display history evicts the notice, seeking cannot reinsert it.
for tick in 1000 .. 1110:
  first.humanChat.appendHumanChat(HumanChatMessage(tick: tick.uint32,
    ordinal: 0, text: "later human chat"))
first.game.world.restore(beforeCrossing)
first.applyPacket(packetAt(2 * TickRate.uint32), localPlayback = true)
for message in first.humanChat:
  doAssert not message.system

let emptyTicks = fixture()
for tick in 1'u32 .. 3'u32 * TickRate.uint32:
  emptyTicks.applyPacket(RoomMessage(kind: TickPacket, match: 1, tick: tick), localPlayback = true)
doAssert emptyTicks.humanChat.len == 0, "No client fallback at the threshold"
for forged in [Command(participant: 1, seat: ServerNoticeSeat, sequence: 1, payload: noticePayload()),
    Command(participant: 0, seat: 0, sequence: 1, payload: noticePayload()),
    Command(participant: 0, seat: ServerNoticeSeat, sequence: 2, payload: noticePayload())]:
  let session = fixture()
  var rejected = false
  try:
    session.applyPacket(RoomMessage(kind: TickPacket, match: 1, tick: 1,
      commands: @[forged]), localPlayback = true)
  except RoomsError: rejected = true
  doAssert rejected and session.game.world.tick == 0 and session.humanChat.len == 0
echo "PASS recorded server event, no fallback, reconnect, short match, seek/eviction dedupe, sentinel validation"
