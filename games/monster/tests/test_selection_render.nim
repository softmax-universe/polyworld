import
  std/[os, tempfiles],
  jsony, opengl, silky, vmath, windy,
  polyworld/[assets, rtscameras, viewers],
  ../[common, maps, resources, scenes, selections, sim]

const
  RepositoryRoot = currentSourcePath().parentDir.parentDir.parentDir.parentDir
  ViewSize = vec2(1440, 900)
  CameraDistance = 34'f

proc project(point: Vec3, cameraTarget: Vec3): Vec2 =
  ## Projects fixture geometry through the same perspective as the game.
  let
    eye = rtsCameraEye(cameraTarget, CameraDistance)
    view = lookAt(eye, cameraTarget, vec3(0, 1, 0))
    projection = perspective(RtsFieldOfView, ViewSize.x / ViewSize.y,
      0.1'f, 300'f)
    clip = projection * view * vec4(point, 1)
  doAssert clip.w > 0
  vec2((clip.x / clip.w + 1) * ViewSize.x / 2,
    (1 - clip.y / clip.w) * ViewSize.y / 2)

proc pickNear(
  scene: MonsterScene,
  world: World,
  cameraTarget: Vec3,
  position: Vec2,
  height: float32,
  expected: Selection,
  radius = 16
): Vec2 =
  ## Checks a bounded visible mesh patch rather than an arbitrary joint point.
  let pixel = project(vec3(position.x,
    world.map.groundHeight(position) + height, position.y), cameraTarget)
  for distance in countup(0, radius, 4):
    for dy in countup(-distance, distance, 4):
      for dx in countup(-distance, distance, 4):
        if abs(dx) != distance and abs(dy) != distance:
          continue
        let mouse = pixel + vec2(dx.float32, dy.float32)
        if scene.pickSelectionAt(world, mouse, ViewSize, cameraTarget,
          CameraDistance, 0) == expected:
            return mouse
  doAssert false, "Visible mesh was not selectable: " & expected.id

proc pixelAt(position: Vec2): array[4, uint8] =
  ## Reads a rendered pixel to detect stale intact scenery after destruction.
  glReadPixels(position.x.GLint, (ViewSize.y - position.y - 1).GLint,
    1, 1, GL_RGBA, GL_UNSIGNED_BYTE, result[0].addr)

echo "Testing native Monster mesh selection without a visible window"
block:
  setCurrentDir(RepositoryRoot)
  let
    directory = createTempDir("monster-selection-render-", "")
    atlasPath = directory / "hud.png"
  defer:
    removeDir(directory)
  let builder = newHudAtlas(2048)
  builder.addFont(DefaultFontPath, "WorldName", 32, AsciiGlyphs)
  builder.write(atlasPath)
  let (window, sk) = initGameWindow("Monster selection test", atlasPath,
    ivec2(ViewSize.x.int32, ViewSize.y.int32), vsync = false, visible = false)
  pollEvents()
  defer:
    window.close()
  var world = newWorld(generateMap())
  world.creature.position = vec2(0)
  world.villagers[0].position = vec2(-5, 0)
  let
    cameraTarget = rtsFollowFrame(vec3(0), CameraDistance, 0.23'f)
    scene = newMonsterScene(window, world.map, sk.atlas, sk.atlasTextureId())
  defer:
    scene.close()
  scene.drawScene(window, world, cameraTarget, CameraDistance, 0)
  let before = world.toJson()
  discard scene.pickNear(world, cameraTarget, world.creature.position, 1.3'f,
    world.selectionById("moss"))
  discard scene.pickNear(world, cameraTarget, world.villagers[0].position,
    0.7'f, world.selectionById("ada"))
  discard scene.pickNear(world, cameraTarget, vec2(9, -10), 1.2'f,
    world.selectionById("miller_hut"), radius = 24)
  discard scene.pickNear(world, cameraTarget, vec2(-3, -5), 1.8'f,
    world.selectionById("village"), radius = 24)
  let pine = world.sources[world.sourceIndex("pine")]
  discard scene.pickNear(world, cameraTarget, pine.position + vec2(0.9'f, 0),
    0.2'f, world.selectionById("pine"), radius = 8)
  let home = world.households[world.householdIndex("weaver_hut")]
  discard scene.pickNear(world, cameraTarget,
    home.position + vec2(0.9'f, -0.3'f), 0.2'f,
    world.selectionById("weaver_hut"), radius = 8)
  let empty = vec2(-6, 12)
  let emptyPixel = project(vec3(empty.x,
    world.map.groundHeight(empty), empty.y), cameraTarget)
  doAssert scene.pickSelectionAt(world, emptyPixel, ViewSize, cameraTarget,
    CameraDistance, 0).kind == NoSelection,
    "Empty ground must not select a nearby entity."
  doAssert world.toJson() == before,
    "Picking and drawing must not issue orders or mutate the simulation."

  for resource in [SoftwoodResource, FishResource]:
    world.villagers[0].task = GatherTask
    world.villagers[0].resource = resource
    world.villagers[0].elapsed = 2
    let working = world.toJson()
    scene.drawScene(window, world, cameraTarget, CameraDistance, 0,
      world.selectionById("ada"))
    discard scene.pickNear(world, cameraTarget, world.villagers[0].position,
      0.7'f, world.selectionById("ada"))
    if resource == FishResource:
      let
        person = world.villagers[0]
        rodPixel = project(vec3(person.position.x + 0.2'f,
          world.map.groundHeight(person.position) + 1.15'f,
          person.position.y + 1.3'f), cameraTarget)
      doAssert scene.pickSelectionAt(world, rodPixel, ViewSize, cameraTarget,
        CameraDistance, 0) == world.selectionById("ada"),
        "The fishing rod belongs to the same selected villager."
    doAssert world.toJson() == working,
      "Rendering tools and inspecting workers cannot change their jobs."

  world.villagers[0].position = world.households[0].position
  world.villagers[0].sleeping = true
  world.villagers[0].task = SleepTask
  scene.drawScene(window, world, cameraTarget, CameraDistance, 0)
  discard scene.pickNear(world, cameraTarget, world.villagers[0].position,
    0.4'f, world.selectionById("ada"))

  world.villagers[0].sleeping = false
  world.villagers[0].position = vec2(9, -10)
  let behindHouse = project(vec3(9,
    world.map.groundHeight(vec2(9, -10)) + 0.6'f, -10), cameraTarget)
  doAssert scene.pickSelectionAt(world, behindHouse, ViewSize, cameraTarget,
    CameraDistance, 0) == world.selectionById("miller_hut"),
    "The opaque hut must win over the villager hidden inside it."

  world.villagers[0].position = vec2(-5, 0)
  scene.drawScene(window, world, cameraTarget, CameraDistance, 0)
  let
    hut = world.selectionById("miller_hut")
    roofPixel = scene.pickNear(world, cameraTarget, vec2(9, -10), 2.3'f,
      hut, radius = 8)
    roofColor = pixelAt(roofPixel)
  world.households[0].integrity = 0
  world.villages[0].health = 0
  world.sources[world.sourceIndex("pine")].destroyed = true
  world.sources[world.sourceIndex("pine")].amount = 0
  world.sources[world.sourceIndex("farm")].destroyed = true
  world.sources[world.sourceIndex("farm")].amount = 0
  let ruined = world.toJson()
  scene.drawScene(window, world, cameraTarget, CameraDistance, 0, hut)
  doAssert pixelAt(roofPixel) != roofColor,
    "The intact roof must disappear from the framebuffer when the hut falls."
  doAssert scene.pickSelectionAt(world, roofPixel, ViewSize, cameraTarget,
    CameraDistance, 0) != hut,
    "The old roof must not remain as an invisible pick target."
  discard scene.pickNear(world, cameraTarget, vec2(9, -10), 0.3'f,
    hut, radius = 20)
  discard scene.pickNear(world, cameraTarget, vec2(-3, -5), 0.3'f,
    world.selectionById("village"), radius = 24)
  discard scene.pickNear(world, cameraTarget, pine.position, 0.2'f,
    world.selectionById("pine"), radius = 16)
  discard scene.pickNear(world, cameraTarget, vec2(10, -8), 0.2'f,
    world.selectionById("farm"), radius = 16)
  doAssert world.toJson() == ruined,
    "Drawing and inspecting ruins cannot rebuild or mutate their owners."

echo "Monster native selection passed"
