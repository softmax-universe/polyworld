## Real Bassy decisions submit last hits and denies through shared commands.
import
  std/[os, strutils, tempfiles],
  bassy,
  polyworld/pathing,
  ../[bots, content, maps, replays, sim]

const
  LegacyPolicy = """
damage = selfAttackDamage
cooldown = selfAttackCooldown
attackRange = selfAttackRange
selectedId = 0
accepted = 0
seenHp = 0
seenMaxHp = 0
for i = 0 to objectCount() - 1
  if objectKind(i) = 3 and objectAlive(i) then
    seenHp = objectHp(i)
    seenMaxHp = objectInfo(i, 2)
    eligible = objectTeam(i) <> selfTeam and denyMode = 0
    if objectTeam(i) = selfTeam and denyMode = 1 then
      eligible = seenHp * 2 < seenMaxHp
    end if
    if eligible and seenHp > 0 and seenHp <= damage then
      selectedId = objectId(i)
    end if
  end if
next i
if forcedId <> 0 then selectedId = forcedId
if selectedId <> 0 then accepted = attackTarget(selectedId)
"""
  StructuredPolicy = """' @gota-structures
damage = self.attackDamage
cooldown = self.attackCooldownTicks
attackRange = self.attackRange
selectedId = 0
accepted = 0
seenHp = 0
seenMaxHp = 0
for i = 0 to match.objectCount - 1
  if objects(i).kind = 3 and objects(i).alive then
    seenHp = objects(i).hp
    seenMaxHp = objects(i).maxHp
    eligible = objects(i).team <> self.team and denyMode = 0
    if objects(i).team = self.team and denyMode = 1 then
      eligible = seenHp * 2 < seenMaxHp
    end if
    if eligible and seenHp > 0 and seenHp <= damage then
      selectedId = objects(i).id
    end if
  end if
next i
if forcedId <> 0 then selectedId = forcedId
if selectedId <> 0 then accepted = attackTarget(selectedId)
"""

proc policyGame(path: string, deny: bool, health = 1'i32): Game =
  ## Isolates one actual policy VM and one visible creep in attack range.
  var preset = defaultConfig()
  preset.roadWidth = 62
  result = newGame(generateMap(2026, preset), 1000, 10, false,
    ReplayData(), drafting = false)
  result.loadBotSources([readFile(path)])
  result.recorder = initReplayRecorder(result.currentSetup(1000), preset)
  let world = result.world
  world.camps.setLen(0)
  world.spawnTimerTicks = 100_000
  world.heroTurnTicks = 100_000
  for hero in world.heroes:
    hero.hp = 0
    hero.state = Dying
    hero.deathTicks = -100_000
  for tower in world.buildings.mitems:
    tower.hp = 0
  let
    hero = world.heroes[0]
    x = mapTiles() * 7 div 16
    z = mapTiles() * 9 div 64
    tile = layers[GroundLayer].tiles[z * mapTiles() + x]
  hero.class = Ranger
  hero.refreshHeroStats()
  hero.hp = hero.maxHp
  hero.state = Marching
  var point = WorldPoint(
    x: (x - mapTiles() div 2).int32 * WorldScale + WorldScale div 2,
    z: (z - mapTiles() div 2).int32 * WorldScale + WorldScale div 2
  )
  for height in tile.tops:
    point.y += height.int32 * WorldScale div 32
  hero.place(point)
  point.x += WorldScale div 2
  var creep = Footman(id: 1000, hp: health,
    team: if deny: hero.team else: Team(1 - hero.team.ord))
  creep.place(point)
  creep.controls[StunControl].ends = 100_000
  world.footmen = @[creep]
  for team in Team:
    for cell in world.teamVisible[team.ord].mitems:
      cell = 255

proc decide(game: Game) =
  ## Runs the real host callbacks and checks script execution succeeded.
  game.runBotDecisions()
  doAssert not game.heroVms[0].failed, game.heroVms[0].lastError

proc finishAttack(game: Game) =
  ## Advances combat until the policy's targeted attack lands lethally.
  for tick in 0 ..< 120:
    game.tickWorld(nil)
    if game.world.footmen[0].hp <= 0:
      return
  doAssert false, "The Bassy-selected target must receive a lethal attack"

let directory = createTempDir("gota-script-last-hits-", "")
try:
  for structured in [false, true]:
    let path = directory / "policy.bas"
    writeFile(path, if structured: StructuredPolicy else: LegacyPolicy)
    echo "Testing real ", (if structured: "structured" else: "legacy"),
      " Bassy last-hit and deny access"
    for deny in [false, true]:
      let
        game = policyGame(path, deny)
        world = game.world
        hero = world.heroes[0]
        vm = game.heroVms[0]
        gold = hero.gold
        xp = hero.totalXp
        cooldown = world.heroAttackCooldown(hero)
      vm.runtime.setGlobal("denyMode", deny.int32)
      game.decide()
      doAssert vm.runtime.getGlobal("seenHp") == 1
      doAssert vm.runtime.getGlobal("seenMaxHp") == FootmanHp
      doAssert vm.runtime.getGlobal("damage") == hero.heroAttackDamage()
      doAssert vm.runtime.getGlobal("cooldown") == cooldown and cooldown > 0
      doAssert vm.runtime.getGlobal("attackRange") > 0
      doAssert vm.runtime.getGlobal("selectedId") == 1000
      doAssert vm.runtime.getGlobal("accepted") != 0
      doAssert hero.attackObjectId == 1000
      doAssert game.recorder.data.actions.len == 1
      let action = game.recorder.data.actions[0]
      doAssert action.kind == ActionAttackTarget and action.heroId == hero.id
      doAssert action.first == 1000, "Commands use IDs, not list indices"
      game.finishAttack()
      if deny:
        doAssert world.denyEffects.len == 1
        doAssert world.denyEffects[0].heroId == hero.id
        doAssert hero.gold == gold and hero.totalXp == xp
      else:
        doAssert world.denyEffects.len == 0
        doAssert hero.gold == gold + 15
        doAssert hero.totalXp == xp + CreepNearbyXp

    block healthyAndHidden:
      let
        game = policyGame(path, false, FootmanHp)
        vm = game.heroVms[0]
      game.decide()
      doAssert vm.runtime.getGlobal("selectedId") == 0
      doAssert game.recorder.data.actions.len == 0
      game.world.footmen[0].hp = 1
      for cell in game.world.teamVisible[RedTeam.ord].mitems:
        cell = 0
      inc game.world.tick
      game.decide()
      doAssert vm.runtime.getGlobal("seenHp") == 0
      doAssert vm.runtime.getGlobal("selectedId") == 0

    block denyBoundary:
      let
        game = policyGame(path, true, FootmanHp div 2)
        vm = game.heroVms[0]
      vm.runtime.setGlobal("denyMode", 1)
      game.decide()
      doAssert vm.runtime.getGlobal("selectedId") == 0
      vm.runtime.setGlobal("forcedId", 1000)
      inc game.world.tick
      game.decide()
      doAssert vm.runtime.getGlobal("accepted") == 0
      doAssert game.world.heroes[0].lastActionError == ActionTargetUnavailable
      doAssert game.world.heroes[0].attackObjectId == 0

    block networkSubmission:
      let
        game = policyGame(path, true)
        hero = game.world.heroes[0]
      game.heroVms[0].runtime.setGlobal("denyMode", 1)
      game.networked = true
      game.decide()
      doAssert game.submissions.len == 1
      doAssert hero.attackObjectId == 0 and game.recorder.data.actions.len == 0
      var action = game.submissions[0].action
      doAssert action.kind == ActionAttackTarget and action.first == 1000
      action.tick = uint32(game.world.tick + 1)
      game.networkActions = @[action]
      game.submissions.setLen(0)
      game.tickWorld(nil)
      doAssert game.actionResults.len == 1 and game.actionResults[0].accepted
      doAssert hero.attackObjectId == 1000
      game.finishAttack()
      doAssert game.world.denyEffects.len == 1

  echo "Testing the documented structured last-hit and deny example"
  let
    root = currentSourcePath().parentDir.parentDir.parentDir.parentDir
    guide = readFile(root / "coworld/gota/guide.md")
    section = guide.split("### Last hits and denies")[1]
    example = section.split("```basic\n")[1].split("```")[0]
    path = directory / "documented.bas"
  writeFile(path, example)
  for deny in [false, true]:
    let game = policyGame(path, deny)
    game.decide()
    doAssert game.world.heroes[0].attackObjectId == 1000
    game.finishAttack()
    doAssert (game.world.denyEffects.len == 1) == deny
finally:
  removeDir(directory)
echo "Bassy last-hit and deny access passed"
