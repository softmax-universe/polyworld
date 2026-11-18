## Team drafts survive roster edits and become identical local/network matches.

import
  jsony,
  polyworld/[roomclients, rooms],
  ../[content, multiplayer, presets, replays, rosterstate, sim]

proc populations(config: LvdConfig): seq[int] =
  ## Counts every assigned setup slot, including currently empty slots.
  result = newSeq[int](config.resolvedTeamCount())
  for player in 0 ..< config.playerCount:
    inc result[config.playerTeam(player)]

block defaultIndependentTeams:
  let config = defaultConfig(6)
  doAssert not config.diplomacySettings.enabled
  doAssert config.teamCount == 6
  doAssert config.diplomacySettings.teams == @[0'i32, 1, 2, 3, 4, 5]
  doAssert parseConfig(config.toJson()) == config
  let omitted = parseConfig("""{"playerCount":4,"teamCount":2}""")
  doAssert omitted.diplomacySettings.teams == @[0'i32, 1, 0, 1]
  doAssert parseConfig(omitted.toJson()) == omitted

block evenlyShuffledTeams:
  for players in 2 .. 12:
    for teams in 1 .. players:
      var
        first = defaultConfig(players)
        repeated = defaultConfig(players)
      first.setTeamCount(teams)
      repeated.setTeamCount(teams)
      doAssert first.diplomacySettings.teams == repeated.diplomacySettings.teams
      let sizes = first.populations()
      doAssert max(sizes) - min(sizes) <= 1
      for size in sizes:
        doAssert size >= 1

block manualAssignmentAndModeToggle:
  var config = defaultConfig(6)
  config.setTeamCount(3)
  let before = config.diplomacySettings.teams
  let team = (config.playerTeam(2) + 1) mod 3
  config.assignTeam(2, team)
  for player in 0 ..< config.playerCount:
    doAssert config.playerTeam(player) ==
      (if player == 2: team else: before[player])
  let assigned = config.diplomacySettings.teams
  config.diplomacySettings.enabled = true
  config.normalizeTeams()
  config.diplomacySettings.enabled = false
  doAssert config.diplomacySettings.teams == assigned
  doAssert parseConfig(config.toJson()) == config

block occupiedPlayersBalanceBeforeEmptySlots:
  let occupied = [1, 3, 5, 7]
  for teams in [2, 3, 6]:
    var
      config = defaultConfig(8)
      repeated = defaultConfig(8)
      activeSizes = newSeq[int](teams)
    config.setTeamCount(teams, occupied)
    repeated.setTeamCount(teams, [7, 5, 3, 1])
    doAssert config.diplomacySettings.teams == repeated.diplomacySettings.teams
    for player in occupied:
      inc activeSizes[config.playerTeam(player)]
    doAssert max(activeSizes) - min(activeSizes) <= 1
    if teams == 2:
      doAssert activeSizes == @[2, 2]
    let sizes = config.populations()
    doAssert max(sizes) - min(sizes) <= 1

block resizingPreservesTeams:
  var config = defaultConfig(3)
  config.resizePlayers(5)
  doAssert config.diplomacySettings.teams == @[0'i32, 1, 2, 3, 4]
  doAssert config.teamCount == 5
  config.resizePlayers(3)
  doAssert config.diplomacySettings.teams == @[0'i32, 1, 2]
  config.setTeamCount(2)
  for player in 0 ..< 3:
    config.assignTeam(player, 0)
  config.resizePlayers(5)
  doAssert config.diplomacySettings.teams == @[0'i32, 0, 0, 1, 1]
  doAssert config.teamCount == 2
  config.teamCount = 4
  config.diplomacySettings.teams = @[3'i32, 2, 2, 1, 0]
  config.resizePlayers(3)
  doAssert config.teamCount == 3
  doAssert config.diplomacySettings.teams == @[0'i32, 2, 2]
  config.validate()

block invalidTeamSettings:
  for bytes in [
    """{"playerCount":3,"teamCount":-1}""",
    """{"playerCount":3,"teamCount":65}""",
    """{"playerCount":3,"teamCount":2,"diplomacySettings":{"teams":[0,1]}}""",
    """{"playerCount":3,"teamCount":2,"diplomacySettings":{"teams":[0,1,2]}}""",
    """{"playerCount":3,"diplomacySettings":{"teams":[0,-1,1]}}"""
  ]:
    var rejected = false
    try:
      discard parseConfig(bytes)
    except LvdError:
      rejected = true
    doAssert rejected, bytes
  var config = defaultConfig(4)
  let before = config
  var rejected = false
  try:
    config.assignTeam(4, 0)
  except LvdError:
    rejected = true
  doAssert rejected and config == before
  for occupied in [@[1, 1], @[-1], @[4]]:
    rejected = false
    try:
      config.setTeamCount(2, occupied)
    except LvdError:
      rejected = true
    doAssert rejected and config == before

block resizePublicationKeepsTeamDraft:
  var
    config = defaultConfig(4)
    state = RosterState(dirty: true)
  let published = config.toJson()
  let client = RoomClient(snapshot: RoomMessage(
    name: "Teams", payload: published, tickRate: uint32(TickRate)
  ))
  config.setTeamCount(2)
  config.assignTeam(0, 1)
  let originalTeams = config.diplomacySettings.teams
  config.seed = 88
  state.resizeRoster(config, client, 5)
  let pending = parseConfig(state.pendingPayload)
  doAssert pending.teamCount == 5
  doAssert config.teamCount == 2
  for player in 0 ..< originalTeams.len:
    doAssert config.playerTeam(player) == originalTeams[player]
  state.acceptConfig(config, state.pendingPayload)
  doAssert state.dirty and not state.pending
  doAssert config.seed == 88 and config.teamCount == 2

block rejectedShrinkRestoresTeamDraft:
  var
    config = defaultConfig(4)
    state = RosterState(dirty: true)
  let published = config.toJson()
  let client = RoomClient(snapshot: RoomMessage(
    name: "Teams", payload: published, tickRate: uint32(TickRate)
  ))
  config.diplomacySettings.teams = @[3'i32, 2, 2, 0]
  config.seed = 88
  let originalTeams = config.diplomacySettings.teams
  state.resizeRoster(config, client, 3)
  doAssert config.playerTeam(0) != 3
  state.rejectConfig(config, published)
  doAssert config.playerCount == 4 and config.teamCount == 4
  doAssert config.diplomacySettings.teams == originalTeams
  doAssert config.seed == 88 and state.dirty and not state.pending

block sparseNetworkTeamsAndReplay:
  var config = defaultConfig(4)
  config.maxTicks = 12
  config.mapSettings = MapSettings(layout: RandomLayout, size: 90, expansions: 0)
  config.diplomacySettings.teams = @[0'i32, 3, 1, 3]
  let snapshot = RoomMessage(
    kind: RoomState, revision: 2, phase: Playing,
    tickRate: uint32(TickRate), payload: config.toJson(),
    seats: @[Seat(), Seat(owner: 1, name: "Human"), Seat(),
      Seat(owner: 2, name: "Human")],
    participants: @[Participant(id: 1, name: "Alice"),
      Participant(id: 2, name: "Bob")]
  )
  let
    first = prepareNetworkMatch(RoomClient(identity: lvdIdentity(),
      participant: 1, match: 1, snapshot: snapshot), [])
    second = prepareNetworkMatch(RoomClient(identity: lvdIdentity(),
      participant: 2, match: 1, snapshot: snapshot), [])
  doAssert first.playerSeats == @[1, 3]
  doAssert first.game.world.diplomacy.settings.teams == @[3'i32, 3]
  doAssert first.game.world.diplomacy.relation(0, 1).state == Allied
  doAssert first.game.networkHash() == second.game.networkHash()
  let tape = decodeReplay(encodeReplay(first.game.recorder.data))
  doAssert tape.header.setup.diplomacySettings.teams == @[3'i32, 3]
  let playback = newGame(first.game.world.map, 12,
    tape.header.setup.diplomacySettings)
  doAssert playback.stateHash() == first.game.stateHash()

echo "Team setup, roster edits, sparse network teams and replay passed"
