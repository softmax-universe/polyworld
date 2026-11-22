## Readiness is shared presentation state and never gates a match start.
import polyworld/[rooms, roomclients]

proc cosmeticReady*(client: RoomClient): bool =
  ## Reads this participant's current visible readiness from the room snapshot.
  if client == nil: return false
  for participant in client.snapshot.participants:
    if participant.id == client.participant: return participant.ready

proc toggleCosmeticReady*(client: RoomClient) =
  ## Publishes a visible preference without preparing or approving game state.
  client.send(RoomMessage(kind: ReadyStatus, flag: not client.cosmeticReady()))
