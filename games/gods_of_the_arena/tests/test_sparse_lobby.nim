import jsony
import polyworld/[rooms, roomclients, menus]
import ../[multiplayer, presets]

var policies: array[10, LocalPolicy]
let seats = localActiveSeats(policies, 3)
doAssert seats == @[3], "Default local slots are empty, preserving assigned human"
policies[8] = LocalPolicy(name: "Bot", bytes: "END")
doAssert localActiveSeats(policies, 3) == @[3, 8]
doAssert localActiveSeats(policies, -1) == @[8]
var snapshot = RoomMessage(revision: 2, phase: Lobby, participant: 1,
  tickRate: 24, payload: parseConfig("{}").toJson(), seats: newSeq[Seat](10),
  participants: @[Participant(id: 1, name: "Host", connected: true),
    Participant(id: 2, name: "Guest", connected: true)])
snapshot.seats[3] = Seat(owner: 1, kind: HumanSeat, name: "Human")
snapshot.seats[8] = Seat(owner: 2, kind: HumanSeat, name: "Human")
let client = RoomClient(participant: 1, snapshot: snapshot)
let session = client.requestStart([])
doAssert session != nil
let start = decode(client.outgoing[0])
doAssert start.kind == StartMatch and start.hash == setupHash(snapshot)
for participant in client.snapshot.participants:
  doAssert not participant.ready, "Start does not require cosmetic consent"
echo "Sparse lobby startup and local defaults passed"
