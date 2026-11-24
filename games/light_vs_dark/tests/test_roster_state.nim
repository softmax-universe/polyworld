import std/unittest
import jsony, polyworld/[rooms, roomclients, relays]
import ../[presets, rosterstate]

proc exchange(relay: Relay, client: RoomClient) =
  ## Delivers the fixture's real relay messages until both queues settle.
  for iteration in 0 ..< 20:
    let requests = client.outgoing
    client.outgoing = @[]
    for bytes in requests:
      relay.process(1, bytes, 0)
    let replies = relay.outgoing
    relay.outgoing = @[]
    for reply in replies:
      if reply.bytes.len > 0: client.accept(reply.bytes)
    if client.outgoing.len == 0: return
  doAssert false, "exchange did not settle"

proc lobby(): tuple[relay: Relay, client: RoomClient, config: LvdConfig] =
  ## Creates a private lobby owned by one connected participant.
  result.relay = Relay()
  result.client = RoomClient(name: "Host",
    identity: GameIdentity(game: "lvd-roster-test", gameplay: 1, protocol: 1))
  result.client.opened()
  exchange(result.relay, result.client)
  result.config = defaultConfig(2)
  result.client.send(RoomMessage(kind: CreateRoom, name: "Roster",
    number: 2, tickRate: 24, flag: false, payload: result.config.toJson()))
  exchange(result.relay, result.client)

suite "LvD roster state":
  test "only an in-flight relay update blocks assignments":
    let saving = RosterState(pendingPayload: "in flight")
    check not saving.assignmentsEnabled(true)
    check saving.assignmentsEnabled(false)
    check RosterState(dirty: true).assignmentsEnabled(true)

  test "add player sends exactly one immediate resize":
    var (relay, client, config) = lobby()
    var state: RosterState
    state.resizeRoster(config, client, 3)
    check client.outgoing.len == 1
    check state.pending
    check not state.dirty
    exchange(relay, client)
    check client.error == ""
    check client.snapshot.seats.len == 3
    check parseConfig(client.snapshot.payload).playerCount == 3

  test "resize acknowledgement preserves newer map settings":
    var (relay, client, config) = lobby()
    var state = RosterState(dirty: true)
    config.seed = 88
    state.resizeRoster(config, client, 3)
    let published = state.pendingPayload
    check parseConfig(published).seed == 2026
    check config.seed == 88
    state.acceptConfig(config, published)
    check not state.pending
    check state.dirty
    check config.seed == 88
    check config.playerCount == 3
    check state.assignmentsEnabled(true)

  test "roster-only rejection restores count without losing other settings":
    var (relay, client, config) = lobby()
    var state = RosterState(dirty: true)
    config.seed = 88
    state.resizeRoster(config, client, 3)
    state.rejectConfig(config, client.snapshot.payload)
    check not state.pending
    check state.dirty
    check config.playerCount == 2
    check config.seed == 88
    check state.assignmentsEnabled(true)

  test "pending resize cannot be sent twice":
    var (relay, client, config) = lobby()
    var state: RosterState
    state.resizeRoster(config, client, 3)
    state.resizeRoster(config, client, 4)
    check client.outgoing.len == 1
    check config.playerCount == 3
    check parseConfig(client.outgoing[0].decode().payload).playerCount == 3

  test "matching acknowledgement clears pending settings":
    var config = defaultConfig(2)
    config.seed = 88
    var state = RosterState(dirty: true, pendingPayload: config.toJson())
    state.acceptConfig(config, config.toJson())
    check not state.pending
    check not state.dirty

  test "local resize adds no relay pending state":
    var config = defaultConfig(2)
    var state: RosterState
    state.resizeRoster(config, nil, 3)
    check config.playerCount == 3
    check config.players.len == 3
    check not state.pending
    check not state.dirty

  test "invalid resize is atomic":
    var (relay, client, config) = lobby()
    var state: RosterState
    expect LvdError:
      state.resizeRoster(config, client, MaxSeats + 1)
    check config.playerCount == 2
    check client.outgoing.len == 0
    check not state.pending

suite "LvD immediate settings synchronization":
  test "a setting publishes immediately and unchanged frames send nothing":
    var (relay, client, config) = lobby()
    var
      state: RosterState
      name = client.snapshot.name
    check not state.publishSettings(config, client, name)
    config.seed = 88
    check state.publishSettings(config, client, name)
    check state.pending and not state.dirty
    require client.outgoing.len == 1
    let packet = decode(client.outgoing[0])
    check packet.kind == ConfigureRoom
    check not packet.flag
    check parseConfig(packet.payload).seed == 88
    for frame in 0 ..< 10:
      check not state.publishSettings(config, client, name)
    check client.outgoing.len == 1
    exchange(relay, client)
    check client.error == ""
    check state.acceptSettings(config, name, client.snapshot)
    check not state.pending and not state.dirty
    for frame in 0 ..< 10:
      check not state.publishSettings(config, client, name)
    check client.outgoing.len == 0

  test "rapid edits coalesce behind one update and survive its acknowledgement":
    var (relay, client, config) = lobby()
    var
      state: RosterState
      name = client.snapshot.name
    config.seed = 88
    check state.publishSettings(config, client, name)
    config.seed = 99
    config.maxTicks += 24
    name = "Newest room"
    check not state.publishSettings(config, client, name)
    check state.pending and state.dirty
    check client.outgoing.len == 1
    let stale = client.snapshot
    check not state.acceptSettings(config, name, stale)
    check config.seed == 99 and name == "Newest room"
    exchange(relay, client)
    check parseConfig(client.snapshot.payload).seed == 88
    check state.acceptSettings(config, name, client.snapshot)
    check not state.pending and state.dirty
    check config.seed == 99 and name == "Newest room"
    check state.publishSettings(config, client, name)
    check client.outgoing.len == 1
    exchange(relay, client)
    check state.acceptSettings(config, name, client.snapshot)
    check parseConfig(client.snapshot.payload) == config
    check client.snapshot.name == "Newest room"
    check not state.pending and not state.dirty

  test "name-only updates preserve payload and require the matching name reply":
    var (relay, client, config) = lobby()
    var
      state: RosterState
      name = "First room name"
    let original = client.snapshot
    check state.publishSettings(config, client, name)
    require client.outgoing.len == 1
    let packet = decode(client.outgoing[0])
    check packet.kind == ResizeRoom
    check packet.payload == original.payload
    check packet.number == original.seats.len.uint32
    check packet.tickRate == original.tickRate and packet.flag == original.flag
    name = "Newer room name"
    check not state.acceptSettings(config, name, original)
    check state.pending and name == "Newer room name"
    exchange(relay, client)
    check state.acceptSettings(config, name, client.snapshot)
    check state.dirty and name == "Newer room name"
    check state.publishSettings(config, client, name)
    exchange(relay, client)
    check state.acceptSettings(config, name, client.snapshot)
    check client.snapshot.name == name
    check client.snapshot.payload == original.payload
    check not state.pending and not state.dirty

  test "latest setting changes follow an acknowledged roster resize":
    var (relay, client, config) = lobby()
    var
      state: RosterState
      name = client.snapshot.name
    state.resizeRoster(config, client, 3)
    config.seed = 77
    config.assignTeam(2, 0)
    check not state.publishSettings(config, client, name)
    exchange(relay, client)
    check state.acceptSettings(config, name, client.snapshot)
    check config.playerCount == 3 and config.seed == 77
    check state.publishSettings(config, client, name)
    exchange(relay, client)
    check state.acceptSettings(config, name, client.snapshot)
    check client.snapshot.seats.len == 3
    check parseConfig(client.snapshot.payload) == config

  test "rejection restores published values without an automatic retry loop":
    var (relay, client, config) = lobby()
    var
      state: RosterState
      name = "Attempted name"
    let published = config
    config.seed = 88
    check state.publishSettings(config, client, name)
    # Inject relay rejection without changing the authoritative room.
    var request = decode(client.outgoing[0])
    request.tickRate = 0
    client.outgoing[0] = request.encode()
    exchange(relay, client)
    check client.error.len > 0
    state.rejectSettings(config, name, client.snapshot)
    check config == published and name == client.snapshot.name
    check not state.pending and not state.dirty
    for frame in 0 ..< 10:
      check not state.publishSettings(config, client, name)
    check client.outgoing.len == 0
    config.seed = 99
    check state.publishSettings(config, client, name)
    check client.error == ""

  test "only a connected lobby host can publish validated changes":
    var (relay, client, config) = lobby()
    var state: RosterState
    config.seed = 88
    let host = client.participant
    client.participant = host + 1
    check not state.publishSettings(config, client, "Guest edit")
    client.participant = host
    client.snapshot.phase = Playing
    check not state.publishSettings(config, client, "Running edit")
    client.snapshot.phase = Lobby
    client.connected = false
    check not state.publishSettings(config, client, "Disconnected")
    client.connected = true
    client.welcomed = false
    check not state.publishSettings(config, client, "Unwelcomed")
    client.welcomed = true
    check not state.publishSettings(config, nil, "Local")
    check not state.publishSettings(config, client, "")
    check not state.publishSettings(config, client, "bad\nname")
    check client.error.len > 0
    check client.outgoing.len == 0 and not state.pending
    config.playerCount = MaxSeats + 1
    expect LvdError:
      discard state.publishSettings(config, client, "Invalid config")
    check client.outgoing.len == 0 and not state.pending
