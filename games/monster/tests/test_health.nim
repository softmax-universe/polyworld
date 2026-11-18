import
  std/[json, os, tempfiles],
  jsony,
  ../[common, maps, sim]

echo "Testing creature and village hall health"
block:
  let directory = createTempDir("monster-health-", "")
  defer:
    removeDir(directory)
  let path = directory / "world.json"
  var world = newWorld(generateMap())
  doAssert world.creature.health == 100
  for village in world.villages:
    doAssert village.health == 100
  world.creature.health = 37.5'f
  world.creature.energy = 62
  world.villages[0].health = 0
  world.villages[1].health = 45
  world.households[0].integrity = 28
  world.villagers[0].health = 65
  world.tick = 1200
  let before = world.toJson()
  world.saveWorld(path)
  doAssert world.toJson() == before,
    "Saving health does not mutate the running simulation."
  let document = parseJson(readFile(path))
  doAssert document["version"].getInt() == 8
  doAssert document["creature"]["health"].getFloat() == 37.5
  var restored = newWorld(generateMap())
  restored.restoreWorld(path)
  doAssert restored.creature.health == world.creature.health
  doAssert restored.creature.energy == world.creature.energy
  for i, village in world.villages:
    doAssert restored.villages[i].health == village.health
  doAssert restored.households[0].integrity == 28
  doAssert restored.villagers[0].health == 65
  doAssert restored.tick == world.tick
  restored.creature.health = 0
  restored.saveWorld(path)
  world.restoreWorld(path)
  doAssert world.creature.health == 0,
    "Explicit zero health survives loading instead of becoming full health."
  doAssert world.creature.energy == 62,
    "Health is independent of energy."

  let legacy = parseJson($document)
  legacy["version"] = %6
  legacy["creature"].delete("health")
  for village in legacy["villages"]:
    village.delete("health")
  writeFile(path, $legacy)
  restored.restoreWorld(path)
  doAssert restored.creature.health == 100
  for village in restored.villages:
    doAssert village.health == 100,
      "Old saves begin with healthy halls rather than absent-field zeros."
  doAssert restored.creature.energy == 62
  doAssert restored.households[0].integrity == 28
  doAssert restored.villagers[0].health == 65
  doAssert restored.tick == 1200

  let previous = restored.toJson()
  for entity in ["creature", "village"]:
    for invalid in ["missing", "null", "type"]:
      let
        broken = parseJson($document)
        owner = if entity == "creature": broken["creature"]
          else: broken["villages"][1]
      case invalid
      of "missing": owner.delete("health")
      of "null": owner["health"] = newJNull()
      else: owner["health"] = %"invalid"
      writeFile(path, $broken)
      var rejected = false
      try:
        restored.restoreWorld(path)
      except MonsterError:
        rejected = true
      doAssert rejected, entity & " health must be explicitly numeric."
      doAssert restored.toJson() == previous,
        "Invalid health must not partially replace the live world."
    for value in [-1'f, 101'f, NaN.float32, Inf.float32, NegInf.float32]:
      let
        broken = parseJson($document)
        owner = if entity == "creature": broken["creature"]
          else: broken["villages"][1]
      owner["health"] = %value
      writeFile(path, $broken)
      var rejected = false
      try:
        restored.restoreWorld(path)
      except MonsterError:
        rejected = true
      doAssert rejected, entity & " health must stay finite and within bounds."
      doAssert restored.toJson() == previous

echo "Monster creature and village hall health passed"
