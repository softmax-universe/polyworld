## Binary relay fixtures for startup, ownership and client game-state checks.
import jsony
import polyworld/[rooms, roomclients, relays]
import ../[multiplayer, presets, content]
export rooms, roomclients, relays, multiplayer, presets, content

type NetworkFixture* = ref object
  relay*: Relay
  clients*: array[2, RoomClient]
  sessions*: array[2, NetworkMatch]
  now*: float64

proc exchange*(fixture: NetworkFixture) =
  ## Delivers real encoded packets without running game simulation implicitly.
  for pass in 0 ..< 40:
    var sent = false
    for i, client in fixture.clients:
      var outgoing: seq[string]
      swap(outgoing, client.outgoing)
      for packet in outgoing:
        fixture.relay.process(i + 1, packet, fixture.now)
        sent = true
    var outgoing: seq[Outgoing]
    swap(outgoing, fixture.relay.outgoing)
    for delivery in outgoing:
      if delivery.bytes.len > 0:
        fixture.clients[delivery.connection - 1].accept(delivery.bytes)
        sent = true
    if not sent: return
  doAssert false, "Relay fixture exchange did not settle"

proc newFixture*(seats = 3): NetworkFixture =
  ## Creates two human controllers and leaves the remaining slots unoccupied.
  result = NetworkFixture(relay: Relay())
  for i in 0 ..< 2:
    result.clients[i] = RoomClient(identity: lvdIdentity(), name: "Player " & $i)
    result.clients[i].opened()
  result.exchange()
  let config = defaultConfig(seats)
  result.clients[0].send(RoomMessage(kind: CreateRoom, name: "Generic LvD",
    number: seats.uint32, tickRate: TickRate.uint32, payload: config.toJson()))
  result.exchange()
  result.clients[1].send(RoomMessage(kind: JoinRoom,
    room: result.clients[0].snapshot.room))
  result.exchange()
  result.clients[0].claimHumanSeat(0)
  result.clients[1].claimHumanSeat(1)
  result.exchange()

proc begin*(fixture: NetworkFixture) =
  ## Starts through the host's setup envelope; peers build only after BeginMatch.
  fixture.sessions[0] = fixture.clients[0].requestStart([])
  fixture.exchange()
  for i, client in fixture.clients:
    if fixture.sessions[i] == nil:
      fixture.sessions[i] = prepareNetworkMatch(client, [])
    doAssert client.events.len == 1
    fixture.sessions[i].start(client.events[0])
    client.events.setLen(0)
  fixture.exchange()
