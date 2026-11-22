## Idle combat must use real sight, pathing and damage, not just target assignment.
import std/unittest
import trafficfixture

proc run(w: World, ticks: int) =
  for _ in 0 ..< ticks: w.tickWorld(nil)

proc farm(w: World, x, y: int32): int32 =
  let builder = w.spawnUnit(1, PeonUnit, tile2(65, 65))
  w.players[1].gold = 10000
  w.players[1].wood = 10000
  doAssert w.applyBuild(1, builder, FarmBuilding.ord.int32, x, y)
  result = w.buildings[^1].id
  doAssert w.applyCancel(1, builder)
  w.buildings[^1].state = BuildingComplete
  w.buildings[^1].hp = BuildingTable[FarmBuilding].hp
  w.buildings[^1].maxHp = BuildingTable[FarmBuilding].hp

suite "Idle military combat":
  test "uncommanded soldier approaches and damages a unit or structure":
    for building in [false, true]:
      let w = trafficFixture(0, "open").world
      let id = w.spawnUnit(0, SoldierUnit, tile2(40, 30))
      let u = w.units[w.unitIndex(id)]
      let target = if building: w.farm(44, 30)
                   else: w.spawnUnit(1, SoldierUnit, tile2(44, 30))
      if not building: w.units[w.unitIndex(target)].holdPosition = true
      let hp = if building: w.buildings[w.buildingIndex(target)].hp
               else: w.units[w.unitIndex(target)].hp
      let start = u.body.pos
      w.rebuildVision()
      doAssert unitOf(0, SoldierUnit).rangeTiles < 4
      doAssert unitOf(0, SoldierUnit).sightTiles >= 4
      w.run(TickRate.int * 5)
      check u.body.pos != start
      check u.targetId == target
      check u.state == UnitAttacking
      check (if building: w.buildings[w.buildingIndex(target)].hp
             else: w.units[w.unitIndex(target)].hp) < hp

  test "finished move releases idle combat without diverting the active move":
    let w = trafficFixture(0, "open").world
    let id = w.spawnUnit(0, SoldierUnit, tile2(38, 30))
    let target = w.spawnUnit(1, SoldierUnit, tile2(44, 30))
    let u = w.units[w.unitIndex(id)]
    let enemy = w.units[w.unitIndex(target)]
    enemy.holdPosition = true
    let hp = enemy.hp
    w.rebuildVision()
    doAssert w.applyMove(0, id, 40, 30)
    var arrived = false
    for _ in 0 ..< TickRate.int * 5:
      w.tickWorld(nil)
      if u.state == UnitIdle:
        arrived = true
        break
      check u.state == UnitMoving
      check u.targetId == NoEntity
      check enemy.hp == hp
    require arrived
    check not u.holdPosition
    w.run(TickRate.int * 5)
    check u.targetId == target
    check enemy.hp < hp

  test "idle melee retaliates against a visible shooter before a closer building":
    let w = trafficFixture(0, "open").world
    let site = w.farm(42, 30)
    let id = w.spawnUnit(0, SoldierUnit, tile2(40, 30))
    let attacker = w.spawnUnit(1, ArcherUnit, tile2(40, 34))
    let u = w.units[w.unitIndex(id)]
    let enemy = w.units[w.unitIndex(attacker)]
    let start = u.body.pos
    let hp = enemy.hp
    w.rebuildVision()
    doAssert w.applyAttack(1, attacker, id)
    # Wait for an actual hit (weapons can miss), then release explicit hold.
    u.holdPosition = true
    for _ in 0 ..< TickRate.int * 4:
      w.tickWorld(nil)
      if u.hp < unitOf(0, SoldierUnit).hp: break
    require u.hp < unitOf(0, SoldierUnit).hp
    u.holdPosition = false
    require u.state == UnitIdle
    w.run(AcquireStagger.int)
    check u.targetId == attacker
    check w.buildings[w.buildingIndex(site)].hp == BuildingTable[FarmBuilding].hp
    w.run(TickRate.int * 3)
    check u.body.pos != start
    check enemy.hp < hp

  test "Shift successors stay ahead of acquisition even under fire":
    let w = trafficFixture(0, "open").world
    let id = w.spawnUnit(0, SoldierUnit, tile2(38, 30))
    let target = w.spawnUnit(1, ArcherUnit, tile2(42, 34))
    let u = w.units[w.unitIndex(id)]
    w.rebuildVision()
    doAssert w.applyAttack(1, target, id)
    doAssert w.applyMove(0, id, 40, 30)
    doAssert w.applyMove(0, id, 44, 30, append = true)
    var first, final = false
    for _ in 0 ..< TickRate.int * 6:
      w.tickWorld(nil)
      check u.targetId == NoEntity
      check u.state in {UnitMoving, UnitIdle}
      if u.state == UnitIdle and u.orderQueue.len == 1: first = true
      if u.state == UnitIdle and u.orderQueue.len == 0:
        final = true
        break
    require first and final
    require u.hp < unitOf(0, SoldierUnit).hp
    w.run(TickRate.int * 2)
    check u.targetId == target

  test "allies, neutral targets, hidden targets and distant visible threats are excluded":
    for scenario in ["allied", "neutral", "hidden", "distant"]:
      let w = trafficFixture(0, "open").world
      let id = w.spawnUnit(0, SoldierUnit, tile2(40, 30))
      let target = w.spawnUnit(1, SoldierUnit,
        tile2((if scenario in ["hidden", "distant"]: 48 else: 44), 30))
      let u = w.units[w.unitIndex(id)]
      let enemy = w.units[w.unitIndex(target)]
      enemy.holdPosition = true
      if scenario == "allied":
        w.diplomacy.pairs[w.diplomacy.pairIndex(0, 1)].state = Allied
      elif scenario == "neutral":
        w.diplomacy.pairs[w.diplomacy.pairIndex(0, 1)].state = Neutral
      elif scenario == "distant":
        discard w.spawnUnit(0, PeonUnit, tile2(48, 28))
        enemy.targetId = id
        enemy.state = UnitAttacking
        enemy.cooldown = 1000
        enemy.repathCooldown = 1000
      w.rebuildVision()
      if scenario == "hidden": check not w.visible(0, enemy.tile)
      if scenario == "distant": check w.visible(0, enemy.tile)
      let start = u.body.pos
      w.run(AcquireStagger.int * 2)
      check u.state == UnitIdle
      check u.targetId == NoEntity
      check u.body.pos == start

  test "explicit hold and idle peons do not auto acquire; Stop clears orders not stance":
    for kind in [PeonUnit, SoldierUnit]:
      let w = trafficFixture(0, "open").world
      let id = w.spawnUnit(0, kind, tile2(40, 30))
      let enemy = w.spawnUnit(1, SoldierUnit, tile2(43, 30))
      w.units[w.unitIndex(enemy)].holdPosition = true
      let u = w.units[w.unitIndex(id)]
      if kind == SoldierUnit: u.holdPosition = true
      w.rebuildVision()
      w.run(TickRate.int)
      check u.state == UnitIdle and u.targetId == NoEntity
      check u.tile == tile2(40, 30)
      doAssert w.applyCancel(0, id)
      check not u.holdPosition
      w.run(TickRate.int)
      if kind == SoldierUnit: check u.targetId == enemy
      else: check u.targetId == NoEntity

  test "equal distance uses stable ID and chase cannot cross solid terrain":
    let w = trafficFixture(0, "open").world
    let id = w.spawnUnit(0, SoldierUnit, tile2(40, 30))
    let first = w.spawnUnit(1, SoldierUnit, tile2(44, 30))
    let second = w.spawnUnit(1, SoldierUnit, tile2(40, 34))
    for target in [first, second]: w.units[w.unitIndex(target)].holdPosition = true
    w.rebuildVision()
    w.run(AcquireStagger.int)
    check w.units[w.unitIndex(id)].targetId == first
    # Enclose the chosen victim in terrain; chase must use ordinary pathing.
    for y in 28'i32 .. 32'i32:
      for x in 42'i32 .. 46'i32:
        if x in [42'i32, 46'i32] or y in [28'i32, 32'i32]:
          w.blocker[w.map.tileIndex(x, y)] = TreeBlocker
    w.run(TickRate.int * 5)
    check w.units[w.unitIndex(first)].hp == unitOf(1, SoldierUnit).hp
    check w.tileOpen(w.units[w.unitIndex(id)].tile)
