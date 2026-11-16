## Inspect literal Relay.advance history bytes BEFORE any client consumes them.
import jsony
import polyworld/[rooms, roomclients, relays]
import ../[chats, content, matchtiming, multiplayer, presets, replays, sim]
import std/importutils
privateAccess(NetworkMatch)

proc run(limit: int32, pickEarly: bool, mode = UniqueDraft, seed = 54'i32) =
  let relay = Relay()
  var now = 0.0
  var clients = @[RoomClient(identity: gotaIdentity(), name: "Host"),
    RoomClient(identity: gotaIdentity(), name: "Guest")]
  proc exchange() =
    for attempt in 0 ..< 40:
      var sent = false
      for i, client in clients:
        let outgoing = client.outgoing
        client.outgoing = @[]
        for bytes in outgoing:
          relay.process(i + 1, bytes, now)
          sent = true
      var outgoing: seq[Outgoing]
      swap(outgoing, relay.outgoing)
      for output in outgoing:
        if output.bytes.len > 0:
          clients[output.connection - 1].accept(output.bytes)
          sent = true
      if not sent: return
    doAssert false, "exchange did not settle"
  for client in clients: client.opened()
  exchange()
  var config = parseConfig("{}")
  config.maxTicks = limit
  config.draftMode = mode
  config.seed = seed
  clients[0].send(RoomMessage(kind: CreateRoom, name: "Server notice QA",
    number: 10, tickRate: 24, payload: config.toJson()))
  exchange()
  clients[1].send(RoomMessage(kind: JoinRoom, room: clients[0].snapshot.room))
  exchange()
  clients[0].claimHumanSeat(1)
  clients[1].claimHumanSeat(8)
  exchange()
  let sessions = [prepareNetworkMatch(clients[0], []), prepareNetworkMatch(clients[1], [])]
  clients[0].send(RoomMessage(kind: StartMatch, revision: sessions[0].revision,
    hash: sessions[0].game.networkHash()))
  exchange()
  for i, session in sessions:
    doAssert clients[i].error.len == 0, clients[i].error
    session.start(clients[i].events[0])
    clients[i].events.setLen(0)
  exchange()
  let room = relay.room(clients[0].snapshot.room)
  var notices = 0
  var expected = 0'u32
  var captured: seq[RoomMessage]
  var beforeNotice: World
  proc step() =
    now += 1.0 / 24 + 0.000001
    relay.advance(now)
    # This is the real server-produced binary packet, not synthesized by clients.
    if room.history.len > captured.len:
      let packet = decode(room.history[^1])
      captured.add packet
      for command in packet.commands:
        if command.participant == 0:
          inc notices
          doAssert command.seat == high(uint32)
          doAssert packet.tick == expected and expected > 0
          doAssert command.sequence == 1
          doAssert command.payload.len == 8
          doAssert sessions[0].game.remainingMatchTicks() == 180 * TickRate + 1,
            "Actual simulation must have exactly 3 minutes left after this tick"
          var reader = PacketReader(data: command.payload)
          doAssert reader.get32() == 3 and reader.get32() == 1
          doAssert sessions[0].humanChat.len == 0, "Inspect server bytes before display"
          beforeNotice = sessions[0].game.world.clone()
    exchange()
    for i, session in sessions:
      var packet: RoomMessage
      while clients[i].takeTick(packet): session.applyPacket(packet)
    exchange()
    doAssert sessions[0].game.networkHash() == sessions[1].game.networkHash()
    doAssert sessions[0].humanChat == sessions[1].humanChat
    if expected == 0 and sessions[0].game.world.phase == Playing:
      expected = uint32(sessions[0].game.world.draftTicks + PreparationTicks + limit - 180 * TickRate)
  # A forged human may not queue a reserved server notice even on its own seat.
  var forged: string
  forged.put32(3)
  forged.put32(1)
  clients[0].send(RoomMessage(kind: SubmitCommand, match: clients[0].match,
    seat: 1, sequence: 1, payload: forged))
  exchange()
  doAssert clients[0].error.len > 0, "Relay must reject reserved server payload from a human"
  clients[0].error = ""
  clients[0].send(RoomMessage(kind: SubmitCommand, match: clients[0].match,
    seat: high(uint32), sequence: 1, payload: forged))
  exchange()
  doAssert clients[0].error.len > 0
  clients[0].error = ""
  var paused = false
  var reconnected = false
  while room.tick < 2 * DraftPickTicks.uint32 + PreparationTicks.uint32 + 3 * TickRate.uint32:
    if pickEarly and sessions[0].game.world.phase == Drafting:
      let hero = sessions[0].game.world.draftHeroId()
      let index = sessions[0].game.world.heroIndex(hero)
      let owner = if index == 0: 0 else: 1
      var classId = 0'i32
      while not sessions[0].game.world.heroAvailable(classId): inc classId
      doAssert clients[owner].submit((if index == 0: 1'u32 else: 8'u32),
        GameSubmission(action: ReplayAction(heroId: hero, kind: ActionDraft,
          first: classId)).encodeSubmission())
      exchange()
    if not paused and expected > 0 and room.tick + 1 == expected:
      relay.disconnect(2)
      clients[1].lost()
      clients[1].opened()
      exchange()
      doAssert clients[1].error.len == 0
      reconnected = true
      clients[0].send(RoomMessage(kind: PauseMatch, match: room.match, flag: true))
      exchange()
      let frozen = room.tick
      for i in 0 ..< 5: step()
      doAssert room.tick == frozen and notices == 0
      clients[0].send(RoomMessage(kind: PauseMatch, match: room.match, flag: false))
      exchange()
      paused = true
    step()
    if limit > 180 * TickRate and notices > 0 and room.tick > expected + 2: break
    if limit <= 180 * TickRate and room.tick > 2 * DraftPickTicks.uint32 + PreparationTicks.uint32 + 2: break
  if limit <= 180 * TickRate:
    doAssert notices == 0 and sessions[0].humanChat.len == 0
  else:
    doAssert reconnected
    doAssert notices == 1 and sessions[0].humanChat.len == 1
    doAssert sessions[0].humanChat[0].system
    doAssert sessions[0].humanChat[0].text == "3 minutes remain"
    doAssert sessions[0].humanChat[0].tick == expected
    # A real late spectator joins and obtains the server-recorded Catchup bytes.
    clients.add RoomClient(identity: gotaIdentity(), name: "Late spectator")
    clients[2].opened()
    exchange()
    clients[2].send(RoomMessage(kind: JoinRoom, room: room.id))
    exchange()
    let late = prepareNetworkMatch(clients[2], [])
    late.start(clients[2].events[0])
    exchange()
    while clients[2].applied < room.tick:
      var packet: RoomMessage
      doAssert clients[2].takeTick(packet), "Catchup must deliver the next history batch"
      late.applyPacket(packet, localPlayback = true)
      clients[2].appliedTick(packet.tick)
      exchange()
    doAssert late.humanChat == sessions[0].humanChat
    doAssert late.game.networkHash() == sessions[0].game.networkHash()
    # Fresh reconnect/packet replay consumes the recorded server command.
    let watcher = prepareNetworkMatch(clients[1], [])
    watcher.started = true
    watcher.match = room.match
    watcher.spectator = true
    for packet in captured: watcher.applyPacket(packet, localPlayback = true)
    doAssert watcher.humanChat == sessions[0].humanChat
    doAssert watcher.game.networkHash() == sessions[0].game.networkHash()
    watcher.game.world.restore(beforeNotice)
    watcher.applyPacket(captured[int(expected) - 1], localPlayback = true)
    doAssert watcher.humanChat.len == 1, "Seek may not duplicate recorded notice"
  echo "Server notice real Relay.advance: limit=", limit, " early=", pickEarly,
    " mode=", mode, " seed=", seed, " notices=", notices, " tick=", expected

run(182 * TickRate, false)
run(182 * TickRate, true)
run(180 * TickRate, true)
run(182 * TickRate, false, TeamDraft, 7)
run(182 * TickRate, false, OpenDraft, 2026)
run(182 * TickRate, true, OpenDraft, 7)
