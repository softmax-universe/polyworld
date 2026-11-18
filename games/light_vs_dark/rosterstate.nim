## Match-setting drafts are independent from seat assignments.
import jsony, polyworld/[rooms, roomclients], presets

type RosterState* = object
  dirty*: bool
  pendingPayload*: string
  resizePlayerCount, resizeTeamCount: int
  resizeTeams: seq[int32]

proc pending*(state: RosterState): bool = state.pendingPayload.len > 0

proc assignmentsEnabled*(state: RosterState, online: bool): bool =
  not online or not state.pending

proc acceptConfig*(state: var RosterState, config: var LvdConfig,
    payload: string) =
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

proc rejectConfig*(state: var RosterState, config: var LvdConfig,
    payload: string) =
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
    state.resizePlayerCount = config.playerCount
    state.resizeTeamCount = config.resolvedTeamCount()
    state.resizeTeams = newSeq[int32](config.playerCount)
    for player in 0 ..< config.playerCount:
      state.resizeTeams[player] = config.playerTeam(player)
  config = updated
