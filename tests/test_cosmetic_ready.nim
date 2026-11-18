import polyworld/[rooms, relays]
import relayfixtures

echo "Testing readiness is display-only for every game identity"
for game in ["unknown-game", "chess", "racing"]:
  for protocol in [0'u32, 1'u32, 4'u32, 972'u32]:
    for flags in [[false, false], [false, true], [true, false], [true, true]]:
      let relay = lobby(game, protocol)
      let room = relay.rooms[0]
      let initial = setupHash(relay.state(room))
      for connection in 1 .. 2:
        relay.send(connection, RoomMessage(kind: ReadyStatus,
          flag: flags[connection - 1]))
      let snapshot = relay.state(room)
      doAssert snapshot.participants[0].ready == flags[0]
      doAssert snapshot.participants[1].ready == flags[1]
      doAssert setupHash(snapshot) == initial
      doAssert room.phase == Lobby
      relay.start()
      doAssert room.phase == Playing
      doAssert relay.begins().len == 3
      for message in relay.begins():
        doAssert message.hash == initial
      doAssert relay.guest(1).ready == flags[0]
      doAssert relay.guest(2).ready == flags[1]

echo "Cosmetic readiness does not authorize another participant"
block:
  let relay = lobby()
  let room = relay.rooms[0]
  relay.send(2, RoomMessage(kind: ReadyStatus, flag: true))
  relay.expectUnchanged(2, relay.startMessage(room))
  doAssert room.phase == Lobby
  relay.start()
  doAssert room.phase == Playing
