## Existing fort pillars render every physically closed tile; no new art.
import std/os
import opengl, pixie, vmath, windy
import polyworld/assets as terrainassets
import polyworld/[pathing, quadterrain, viewers]
import ../[assets, content, graphics, maps, replays, sim]

let window = newWindow("GotA preparation gates", ivec2(1000, 700), visible = false)
window.makeContextCurrent()
loadExtensions()
let arena = generateMap(2026)
let game = newGame(arena, 240, 10, false, ReplayData())
while game.world.phase == Drafting:
  var classId = 0'i32
  while not game.world.heroAvailable(classId): inc classId
  doAssert game.world.applyDraft(game.world.draftHeroId(), classId)
let before = game.stateHash()
let gates = preparationGatePlacements(game, 0)
doAssert gates.len == arena.preparationGates.len and gates.len > 0
var counts: array[Team, int]
for i, gate in gates:
  let tile = arena.preparationGates[i]
  let center = tileCenter(tile.layer, tile.x, tile.z)
  doAssert gate.position.x == center.x and gate.position.z == center.z
  doAssert not navigationOpen(tile.layer, tile.x, tile.z)
  inc counts[gate.team]
doAssert counts[RedTeam] > 0 and counts[BlueTeam] > 0
doAssert game.stateHash() == before
for team in Team:
  let teamGates = game.preparationGatePlacements(team.ord.int32 + 1)
  doAssert teamGates.len > 0
  for gate in teamGates:
    doAssert game.world.visible(team, WorldPoint(
      x: int32(gate.position.x * WorldScale.float32),
      z: int32(gate.position.z * WorldScale.float32)))
let savedVision = game.world.teamVisible
for team in 0 .. 1:
  game.world.teamVisible[team] = newSeq[uint8](savedVision[team].len)
  doAssert game.preparationGatePlacements(team.int32 + 1).len == 0,
    "Unseen gates and their retained shadow/reflection casters must disappear together"
game.world.teamVisible = savedVision
initTerrain(treeStyle = NoTrees, rockStyle = NoRocks, terrainStyle = GeneratedTerrain,
  settings = TerrainAssets(size: 256))
var packs: array[Team, PropPack]
for team in Team:
  packs[team] = loadPropPack(fortModelPaths(team.ord), textured = true,
    textureSize = FortTextureSize, mergeNodes = true)
let focus = gates[0].position
let vp = perspective(45'f32, 1000'f32 / 700, 0.1'f32, 100'f32) *
  lookAt(focus + vec3(6, 7, 8), focus + vec3(0, 1, 0), vec3(0, 1, 0))
var fb, tex, depth: GLuint
glGenFramebuffers(1, fb.addr)
glGenTextures(1, tex.addr)
glBindTexture(GL_TEXTURE_2D, tex)
glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.GLint, 1000, 700, 0, GL_RGBA, GL_UNSIGNED_BYTE, nil)
glBindFramebuffer(GL_FRAMEBUFFER, fb)
glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0)
glGenRenderbuffers(1, depth.addr)
glBindRenderbuffer(GL_RENDERBUFFER, depth)
glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, 1000, 700)
glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depth)
doAssert glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE
proc render(): Image =
  glViewport(0, 0, 1000, 700)
  glClearColor(0.05, 0.06, 0.09, 0)
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
  packs.drawPreparationGates(game.preparationGatePlacements(0), vp)
  result = newImage(1000, 700)
  glReadPixels(0, 0, 1000, 700, GL_RGBA, GL_UNSIGNED_BYTE, result.data[0].addr)
  result.flipVertical()
let closed = render()
var ink = 0
for pixel in closed.data:
  if pixel.a > 0: inc ink
doAssert ink > 1000
closed.writeFile(getEnv("GOTA_GATE_FIXTURE", getTempDir() / "gota-preparation-gates.png"))
doAssert game.stateHash() == before
for tick in 0 ..< PreparationTicks: game.tickWorld(nil)
doAssert game.preparationGatePlacements(0).len == 0
let opened = render()
for pixel in opened.data: doAssert pixel.a == 0
window.close()
echo "PASS native gate props: both teams, exact occupied centers, unchanged simulation hash, disappear on opening; pixels=", ink
