import polyworld/[rooms, relays]
import relayfixtures

echo "Testing sparse rosters and uniform slot permissions"
for game in ["sandbox", "turn-based-game", "future-game"]:
  let relay = lobby(game, slots = 8)
  let room = relay.rooms[0]
  relay.send(2, RoomMessage(kind: ClaimSeat, seat: 5,
    seatKind: BotSeat, name: "Human"))
  relay.send(2, RoomMessage(kind: ClaimSeat, seat: 7,
    seatKind: BotSeat, name: "Second policy"))
  doAssert room.seats[5].kind == BotSeat
  relay.expectUnchanged(3, RoomMessage(kind: ReleaseSeat, seat: 5))
  relay.expectUnchanged(3, RoomMessage(kind: ClaimSeat, seat: 5,
    seatKind: HumanSeat, name: "Steal"))
  relay.expectUnchanged(2, RoomMessage(kind: ClaimSeat, seat: 6,
    participant: 3, seatKind: BotSeat, name: "Foreign policy"))
  relay.send(2, RoomMessage(kind: ReleaseSeat, seat: 7))
  doAssert room.seats[7] == Seat()
  relay.start()
  doAssert room.phase == Playing
  doAssert room.seats[2] == Seat() and room.seats[4] == Seat()
  relay.send(1, RoomMessage(kind: ReleaseSeat, seat: 5))
  relay.send(1, RoomMessage(kind: ReleaseSeat, seat: 1))
  doAssert room.seats[5] == Seat() and room.seats[1] == Seat()
  doAssert relay.guest(2).room == room.id
  relay.send(1, RoomMessage(kind: ClaimSeat, seat: 0,
    participant: 3, seatKind: HumanSeat, name: "Assigned human"))
  doAssert room.seats[0].owner == 3
  relay.send(3, RoomMessage(kind: ReleaseSeat, seat: 0))
  relay.send(3, RoomMessage(kind: ClaimSeat, seat: 4,
    seatKind: HumanSeat, name: "My own slot"))
  doAssert room.seats[4].owner == 3
  relay.send(1, RoomMessage(kind: ClaimSeat, seat: 4,
    participant: 2, seatKind: BotSeat, name: "Replacement policy"))
  doAssert room.seats[4] == Seat(owner: 2, kind: BotSeat,
    name: "Replacement policy")
  relay.expectUnchanged(3, RoomMessage(kind: ReleaseSeat, seat: 4))

echo "Host moderation applies while paused, ended and desynced"
for phase in [Waiting, Ended, Desynced]:
  let relay = lobby()
  let room = relay.rooms[0]
  relay.start()
  room.phase = phase
  relay.send(1, RoomMessage(kind: ReleaseSeat, seat: 1))
  relay.send(1, RoomMessage(kind: ClaimSeat, seat: 1,
    participant: 3, seatKind: BotSeat, name: "Replacement"))
  doAssert room.seats[1].owner == 3
  relay.send(1, RoomMessage(kind: KickParticipant, participant: 3))
  doAssert room.seats[1] == Seat()
  doAssert relay.guest(3).room == ""
