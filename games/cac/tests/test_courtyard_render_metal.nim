## Native Metal rendering regression for the CaC scene and post effects.
## Build with -d:useMetal4; use -d:cacPostLayers to verify diagnostic passes.

import std/[math, os]
import pixie, shady, vmath, windy
import polyworld/backends/metal/common
import ../scene/courtyard
import ../scene/post as postfx

const Width = 640
const Height = 400
let window = newWindow("CaC Metal courtyard regression", ivec2(Width, Height),
  visible = false)
initMetal(window)

proc occluderVertex(position: Vec2, gl_Position: var Vec4) =
  ## Writes a foreground rectangle into the scene depth attachment.
  gl_Position = vec4(position.x, position.y, 0.0'f, 1.0'f)

let
  occluderProgram = newProgram(
    toShader(occluderVertex, metalMSL, shaderVertex), "",
    VertexLayout(stride: sizeof(Vec2), attributes: @[
      VertexAttribute(name: "position", format: Float2, offset: 0)
    ])
  )
  occluderVertices = newBuffer([
    vec2(-0.1, -0.1), vec2(0.1, -0.1), vec2(0.1, 0.1),
    vec2(-0.1, -0.1), vec2(0.1, 0.1), vec2(-0.1, 0.1)
  ])
  eye = vec3(0, 12.05, 13.08)
  view = lookAt(eye, eye + vec3(0, -sin(0.7659'f), -cos(0.7659'f)), vec3(0, 1, 0))
  projection = perspective(42.0'f, Width.float32 / Height, 0.1'f, 100.0'f)
  vp = projection * view
var effects = initPostFx()
effects.settings.enabled = true
effects.settings.occlusion = true
effects.settings.bloom = true
putEnv("CAC_STONE_NORMALS", "1")
var detailed = initCourtyardRenderer()
putEnv("CAC_STONE_NORMALS", "0")
var flat = initCourtyardRenderer()
delEnv("CAC_STONE_NORMALS")

proc readColor(target: RenderTarget): Image =
  ## Reads a completed offscreen color attachment.
  waitForGpu()
  result = newImage(target.width, target.height)
  target.color.handle.getBytes(result.data[0].addr, (target.width * 4).uint,
    MTLRegion(origin: MTLOrigin(), size: MTLSize(width: target.width.uint,
      height: target.height.uint, depth: 1)), 0)

proc normals(renderer: var CourtyardRenderer, occluder = false): Image =
  ## Renders the courtyard and snapshots its visible mapped normals.
  beginFrame(Width, Height, color(0, 0, 0, 1))
  effects.beginScene(ivec2(Width, Height), 0.1, 100)
  clear(color(0, 0, 0, 1))
  renderer.drawSky(vp, eye, 0)
  renderer.draw(vp, eye, 0, 1)
  if occluder:
    draw(occluderProgram, occluderVertices, 6,
      DrawState(depthTest: true, depthWrite: true))
  doAssert effects.beginMaterialNormals()
  renderer.draw(vp, eye, 0, 1, normalsOnly = true, normalView = view)
  let captured = snapshotTarget(depth = false)
  effects.endMaterialNormals()
  effects.applyOcclusion(projection)
  effects.present(ivec2(Width, Height))
  endFrame(false)
  result = readColor(captured)
  destroy(captured)

let
  withDetail = normals(detailed)
  withoutDetail = normals(flat)
  masked = normals(detailed, true)
var changed, valid, sky = 0
for i, pixel in withDetail.data:
  if pixel.a > 0:
    inc valid
    let other = withoutDetail.data[i]
    if abs(int(pixel.r) - int(other.r)) + abs(int(pixel.g) - int(other.g)) +
      abs(int(pixel.b) - int(other.b)) > 5:
        inc changed
  else:
    inc sky
doAssert valid > Width * Height div 2, "Courtyard must fill more than half the frame"
doAssert changed > valid div 8, "Mapped normals must visibly perturb the courtyard"
doAssert sky > Width * Height div 30, "Sky must stay outside the normal pass"

for y in Height * 45 div 100 + 2 ..< Height * 55 div 100 - 2:
  for x in Width * 45 div 100 + 2 ..< Width * 55 div 100 - 2:
    doAssert masked[x, y].a == 0,
      "Foreground geometry must reject courtyard normals through shared depth"

proc skyFrame(time: float32): Image =
  ## Renders a real courtyard sky frame for animation comparison.
  beginFrame(Width, Height, color(0, 0, 0, 1))
  detailed.drawSky(vp, eye, time)
  endFrame(false)
  captureImage()

let first = skyFrame(0)
let later = skyFrame(18)
var animated, stars = 0
for i, p in first.data:
  let q = later.data[i]
  if abs(int(p.r) - int(q.r)) + abs(int(p.g) - int(q.g)) +
    abs(int(p.b) - int(q.b)) > 8:
      inc animated
  if max(p.r, max(p.g, p.b)) > 90:
    inc stars
doAssert animated > 250, "Layered sky must drift and twinkle"
doAssert stars > 150, "Night sky must contain a visible starfield"
effects.dispose()
destroy(occluderProgram)
destroy(occluderVertices)
detailed.dispose()
flat.dispose()
shutdownMetal()
echo "PASS: Metal courtyard mapped normals (", changed,
  " pixels), foreground masking, SSAO/bloom, ", stars, " star pixels, ", animated,
  " animated sky pixels."
