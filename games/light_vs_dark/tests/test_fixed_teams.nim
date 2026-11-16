## Fixed teams control combat, shared sight, immutable relations, and victory.

import
  polyworld/tapes,
  ../[content, diplomacies, maps, replays, sim]

proc teamSettings(): DiplomacySettings =
  ## Assigns alternating players to two fixed teams.
  DiplomacySettings(teams: @[0'i32, 1, 0, 1])

proc teamGame(maximumTicks = 1000'i32): Game =
  ## Constructs a normal four-player map with the fixed-team fixture.
  newGame(generateMap(42, 4), maximumTicks, teamSettings())

proc defeatNextTick(world: World, player: int32) =
  ## Uses normal hall destruction and expires its independently tested grace.
  for building in world.buildings:
    if building.owner == player and building.kind == TownHallBuilding:
      world.damageEntity(building.id, building.hp)
  world.players[player].hallLossDeadline = world.tick + 1

echo "Testing fixed-team initialization and immutable diplomacy"
block defaults:
  var independent = initDiplomacy(4)
  for player in 0'i32 ..< 4:
    doAssert independent.teamFor(player) == player
    for other in 0'i32 ..< 4:
      doAssert independent.atWar(player, other) == (player != other)
  for command in DiplomacyCommand:
    doAssert not independent.apply(0, 1, 1, command)

block relationships:
  var teams = initDiplomacy(4, teamSettings())
  for first in 0'i32 ..< 4:
    for second in first + 1 ..< 4:
      let allied = first mod 2 == second mod 2
      doAssert teams.atWar(first, second) == not allied
      doAssert teams.sharesVision(first, second) == allied
      for command in DiplomacyCommand:
        doAssert not teams.apply(first, second, 1, command)
  let baseline = teams
  teams.advance(TickRate * 60)
  doAssert teams == baseline

block validation:
  for invalid in [@[0'i32, 1, 0], @[0'i32, -1, 0, 1],
      @[0'i32, 64, 0, 1]]:
    var rejected = false
    try:
      discard initDiplomacy(4, DiplomacySettings(teams: invalid))
    except LvdError:
      rejected = true
    doAssert rejected

echo "Testing allied combat protection and shared vision"
block combatAndVision:
  let
    game = teamGame()
    world = game.world
    center = world.map.side div 2
    attacker = world.spawnUnit(0, SoldierUnit, tile2(center, center))
    ally = world.spawnUnit(2, PeonUnit, tile2(center + 1, center))
    enemy = world.spawnUnit(1, PeonUnit, tile2(center, center + 1))
  world.rebuildVision()
  let allyHp = world.units[world.unitIndex(ally)].hp
  doAssert world.visible(0, world.map.hallOrigin[2])
  doAssert not world.visible(0, world.map.hallOrigin[1])
  doAssert not world.applyAttack(0, attacker, ally)
  world.damageEntity(ally, 1000, 0)
  doAssert world.units[world.unitIndex(ally)].hp == allyHp
  doAssert world.applyAttack(0, attacker, enemy)
  doAssert not world.applyDiplomacy(0, 2, EndAlliance)
  doAssert not world.applyDiplomacy(0, 1, OfferPeace)
  let before = game.stateHash()
  for command in DiplomacyCommand:
    doAssert not world.applyDiplomacy(0, 1, command)
  doAssert game.stateHash() == before
  for tick in 1 .. TickRate * 2:
    world.tickWorld(nil)
  doAssert world.units[world.unitIndex(ally)].hp == allyHp
  let enemyIndex = world.unitIndex(enemy)
  doAssert enemyIndex < 0 or world.units[enemyIndex].hp < 40
  doAssert not world.over

echo "Testing team victory, eliminated teammates, and simultaneous draws"
block victory:
  let world = teamGame().world
  world.defeatNextTick(0)
  world.tickWorld(nil)
  doAssert world.players[0].defeated
  doAssert not world.over
  world.defeatNextTick(1)
  world.tickWorld(nil)
  doAssert not world.over
  world.defeatNextTick(3)
  world.tickWorld(nil)
  doAssert world.over and world.winner == 2
  doAssert world.scores() == @[1, 0, 1, 0]

block survivingTeammates:
  let world = teamGame().world
  world.defeatNextTick(1)
  world.defeatNextTick(3)
  world.tickWorld(nil)
  doAssert world.over
  doAssert world.winner == 0
  doAssert world.diplomacy.teamFor(world.winner) == 0
  doAssert not world.players[0].defeated
  doAssert not world.players[2].defeated
  doAssert world.scores() == @[1, 0, 1, 0]

block draws:
  let world = teamGame().world
  for player in 0'i32 ..< 4:
    world.defeatNextTick(player)
  world.tickWorld(nil)
  doAssert world.over and world.winner == -1
  doAssert world.scores() == @[0, 0, 0, 0]
  let capped = teamGame(2).world
  for tick in 1 .. 2:
    capped.tickWorld(nil)
  doAssert capped.over and capped.winner == -1

block cooperativeSandbox:
  let world = newGame(generateMap(42, 4), 3,
    DiplomacySettings(teams: @[0'i32, 0, 0, 0])).world
  for tick in 1 .. 2:
    world.tickWorld(nil)
    doAssert not world.over
  world.tickWorld(nil)
  doAssert world.over and world.winner == 0
  doAssert world.scores() == @[1, 1, 1, 1]

echo "Testing fixed-team settings through replay serialization"
block canonicalAssignments:
  let map = generateMap(87, 4)
  for negotiated in [false, true]:
    let
      implicit = newGame(map, 48, DiplomacySettings(enabled: negotiated))
      explicit = newGame(map, 48,
        DiplomacySettings(enabled: negotiated, teams: @[0'i32, 1, 2, 3]))
    doAssert implicit.world.diplomacy.settings.teams == @[0'i32, 1, 2, 3]
    doAssert implicit.stateHash() == explicit.stateHash()
    for tick in 1 .. 48:
      implicit.world.tickWorld(nil)
      explicit.world.tickWorld(nil)
      doAssert implicit.stateHash() == explicit.stateHash()

block replay:
  let
    map = generateMap(87, 4)
    game = newGame(map, 48, teamSettings())
  var setup = Setup(
    mapSeed: map.seed,
    tickRate: TickRate.uint16,
    gridTiles: map.side.uint16,
    decisionTicks: DecisionTicks.uint16,
    maximumTicks: 48,
    mapHash: map.hash,
    contentHash: contentHash(),
    mapSettings: map.settings,
    diplomacySettings: teamSettings()
  )
  for player, tile in map.hallOrigin:
    setup.players.add ReplayPlayerSetup(
      id: player.int32, startX: tile.x.int32, startY: tile.y.int32
    )
  game.recorder = initReplayRecorder(setup)
  for tick in 1 .. 48:
    game.world.tickWorld(nil)
    game.recorder.recordHash(game.stateHash())
  let
    data = decodeReplay(encodeReplay(game.recorder.data))
    playback = newGame(map, 48, data.header.setup.diplomacySettings)
  doAssert data.header.setup.diplomacySettings == teamSettings()
  for tick in 1 .. 48:
    playback.world.tickWorld(nil)
    doAssert playback.stateHash() == data.hashes[tick - 1]
  let changed = newGame(map, 48,
    DiplomacySettings(teams: @[0'i32, 0, 1, 1]))
  let initial = newGame(map, 48, teamSettings())
  doAssert changed.stateHash() != initial.stateHash()

echo "Fixed-team rules passed"
