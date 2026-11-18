## Hero command queues are authoritative across ticks, replay, and multiplayer.

import
  fixxy,
  polyworld/pathing,
  ../[content, maps, multiplayer, replays, sim]

proc arena(): Game =
  ## Creates one living hero on a wide road with no autonomous participants.
  var preset = defaultConfig()
  preset.roadWidth = 62
  result = newGame(generateMap(2026, preset), 100_000, 10, false,
    ReplayData(), drafting = false)
  result.world.camps.setLen(0)
  result.world.spawnTimerTicks = 100_000
  result.world.heroTurnTicks = 100_000
  for hero in result.world.heroes:
    hero.hp = 0
    hero.state = Dying
    hero.deathTicks = -100_000
  for tower in result.world.buildings.mitems:
    tower.hp = 0
  result.world.syncBuildings()
  let
    hero = result.world.heroes[0]
    x = mapTiles() * 7 div 16
    z = mapTiles() * 9 div 64
    tile = layers[GroundLayer].tiles[z * mapTiles() + x]
  hero.class = Ranger
  hero.refreshHeroStats()
  hero.hp = hero.maxHp
  hero.state = Marching
  var point = WorldPoint(
    x: (x - mapTiles() div 2).int32 * WorldScale + WorldScale div 2,
    z: (z - mapTiles() div 2).int32 * WorldScale + WorldScale div 2)
  for height in tile.tops:
    point.y += height.int32 * WorldScale div 32
  hero.place(point)

proc settle(game: Game, limit = 600) =
  ## Ticks until every explicit order completes or reports a stuck sequence.
  let hero = game.world.heroes[0]
  for tick in 0 ..< limit:
    game.tickWorld(nil)
    if not hero.hasOrder and hero.queuedOrders.len == 0:
      return
  doAssert false, "The hero's queued path did not finish"

proc addCreep(game: Game, id: int32, allied = false, dx = WorldScale) =
  ## Places one harmless visible creep close to the controlled hero.
  let hero = game.world.heroes[0]
  var creep = Footman(id: id, hp: 1,
    team: (if allied: hero.team else: BlueTeam))
  var position = hero.position
  position.x += dx
  creep.place(position)
  creep.controls[StunControl].ends = 100_000
  game.world.footmen.add creep
  for team in Team:
    for value in game.world.teamVisible[team.ord].mitems:
      value = 255

echo "Testing queued paths preserve order, offsets, snapshots, and completion"
block:
  let
    game = arena()
    hero = game.world.heroes[0]
    x = mapCoordinate(hero.position.x)
    z = mapCoordinate(hero.position.z)
    offset = fixedVec2(Fixed(16384), Fixed(-16384))
  doAssert game.world.applyWalkTo(hero.id, x + 2, z)
  doAssert game.world.applyQueuedWalkTo(hero.id, x + 2, z + 2)
  doAssert game.world.applyQueuedWalkTo(hero.id, x, z + 2, offset)
  doAssert hero.activeOrder.first == x + 2
  doAssert hero.queuedOrders.len == 2
  let snapshot = game.world.clone()
  let oldHash = game.stateHash()
  hero.queuedOrders[1].first += 1
  doAssert game.stateHash() != oldHash
  doAssert snapshot.heroes[0].queuedOrders[1].first == x
  hero.queuedOrders[1].first -= 1
  var seen: seq[HeroOrder]
  for tick in 0 ..< 600:
    if hero.hasOrder and (seen.len == 0 or seen[^1] != hero.activeOrder):
      seen.add hero.activeOrder
    game.tickWorld(nil)
    if not hero.hasOrder and hero.queuedOrders.len == 0:
      break
  doAssert seen.len == 3
  doAssert seen[1].second == z + 2 and seen[2].offset == offset
  doAssert not hero.hasOrder and not hero.hasMoveTarget
  let expected = WorldPoint(
    x: (x - mapTiles().int32 div 2) * WorldScale +
      WorldScale div 2 + WorldScale div 4,
    z: (z + 2 - mapTiles().int32 div 2) * WorldScale +
      WorldScale div 2 - WorldScale div 4,
    y: hero.position.y)
  doAssert within(hero.position, expected, 200)

echo "Testing replacements, Stop, death, and queue bounds"
block:
  let
    game = arena()
    hero = game.world.heroes[0]
    x = mapCoordinate(hero.position.x)
    z = mapCoordinate(hero.position.z)
  doAssert game.world.applyQueuedWalkTo(hero.id, x + 2, z)
  doAssert hero.hasOrder and hero.queuedOrders.len == 0
  for i in 0 ..< MaxHeroOrders:
    doAssert game.world.applyQueuedWalkTo(hero.id, x + 3, z)
  doAssert not game.world.applyQueuedWalkTo(hero.id, x + 4, z)
  doAssert hero.queuedOrders.len == MaxHeroOrders
  doAssert game.world.applyWalkTo(hero.id, x - 2, z)
  doAssert hero.queuedOrders.len == 0
  doAssert game.world.applyQueuedAttackMove(hero.id, x + 2, z)
  doAssert game.world.applyStop(hero.id)
  doAssert not hero.hasOrder and hero.queuedOrders.len == 0,
    $hero.activeOrder & " at " & $hero.position
  doAssert game.world.applyQueuedWalkTo(hero.id, x + 2, z)
  doAssert game.world.applyQueuedWalkTo(hero.id, x + 3, z)
  hero.hp = 0
  game.tickWorld(nil)
  doAssert hero.state == Dying
  doAssert not hero.hasOrder and hero.queuedOrders.len == 0

echo "Testing rooted and stunned heroes retain queued orders"
for control in [RootControl, StunControl]:
  let
    game = arena()
    hero = game.world.heroes[0]
    x = mapCoordinate(hero.position.x)
    z = mapCoordinate(hero.position.z)
  hero.controls[control].ends = game.world.tick + 5
  doAssert game.world.applyQueuedWalkTo(hero.id, x + 2, z)
  doAssert hero.queuedOrders.len == 1 and not hero.hasOrder
  for tick in 0 ..< 3:
    game.tickWorld(nil)
    doAssert hero.queuedOrders.len == 1
  game.settle()
  doAssert mapCoordinate(hero.position.x) == x + 2

echo "Testing attack completion, denies, and stale-target skipping"
block:
  let
    game = arena()
    hero = game.world.heroes[0]
    x = mapCoordinate(hero.position.x)
    z = mapCoordinate(hero.position.z)
  game.addCreep(1000)
  game.addCreep(1001, allied = true, dx = -WorldScale)
  game.addCreep(1002, dx = 2 * WorldScale)
  doAssert game.world.applyQueuedAttackTarget(hero.id, 1000)
  doAssert game.world.applyQueuedAttackTarget(hero.id, 1001)
  doAssert game.world.applyQueuedAttackTarget(hero.id, 1002)
  doAssert game.world.applyQueuedWalkTo(hero.id, x + 2, z + 2)
  game.world.footmen[2].hp = 0
  game.world.footmen[2].state = Dying
  game.settle()
  doAssert game.world.footmanById(1000).hp <= 0
  doAssert game.world.footmanById(1001).hp <= 0
  doAssert hero.attacksLanded == 2
  doAssert mapCoordinate(hero.position.z) == z + 2

echo "Testing healed denies are skipped before the next move"
block:
  let
    game = arena()
    hero = game.world.heroes[0]
    x = mapCoordinate(hero.position.x)
    z = mapCoordinate(hero.position.z)
  game.addCreep(1000, allied = true)
  doAssert game.world.applyWalkTo(hero.id, x - 1, z)
  doAssert game.world.applyQueuedAttackTarget(hero.id, 1000)
  doAssert game.world.applyQueuedWalkTo(hero.id, x - 2, z)
  game.world.footmen[0].hp = FootmanHp div 2
  game.settle()
  doAssert hero.attacksLanded == 0
  doAssert mapCoordinate(hero.position.x) == x - 2

echo "Testing attack-move resumes its original destination after a chase"
block:
  let
    game = arena()
    hero = game.world.heroes[0]
    x = mapCoordinate(hero.position.x)
    z = mapCoordinate(hero.position.z)
  hero.class = VanguardKnight
  hero.refreshHeroStats()
  game.addCreep(1000, dx = 3 * WorldScale)
  doAssert game.world.applyAttackMove(hero.id, x + 6, z)
  doAssert game.world.applyQueuedWalkTo(hero.id, x + 6, z + 2)
  game.settle()
  doAssert hero.attacksLanded == 1
  doAssert mapCoordinate(hero.position.x) == x + 6
  doAssert mapCoordinate(hero.position.z) == z + 2

echo "Testing spells replace old paths and allow newly appended movement"
block:
  let
    game = arena()
    hero = game.world.heroes[0]
    x = mapCoordinate(hero.position.x)
    z = mapCoordinate(hero.position.z)
  hero.class = VanguardKnight
  hero.abilityLevels = [1'i32, 1, 1, 1]
  hero.charges = [1'i32, 1, 1, 1]
  hero.mana = 10_000
  hero.maxMana = 10_000
  hero.hp -= 20
  doAssert game.world.applyWalkTo(hero.id, x + 2, z)
  doAssert game.world.applyQueuedWalkTo(hero.id, x + 3, z)
  doAssert game.world.applyCastTarget(hero.id, PassiveAbility.ord.int32,
    hero.id), $hero.lastActionError
  doAssert not hero.hasOrder and hero.queuedOrders.len == 0
  doAssert game.world.applyQueuedWalkTo(hero.id, x - 2, z)
  doAssert hero.queuedOrders.len == 1
  game.settle()
  doAssert mapCoordinate(hero.position.x) == x - 2

echo "Testing lost routes discard unreachable orders instead of stalling"
block:
  let
    game = arena()
    hero = game.world.heroes[0]
    x = mapCoordinate(hero.position.x)
    z = mapCoordinate(hero.position.z)
  doAssert game.world.applyWalkTo(hero.id, x + 2, z)
  doAssert game.world.applyQueuedWalkTo(hero.id, x + 3, z)
  for floor in game.world.occupancy.mitems:
    for cell in floor.mitems:
      cell = 1
  inc game.world.navigationRevision
  game.tickWorld(nil)
  doAssert not hero.hasOrder and not hero.hasMoveTarget
  doAssert hero.queuedOrders.len == 0

echo "Testing replay and multiplayer preserve queues without synthetic inputs"
block:
  let
    local = arena()
    remote = arena()
    playback = arena()
    hero = local.world.heroes[0]
    x = mapCoordinate(hero.position.x)
    z = mapCoordinate(hero.position.z)
    actions = [
      ReplayAction(heroId: hero.id, kind: ActionQueueWalkTo,
        first: x + 2, second: z),
      ReplayAction(heroId: hero.id, kind: ActionQueueAttackMove,
        first: x + 2, second: z + 2),
      ReplayAction(heroId: hero.id, kind: ActionQueueAttackTarget,
        first: 1000),
      ReplayAction(heroId: hero.id, kind: ActionQueueWalkTo,
        first: x, second: z + 2)]
  local.addCreep(1000, dx = -WorldScale)
  remote.addCreep(1000, dx = -WorldScale)
  playback.addCreep(1000, dx = -WorldScale)
  remote.networked = true
  local.recorder = initReplayRecorder(local.currentSetup(1000))
  for action in actions:
    doAssert local.submitAction(action)
    let decoded = decodeSubmission(
      GameSubmission(action: action).encodeSubmission())
    doAssert decoded.action == action
    remote.networkActions.add decoded.action
  doAssert local.recorder.data.actions.len == actions.len
  let tape = decodeReplay(encodeReplay(local.recorder.data))
  doAssert tape.actions == @actions
  for action in tape.actions:
    doAssert playback.world.applyReplayAction(action)
  for tick in 0 ..< 500:
    local.tickWorld(nil)
    remote.tickWorld(nil)
    playback.tickWorld(nil)
    doAssert local.stateHash() == remote.stateHash()
    doAssert local.stateHash() == playback.stateHash()
    if not hero.hasOrder and hero.queuedOrders.len == 0:
      break
  doAssert not hero.hasOrder and hero.queuedOrders.len == 0,
    $hero.activeOrder & " at " & $hero.position & " queued=" &
      $hero.queuedOrders.len & " tick=" & $local.world.tick
  doAssert local.recorder.data.actions.len == actions.len

echo "PASS authoritative hero order queues"
