## Join-time seating through the real relay, without a window or game renderer.
import polyworld/[rooms, relays, roomclients]
import ../[joiningseats, multiplayer]

type Fixture = ref object
  relay: Relay
  clients: seq[RoomClient]
  joining: seq[JoiningSeat]

proc exchange(f: Fixture) =
  ## Deliver queued requests and replies until the in-process relay is idle.
  for iteration in 0 ..< 30:
    var sent = false
    for i, client in f.clients:
      if not client.connected: continue
      let requests = client.outgoing
      client.outgoing = @[]
      for bytes in requests:
        f.relay.process(i + 1, bytes, 0)
        sent = true
    let replies = f.relay.outgoing
    f.relay.outgoing = @[]
    for reply in replies:
      let client = f.clients[reply.connection - 1]
      if not client.connected: continue
      if reply.bytes.len > 0:
        client.accept(reply.bytes)
        sent = true
      if reply.close: client.lost()
    if not sent: return
  doAssert false, "Relay exchange did not settle"

proc lobby(seats = 4, participants = 3): Fixture =
  ## Connect participants and create an empty lobby without auto-claiming yet.
  result = Fixture(relay: Relay())
  result.joining = newSeq[JoiningSeat](participants)
  for i in 0 ..< participants:
    let client = RoomClient(identity: lvdIdentity(), name: "Player " & $i)
    result.clients.add client
    client.opened()
    result.exchange()
  result.clients[0].send(RoomMessage(kind: CreateRoom, name: "Joining seats",
    number: uint32(seats), tickRate: 24))
  result.exchange()

proc join(f: Fixture, index: int) =
  ## Join the host's room and receive its authoritative roster.
  f.clients[index].send(RoomMessage(kind: JoinRoom,
    room: f.clients[0].snapshot.room))
  f.exchange()

proc claim(f: Fixture, index: int): tuple[updated: bool, seat: int] =
  ## Run the same per-frame joining helper used by the frontend.
  f.joining[index].claimJoiningSeat(f.clients[index])

proc human(f: Fixture, index: int): int =
  ## Read the participant's confirmed human seat from its relay snapshot.
  f.clients[index].snapshot.humanSeatFor(f.clients[index].participant)

proc confirm(f: Fixture, index: int) =
  ## Acknowledge a successful claim and verify that it sends no duplicate.
  f.exchange()
  discard f.claim(index)
  doAssert f.clients[index].outgoing.len == 0
  doAssert f.clients[index].error == ""

proc reconnect(f: Fixture, index: int) =
  ## Drop unsent messages and reconnect using the existing participant token.
  f.relay.disconnect(index + 1)
  f.clients[index].lost()
  discard f.claim(index)
  f.exchange()
  f.clients[index].opened()
  f.exchange()

block hostAndGuest:
  let f = lobby()
  doAssert f.human(0) == -1
  doAssert f.claim(0) == (true, 0)
  doAssert f.clients[0].outgoing.len == 1
  for frame in 0 ..< 4:
    discard f.claim(0)
  doAssert f.clients[0].outgoing.len == 1, "Only one claim may be in flight"
  f.confirm(0)
  doAssert f.human(0) == 0
  f.join(1)
  doAssert f.claim(1).seat == 1
  f.confirm(1)
  doAssert f.human(1) == 1
  for frame in 0 ..< 4:
    doAssert f.claim(0) == (false, -1)
    doAssert f.claim(1) == (false, -1)
  doAssert f.clients[0].outgoing.len == 0
  doAssert f.clients[1].outgoing.len == 0

block unidentifiedClientWaits:
  let f = lobby()
  let participant = f.clients[0].participant
  f.clients[0].participant = 0
  doAssert f.claim(0) == (false, -1)
  doAssert f.clients[0].outgoing.len == 0
  f.clients[0].participant = participant
  doAssert f.claim(0) == (true, 0)
  f.confirm(0)
  doAssert f.human(0) == 0

block simultaneousJoins:
  let f = lobby()
  discard f.claim(0)
  f.confirm(0)
  f.join(1)
  f.join(2)
  # Both guests choose from the same authoritative empty-seat snapshot.
  doAssert f.claim(1).seat == 1
  doAssert f.claim(2).seat == 1
  f.exchange()
  doAssert f.human(1) == 1
  doAssert f.human(2) == -1
  doAssert f.clients[2].error == "Seat belongs to another participant"
  discard f.claim(1)
  doAssert f.claim(2).seat == 2
  f.confirm(2)
  doAssert f.human(2) == 2
  doAssert f.clients[0].snapshot.seats[0].owner == f.clients[0].participant
  doAssert f.clients[0].snapshot.seats[1].owner == f.clients[1].participant
  doAssert f.clients[0].snapshot.seats[2].owner == f.clients[2].participant

block winningClaimIsReleasedBeforeRepliesArrive:
  let f = lobby()
  discard f.claim(0)
  f.confirm(0)
  f.join(1)
  f.join(2)
  doAssert f.claim(1).seat == 1
  doAssert f.claim(2).seat == 1
  # Process the competing claims, then release the winning seat before either
  # client receives the accumulated snapshots and rejection.
  for index in [1, 2]:
    let requests = f.clients[index].outgoing
    f.clients[index].outgoing = @[]
    for bytes in requests:
      f.relay.process(index + 1, bytes, 0)
  f.clients[1].send(RoomMessage(kind: ReleaseSeat, seat: 1))
  f.exchange()
  doAssert f.clients[2].snapshot.seats[1].owner == 0
  doAssert f.clients[2].error == "Seat belongs to another participant"
  doAssert f.claim(2).seat == 1
  f.confirm(2)
  doAssert f.human(2) == 1

block concurrentJoinTakesLastSeat:
  let f = lobby(seats = 2)
  discard f.claim(0)
  f.confirm(0)
  f.join(1)
  f.join(2)
  discard f.claim(1)
  discard f.claim(2)
  f.exchange()
  doAssert f.claim(2) == (true, -1), "Clear the optimistic seat after losing it"
  doAssert f.clients[2].error == ""
  doAssert f.clients[2].outgoing.len == 0
  f.clients[1].send(RoomMessage(kind: ReleaseSeat, seat: 1))
  f.exchange()
  doAssert f.claim(2) == (false, -1)
  doAssert f.human(2) == -1
  doAssert f.clients[2].outgoing.len == 0

block rosterShrinkInvalidatesPendingSeat:
  let f = lobby(seats = 3)
  discard f.claim(0)
  f.confirm(0)
  f.clients[0].send(RoomMessage(kind: ClaimSeat, seat: 1, name: "Host bot"))
  f.exchange()
  f.join(1)
  doAssert f.claim(1).seat == 2
  f.clients[0].send(RoomMessage(kind: ResizeRoom, name: "Joining seats",
    number: 2, tickRate: 24))
  f.clients[0].send(RoomMessage(kind: ReleaseSeat, seat: 1))
  f.exchange()
  doAssert f.clients[1].snapshot.seats.len == 2
  doAssert f.clients[1].error == "Seats can only change in the lobby"
  doAssert f.claim(1).seat == 1
  f.confirm(1)
  doAssert f.human(1) == 1

block preserveExistingAssignments:
  let f = lobby()
  f.clients[0].claimHumanSeat(0)
  f.clients[0].send(RoomMessage(kind: ClaimSeat, seat: 2, name: "Host bot"))
  f.exchange()
  discard f.claim(0)
  doAssert f.clients[0].outgoing.len == 0
  f.join(1)
  f.clients[1].send(RoomMessage(kind: ClaimSeat, seat: 1, name: "Guest bot"))
  f.exchange()
  doAssert f.claim(1) == (true, -1), "An existing bot controller keeps its choice"
  doAssert f.clients[1].outgoing.len == 0
  f.join(2)
  doAssert f.claim(2).seat == 3
  f.confirm(2)
  let seats = f.clients[0].snapshot.seats
  doAssert seats[0] == Seat(owner: f.clients[0].participant, name: "Human")
  doAssert seats[1] == Seat(owner: f.clients[1].participant, name: "Guest bot")
  doAssert seats[2] == Seat(owner: f.clients[0].participant, name: "Host bot")

block fullRoomStaysSpectator:
  let f = lobby(seats = 1)
  discard f.claim(0)
  f.confirm(0)
  f.join(1)
  doAssert f.claim(1) == (true, -1)
  doAssert f.clients[1].outgoing.len == 0
  f.clients[0].send(RoomMessage(kind: ReleaseSeat, seat: 0))
  f.exchange()
  doAssert f.claim(1) == (false, -1)
  doAssert f.clients[1].outgoing.len == 0
  doAssert f.human(1) == -1

block playingRoomStaysSpectatorOnRematch:
  let f = lobby()
  discard f.claim(0)
  f.confirm(0)
  let host = f.clients[0]
  host.send(RoomMessage(kind: PreparedDuration,
    revision: host.snapshot.revision, hash: 123, durationTicks: 24))
  host.send(RoomMessage(kind: StartMatch))
  f.exchange()
  doAssert host.snapshot.phase == Playing
  f.join(1)
  doAssert f.clients[1].snapshot.phase == Playing
  doAssert f.claim(1) == (true, -1)
  doAssert f.clients[1].outgoing.len == 0
  host.send(RoomMessage(kind: AbortMatch, match: host.match,
    detail: "Return to lobby for the seating regression"))
  f.exchange()
  host.send(RoomMessage(kind: ReturnLobby))
  f.exchange()
  doAssert f.clients[1].snapshot.phase == Lobby
  doAssert f.claim(1) == (false, -1)
  doAssert f.human(1) == -1
  doAssert f.clients[1].outgoing.len == 0

block manualClearStaysSpectator:
  let f = lobby()
  discard f.claim(0)
  f.confirm(0)
  f.join(1)
  discard f.claim(1)
  f.confirm(1)
  f.joining[1].cancelJoiningSeat()
  f.clients[1].send(RoomMessage(kind: ReleaseSeat, seat: 1))
  f.exchange()
  doAssert f.claim(1) == (false, -1)
  doAssert f.clients[1].outgoing.len == 0
  f.reconnect(1)
  doAssert f.claim(1) == (false, -1)
  doAssert f.human(1) == -1
  doAssert f.clients[1].outgoing.len == 0

block manualChoiceCancelsPendingClaim:
  let f = lobby()
  f.join(1)
  doAssert f.claim(1).seat == 0
  f.joining[1].cancelJoiningSeat()
  f.clients[1].claimHumanSeat(2, 0)
  f.exchange()
  doAssert f.human(1) == 2
  doAssert f.claim(1).seat == -1
  doAssert f.clients[1].snapshot.seats[0].owner == 0
  doAssert f.clients[1].outgoing.len == 0

block reconnectPreservesHumanAndBot:
  let f = lobby()
  discard f.claim(0)
  f.confirm(0)
  f.clients[0].send(RoomMessage(kind: ClaimSeat, seat: 2, name: "Private bot"))
  f.exchange()
  let participant = f.clients[0].participant
  f.join(1)
  f.reconnect(0)
  doAssert f.clients[0].participant == participant
  discard f.claim(0)
  doAssert f.human(0) == 0
  doAssert f.clients[0].snapshot.seats[2] ==
    Seat(owner: participant, name: "Private bot")
  doAssert f.clients[0].outgoing.len == 0

block reconnectRetriesUndeliveredClaim:
  let f = lobby()
  discard f.claim(0)
  f.confirm(0)
  f.join(1)
  doAssert f.claim(1).seat == 1
  doAssert f.clients[1].outgoing.len == 1
  # lost() drops this unsent control message while keeping the room snapshot.
  f.reconnect(1)
  doAssert f.human(1) == -1
  doAssert f.claim(1).seat == 1
  f.confirm(1)
  doAssert f.human(1) == 1

block leavingAndRejoiningStartsNewAttempt:
  let f = lobby()
  discard f.claim(0)
  f.confirm(0)
  f.join(1)
  discard f.claim(1)
  f.confirm(1)
  f.clients[1].send(RoomMessage(kind: LeaveRoom))
  f.exchange()
  doAssert f.clients[1].snapshot.room == ""
  doAssert f.claim(1).seat == -1
  f.join(1)
  doAssert f.claim(1).seat == 1
  f.confirm(1)
  doAssert f.human(1) == 1

echo "LvD automatic joining seats passed"
