import polyworld/[rooms, relays]
import relayfixtures

echo "Testing immediate host starts and match lifetimes"
block:
  let relay = lobby()
  let room = relay.rooms[0]
  let request = relay.startMessage(room)
  relay.send(1, request)
  doAssert room.phase == Playing and room.match == 1
  doAssert relay.begins().len == 3
  relay.expectUnchanged(1, request)
  doAssert room.match == 1
  doAssert relay.begins().len == 3

echo "Host starts while another controller is disconnected"
block:
  let relay = lobby()
  let room = relay.rooms[0]
  let peer = relay.guest(2)
  relay.disconnect(2)
  relay.start()
  doAssert room.phase == Playing
  let first = relay.begins()[0]
  relay.send(4, RoomMessage(kind: Hello, name: peer.name,
    identity: peer.identity, token: peer.token))
  let reconnected = relay.begins()[^1]
  doAssert reconnected.match == first.match
  doAssert reconnected.revision == first.revision
  doAssert reconnected.hash == first.hash
  doAssert reconnected.seats == first.seats
  doAssert reconnected.payload == first.payload
  doAssert room.match == 1

echo "Only the current owner can start after ownership succession"
block:
  let relay = lobby()
  let room = relay.rooms[0]
  relay.send(1, RoomMessage(kind: LeaveRoom))
  doAssert room.owner == 2
  relay.expectUnchanged(3, relay.startMessage(room))
  relay.start(2)
  doAssert room.phase == Playing

echo "Stale revision and changed setup hash cannot authorize a start"
for operation in [ConfigureRoom, ResizeRoom]:
  let relay = lobby()
  let room = relay.rooms[0]
  let stale = relay.startMessage(room)
  relay.send(1, RoomMessage(kind: operation, name: room.name,
    number: uint32(room.seats.len), tickRate: room.tickRate,
    payload: "{\"seed\":18}"))
  relay.expectUnchanged(1, stale)
  var wrongHash = relay.startMessage(room)
  wrongHash.hash = wrongHash.hash xor 1
  relay.expectUnchanged(1, wrongHash)
  relay.start()
  doAssert room.phase == Playing

echo "Returning to the lobby needs a new explicit start"
block:
  let relay = lobby()
  let room = relay.rooms[0]
  relay.start()
  relay.send(1, RoomMessage(kind: AbortMatch, match: room.match, detail: "Done"))
  relay.send(1, RoomMessage(kind: ReturnLobby))
  doAssert room.phase == Lobby and room.match == 1
  relay.send(1, RoomMessage(kind: ReadyStatus, flag: true))
  doAssert room.phase == Lobby
  relay.start()
  doAssert room.phase == Playing and room.match == 2
