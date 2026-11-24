## Immediate match-setting changes share one acknowledged relay update.
import jsony, polyworld/[rooms, roomclients], presets

type RosterState* = object
  dirty*: bool
  pendingPayload*: string
  pendingName*: string
  resizePlayerCount, resizeTeamCount: int
  resizeTeams: seq[int32]

proc pending*(state: RosterState): bool =
  ## Reports an update waiting for its authoritative snapshot.
  state.pendingPayload.len > 0

proc assignmentsEnabled*(state: RosterState, online: bool): bool =
  ## Roster edits wait only while a relay update is in flight.
  not online or not state.pending

proc publishSettings*(state: var RosterState, config: LvdConfig,
    client: RoomClient, name: string): bool =
  ## Sends current valid settings once, retaining newer edits until the reply.
  if client == nil or not client.connected or not client.welcomed or
    client.snapshot.room.len == 0 or client.participant == 0 or
    client.participant != client.snapshot.participant or
    client.snapshot.phase != Lobby:
      return false
  if state.pending:
    state.dirty = config != parseConfig(state.pendingPayload) or
      name != state.pendingName
    return false
  let changed = config != parseConfig(client.snapshot.payload)
  state.dirty = changed or name != client.snapshot.name
  if not state.dirty:
    return false
  if not name.validName or name.len > 128:
    client.error = "Game name must contain visible text and fit in 128 UTF-8 bytes"
    return false
  config.validate()
  let payload = if changed: config.toJson() else: client.snapshot.payload
  client.error = ""
  client.send(RoomMessage(
    kind: if changed: ConfigureRoom else: ResizeRoom,
    name: name, number: uint32(config.playerCount),
    tickRate: client.snapshot.tickRate, flag: client.snapshot.flag,
    payload: payload
  ))
  state.pendingPayload = payload
  state.pendingName = name
  state.dirty = false
  true

proc acceptSettings*(state: var RosterState, config: var LvdConfig,
    name: var string, snapshot: RoomMessage): bool =
  ## Acknowledges payload and name together without discarding newer edits.
  if state.pending and (snapshot.payload != state.pendingPayload or
    snapshot.name != state.pendingName):
      return false
  let published = parseConfig(snapshot.payload)
  if state.pending:
    state = RosterState(dirty: config != published or name != snapshot.name)
  else:
    config = published
    name = snapshot.name
    state = RosterState()
  true

proc rejectSettings*(state: var RosterState, config: var LvdConfig,
    name: var string, snapshot: RoomMessage) =
  ## Restores authoritative values after a failure instead of retrying forever.
  config = parseConfig(snapshot.payload)
  name = snapshot.name
  state = RosterState()

proc acceptConfig*(state: var RosterState, config: var LvdConfig,
    payload: string) =
  ## Acknowledges a roster-only update without losing edits made after sending.
  if state.pending and payload != state.pendingPayload:
    return
  let published = parseConfig(payload)
  if state.pending and payload == state.pendingPayload:
    state.pendingPayload = ""
    state.dirty = config != published
  else:
    config = published
    state.dirty = false
    state.pendingPayload = ""
  state.resizePlayerCount = 0
  state.resizeTeamCount = 0
  state.resizeTeams = @[]
  state.pendingName = ""

proc rejectConfig*(state: var RosterState, config: var LvdConfig,
    payload: string) =
  ## Restores a rejected roster count while retaining independent setting edits.
  let published = parseConfig(payload)
  if state.resizePlayerCount == published.playerCount:
    config.playerCount = published.playerCount
    config.teamCount = state.resizeTeamCount
    config.diplomacySettings.teams = state.resizeTeams
  elif config.playerCount != published.playerCount:
    config.resizePlayers(published.playerCount)
  config.players = published.players
  state.pendingPayload = ""
  state.resizePlayerCount = 0
  state.resizeTeamCount = 0
  state.resizeTeams = @[]
  state.pendingName = ""
  state.dirty = config != published

proc resizeRoster*(state: var RosterState, config: var LvdConfig,
    client: RoomClient, count: int, publicRoom = true) =
  ## Update the requested roster (local games have no relay client).
  if state.pending: return
  var updated = config
  updated.resizePlayers(count)
  updated.validate()
  if client != nil:
    var published = parseConfig(client.snapshot.payload)
    published.resizePlayers(count)
    published.validate()
    let payload = published.toJson()
    client.send(RoomMessage(kind: ResizeRoom, name: client.snapshot.name,
      number: uint32(count), tickRate: client.snapshot.tickRate,
      flag: publicRoom, payload: payload))
    state.pendingPayload = payload
    state.pendingName = client.snapshot.name
    state.resizePlayerCount = config.playerCount
    state.resizeTeamCount = config.resolvedTeamCount()
    state.resizeTeams = newSeq[int32](config.playerCount)
    for player in 0 ..< config.playerCount:
      state.resizeTeams[player] = config.playerTeam(player)
  config = updated
