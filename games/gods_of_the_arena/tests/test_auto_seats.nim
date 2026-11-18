## Join-time defaults exercise actual wire clients and relay ownership rules.
import
  std/strutils,
  polyworld/[rooms, relays, roomclients],
  ../[joiningseats, multiplayer]

type Fixture = ref object
  relay: Relay
  clients: seq[RoomClient]
  joining: seq[JoiningSeat]

proc exchange(f: Fixture) =
  ## Pump actual encoded requests and replies without invoking the UI helper.
  for attempt in 0 ..< 30:
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
  doAssert false, "Auto-seat relay transport did not settle"

proc lobby(): Fixture =
  ## Creates three connected participants and an empty ten-slot room.
  result = Fixture(relay: Relay(), joining: newSeq[JoiningSeat](3))
  for i in 0 ..< 3:
    let client = RoomClient(identity: gotaIdentity(), name: "Player " & $i)
    result.clients.add client
    client.opened()
    result.exchange()
  result.joining[0].beginJoiningSeat()
  result.clients[0].send(RoomMessage(kind: CreateRoom, name: "Automatic seating",
    number: 10, tickRate: 24, payload: "{}"))
  result.exchange()

proc join(f: Fixture, index: int, watching = false) =
  ## Records arrival intent before delivering the authoritative room snapshot.
  f.joining[index].beginJoiningSeat(watching)
  f.clients[index].send(RoomMessage(kind: JoinRoom,
    room: f.clients[0].snapshot.room))
  f.exchange()

proc claim(f: Fixture, index: int): tuple[updated: bool, seat: int] =
  ## Runs the same arrival policy called once per frontend iteration.
  f.joining[index].claimJoiningSeat(f.clients[index])

proc human(f: Fixture, index: int): int =
  ## Reads the participant's confirmed human assignment from the relay.
  f.clients[index].snapshot.humanSeatFor(f.clients[index].participant)

proc confirm(f: Fixture, index: int) =
  ## Resolves the pending claim and verifies that later polls stay quiet.
  f.exchange()
  discard f.claim(index)
  doAssert f.clients[index].error == ""
  doAssert f.clients[index].outgoing.len == 0, "No duplicate confirmed claim"
  doAssert not f.joining[index].joiningSeatPending()

proc bot(f: Fixture, slot: int, owner = 0) =
  ## Claims a typed bot with a deliberately human-looking display name.
  f.clients[owner].send(RoomMessage(kind: ClaimSeat, seat: uint32(slot),
    seatKind: BotSeat, name: "Human")) # Display labels never determine role.
  f.exchange()

proc start(f: Fixture) =
  ## Starts the generic room with its authoritative initialization hash.
  let host = f.clients[0]
  host.send(RoomMessage(kind: StartMatch, revision: host.snapshot.revision,
    hash: setupHash(host.snapshot)))
  f.exchange()
  doAssert host.snapshot.phase == Playing

proc rematch(f: Fixture) =
  ## Returns the existing room to its lobby without changing join intent.
  let host = f.clients[0]
  host.send(RoomMessage(kind: AbortMatch, match: host.match,
    detail: "Auto-seat test returns to lobby"))
  f.exchange()
  host.send(RoomMessage(kind: ReturnLobby))
  f.exchange()
  doAssert host.snapshot.phase == Lobby

proc reconnect(f: Fixture, index: int) =
  ## Exposes the disconnected frame before restoring the same participant.
  f.relay.disconnect(index + 1)
  f.clients[index].lost()
  discard f.claim(index)
  f.exchange()
  f.clients[index].opened()
  f.exchange()

block fixedTeamBalance:
  var snapshot = RoomMessage(seats: newSeq[Seat](10))
  doAssert joiningHumanSeat(snapshot) == 0
  snapshot.seats[0] = Seat(owner: 1, kind: HumanSeat)
  doAssert joiningHumanSeat(snapshot) == 5
  snapshot.seats[5] = Seat(owner: 2, kind: BotSeat, name: "Human")
  doAssert joiningHumanSeat(snapshot) == 1, "Equal teams choose first empty slot"
  for slot in 1 .. 3:
    snapshot.seats[slot] = Seat(owner: 1, kind: BotSeat)
  doAssert joiningHumanSeat(snapshot) == 6, "Bots count toward team population"
  for slot in 6 .. 9:
    snapshot.seats[slot] = Seat(owner: 2, kind: HumanSeat)
  doAssert joiningHumanSeat(snapshot) == 4, "A full team cannot receive a join"
  snapshot.seats[4] = Seat(owner: 1)
  doAssert joiningHumanSeat(snapshot) == -1

block hostAndBalancedGuests:
  let f = lobby()
  doAssert not f.joining[0].joiningSeatPending()
  doAssert f.claim(0) == (true, 0)
  for frame in 0 ..< 4:
    discard f.claim(0)
    doAssert f.joining[0].joiningSeatPending()
  doAssert f.clients[0].outgoing.len == 1, "One claim in flight"
  f.confirm(0)
  doAssert f.human(0) == 0
  f.join(1)
  doAssert f.claim(1) == (true, 5)
  f.confirm(1)
  doAssert f.human(1) == 5
  f.bot(1)
  f.bot(2)
  f.join(2)
  doAssert f.claim(2) == (true, 6)
  f.confirm(2)
  doAssert f.human(2) == 6
  for index in 0 .. 2:
    doAssert f.claim(index) == (false, -1)
    doAssert f.clients[index].outgoing.len == 0

block waitsForIdentity:
  let
    f = lobby()
    participant = f.clients[0].participant
  f.clients[0].participant = 0
  doAssert f.claim(0) == (false, -1)
  doAssert f.clients[0].outgoing.len == 0
  f.clients[0].participant = participant
  doAssert f.claim(0) == (true, 0)
  f.confirm(0)

block simultaneousGuestsRebalance:
  let f = lobby()
  discard f.claim(0)
  f.confirm(0)
  f.join(1)
  f.join(2)
  doAssert f.claim(1).seat == 5
  doAssert f.claim(2).seat == 5
  f.exchange()
  doAssert f.human(1) == 5 and f.human(2) == -1
  doAssert f.clients[2].error == "Seat belongs to another participant"
  doAssert f.claim(2) == (true, 1)
  doAssert f.clients[2].error == ""
  for frame in 0 ..< 4: discard f.claim(2)
  doAssert f.clients[2].outgoing.len == 1
  f.confirm(2)
  doAssert f.human(2) == 1
  doAssert f.clients[0].snapshot.seats[0].owner == f.clients[0].participant
  doAssert f.clients[0].snapshot.seats[5].owner == f.clients[1].participant

block collisionRetryWaitsForNewRevision:
  let f = lobby()
  discard f.claim(0)
  f.confirm(0)
  f.join(1)
  doAssert f.claim(1) == (true, 5)
  # Model a rejection observed while the frontend still has its prior snapshot.
  # No repeated frame may publish another claim for the same roster revision.
  f.clients[1].outgoing.setLen(0)
  f.clients[1].accept(RoomMessage(kind: Failure,
    detail: "Seat belongs to another participant").encode())
  for frame in 0 ..< 4:
    doAssert f.claim(1) == (false, -1)
    doAssert not f.joining[1].joiningSeatPending()
    doAssert f.clients[1].outgoing.len == 0
  doAssert f.clients[1].error == ""
  f.bot(5)
  doAssert f.claim(1) == (true, 1)
  for frame in 0 ..< 4: discard f.claim(1)
  doAssert f.clients[1].outgoing.len == 1
  f.confirm(1)

block winningClaimReleasedBeforeReplies:
  let f = lobby()
  discard f.claim(0)
  f.confirm(0)
  f.join(1)
  f.join(2)
  doAssert f.claim(1).seat == 5
  doAssert f.claim(2).seat == 5
  for index in [1, 2]:
    let requests = f.clients[index].outgoing
    f.clients[index].outgoing = @[]
    for bytes in requests: f.relay.process(index + 1, bytes, 0)
  f.clients[1].send(RoomMessage(kind: ReleaseSeat, seat: 5))
  f.exchange()
  doAssert f.clients[2].snapshot.seats[5].owner == 0
  doAssert f.claim(2) == (true, 5)
  f.confirm(2)

block preserveExistingAssignments:
  let f = lobby()
  f.clients[0].claimHumanSeat(3)
  f.bot(7)
  doAssert f.claim(0) == (true, 3)
  doAssert f.clients[0].outgoing.len == 0
  f.join(1)
  f.bot(8, owner = 1)
  doAssert f.claim(1) == (true, -1)
  doAssert not f.joining[1].joiningSeatPending()
  doAssert f.clients[1].outgoing.len == 0
  f.reconnect(0)
  doAssert f.claim(0) == (false, -1)
  doAssert f.human(0) == 3
  doAssert f.clients[0].snapshot.seats[7].kind == BotSeat
  doAssert f.clients[0].snapshot.seats[7].owner == f.clients[0].participant

block fullRoomRemainsSpectator:
  let f = lobby()
  for slot in 0 .. 9: f.bot(slot)
  f.join(1)
  doAssert f.claim(1) == (true, -1)
  doAssert not f.joining[1].joiningSeatPending()
  doAssert f.clients[1].outgoing.len == 0
  f.clients[0].send(RoomMessage(kind: ReleaseSeat, seat: 5))
  f.exchange()
  doAssert f.claim(1) == (false, -1)
  doAssert f.human(1) == -1

block runningJoinRemainsSpectatorOnRematch:
  let f = lobby()
  discard f.claim(0)
  f.confirm(0)
  f.start()
  f.join(1)
  doAssert f.claim(1) == (true, -1)
  doAssert not f.joining[1].joiningSeatPending()
  doAssert f.clients[1].outgoing.len == 0
  f.rematch()
  doAssert f.claim(1) == (false, -1)
  doAssert f.human(1) == -1

block explicitWatchSurvivesRoomOpening:
  let f = lobby()
  discard f.claim(0)
  f.confirm(0)
  f.start()
  # Watch was selected from a playing-room listing. The host returns to lobby
  # before JoinRoom replies, so the first snapshot alone cannot imply intent.
  f.joining[1].beginJoiningSeat(watching = true)
  for frame in 0 ..< 4:
    doAssert f.clients[1].snapshot.room == ""
    doAssert f.claim(1) == (false, -1)
  f.rematch()
  f.clients[1].send(RoomMessage(kind: JoinRoom,
    room: f.clients[0].snapshot.room))
  f.exchange()
  doAssert f.clients[1].snapshot.phase == Lobby
  doAssert f.claim(1) == (true, -1)
  doAssert not f.joining[1].joiningSeatPending()
  doAssert f.clients[1].outgoing.len == 0 and f.human(1) == -1
  f.clients[1].send(RoomMessage(kind: LeaveRoom))
  f.exchange()
  discard f.claim(1)
  f.join(1)
  doAssert f.claim(1) == (true, 5), "A new normal join resets Watch intent"
  f.confirm(1)

block successfulAssignmentIsNeverReclaimed:
  for hostRemoves in [false, true]:
    let f = lobby()
    discard f.claim(0)
    f.confirm(0)
    f.join(1)
    discard f.claim(1)
    f.confirm(1)
    if not hostRemoves: f.joining[1].cancelJoiningSeat()
    f.clients[if hostRemoves: 0 else: 1].send(
      RoomMessage(kind: ReleaseSeat, seat: 5))
    f.exchange()
    doAssert f.claim(1) == (false, -1)
    f.reconnect(1)
    doAssert f.claim(1) == (false, -1)
    doAssert f.human(1) == -1 and f.clients[1].outgoing.len == 0

block manualChoiceCancelsPendingDefault:
  let f = lobby()
  f.join(1)
  doAssert f.claim(1).seat == 0
  doAssert f.joining[1].joiningSeatPending()
  f.joining[1].cancelJoiningSeat()
  doAssert not f.joining[1].joiningSeatPending()
  f.clients[1].claimHumanSeat(8, previous = 0)
  f.exchange()
  doAssert f.human(1) == 8
  doAssert f.clients[1].snapshot.seats[0].owner == 0
  doAssert f.claim(1) == (false, -1)

block reconnectRetriesUndeliveredClaim:
  let f = lobby()
  discard f.claim(0)
  f.confirm(0)
  f.join(1)
  doAssert f.claim(1) == (true, 5)
  f.reconnect(1)
  doAssert f.human(1) == -1
  doAssert f.claim(1) == (true, 5)
  f.confirm(1)
  doAssert f.human(1) == 5

block leaveAndRejoinStartsFresh:
  let f = lobby()
  discard f.claim(0)
  f.confirm(0)
  f.join(1)
  discard f.claim(1)
  f.confirm(1)
  f.clients[1].send(RoomMessage(kind: LeaveRoom))
  f.exchange()
  discard f.claim(1)
  f.join(1)
  doAssert f.claim(1) == (true, 5)
  f.confirm(1)

block frontendCapturesEveryArrival:
  # Runtime cases above cover policy behavior; guard its three rendered entry
  # points so invite links and Watch buttons do not silently bypass that policy.
  let frontend = readFile("games/gods_of_the_arena/frontend.nim").splitWhitespace().join("")
  doAssert "joiningSeat.beginJoiningSeat()client.send(RoomMessage(kind:JoinRoom,room:invite))" in frontend
  doAssert "joiningSeat.beginJoiningSeat(watching)connection.client.send(RoomMessage(kind:JoinRoom,room:room.id))" in frontend
  doAssert "joiningSeat.beginJoiningSeat()connection.client.send(RoomMessage(kind:CreateRoom," in frontend
  doAssert "seatPending=onlineandjoiningSeat.joiningSeatPending()" in frontend
  let
    fillAt = frontend.find("ifsk.lobbyButton(\"Fill")
    fillEnd = frontend.find("):", fillAt)
    launchAt = frontend.find("client.requestStart(sources)")
    startAt = frontend.rfind("ifsk.lobbyButton(\"StartGame\"", last = launchAt)
    startEnd = frontend.find("):", startAt)
  doAssert fillAt >= 0 and fillEnd > fillAt
  doAssert launchAt > 0 and startAt >= 0 and startEnd > startAt
  doAssert "notseatPending" in frontend[fillAt ..< fillEnd],
    "Fill must await acknowledgement so it does not replace the arriving human"
  doAssert "notseatPending" in frontend[startAt ..< startEnd],
    "Start must include the arriving human in its authoritative setup"

echo "GotA balanced joining, collision retry, Watch intent and roster choices passed"
