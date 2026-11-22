import
  std/[json, os, tempfiles],
  jsony,
  ../[common, maps, sim]

echo "Testing persistent destruction and relationships"
block:
  let directory = createTempDir("monster-violence-save-", "")
  defer:
    removeDir(directory)
  let path = directory / "world.json"
  var world = newWorld(generateMap())
  world.sources[0].destroyed = true
  world.sources[0].amount = 0
  world.households[0].integrity = 0
  world.households[0].stock = default(Inventory)
  world.households[0].fuel = 0
  world.villages[1].health = 0
  world.villages[1].stock = default(Inventory)
  world.villagers[0].trust = 72
  world.villagers[0].fearLevel = 8
  world.villagers[1].trust = 0
  world.villagers[1].fearLevel = 95
  world.villagers[1].fear = 9
  let before = world.toJson()
  world.saveWorld(path)
  doAssert world.toJson() == before
  let document = parseJson(readFile(path))
  doAssert document["version"].getInt() == 8
  var restored = newWorld(generateMap())
  restored.restoreWorld(path)
  doAssert restored.sources[0].destroyed
  doAssert restored.sources[0].amount == 0
  doAssert restored.households[0].integrity == 0
  doAssert restored.villages[1].health == 0
  doAssert restored.villagers[0].trust == 72
  doAssert restored.villagers[0].fearLevel == 8
  doAssert restored.villagers[1].trust == 0
  doAssert restored.villagers[1].fearLevel == 95
  doAssert restored.villagers[1].fear == 9

  let previous = restored.toJson()
  for field in ["trust", "fearLevel"]:
    for value in [-1'f, 101'f, NaN.float32, Inf.float32, NegInf.float32]:
      let broken = parseJson($document)
      broken["villagers"][0][field] = %value
      writeFile(path, $broken)
      var rejected = false
      try:
        restored.restoreWorld(path)
      except MonsterError:
        rejected = true
      doAssert rejected, field & " must remain finite and bounded."
      doAssert restored.toJson() == previous
    for invalid in ["missing", "null", "text"]:
      let broken = parseJson($document)
      case invalid
      of "missing": broken["villagers"][0].delete(field)
      of "null": broken["villagers"][0][field] = newJNull()
      else: broken["villagers"][0][field] = %"invalid"
      writeFile(path, $broken)
      var rejected = false
      try:
        restored.restoreWorld(path)
      except MonsterError:
        rejected = true
      doAssert rejected, "New saves require explicit " & field & "."
      doAssert restored.toJson() == previous
  for invalid in ["missing", "null", "text", "stock"]:
    let broken = parseJson($document)
    case invalid
    of "missing": broken["sources"][0].delete("destroyed")
    of "null": broken["sources"][0]["destroyed"] = newJNull()
    of "text": broken["sources"][0]["destroyed"] = %"true"
    else: broken["sources"][0]["amount"] = %1
    writeFile(path, $broken)
    var rejected = false
    try:
      restored.restoreWorld(path)
    except MonsterError:
      rejected = true
    doAssert rejected, "Destroyed supplies must be explicit and empty."
    doAssert restored.toJson() == previous

  let old = parseJson($document)
  old["version"] = %7
  for person in old["villagers"]:
    person.delete("trust")
    person.delete("fearLevel")
  for source in old["sources"]:
    source.delete("destroyed")
  writeFile(path, $old)
  restored.restoreWorld(path)
  doAssert not restored.sources[0].destroyed,
    "An exhausted old resource source is not retroactively destroyed."
  doAssert restored.villagers[0].trust == 0
  doAssert restored.villagers[0].fearLevel == InitialFear
  doAssert restored.villagers[1].fearLevel == 80,
    "A resident already fleeing remembers danger after migration."
  doAssert restored.villagers[1].fear == 9

echo "Testing sleeping survivors after losing their home"
block:
  let directory = createTempDir("monster-survivor-save-", "")
  defer:
    removeDir(directory)
  let path = directory / "world.json"
  var world = newWorld(generateMap())
  world.households[0].integrity = 0
  world.households[0].stock = default(Inventory)
  world.households[0].fuel = 0
  world.villagers[0].position = world.villages[0].position
  world.villagers[0].sleeping = true
  world.villagers[0].fear = 0
  world.saveWorld(path)
  var restored = newWorld(generateMap())
  restored.restoreWorld(path)
  doAssert restored.villagers[0].sleeping
  doAssert restored.villagers[0].target == world.villages[0].id
  world.villages[0].health = 0
  world.villages[0].stock = default(Inventory)
  world.saveWorld(path)
  restored.restoreWorld(path)
  doAssert restored.villagers[0].sleeping
  doAssert restored.villagers[0].target == world.villagers[0].id

echo "Monster destruction and relationship saves passed"
