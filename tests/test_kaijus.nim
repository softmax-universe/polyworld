import
  std/[math, os],
  gltf, vmath,
  polyworld/kaijus

proc checkGeometry(root: Node): int =
  ## Checks every generated triangle for finite coordinates and unit normals.
  for child in root.walkNodes():
    if child.mesh == nil:
      continue
    for mesh in child.mesh.primitives:
      doAssert mesh.material != nil
      doAssert mesh.points.len == mesh.normals.len
      doAssert mesh.points.len mod 3 == 0
      for i in 0 ..< mesh.points.len:
        for component in [mesh.points[i].x, mesh.points[i].y, mesh.points[i].z]:
          doAssert classify(component) notin {fcNan, fcInf, fcNegInf}
        doAssert abs(length(mesh.normals[i]) - 1) < 0.001
      for i in countup(0, mesh.points.len - 3, 3):
        let normal = cross(
          mesh.points[i + 1] - mesh.points[i],
          mesh.points[i + 2] - mesh.points[i]
        )
        doAssert length(normal) > 0.000001
        doAssert dot(normal, mesh.normals[i]) > 0,
          child.name & " has an inverted normal at vertex " & $i
      if mesh.material.name == "Spikes":
        var volume = 0.0'f
        for i in countup(0, mesh.points.len - 3, 3):
          volume += dot(mesh.points[i],
            cross(mesh.points[i + 1], mesh.points[i + 2])) / 6
        doAssert volume > 0, child.name & " must have outward winding."
      result += mesh.points.len div 3

proc checkFiles(settings: KaijuSettings) =
  ## Verifies recipe round trips, malformed inputs, and a real GLB reload.
  let directory = getTempDir() / "polyworld-kaijugen-tests"
  createDir(directory)
  defer:
    removeDir(directory)
  settings.saveKaiju(directory / "recipe.json")
  doAssert loadKaiju(directory / "recipe.json") == settings
  writeFile(directory / "defaults.json", "{}")
  doAssert loadKaiju(directory / "defaults.json") == classicKaiju()
  for contents in ["{", "{\"headSize\":100}", "{\"head\":\"Unknown\"}"]:
    writeFile(directory / "invalid.json", contents)
    var rejected = false
    try:
      discard loadKaiju(directory / "invalid.json")
    except KaijugenError:
      rejected = true
    doAssert rejected
  settings.exportKaiju(directory / "kaiju.glb")
  let loaded = readGltfFile(directory / "kaiju.glb")
  doAssert loaded.root.hasGeometry()
  var names: seq[string]
  for child in loaded.root.walkNodes():
    names.add child.name
  for name in ["Head_Classic", "Eyes_Fierce", "Tail"]:
    doAssert name in names

echo "Testing modular kaiju geometry"
block:
  let
    settings = classicKaiju()
    root = generateKaiju(settings)
    triangles = checkGeometry(root)
  doAssert triangles > 1000 and triangles < 30000
  doAssert root.nodes.len == 4
  doAssert root["Head_Classic"] != nil
  doAssert root["Head_Classic"]["Eyes_Fierce"] != nil
  let bounds = root.getAABounds()
  doAssert bounds.min.y >= -0.011
  doAssert bounds.max.y > 4.0
  doAssert bounds.min.z < -2.8
  echo "Classic kaiju: ", triangles, " triangles"

echo "Testing proportion limits and palette edits"
block:
  for size in [0.75'f, 1.25'f]:
    var settings = classicKaiju()
    settings.headSize = size
    settings.eyeSize = size
    settings.tailLength = size
    settings.spikeSize = if size < 1: 0.4 else: 1.5
    settings.facets = if size < 1: 0 else: 1
    discard checkGeometry(generateKaiju(settings))
  var settings = classicKaiju()
  let materials = kaijuMaterials(settings)
  settings.colors[KaijuColor.Skin] = vec3(0.1, 0.3, 0.9)
  materials.tint(settings)
  doAssert materials[KaijuColor.Skin].baseColorFactor.b == 0.9'f
  for invalid in [-1.0'f, 0.0'f, 3.0'f, NaN.float32, Inf.float32]:
    settings.headSize = invalid
    var rejected = false
    try:
      settings.validate()
    except KaijugenError:
      rejected = true
    doAssert rejected

echo "Testing recipe persistence and GLB export"
checkFiles(classicKaiju())
echo "Kaijugen tests passed"
