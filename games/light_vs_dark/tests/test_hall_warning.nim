import std/unittest
import ../[content, maps, sim, hudpresentation]
suite "local no-hall warning":
  test "ceiling seconds local only and disappears for living construction":
    let w = newWorld(generateMap(DefaultSeed), TickRate * 60)
    for b in w.buildings.mitems:
      if b.owner == 0 and b.kind == TownHallBuilding: b.state = BuildingDying
    w.players[0].hallLossDeadline = w.tick + TickRate + 1
    when declared(hallDefeatWarning):
      check w.hallDefeatWarning(1) == "No Town Hall — defeat in 2s"
      check w.hallDefeatWarning(0) == ""
      check w.hallDefeatWarning(2) == ""
      for b in w.buildings.mitems:
        if b.owner == 0 and b.kind == TownHallBuilding: b.state = BuildingUnderConstruction
      check w.hallDefeatWarning(1) == ""
    else:
      check false
