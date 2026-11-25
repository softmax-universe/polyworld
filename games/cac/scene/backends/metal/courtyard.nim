## Metal rendering for the shared courtyard geometry and Shady stages.

import std/os
import pixie, vmath
import polyworld/[nightskies, backends/metal/common]
import ../../../paths
import ../../[courtyardgeometry, courtyardmaterials, courtyardshaders, ring]
export courtyardmaterials

const ShadowSize = 2048

type
  CourtyardRenderer* = object
    material*: CourtyardMaterial
    lamps*: array[2, Vec3]
    program, skyProgram, depthProgram: MetalProgram
    vertices: MetalBuffer
    normalMap: MetalTexture
    shadows: array[2, RenderTarget]
    lightMatrices: array[2, Mat4]
    commonCount, backdropCount, centerCount: int
    playerCount: int
    arenaRadius, balconyLampRadius, balconyLampHalfAngle: float32
    shadowsReady: bool

proc initCourtyardRenderer*(mesh: CourtyardMesh, playerCount = 2,
    arenaRadius = 0.0'f, balconyLampRadius = 0.0'f,
    balconyLampHalfAngle = 0.0'f): CourtyardRenderer =
  ## Uploads the deterministic stone mesh and prepares its material pipelines.
  result.playerCount = playerCount
  result.arenaRadius = arenaRadius
  result.balconyLampRadius = balconyLampRadius
  result.balconyLampHalfAngle = balconyLampHalfAngle
  result.lamps = [vec3(-6.75, 1.25, -6.32), vec3(6.75, 1.25, -6.32)]
  result.commonCount = mesh.commonCount
  result.backdropCount = mesh.backdropCount
  result.centerCount = mesh.centerCount
  result.material = defaultCourtyardMaterial()
  let layout = VertexLayout(stride: 12 * sizeof(float32), attributes: @[
    VertexAttribute(name: "position", format: Float3, offset: 0),
    VertexAttribute(name: "normal", format: Float3, offset: 3 * sizeof(float32)),
    VertexAttribute(name: "color", format: Float3, offset: 6 * sizeof(float32)),
    VertexAttribute(name: "material", format: Float1, offset: 9 * sizeof(float32)),
    VertexAttribute(name: "uv", format: Float2, offset: 10 * sizeof(float32))
  ])
  result.program = newProgram(CourtyardVertexSource, CourtyardFragmentSource,
    layout)
  result.depthProgram = newProgram(CourtyardDepthVertexSource,
    CourtyardDepthFragmentSource, layout)
  result.skyProgram = newProgram(NightSkyVertexSource, NightSkyFragmentSource)
  var vertices = newSeqOfCap[float32](mesh.vertices.len * 12)
  for vertex in mesh.vertices:
    vertices.add [vertex.position.x, vertex.position.y, vertex.position.z,
      vertex.normal.x, vertex.normal.y, vertex.normal.z,
      vertex.color.x, vertex.color.y, vertex.color.z, vertex.material,
      vertex.uv.x, vertex.uv.y]
  result.vertices = newBuffer(vertices)
  result.normalMap = newTexture(readImage(
    artworkRoot() / "battlefield/textures/stone-slab-normal.png"),
    linear = true, repeat = true, mipmaps = true)
  for seat in 0 .. 1:
    let
      side = if seat == 0: 1.0'f else: -1.0'f
      light = normalize(vec3(-0.48'f * side, 0.85, 0.35'f * side))
      extent = max(18.0'f, arenaRadius + 3.0'f)
      distance = if arenaRadius > 0: extent * 2 else: 35.0'f
      farPlane = if arenaRadius > 0: max(70.0'f, extent * 4) else: 70.0'f
    result.lightMatrices[seat] = ortho(-extent, extent, -extent, extent,
      1.0'f, farPlane) * lookAt(light * distance, vec3(0), vec3(0, 1, 0))
    result.shadows[seat] = newRenderTarget(ShadowSize, ShadowSize,
      color = false, depth = true)

proc initCourtyardRenderer*(playerCount = 2): CourtyardRenderer =
  ## Builds and uploads the courtyard appropriate for the seat count.
  if playerCount > 2:
    let layout = buildMultiplayerLayout(playerCount)
    result = initCourtyardRenderer(buildMultiplayerCourtyardMesh(layout),
      playerCount, layout.outerRadius, layout.lampRadius, layout.lampHalfAngle)
  else:
    result = initCourtyardRenderer(buildCourtyardMesh(), playerCount)

proc bakeShadows(renderer: var CourtyardRenderer) =
  ## Bakes both static camera directions once on the first active frame.
  if renderer.shadowsReady:
    return
  for seat in 0 .. 1:
    pushTarget(renderer.shadows[seat])
    clearDepth()
    renderer.depthProgram.setUniform("lightMatrix", renderer.lightMatrices[seat])
    let state = DrawState(depthTest: true, depthWrite: true)
    draw(renderer.depthProgram, renderer.vertices, renderer.commonCount, state)
    draw(renderer.depthProgram, renderer.vertices, renderer.backdropCount,
      state, first = renderer.commonCount + seat * renderer.backdropCount)
    popTarget()
  renderer.shadowsReady = true

proc dispose*(renderer: var CourtyardRenderer) =
  ## Releases the battlefield resources before a layout replaces it.
  destroy(renderer.program)
  destroy(renderer.skyProgram)
  destroy(renderer.depthProgram)
  destroy(renderer.vertices)
  destroy(renderer.normalMap)
  for target in renderer.shadows:
    destroy(target)
  renderer = CourtyardRenderer()

proc drawSky*(renderer: CourtyardRenderer, viewProjection: Mat4,
    cameraEye: Vec3, time: float32, brightness = 1.0'f) =
  ## Draws the far sky while leaving scene depth available for occlusion.
  renderer.skyProgram.setUniform("inverseViewProjection", viewProjection.inverse)
  renderer.skyProgram.setUniform("cameraEye", cameraEye)
  renderer.skyProgram.setUniform("time", time)
  renderer.skyProgram.setUniform("skyBrightness", brightness)
  draw(renderer.skyProgram, nil, 3,
    DrawState(depthTest: true, depthWrite: false, depthCompare: LessEqual))

proc draw*(renderer: var CourtyardRenderer, viewProjection: Mat4,
    cameraEye: Vec3, time, cameraSide: float32,
    normalsOnly = false, normalView = mat4(), stageYaw = 0.0'f) =
  ## Draws the fixed island and rotating balconies in their lighting frames.
  renderer.bakeShadows()
  let
    seat = if cameraSide > 0: 0 else: 1
    program = renderer.program
    state = DrawState(depthTest: true, depthWrite: not normalsOnly,
      depthCompare: if normalsOnly: Equal else: Less)
  program.setUniform("viewProjection", viewProjection)
  # Native Metal textures start at the top left, including sun depth maps.
  program.setUniform("lightMatrix",
    scale(vec3(1, -1, 1)) * renderer.lightMatrices[seat])
  program.setUniform("cameraEye", cameraEye)
  program.setUniform("time", time)
  program.setUniform("cameraSide", cameraSide)
  program.setUniform("normalStrength", renderer.material.normalStrength)
  program.setUniform("lampIntensity", renderer.material.lampIntensity)
  program.setUniform("firstLamp", renderer.lamps[0] * vec3(1, 1, cameraSide))
  program.setUniform("secondLamp", renderer.lamps[1] * vec3(1, 1, cameraSide))
  program.setUniform("playerCount", renderer.playerCount.int32)
  program.setUniform("arenaRadius", renderer.arenaRadius)
  program.setUniform("balconyLampRadius", renderer.balconyLampRadius)
  program.setUniform("balconyLampHalfAngle", renderer.balconyLampHalfAngle)
  program.setUniform("slopeBroad", renderer.material.slopeBroad)
  program.setUniform("scaleBroad", renderer.material.scaleBroad)
  program.setUniform("normalsOnly", normalsOnly)
  program.setUniform("normalView", normalView)
  program.bindTexture("shadowMap", renderer.shadows[seat].depth)
  program.bindTexture("stoneNormalMap", renderer.normalMap)
  program.setUniform("stageYaw", stageYaw)
  draw(program, renderer.vertices, renderer.centerCount, state)
  let
    stage = stageRotation(stageYaw)
    stageEye = (stage.inverse * vec4(cameraEye, 1)).xyz
  program.setUniform("viewProjection", viewProjection * stage)
  program.setUniform("normalView", normalView * stage)
  program.setUniform("cameraEye", stageEye)
  program.setUniform("stageYaw", 0.0'f)
  draw(program, renderer.vertices, renderer.commonCount - renderer.centerCount,
    state, first = renderer.centerCount)
  draw(program, renderer.vertices, renderer.backdropCount, state,
    first = renderer.commonCount + seat * renderer.backdropCount)
