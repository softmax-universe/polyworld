## Runs real Metal depth, cutout, comparison, and pass-restoration checks.

import
  pixie, shady, vmath, windy,
  polyworld/shadows,
  polyworld/backends/metal/[common, textures]

when not defined(useMetal4):
  {.error: "Compile this rendering test with -d:useMetal4.".}

type ShadowTestError = object of CatchableError

var
  testShadowMap: Uniform[Sampler2dShadow]
  testShadowMatrix: Uniform[Mat4]

proc receiverVert(
  gl_Position: var Vec4, worldPosition: var Vec3, position: Vec2
) =
  ## Covers the output while keeping world coordinates for shadow lookup.
  gl_Position = vec4(position.x, position.y, 0, 1)
  worldPosition = vec3(position.x, position.y, 0.5)

proc receiverFrag(fragColor: var Vec4, worldPosition: Vec3) =
  ## Visualizes the actual comparison sample in receiver coordinates.
  let
    projected = testShadowMatrix * vec4(worldPosition, 1)
    lit = texture(testShadowMap, vec3(
      projected.x * 0.5'f + 0.5'f,
      projected.y * 0.5'f + 0.5'f,
      projected.z * 0.5'f + 0.5'f
    ))
  fragColor = vec4(lit, lit, lit, 1)

proc checkShadows() =
  ## Verifies real depth textures, both sun steps, and alpha-cutout holes.
  let window = newWindow(
    "Metal shadow check", ivec2(64, 64), visible = false, vsync = false
  )
  defer: window.close()
  initMetal(window)
  defer: shutdownMetal()
  let
    receiver = newProgram(
      toShader(receiverVert, metalMSL, shaderVertex),
      toShader(receiverFrag, metalMSL, shaderFragment),
      VertexLayout(stride: sizeof(Vec2), attributes: @[
        VertexAttribute(name: "position", format: Float2, offset: 0)
      ])
    )
    receiverVertices = newBuffer([
      vec2(-1, -1), vec2(3, -1), vec2(-1, 3)
    ])
  defer:
    destroy(receiver)
    destroy(receiverVertices)

  initUnshadowedShadows()
  beginFrame(64, 64, color(1, 0, 0, 1))
  receiver.bindTexture("testShadowMap", sunShadowTextures[0])
  receiver.setUniform("testShadowMatrix", mat4(1))
  draw(receiver, receiverVertices, 3)
  let unshadowed = captureImage()
  doAssert unshadowed[32, 32].r >= 250
  closeUnshadowedShadows()

  # Resource setup also works before the first explicit frame begins.
  initSunShadows()
  defer: closeSunShadows()
  sunLightMvp0 = mat4(1)
  sunLightMvp1 = mat4(1)
  sunShadowBlend = 0.5'f
  let
    casterVertices = newBuffer([
      -0.8'f, 0.2, 0, 0, 0, 0,
      0.8'f, 0.2, 0, 1, 0, 0,
      0.8'f, 0.8, 0, 1, 1, 0,
      -0.8'f, 0.2, 0, 0, 0, 0,
      0.8'f, 0.8, 0, 1, 1, 0,
      -0.8'f, 0.8, 0, 0, 1, 0
    ])
    cutoutImage = newImage(2, 1)
  cutoutImage[0, 0] = rgbx(255, 255, 255, 255)
  cutoutImage[1, 0] = rgbx(0, 0, 0, 0)
  var cutout = createTextureArray(@[@[cutoutImage]], repeat = false)
  defer:
    destroy(casterVertices)
    deleteTexture(cutout)
  sunDepthProgramId().setVertexLayout(VertexLayout(
    stride: 6 * sizeof(float32), attributes: @[
      VertexAttribute(name: "vertPos", format: Float3, offset: 0)
    ]
  ))
  beginFrame(64, 64, color(1, 0, 0, 1))
  let callerTarget = metalRenderer.target
  var passCount = 0
  sunDepthPasses(window.size):
    inc passCount
    if sunPassIndex == 0:
      bindSunDepth(sunDepthPassMvp())
      draw(sunDepthProgramId(), casterVertices, 6,
        DrawState(depthTest: true, depthWrite: true))
    else:
      bindSunCutoutDepth(sunDepthPassMvp(), 0.5'f)
      sunBindCutoutTexture(cutout)
      draw(sunCutoutProgramId(), casterVertices, 6,
        DrawState(depthTest: true, depthWrite: true))
  doAssert passCount == 2
  doAssert metalRenderer.target == callerTarget

  for step in 0 .. 1:
    beginFrame(64, 64, color(1, 0, 0, 1))
    receiver.bindTexture("testShadowMap", sunShadowTextures[step])
    receiver.setUniform("testShadowMatrix", sunShadowMvp(step))
    draw(receiver, receiverVertices, 3)
    let output = captureImage()
    doAssert output[16, 16].r < 5, "Opaque caster must cast a shadow"
    doAssert output[16, 48].r >= 250, "Shadow coordinates must keep Y correct"
    if step == 0:
      doAssert output[48, 16].r < 5, "Plain caster must keep its right half"
    else:
      doAssert output[48, 16].r >= 250, "Cutout hole must pass light"
    echo "Metal shadow step ", step, " passed comparison and Y checks"

  beginFrame(64, 64, color(0, 0, 0, 1))
  var interrupted = false
  try:
    sunDepthPasses(window.size):
      raise newException(ShadowTestError, "Interrupted shadow pass")
  except ShadowTestError:
    interrupted = true
  doAssert interrupted
  doAssert metalRenderer.target == callerTarget
  endFrame(false)
  echo "Metal shadow depths, alpha cutouts, and target restoration passed"

checkShadows()
