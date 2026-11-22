## Default-config combat: real registered buildings, no forced war or vision.
import std/unittest
import ../[content, multiplayer, presets, sim]

proc arena(players = 2): World =
  result = newLocalMatch(defaultConfig(players), newSeq[string](players)).world
  result.maximumTicks = 10000
  for player in result.players.mitems:
    player.gold = 20000
    player.wood = 20000

proc structure(w: World, owner: int32, kind: BuildingKind, x, y: int32): int32 =
  # Farm and tower have the same footprint. Register via the authoritative
  # build API; the fixture completes it without waiting for remote builders.
  var builder = NoEntity
  for u in w.units:
    if u.owner == owner and u.kind == PeonUnit:
      builder = u.id
      break
  doAssert w.applyBuild(owner, builder, FarmBuilding.ord.int32, x, y)
  result = w.buildings[^1].id
  doAssert w.applyCancel(owner, builder)
  let i = w.buildingIndex(result)
  w.buildings[i].kind = kind
  w.buildings[i].state = BuildingComplete
  w.buildings[i].hp = BuildingTable[kind].hp
  w.buildings[i].maxHp = BuildingTable[kind].hp

proc run(w: World, ticks: int) =
  for _ in 0 ..< ticks: w.tickWorld(nil)

suite "Attack-move siege":
  test "nearer hostile structure beats farther hostile unit":
    let w = arena()
    let c = w.map.side div 2
    let farm = w.structure(1, FarmBuilding, c + 2, c)
    let soldier = w.spawnUnit(0, SoldierUnit, tile2(c, c))
    let decoy = w.spawnUnit(1, PeonUnit, tile2(c - 4, c))
    doAssert w.applyCancel(1, decoy)
    w.rebuildVision()
    doAssert w.buildingVisible(0, w.buildings[w.buildingIndex(farm)])
    doAssert w.visible(0, w.units[w.unitIndex(decoy)].tile)
    doAssert w.applyAttackMove(0, soldier, c + 7, c)
    w.run(AcquireStagger.int)
    check w.units[w.unitIndex(soldier)].targetId == farm

  test "closer unit wins and equal distance resolves by global entity ID":
    for gap in [1'i32, 2'i32]:
      let w = arena()
      let c = w.map.side div 2
      let farm = w.structure(1, FarmBuilding, c + 2, c)
      let soldier = w.spawnUnit(0, SoldierUnit, tile2(c, c))
      let enemy = w.spawnUnit(1, PeonUnit, tile2(c - gap, c))
      doAssert w.applyCancel(1, enemy)
      w.rebuildVision()
      doAssert w.applyAttackMove(0, soldier, c + 7, c)
      # Stop exactly at the acquisition tick, before chasing alters distances.
      while (w.tick + soldier) mod AcquireStagger != AcquireStagger - 1:
        w.tickWorld(nil)
      w.tickWorld(nil)
      check w.units[w.unitIndex(soldier)].targetId == (if gap == 1: enemy else: farm)

  test "hidden and nonhostile buildings are ineligible":
    for allied in [false, true]:
      let w = arena()
      let c = w.map.side div 2
      let farm = w.structure(1, FarmBuilding, c + (if allied: 2 else: 9), c)
      let soldier = w.spawnUnit(0, SoldierUnit, tile2(c, c))
      if allied:
        w.diplomacy.pairs[w.diplomacy.pairIndex(0, 1)].state = Allied
      w.rebuildVision()
      if not allied: check not w.buildingVisible(0, w.buildings[w.buildingIndex(farm)])
      doAssert w.applyAttackMove(0, soldier, c - 8, c)
      w.run(AcquireStagger.int)
      check w.units[w.unitIndex(soldier)].targetId == NoEntity
      check w.buildings[w.buildingIndex(farm)].hp == BuildingTable[FarmBuilding].hp

  test "Bomber sees farther than towers and kills sequentially at standoff":
    let w = arena()
    let c = w.map.side div 2
    let first = w.structure(1, TowerBuilding, c + 2, c)
    let second = w.structure(1, TowerBuilding, c + 8, c)
    let bomber = w.spawnUnit(0, CatapultUnit, tile2(c - 8, c))
    let unit = w.units[w.unitIndex(bomber)]
    check unitOf(0, CatapultUnit).sightTiles > BuildingTable[TowerBuilding].sightTiles
    check unitOf(0, CatapultUnit).rangeTiles > BuildingTable[TowerBuilding].rangeTiles
    w.rebuildVision()
    check w.buildingVisible(0, w.buildings[w.buildingIndex(first)])
    doAssert w.applyAttackMove(0, bomber, c + 14, c)
    var firstDead = false
    var secondDead = false
    var shotFirst = false
    var shotSecond = false
    for tick in 0 ..< 2400:
      w.tickWorld(nil)
      check unit.hp == unitOf(0, CatapultUnit).hp
      if w.entityAlive(first):
        let b = w.buildings[w.buildingIndex(first)]
        if b.hp < b.maxHp:
          shotFirst = true
          check tileDistance(unit.tile, b.origin) > BuildingTable[TowerBuilding].rangeTiles
        check w.buildings[w.buildingIndex(second)].hp == BuildingTable[TowerBuilding].hp
      else: firstDead = true
      if firstDead and w.entityAlive(second):
        let b = w.buildings[w.buildingIndex(second)]
        if b.hp < b.maxHp:
          shotSecond = true
          check tileDistance(unit.tile, b.origin) > BuildingTable[TowerBuilding].rangeTiles
      elif firstDead: secondDead = true
      if secondDead and unit.tile.x >= c + 12: break
    check shotFirst and shotSecond and firstDead and secondDead
    check unit.tile.x >= c + 12

suite "Ranged retaliation vision":
  test "every ranged roster source reveals on shots but melee does not":
    for owner in 0'i32 .. 1'i32:
      for kind in UnitKind:
        if kind == PeonUnit: continue
        let w = arena()
        let c = w.map.side div 2
        let attacker = w.spawnUnit(owner, kind, tile2(c, c))
        let victim = w.spawnUnit(1 - owner, PeonUnit, tile2(c + 1, c))
        w.units[w.unitIndex(victim)].hp = 10000
        doAssert w.applyCancel(1 - owner, victim)
        w.rebuildVision()
        doAssert w.applyAttack(owner, attacker, victim)
        for tick in 0 ..< 20:
          w.tickWorld(nil)
          if w.units[w.unitIndex(attacker)].cooldown > 0: break
        check w.units[w.unitIndex(attacker)].cooldown > 0
        if unitOf(owner, kind).rangeTiles > 1:
          require w.rangedReveals.len == 1
          check w.rangedReveals[0].sourceId == attacker
          check w.rangedReveals[0].recipient == 1 - owner
          check w.rangedReveals[0].expiresTick == w.tick + RangedRevealTicks
        else:
          check w.rangedReveals.len == 0

  test "refresh, exact expiry, alliance changes and snapshot hash isolation":
    let w = arena(4)
    let c = w.map.side div 2
    let tower = w.structure(1, TowerBuilding, c + 6, c)
    let victim = w.spawnUnit(0, PeonUnit, tile2(c, c))
    w.units[w.unitIndex(victim)].hp = 10000
    doAssert w.applyCancel(0, victim)
    let alliance = w.diplomacy.pairIndex(0, 2)
    w.diplomacy.pairs[alliance].state = Allied
    w.rebuildVision()
    check not w.visible(2, c + 7, c)
    w.run(TowerStagger.int)
    require w.rangedReveals.len == 1
    let originalExpiry = w.rangedReveals[0].expiresTick
    check w.visible(0, c + 7, c)
    check w.visible(2, c + 7, c)
    check not w.visible(3, c + 7, c)
    let snapshot = w.clone()
    let baseline = Game(world: snapshot).stateHash()
    w.rangedReveals[0].expiresTick += 1
    check Game(world: w).stateHash() != baseline
    check Game(world: snapshot).stateHash() == baseline
    w.restore(snapshot)
    check Game(world: w).stateHash() == baseline
    w.run(BuildingTable[TowerBuilding].cooldownTicks.int + TowerStagger.int)
    require w.rangedReveals.len == 1
    check w.rangedReveals[0].expiresTick > originalExpiry
    w.diplomacy.pairs[alliance].state = Neutral
    w.tickWorld(nil)
    check not w.visible(2, c + 7, c)
    w.diplomacy.pairs[alliance].state = Allied
    w.tickWorld(nil)
    check w.visible(2, c + 7, c)
    let expiry = w.rangedReveals[0].expiresTick
    # Silence the source after a real shot; no more refreshes.
    w.buildings[w.buildingIndex(tower)].cooldown = RangedRevealTicks * 10
    while w.tick < expiry - 1: w.tickWorld(nil)
    check w.visible(0, c + 7, c)
    check w.visible(2, c + 7, c)
    w.tickWorld(nil)
    check w.rangedReveals.len == 0
    check not w.visible(0, c + 7, c)
    check not w.visible(2, c + 7, c)
    check w.explored(0, c + 7, c)

  test "near tower fires but far tower does not reveal or fire":
    for gap in [3'i32, 9'i32]:
      let w = arena()
      let c = w.map.side div 2
      let tower = w.structure(1, TowerBuilding, c + gap, c)
      let victim = w.spawnUnit(0, PeonUnit, tile2(c, c))
      doAssert w.applyCancel(0, victim)
      w.rebuildVision()
      w.run(40)
      if gap <= BuildingTable[TowerBuilding].rangeTiles:
        check w.units[w.unitIndex(victim)].hp < unitOf(0, PeonUnit).hp
        check w.rangedReveals.len == 1
      else:
        check w.units[w.unitIndex(victim)].hp == unitOf(0, PeonUnit).hp
        check w.rangedReveals.len == 0
        check w.buildings[w.buildingIndex(tower)].cooldown == 0
        check not w.buildingVisible(0, w.buildings[w.buildingIndex(tower)])

  test "missed ranged shots still reveal and idle cooldown does not refresh":
    let w = arena()
    let c = w.map.side div 2
    let attacker = w.spawnUnit(0, ArcherUnit, tile2(c, c))
    let victim = w.spawnUnit(1, PeonUnit, tile2(c + 4, c))
    w.units[w.unitIndex(victim)].hp = 10000
    doAssert w.applyCancel(1, victim)
    w.rebuildVision()
    doAssert w.applyAttack(0, attacker, victim)
    var sawMiss = false
    for tick in 0 ..< 1000:
      let hp = w.units[w.unitIndex(victim)].hp
      w.tickWorld(nil)
      if w.units[w.unitIndex(attacker)].cooldown == unitOf(0, ArcherUnit).cooldownTicks:
        require w.rangedReveals.len == 1
        check w.rangedReveals[0].expiresTick == w.tick + RangedRevealTicks
        if hp == w.units[w.unitIndex(victim)].hp:
          sawMiss = true
          let expiry = w.rangedReveals[0].expiresTick
          w.tickWorld(nil)
          check w.rangedReveals[0].expiresTick == expiry
          break
    check sawMiss

  test "hidden firing tower reveals its footprint and small area immediately":
    let w = arena()
    let c = w.map.side div 2
    let tower = w.structure(1, TowerBuilding, c + 6, c)
    let victim = w.spawnUnit(0, PeonUnit, tile2(c, c))
    doAssert w.applyCancel(0, victim)
    w.rebuildVision()
    check not w.buildingVisible(0, w.buildings[w.buildingIndex(tower)])
    let hp = w.units[w.unitIndex(victim)].hp
    for tick in 0 ..< TowerStagger: w.tickWorld(nil)
    check w.units[w.unitIndex(victim)].hp < hp
    check w.buildingVisible(0, w.buildings[w.buildingIndex(tower)])
    check w.visible(0, c + 9, c)
    check not w.visible(0, c + 10, c)
    doAssert w.applyMove(0, victim, c - 10, c)
    w.run(180)
    check not w.buildingVisible(0, w.buildings[w.buildingIndex(tower)])
