import polyworld/[rooms, relays]
import relayfixtures

echo "Testing game configuration remains opaque and byte-preserving"
for payload in [
    "{}",
    "[1,{\"arbitrary\":true},null]",
    "{\"players\":\"not a count\",\"teamCount\":-9}",
    "{\"players\":[{\"unexpected\":17}],\"playerCount\":200}",
    "{\"diplomacySettings\":{\"teams\":\"game-defined\"}}",
    "{ \"seed\": 1, \"maxTicks\": 999999999999999 }"
]:
  let relay = lobby(payload = payload)
  let room = relay.rooms[0]
  doAssert relay.state(room).payload == payload
  relay.send(1, RoomMessage(kind: ResizeRoom, name: room.name,
    number: 6, tickRate: room.tickRate, payload: payload))
  doAssert room.seats.len == 6
  doAssert room.payload == payload
  relay.start()
  for message in relay.begins():
    doAssert message.payload == payload
    doAssert message.hash == setupHash(message)

echo "Setup hashing includes game bytes, slot owners and controller kinds"
block:
  let relay = lobby()
  let original = relay.state(relay.rooms[0])
  let expected = setupHash(original)
  var changed = decode(original.encode())
  changed.payload.add " "
  doAssert setupHash(changed) != expected
  changed = decode(original.encode())
  changed.seats[1].owner = 1
  doAssert setupHash(changed) != expected
  changed = decode(original.encode())
  changed.seats[1].kind = BotSeat
  doAssert setupHash(changed) != expected
  changed = decode(original.encode())
  changed.participants[1].name = "Renamed participant"
  doAssert setupHash(changed) != expected
  changed = decode(original.encode())
  changed.participants[2].name = "Renamed spectator"
  changed.participants[0].ready = true
  changed.participants[1].connected = false
  doAssert setupHash(changed) == expected

echo "Configuration changes never receive a game-specific exception"
for game in ["new-game", "another-game"]:
  let relay = lobby(game)
  let room = relay.rooms[0]
  let original = relay.startMessage(room)
  let payload = "{\"players\":5,\"teams\":[4,3,2,1,0]}"
  relay.send(1, RoomMessage(kind: ResizeRoom, name: room.name,
    number: 5, tickRate: room.tickRate, payload: payload))
  relay.expectUnchanged(1, original)
  relay.start()
  doAssert room.phase == Playing
  doAssert relay.begins()[0].payload == payload
