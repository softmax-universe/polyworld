## Explicit cargo delivery uses the authoritative automatic-trip machinery.
import ../[content, maps, sim]

type Fixture = object
  world: World
  unit: Unit
  hall, mill: int32

proc arena(w: World, x, y: int32): Tile2 =
  ## Addresses an open area in the map centre.
  tile2(w.map.side div 2 + x, w.map.side div 2 + y)

proc fixture(): Fixture =
  ## Creates two owned depots through normal building registration.
  let w = newWorld(generateMap(DefaultSeed), TickRate * 120)
  result.world = w
  result.unit = w.units[0]
  for y in -10'i32 .. 10'i32:
    for x in -10'i32 .. 10'i32:
      let tile = w.arena(x, y)
      doAssert w.terrainOpen(tile.x.int32, tile.y.int32)
      w.blocker[w.map.tileIndex(tile)] = 0
      w.treeWood[w.map.tileIndex(tile)] = 0
  for i in 0 ..< w.buildings.len:
    if w.buildings[i].kind == TownHallBuilding and w.buildings[i].owner == 0:
      result.hall = w.buildings[i].id
      for cell in w.blocker.mitems:
        if cell == result.hall: cell = 0
      w.buildings[i].origin = w.arena(-6, 0)
      w.buildings[i].footprint = (1'i32, 1'i32)
      w.blocker[w.map.tileIndex(w.buildings[i].origin)] = result.hall
      break
  doAssert result.hall != NoEntity
  w.place(result.unit, w.arena(0, 0))
  w.players[0].gold = 5000
  w.players[0].wood = 5000
  let site = w.arena(6, 0)
  doAssert w.applyBuild(0, result.unit.id, LumberMillBuilding.ord.int32,
    site.x.int32, site.y.int32)
  for structure in w.buildings.mitems:
    if structure.owner == 0 and structure.kind == LumberMillBuilding:
      result.mill = structure.id
      structure.state = BuildingComplete
      structure.hp = structure.maxHp
  doAssert result.mill != NoEntity
  doAssert w.applyCancel(0, result.unit.id)

proc finishDelivery(f: Fixture) =
  ## Advances actual movement and deposit ticks until cargo is empty.
  for tick in 0 ..< TickRate * 40:
    f.world.tickWorld(nil)
    if f.unit.carryGold == 0 and f.unit.carryWood == 0: return
  doAssert false, "Cargo delivery did not finish"

for wood in [false, true]:
  for mill in [false, true]:
    let f = fixture()
    let target = if mill: f.mill else: f.hall
    if wood: f.unit.carryWood = 37
    else: f.unit.carryGold = 37
    let before = Game(world: f.world).stateHash()
    if mill and not wood:
      doAssert not f.world.canDeposit(0, f.unit.id, target)
      doAssert not f.world.applyDeposit(0, f.unit.id, target)
      doAssert Game(world: f.world).stateHash() == before
      continue
    let gold = f.world.players[0].gold
    let timber = f.world.players[0].wood
    doAssert f.world.canDeposit(0, f.unit.id, target)
    doAssert f.world.applyDeposit(0, f.unit.id, target)
    doAssert f.unit.targetId == target
    f.finishDelivery()
    doAssert f.world.players[0].gold == gold + (if wood: 0 else: 37)
    doAssert f.world.players[0].wood == timber + (if wood: 37 else: 0)
    doAssert f.unit.state == UnitIdle
    let after = (f.world.players[0].gold, f.world.players[0].wood)
    for tick in 0 ..< TickRate: f.world.tickWorld(nil)
    doAssert (f.world.players[0].gold, f.world.players[0].wood) == after

echo "Town halls accept both resources; mills accept only wood"

block selectedDepotWins:
  let f = fixture()
  f.world.place(f.unit, f.world.arena(-4, 0))
  f.unit.carryWood = 19
  doAssert f.world.nearestDropOff(0, f.unit.tile, true) == f.hall
  doAssert f.world.applyDeposit(0, f.unit.id, f.mill)
  doAssert f.unit.targetId == f.mill
  f.finishDelivery()
  let depot = f.world.buildings[f.world.buildingIndex(f.mill)]
  doAssert adjacentToFootprint(depot.origin, depot.footprint,
    f.unit.tile.x.int32, f.unit.tile.y.int32)

echo "Delivery honors the clicked depot instead of the nearest"

block mixedCargo:
  let f = fixture()
  f.unit.carryGold = 17
  f.unit.carryWood = 23
  let gold = f.world.players[0].gold
  let wood = f.world.players[0].wood
  doAssert f.world.applyDeposit(0, f.unit.id, f.mill)
  var unloadedWood = false
  for tick in 0 ..< TickRate * 40:
    f.world.tickWorld(nil)
    if f.unit.carryWood == 0:
      unloadedWood = true
      break
  doAssert unloadedWood
  doAssert f.world.players[0].gold == gold
  doAssert f.world.players[0].wood == wood + 23
  doAssert f.unit.carryGold == 17
  doAssert f.unit.targetId == f.hall
  f.finishDelivery()
  doAssert f.world.players[0].gold == gold + 17

echo "Mixed cargo never credits gold to a lumber mill"

block invalidOrdersPreserveState:
  for invalid in 0 .. 7:
    let f = fixture()
    let index = f.world.buildingIndex(f.hall)
    f.unit.carryGold = 13
    case invalid
    of 0: f.world.buildings[index].state = BuildingUnderConstruction
    of 1: f.world.buildings[index].state = BuildingDying
    of 2: f.world.buildings[index].owner = 1
    of 3: f.world.buildings[index].hp = 0
    of 4: f.unit.owner = 1
    of 5: f.unit.kind = SoldierUnit
    of 6: f.unit.state = UnitInMine
    else: f.unit.carryGold = 0
    let before = Game(world: f.world).stateHash()
    doAssert not f.world.canDeposit(0, f.unit.id, f.hall)
    doAssert not f.world.applyDeposit(0, f.unit.id, f.hall)
    doAssert Game(world: f.world).stateHash() == before

echo "Invalid deliveries preserve orders, cargo and resources"

block depotRevalidation:
  for invalid in 0 .. 2:
    for duringDeposit in [false, true]:
      let f = fixture()
      f.unit.carryWood = 21
      let wood = f.world.players[0].wood
      doAssert f.world.applyDeposit(0, f.unit.id, f.mill)
      if duringDeposit:
        for tick in 0 ..< TickRate * 40:
          f.world.tickWorld(nil)
          if f.unit.state == UnitDepositWood: break
        doAssert f.unit.state == UnitDepositWood
      let index = f.world.buildingIndex(f.mill)
      case invalid
      of 0: f.world.buildings[index].state = BuildingUnderConstruction
      of 1: f.world.buildings[index].state = BuildingDying
      else: f.world.buildings[index].owner = 1
      f.world.tickWorld(nil)
      doAssert f.world.players[0].wood == wood
      doAssert f.unit.carryWood == 21
      f.finishDelivery()
      doAssert f.world.players[0].wood == wood + 21

echo "Depots are revalidated en route and before crediting cargo"

block preservesHarvestAssignment:
  let f = fixture()
  var mine = NoEntity
  for structure in f.world.buildings:
    if structure.kind == GoldMineBuilding:
      mine = structure.id
      break
  doAssert mine != NoEntity
  f.unit.carryGold = 11
  f.unit.sourceId = mine
  doAssert f.world.applyDeposit(0, f.unit.id, f.hall)
  f.finishDelivery()
  doAssert f.unit.sourceId == mine
  doAssert f.unit.state == UnitToMine

block queuedDeliveryAndSuccessor:
  let f = fixture()
  f.unit.carryWood = 29
  let waypoint = f.world.arena(1, 0)
  let destination = f.world.arena(0, 4)
  doAssert f.world.applyMove(0, f.unit.id, waypoint.x.int32, waypoint.y.int32)
  doAssert f.world.applyDeposit(0, f.unit.id, f.mill, append = true)
  doAssert f.world.applyMove(0, f.unit.id, destination.x.int32,
    destination.y.int32, append = true)
  doAssert f.unit.orderQueue.len == 2
  f.finishDelivery()
  for tick in 0 ..< TickRate * 40:
    f.world.tickWorld(nil)
    if f.unit.state == UnitIdle and f.unit.orderQueue.len == 0: break
  doAssert f.unit.tile == destination
  doAssert f.unit.orderQueue.len == 0

echo "Harvest jobs resume and queued movement follows delivery"
