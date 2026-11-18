import polyworld/[rooms, relays]
import relayfixtures

echo "Testing displayed readiness survives unrelated membership edits"
for operation in [JoinRoom, LeaveRoom, KickParticipant]:
  let relay = lobby()
  let room = relay.rooms[0]
  if operation == JoinRoom:
    relay.send(3, RoomMessage(kind: LeaveRoom))
  relay.send(1, RoomMessage(kind: ReadyStatus, flag: true))
  let revision = room.revision
  case operation
  of JoinRoom:
    relay.send(3, RoomMessage(kind: JoinRoom, room: room.id))
  of LeaveRoom:
    relay.send(3, RoomMessage(kind: LeaveRoom))
  else:
    relay.send(1, RoomMessage(kind: KickParticipant, participant: 3))
  doAssert room.revision == revision
  doAssert relay.guest(1).ready
  relay.start()
  doAssert room.phase == Playing

echo "Controller departure does not create a preparation gate"
for kick in [false, true]:
  let relay = lobby()
  let room = relay.rooms[0]
  relay.send(1, RoomMessage(kind: ReadyStatus, flag: true))
  let stale = relay.startMessage(room)
  if kick:
    relay.send(1, RoomMessage(kind: KickParticipant, participant: 2))
  else:
    relay.send(2, RoomMessage(kind: LeaveRoom))
  doAssert room.seats[1] == Seat()
  doAssert relay.guest(1).ready
  relay.expectUnchanged(1, stale)
  relay.send(3, RoomMessage(kind: ClaimSeat, seat: 1,
    seatKind: HumanSeat, name: "Replacement"))
  doAssert not relay.guest(3).ready
  relay.start()
  doAssert room.phase == Playing

echo "Simulation disagreement after startup still stops the match"
block:
  let relay = lobby()
  let room = relay.rooms[0]
  relay.start()
  relay.send(1, RoomMessage(kind: ReportHash, match: room.match,
    tick: 0, hash: 41))
  doAssert room.phase == Playing
  relay.send(2, RoomMessage(kind: ReportHash, match: room.match,
    tick: 0, hash: 42))
  doAssert room.phase == Desynced
