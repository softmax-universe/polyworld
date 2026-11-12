## Native real-tick -> production emission/draw -> GPU projectile regression.
## Force recompilation: the graphics procedures are extracted with staticRead.
import std/[macros, tables, math]
import opengl, vmath, windy
import polyworld/particles as particlefx
import polyworld/particleshaders
import ../[rendervisibility, assets]
import trafficfixture

const Size = 256
let window = newWindow("LvD incoming projectiles", ivec2(Size, Size),
  visible = false, vsync = false)
window.makeContextCurrent()
loadExtensions()
var framebuffer, texture: GLuint
glGenFramebuffers(1, framebuffer.addr)
glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
glGenTextures(1, texture.addr)
glBindTexture(GL_TEXTURE_2D, texture)
glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.GLint, Size, Size, 0,
  GL_RGBA, GL_UNSIGNED_BYTE, nil)
glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0)
doAssert glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE
let world = trafficFixture(0, "open").world
let run = Game(world: world)
var viewMode = 1'i32
var particles = initParticleSystem()
var currentSight: seq[uint8]
proc mapHalf(): float32 = world.map.side.float32 / 2
proc renderPoint(u: Unit): Vec3 =
  vec3(toFloat32(u.body.pos.x) - mapHalf(), 0, toFloat32(u.body.pos.y) - mapHalf())
proc buildingCentre(b: Building): Vec3 =
  vec3(b.origin.x.float32 + b.footprint.width.float32 / 2 - mapHalf(), 0,
    b.origin.y.float32 + b.footprint.depth.float32 / 2 - mapHalf())
proc shownUnit(u: Unit): bool = world.renderUnitVisible(viewMode, u)
proc shownBuilding(b: Building): bool = world.renderBuildingVisible(viewMode, b)
var buildingArt: tuple[heights: array[BuildingKind, float32]]
buildingArt.heights[TowerBuilding] = 3
# Top-down orthographic view makes each pixel's fog tile unambiguous.
let viewProjection = ortho(-8'f32, 8'f32, -8'f32, 8'f32, 0.1'f32, 100'f32) *
  lookAt(vec3(0, 30, 0), vec3(0, 0, 0), vec3(0, 0, -1))
let barCameraRight = vec3(1, 0, 0)
let barCameraUp = vec3(0, 0, -1)
let cameraForward = vec3(0, -1, 0)
macro productionCombat(): untyped =
  result = newStmtList()
  for node in parseStmt(staticRead("../graphics.nim")):
    if node.kind == nnkProcDef and node[0].repr == "runGraphics*":
      for child in node[^1]:
        if child.kind == nnkProcDef and child[0].repr in
            ["particleTargetPosition", "expectedTowerTargets", "emitTickParticles"]:
          result.add child
macro productionDraw(): untyped =
  proc find(n: NimNode): NimNode =
    if n.kind in {nnkCall, nnkCommand} and n.len > 0 and
        n[0].repr == "particles.drawParticles": return n
    for c in n:
      let found = find(c)
      if found != nil: return found
  result = find(parseStmt(staticRead("../graphics.nim")))
  if result == nil: error("Missing production particle draw")
productionCombat()

proc draw(): tuple[visible, hidden: int] =
  currentSight = world.renderVisibilityValues(viewMode, CurrentSightMask)
  let hashBefore = run.stateHash()
  glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
  glViewport(0, 0, Size, Size)
  glClearColor(0, 0, 0, 1)
  glClear(GL_COLOR_BUFFER_BIT)
  productionDraw()
  var pixels = newSeq[uint8](Size * Size * 4)
  glReadPixels(0, 0, Size, Size, GL_RGBA, GL_UNSIGNED_BYTE, pixels[0].addr)
  for y in 0 ..< Size:
    for x in 0 ..< Size:
      let i = (y * Size + x) * 4
      if pixels[i] == 0 and pixels[i+1] == 0 and pixels[i+2] == 0: continue
      let tx = int32(floor(mapHalf() - 8 + (x.float32 + 0.5'f32) / Size.float32 * 16))
      let ty = int32(floor(mapHalf() + 8 - (y.float32 + 0.5'f32) / Size.float32 * 16))
      if world.renderTileVisible(viewMode, tx, ty): inc result.visible
      else: inc result.hidden
  doAssert glGetError() == GL_NO_ERROR
  doAssert run.stateHash() == hashBefore

# A real tower shot from beyond the victim's sight, into that owned victim.
# Reuse a valid building ID/lookup slot while leaving both town halls intact.
var towerIndex = -1
for i, b in world.buildings:
  if b.kind == GoldMineBuilding: towerIndex = i
world.buildings[towerIndex].kind = TowerBuilding
world.buildings[towerIndex].owner = 1
world.buildings[towerIndex].origin = tile2(34, 39)
world.buildings[towerIndex].footprint = BuildingTable[TowerBuilding].footprint
let victimId = world.spawnUnit(0, PeonUnit, tile2(41, 40))
let victim = world.units[world.unitIndex(victimId)]
world.rebuildVision()
doAssert not shownBuilding(world.buildings[towerIndex])
let initialHp = victim.hp
for tick in 0 ..< 4:
  var old: Table[int32, int32]
  for u in world.units: old[u.id] = u.cooldown
  let targets = expectedTowerTargets()
  world.tickWorld(nil)
  let hashBeforeEmission = run.stateHash()
  emitTickParticles(old, targets)
  doAssert run.stateHash() == hashBeforeEmission
  if victim.hp < initialHp: break
doAssert victim.hp < initialHp, "Fixture must execute an authoritative tower strike"
particles.advanceParticles(0.36'f32)
let incoming = draw()
echo "real hidden tower -> own visible victim: ", incoming
doAssert incoming.visible > 10, "Incoming fireball must draw inside current sight despite hidden source"
doAssert incoming.hidden == 0, "Enemy fireball fragments must not leak through fog"

# Existing effects obey current sight every frame, including paused frames.
for stamp in world.visibleStamp[0].mitems: stamp = 0
let hidden = draw()
doAssert hidden == (0, 0)
# Existing upstream owner exception is intentional; do not revert it.
viewMode = 2
let own = draw()
doAssert own.visible + own.hidden > 10
viewMode = 0
let omniscient = draw()
doAssert omniscient.visible > 10
# Actual ranged attack transition uses the same emission path, independently
# of whether the source remains visible when the visual reaches the victim.
particles.clearParticles()
viewMode = 1
world.buildings[towerIndex].cooldown = 100
let rangedId = world.spawnUnit(1, ArcherUnit, tile2(37, 40))
let ranged = world.units[world.unitIndex(rangedId)]
world.rebuildVision()
doAssert world.applyAttack(1, rangedId, victimId)
let beforeRanged = victim.hp
for tick in 0 ..< 80:
  var old: Table[int32, int32]
  for u in world.units: old[u.id] = u.cooldown
  let targets = expectedTowerTargets()
  world.tickWorld(nil)
  # Model source reveal expiring or LOS changing before presentation. Keep
  # just the victim-side strip; this must not suppress the entire arrow.
  for y in 0'i32 ..< world.map.side:
    for x in 0'i32 ..< world.map.side:
      world.visibleStamp[0][world.map.tileIndex(x, y)] =
        if x >= 40 and x <= 42 and y >= 39 and y <= 41:
          world.visionGeneration[0]
        else: 0
  let hashBeforeEmission = run.stateHash()
  emitTickParticles(old, targets)
  doAssert run.stateHash() == hashBeforeEmission
  if victim.hp < beforeRanged: break
doAssert victim.hp < beforeRanged
particles.advanceParticles(0.22'f32)
let arrow = draw()
echo "real ranged shot -> narrow current sight: ", arrow
doAssert arrow.visible > 0 and arrow.hidden == 0

# Test edge clipping independent of emission: even a one-cell island of sight
# must retain fireball pixels, while every other projected fragment is removed.
particles.clearParticles()
particles.emitParticleProjectile(Fireball, FireBurst,
  vec3(-5, 2, 0.5'f32), vec3(1.5'f32, 1, 0.5'f32), 0.5'f32, owner = 1)
particles.advanceParticles(0.46'f32)
for stamp in world.visibleStamp[0].mitems: stamp = 0
world.visibleStamp[0][world.map.tileIndex(41, 40)] = world.visionGeneration[0]
let island = draw()
echo "fireball one-cell sight edge: ", island
doAssert island.visible > 0 and island.hidden == 0
# Sight loss immediately removes the retained flight and delayed impact.
for stamp in world.visibleStamp[0].mitems: stamp = 0
doAssert draw() == (0, 0)
particles.advanceParticles(0.24'f32)
doAssert draw() == (0, 0)
world.visibleStamp[0][world.map.tileIndex(41, 40)] = world.visionGeneration[0]
let impact = draw()
echo "fireball impact one-cell sight: ", impact
doAssert impact.visible > 0 and impact.hidden == 0

# Real own-tower fire still emits when its enemy victim is outside sight:
# ownership is the newer upstream policy, not a new global fog bypass.
particles.clearParticles()
world.units.setLen(0)
for slot in world.unitSlot.mitems: slot = -1
for cell in world.occupancy.mitems: cell = 0
world.buildings[towerIndex].owner = 0
world.buildings[towerIndex].cooldown = 0
let enemyId = world.spawnUnit(1, PeonUnit, tile2(41, 40))
let enemy = world.units[world.unitIndex(enemyId)]
let enemyHp = enemy.hp
for tick in 0 ..< 4:
  var old: Table[int32, int32]
  for u in world.units: old[u.id] = u.cooldown
  let targets = expectedTowerTargets()
  world.tickWorld(nil)
  for stamp in world.visibleStamp[0].mitems: stamp = 0
  let hashBeforeEmission = run.stateHash()
  emitTickParticles(old, targets)
  doAssert run.stateHash() == hashBeforeEmission
  if enemy.hp < enemyHp: break
doAssert enemy.hp < enemyHp
particles.advanceParticles(0.36'f32)
let ownTower = draw()
echo "real own tower with hidden victim: ", ownTower
doAssert ownTower.hidden > 10
viewMode = 0
doAssert draw().visible > 10
particles.closeParticles()
window.close()
echo "Native production combat emission/current-sight projectile pixels passed"
