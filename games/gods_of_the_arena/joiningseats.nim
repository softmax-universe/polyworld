## Chooses a human slot once per arrival; teams remain a GotA client policy.
import polyworld/[rooms, roomclients], multiplayer

type JoiningSeat* = object
  room: string
  pendingSeat: int = -1
  attemptedRevision: uint32
  attempted, awaitingRoom, watching, finished: bool

proc beginJoiningSeat*(state: var JoiningSeat, watching = false) =
  ## Captures Play or Watch before its asynchronous room snapshot arrives.
  state = JoiningSeat(awaitingRoom: true, watching: watching)

proc cancelJoiningSeat*(state: var JoiningSeat) =
  ## A manual roster choice takes precedence over automatic arrival seating.
  state.finished = true
  state.awaitingRoom = false

proc joiningSeatPending*(state: JoiningSeat): bool =
  ## Holds dependent lobby actions until the automatic claim is acknowledged.
  not state.finished and state.pendingSeat >= 0

proc joiningHumanSeat*(snapshot: RoomMessage): int =
  ## Balances occupied slots across the fixed red and blue teams, bots included.
  var
    occupied: array[2, int]
    empty = [-1, -1]
  for i in 0 ..< min(10, snapshot.seats.len):
    let team = i div 5
    if snapshot.seats[i].owner != 0:
      inc occupied[team]
    elif empty[team] < 0:
      empty[team] = i
  if empty[0] < 0:
    return empty[1]
  if empty[1] < 0:
    return empty[0]
  if occupied[0] <= occupied[1]: empty[0] else: empty[1]

proc claimJoiningSeat*(state: var JoiningSeat,
    client: RoomClient): tuple[updated: bool, seat: int] =
  ## Sends one claim at a time and retires arrival intent after a final choice.
  result.seat = -1
  if client == nil or client.snapshot.room.len == 0:
    # An explicit Watch click must survive frames before JoinRoom is answered.
    if not state.awaitingRoom:
      state = JoiningSeat()
    return
  let snapshot = client.snapshot
  if state.room != snapshot.room:
    let watching = state.awaitingRoom and state.watching
    state = JoiningSeat(room: snapshot.room, watching: watching)
  if state.finished:
    return
  if not client.connected or not client.welcomed or client.participant == 0:
    # Reconnection discards unsent claims but retains acknowledged assignments.
    state.pendingSeat = -1
    state.attempted = false
    return
  let human = snapshot.humanSeatFor(client.participant)
  if human >= 0:
    state.finished = true
    return (true, human)
  for seat in snapshot.seats:
    if seat.owner == client.participant:
      # A reconnecting bot controller must not gain an unwanted human actor.
      state.finished = true
      return (true, -1)
  if state.watching or snapshot.phase != Lobby:
    state.finished = true
    return (true, -1)
  if state.pendingSeat >= 0:
    if client.error == "Seat belongs to another participant" or
      (state.pendingSeat >= snapshot.seats.len and
        client.error == "Seat is outside this room"):
        client.error = ""
        state.pendingSeat = -1
    else:
      return
  let seat = snapshot.joiningHumanSeat()
  if seat < 0:
    # Full arrivals stay spectators even if a slot becomes available later.
    state.finished = true
    return (true, -1)
  if state.attempted and state.attemptedRevision == snapshot.revision:
    # Wait for the collision's newer roster instead of repeating a stale claim.
    return
  client.claimHumanSeat(seat)
  state.pendingSeat = seat
  state.attemptedRevision = snapshot.revision
  state.attempted = true
  (true, seat)
