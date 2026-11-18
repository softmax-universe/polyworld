## Public, source-free match settings for local and relay games.
import std/random
import jsony, polyworld/[configs, rooms], maps, diplomacies
export configs, maps, diplomacies

const
  MaxConfigMapCells* = 512'i64 * 512
    ## Bounds shared terrain, pathing, preview and simulation cell arrays.
    ## At this cap: 6 MiB of Tile geometry, 1.5 MiB of map cell arrays,
    ## and 2 MiB of world blocker/occupancy arrays (excluding scratch/copies).
  MaxConfigPlayerCells* = 8'i64 * 1024 * 1024
    ## visibleStamp (uint32) + explored (uint8): at most 40 MiB per world.
    ## The separate map cap leaves browser headroom for rendering and policies;
    ## these are cell-array bounds, not a cap on total process/GPU memory.

type LvdConfig* = object
  seed*: int32 = 2026
  maxTicks*: int32 = DefaultDurationTicks
  playerCount*: int = 2
  teamCount*: int
  players*: seq[PlayerConfig]
  playerSlot*: int32
  mapSettings*: MapSettings
  diplomacySettings*: DiplomacySettings

proc newHook*(settings: var MapSettings) = settings = MapSettings()
proc newHook*(settings: var DiplomacySettings) = settings = DiplomacySettings()
proc newHook*(config: var LvdConfig) = config = LvdConfig()

proc resolvedTeamCount*(config: LvdConfig): int =
  ## An omitted team count gives every player an independent team.
  if config.teamCount == 0: config.playerCount else: config.teamCount

proc playerTeam*(config: LvdConfig, player: int): int32 =
  ## Reads a stable zero-based team number before or after normalization.
  if player notin 0 ..< config.playerCount:
    return -1
  if config.diplomacySettings.teams.len == 0:
    return int32(player mod max(1, config.resolvedTeamCount()))
  config.diplomacySettings.teams[player]

proc normalizeTeams*(config: var LvdConfig) =
  ## Materializes omitted team settings without changing explicit assignments.
  if config.playerCount notin 1 .. MaxSeats or
    config.resolvedTeamCount() notin 1 .. MaxSeats:
      raise newException(LvdError, "Invalid roster or team count")
  config.teamCount = config.resolvedTeamCount()
  if config.diplomacySettings.teams.len == 0:
    config.diplomacySettings.teams = newSeq[int32](config.playerCount)
    for player in 0 ..< config.playerCount:
      config.diplomacySettings.teams[player] = int32(player mod config.teamCount)
  elif config.diplomacySettings.teams.len != config.playerCount:
    raise newException(LvdError, "Team assignments must match the complete roster")

proc setTeamCount*(config: var LvdConfig, count: int,
    occupied: openArray[int] = []) =
  ## Balances occupied players first, then fills teams with empty slots.
  if count notin 1 .. config.playerCount:
    raise newException(LvdError, "Team count must be between one and the player count")
  var
    active = newSeq[bool](config.playerCount)
    order: seq[int]
  for player in occupied:
    if player notin 0 ..< config.playerCount or active[player]:
      raise newException(LvdError, "Occupied players must be unique roster slots")
    active[player] = true
  for player in 0 ..< config.playerCount:
    if occupied.len == 0:
      active[player] = true
    if active[player]:
      order.add player
  var rng = initRand(int64(config.seed) xor (int64(count) shl 32) xor
    int64(config.playerCount))
  rng.shuffle(order)
  config.teamCount = count
  config.diplomacySettings.teams = newSeq[int32](config.playerCount)
  var populations = newSeq[int](count)
  for rank, player in order:
    let team = rank mod count
    config.diplomacySettings.teams[player] = int32(team)
    inc populations[team]
  for player in 0 ..< config.playerCount:
    if active[player]:
      continue
    var team = 0
    for candidate in 1 ..< count:
      if populations[candidate] < populations[team]:
        team = candidate
    config.diplomacySettings.teams[player] = int32(team)
    inc populations[team]

proc assignTeam*(config: var LvdConfig, player: int, team: int32) =
  ## Reassigns one player while preserving every other manual team choice.
  if player notin 0 ..< config.playerCount or
    team < 0 or team >= config.resolvedTeamCount():
      raise newException(LvdError, "Player or team is outside the roster")
  config.normalizeTeams()
  config.diplomacySettings.teams[player] = team

proc resizePlayers*(config: var LvdConfig, count: int) =
  ## Preserves existing teams and gives new players the least-populated team.
  if count notin 1 .. MaxSeats:
    raise newException(LvdError, "Player count exceeds relay seat capacity")
  config.normalizeTeams()
  let previousCount = config.playerCount
  var populations = newSeq[int](config.teamCount)
  for team in config.diplomacySettings.teams:
    if team < 0 or team >= config.teamCount:
      raise newException(LvdError, "Team assignment is outside the team count")
    inc populations[team]
  var independent = config.teamCount == previousCount
  for population in populations:
    independent = independent and population == 1
  config.teamCount =
    if independent: count
    else: min(config.teamCount, count)
  config.playerCount = count
  config.players.setLen(count)
  config.diplomacySettings.teams.setLen(count)
  populations = newSeq[int](config.teamCount)
  for player in 0 ..< count:
    var team = config.diplomacySettings.teams[player]
    if player >= previousCount or team >= config.teamCount:
      team = -1
    if team >= 0:
      inc populations[team]
    config.diplomacySettings.teams[player] = team
  for player in 0 ..< count:
    if config.diplomacySettings.teams[player] >= 0:
      continue
    var team = 0
    for candidate in 1 ..< populations.len:
      if populations[candidate] < populations[team]:
        team = candidate
    config.diplomacySettings.teams[player] = int32(team)
    inc populations[team]
  if config.playerSlot > count:
    config.playerSlot = 0

proc validate*(config: LvdConfig) =
  if config.playerCount notin 1 .. MaxSeats:
    raise newException(LvdError, "Player count exceeds relay seat capacity")
  if config.maxTicks notin 1'i32 .. SharedTickRate * 60 * 60 or
    config.playerSlot < 0 or config.playerSlot > config.playerCount:
      raise newException(LvdError, "Invalid match duration or human slot")
  if config.players.len notin [0, config.playerCount]:
    raise newException(LvdError, "Player names must match the complete roster")
  if config.teamCount notin 0 .. MaxSeats:
    raise newException(LvdError, "Team count exceeds relay seat capacity")
  if config.diplomacySettings.teams.len notin [0, config.playerCount]:
    raise newException(LvdError, "Team assignments must match the complete roster")
  for team in config.diplomacySettings.teams:
    if team < 0 or team >= config.resolvedTeamCount():
      raise newException(LvdError, "Team assignment is outside the team count")
  config.mapSettings.validate(config.playerCount)
  config.diplomacySettings.validate()
  let
    side = int64(generatedMapSide(config.seed, config.playerCount, config.mapSettings))
    cells = side * side
  if cells > MaxConfigMapCells or
    cells * int64(config.playerCount) > MaxConfigPlayerCells:
    raise newException(LvdError,
      "Map and roster exceed browser cell budget; reduce map size, spacing, expansions or players")

proc defaultConfig*(playerCount = 2): LvdConfig =
  result = LvdConfig(playerCount: playerCount)
  result.normalizeTeams()
  result.validate()
  result.players = unnamedPlayers(playerCount)

proc parseConfig*(bytes: string): LvdConfig =
  try:
    result = bytes.fromJson(LvdConfig)
    result.validate()
    result.normalizeTeams()
    if result.players.len == 0:
      result.players = unnamedPlayers(result.playerCount)
  except JsonError:
    raise newException(LvdError, "Invalid LvD config: " & getCurrentExceptionMsg())

proc gameConfig*(config: LvdConfig): GameConfig =
  GameConfig(seed: config.seed, maxTicks: config.maxTicks,
    players: (if config.players.len == 0: unnamedPlayers(config.playerCount)
      else: config.players), playerSlot: config.playerSlot)
