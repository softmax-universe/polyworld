## Fixtures that repurpose opening halls still need real registered hall sites.
import ../[sim, content]

proc retainFixtureHalls*(w: World) =
  for owner in 0'i32 ..< w.players.len.int32:
    var hasHall = false
    for b in w.buildings:
      if b.owner == owner and b.kind == TownHallBuilding and b.state != BuildingDying:
        hasHall = true
    if hasHall: continue
    var worker = NoEntity
    for u in w.units:
      if u.owner == owner and u.kind == PeonUnit:
        worker = u.id
        break
    doAssert worker != NoEntity
    let gold = w.players[owner].gold
    let wood = w.players[owner].wood
    w.players[owner].gold = max(gold, BuildingTable[TownHallBuilding].gold)
    w.players[owner].wood = max(wood, BuildingTable[TownHallBuilding].wood)
    var placed = false
    for y in 1'i32 ..< w.map.side - 5:
      for x in 1'i32 ..< w.map.side - 5:
        if w.canPlace(owner, TownHallBuilding, x, y, worker):
          doAssert w.applyBuild(owner, worker, TownHallBuilding.ord.int32, x, y)
          doAssert w.applyCancel(owner, worker)
          placed = true
          break
      if placed: break
    doAssert placed
    w.players[owner].gold = gold
    w.players[owner].wood = wood
