## Each client derives the warning from its own authoritative simulation.
import std/importutils
import polyworld/[rooms, roomclients]
import ../[chats, content, maps, matchnotices, multiplayer, replays, sim]
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
  doAssert session.client.outgoing.len == 0, "The local notice never submits a command"
  let tape = decodeReplay(encodeReplay(session.game.recorder.data))
  doAssert tape.actions.len == 1
  doAssert tape.actions[0].kind == ActionSystemNotice
  doAssert tape.actions[0].heroId == 0
  doAssert tape.actions[0].first == -2
  doAssert tape.actions[0].text == ThreeMinuteNotice
  doAssert tape.actions[0].tick == 2 * TickRate.uint32
  var view: ReplayChatView
  doAssert view.chatAt(tape, 2 * TickRate.uint32 - 1).len == 0
  doAssert view.chatAt(tape, 2 * TickRate.uint32).len == 1
  doAssert view.chatAt(tape, 0).len == 0
  doAssert view.chatAt(tape, 3 * TickRate.uint32).len == 1,
    "Backward and forward seeks consume the one recorded notice"
# Seek back across threshold with the independently retained chat/cursor.
first.game.world.restore(beforeCrossing)
first.applyPacket(packetAt(2 * TickRate.uint32), localPlayback = true)
doAssert first.humanChat.len == 1
doAssert first.game.recorder.data.actions.len == 1,
  "Cached packet playback must not record a second notice"
let reconnect = fixture()
for tick in 1'u32 .. 3'u32 * TickRate.uint32:
  reconnect.applyPacket(packetAt(tick), localPlayback = true)
doAssert reconnect.humanChat == second.humanChat, "Reconnect history reconstructs identical notice"
let shortMatch = fixture(180 * TickRate)
shortMatch.applyPacket(RoomMessage(kind: TickPacket, match: 1, tick: 1), localPlayback = true)
doAssert shortMatch.humanChat.len == 0
# Seeking reconstructs one recorded notice after the display cache evicts it.
for tick in 1000 .. 1110:
  first.humanChat.appendHumanChat(HumanChatMessage(tick: tick.uint32,
    ordinal: 0, text: "later human chat"))
first.game.world.restore(beforeCrossing)
first.applyPacket(packetAt(2 * TickRate.uint32), localPlayback = true)
doAssert first.humanChat.len == 1 and first.humanChat[0].system
doAssert first.game.recorder.data.actions.len == 1

let emptyTicks = fixture()
for tick in 1'u32 .. 3'u32 * TickRate.uint32:
  emptyTicks.applyPacket(RoomMessage(kind: TickPacket, match: 1, tick: tick), localPlayback = true)
doAssert emptyTicks.humanChat.len == 1, "Empty relay ticks need no notice payload"
echo "Testing notice follows admitted actions in the same canonical tick"
let ordered = fixture()
ordered.heroSeats = @[0, 1]
for tick in 1'u32 .. 2'u32 * TickRate.uint32:
  var packet = packetAt(tick)
  if tick == 2 * TickRate.uint32:
    packet.commands.add Command(participant: 1, seat: 0,
      seatKind: HumanSeat, sequence: 1,
      payload: GameSubmission(action: ReplayAction(
        heroId: ordered.game.world.heroes[0].id,
        kind: ActionStop)).encodeSubmission())
  ordered.applyPacket(packet, localPlayback = true)
let orderedTape = decodeReplay(encodeReplay(ordered.game.recorder.data))
doAssert orderedTape.actions.len == 2
doAssert orderedTape.actions[0].kind == ActionStop
doAssert orderedTape.actions[1].kind == ActionSystemNotice
doAssert orderedTape.actions[0].tick == orderedTape.actions[1].tick
doAssert orderedTape.actions[1].text == ThreeMinuteNotice

echo "PASS local warning, canonical action order, reconnect and seek dedupe"
