## Claims one human slot on arrival without overriding later roster choices.
import polyworld/[rooms, roomclients], multiplayer

type JoiningSeat* = object
  room: string
  pendingSeat: int = -1
  finished: bool

proc cancelJoiningSeat*(state: var JoiningSeat) =
  ## Leaves subsequent assignments under the player's control.
  state.finished = true

proc claimJoiningSeat*(state: var JoiningSeat,
    client: RoomClient): tuple[updated: bool, seat: int] =
  ## Reports a human slot change, including minus one when joining as spectator.
  result.seat = -1
  if client == nil or client.snapshot.room.len == 0:
    state = JoiningSeat()
    return
  let snapshot = client.snapshot
  if state.room != snapshot.room:
    state = JoiningSeat(room: snapshot.room)
  if state.finished:
    return
  if not client.connected or not client.welcomed or client.participant == 0:
    # A lost connection discards unsent claims. Retry after its fresh snapshot.
    state.pendingSeat = -1
    return
  let human = snapshot.humanSeatFor(client.participant)
  if human >= 0:
    state.finished = true
    return (true, human)
  if snapshot.phase != Lobby:
    state.finished = true
    result.updated = true
    return
  for seat in snapshot.seats:
    if seat.owner == client.participant:
      # Preserve reconnecting controllers' existing bot-only assignments.
      state.finished = true
      result.updated = true
      return
  if state.pendingSeat >= 0:
    if client.error == "Seat belongs to another participant" or
      (state.pendingSeat >= snapshot.seats.len and
      client.error == "Seat is outside this room"):
        # Concurrent claims or a roster shrink can invalidate the chosen slot.
        client.error = ""
        state.pendingSeat = -1
    else:
      return
  for i, seat in snapshot.seats:
    if seat.owner == 0:
      client.claimHumanSeat(i)
      state.pendingSeat = i
      return (true, i)
  # Full rooms remain spectator joins even when another player later leaves.
  state.finished = true
  result.updated = true
