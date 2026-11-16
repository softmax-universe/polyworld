import std/unittest
import jsony
import polyworld/[rooms, roomclients, relays]
import ../[multiplayer, lobbyreadiness, presets, humancommunication, sim, content]

suite "LvD clock adapter and authenticated feed":
  test "automatic preparation opts into protocol four and agreed max ticks":
    check lvdIdentity().protocol == 4
    let c = RoomClient(identity: lvdIdentity(), participant: 1,
      connected: true, welcomed: true,
      snapshot: RoomMessage(kind: RoomState, room: "clock", phase: Lobby,
        revision: 7, tickRate: uint32(TickRate), payload: defaultConfig().toJson(),
        participants: @[Participant(id: 1, name: "One"), Participant(id: 2, name: "Two")],
        seats: @[Seat(owner: 1, name: "Human"), Seat(owner: 2, name: "Human")]))
    var refresh: ReadyRefresh
    var prepared: NetworkMatch
    var revision: uint32
    check refresh.refreshRetainedReady(c, [], prepared, revision)
    check c.outgoing.len == 1
    let proof = decode(c.outgoing[0])
    check proof.kind == PreparedDuration
    check proof.durationTicks == uint32(prepared.game.maximumTicks)
    check proof.hash == prepared.game.networkHash()
  test "server notice uses dedicated attribution and waits for local application":
    when declared(observeServerNotices):
      let c = RoomClient()
      c.accept(RoomMessage(kind: BeginMatch, match: 1).encode)
      let session = NetworkMatch(client: c)
      var state: HumanCommunication
      c.accept(RoomMessage(kind: ServerNotice, match: 1, tick: 4,
        noticeId: 1, noticeCode: ThreeMinutesRemain).encode)
      state.observeServerNotices(session)
      check state.feed.len == 0
      for tick in 1'u32 .. 4: c.appliedTick(tick)
      state.observeServerNotices(session)
      check state.feed.len == 1
      check state.feed[0].name == "Server"
      check state.feed[0].text == "3 minutes remain"
      check state.feed[0].serverNotice
      check state.feed[0].player == -1
      state.observeServerNotices(session)
      check state.feed.len == 1
    else:
      check false

suite "real LvD notice across lagged human and spectator":
  test "actual applied simulations display the same server notice at their own trigger":
    let relay = Relay()
    var clients = [RoomClient(identity: lvdIdentity(), name: "Host"),
      RoomClient(identity: lvdIdentity(), name: "Peer"),
      RoomClient(identity: lvdIdentity(), name: "Spectator")]
    var now = 0.0
    proc exchange() =
      for attempt in 0 ..< 40:
        var sent = false
        for i, c in clients:
          let outgoing = c.outgoing
          c.outgoing = @[]
          for bytes in outgoing:
            relay.process(i+1, bytes, now)
            sent = true
        let outgoing = relay.outgoing
        relay.outgoing = @[]
        for output in outgoing:
          if output.bytes.len > 0:
            clients[output.connection-1].accept(output.bytes)
            sent = true
        for c in clients: doAssert c.error.len == 0, c.error
        if not sent: return
      doAssert false, "Exchange did not settle"
    for c in clients: c.opened()
    exchange()
    var config = defaultConfig()
    config.maxTicks = TickRate * 180 + 4
    config.mapSettings = MapSettings(layout: RandomLayout, size: 90, expansions: 0)
    clients[0].send(RoomMessage(kind: CreateRoom, name: "Notice", number: 2,
      tickRate: uint32(TickRate), payload: config.toJson()))
    exchange()
    for i in 1 .. 2:
      clients[i].send(RoomMessage(kind: JoinRoom, room: clients[0].snapshot.room))
    exchange()
    for i in 0 .. 1: clients[i].claimHumanSeat(i)
    exchange()
    var sessions: array[3, NetworkMatch]
    for i, c in clients:
      sessions[i] = prepareNetworkMatch(c, [])
      if i < 2:
        c.send(RoomMessage(kind: PreparedDuration, revision: c.snapshot.revision,
          hash: sessions[i].game.networkHash(), durationTicks: uint32(config.maxTicks)))
    exchange()
    clients[0].send(RoomMessage(kind: StartMatch))
    exchange()
    for i, c in clients: sessions[i].start(c.events[0])
    exchange()
    var feeds: array[3, HumanCommunication]
    for tick in 1 .. 4:
      now += 1.0 / float64(TickRate)
      relay.advance(now)
      exchange()
      check sessions[0].advance()
      exchange()
    relay.advance(now) # AppliedTick batch is now complete.
    exchange()
    for i in 0 .. 2: feeds[i].observeServerNotices(sessions[i])
    check feeds[0].feed.len == 1
    check feeds[1].feed.len == 0 and feeds[2].feed.len == 0
    # Pending notice survives authenticated reconnect before local catch-up.
    relay.disconnect(2)
    clients[1].lost()
    clients[1].opened()
    exchange()
    for i in 1 .. 2:
      for tick in 1 .. 4:
        check sessions[i].advance()
        feeds[i].observeServerNotices(sessions[i])
        check feeds[i].feed.len == (if tick < 4: 0 else: 1)
      check feeds[i].feed == feeds[0].feed
      check sessions[i].game.networkHash() == sessions[0].game.networkHash()
    exchange()
    relay.disconnect(2)
    clients[1].lost()
    clients[1].opened()
    exchange()
    feeds[1].observeServerNotices(sessions[1])
    check feeds[1].feed.len == 1
