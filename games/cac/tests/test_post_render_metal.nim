## Native Metal rendering regression for the CaC scene and post effects.
## Build with -d:useMetal4; use -d:cacPostLayers to verify diagnostic passes.

import pixie, shady, vmath, windy
import polyworld/backends/metal/common
import ../scene/post as postfx

const Width = 192
const Height = 128

proc sceneVertex(gl_Position: var Vec4, uv: var Vec2) =
  ## Generates a fullscreen triangle with native Metal texture coordinates.
  let corner = vec2(float32((gl_VertexID mod 2) * 2),
    float32((gl_VertexID div 2) * 2))
  uv = vec2(corner.x, 1.0'f - corner.y)
  gl_Position = vec4(corner.x * 2.0'f - 1.0'f,
    corner.y * 2.0'f - 1.0'f, 0.0'f, 1.0'f)

proc sceneFragment(uv: Vec2, fragColor: var Vec4, gl_FragDepth: var float32) =
  ## Provides a color gradient and a depth discontinuity for occlusion.
  fragColor = vec4(0.1'f + uv.x * 0.4'f, 0.1'f + uv.y * 0.4'f, 0.1'f, 1.0'f)
  gl_FragDepth = if uv.x < 0.5'f: 0.98098'f else: 0.98431'f

proc glowFragment(uv: Vec2, fragColor: var Vec4) =
  ## Adds a localized emissive rectangle to verify bloom spreading.
  let enabled = if uv.x > 0.7'f and uv.x < 0.8'f and
    uv.y > 0.4'f and uv.y < 0.6'f: 1.0'f else: 0.0'f
  fragColor = vec4(enabled * 0.5'f, enabled * 0.4'f, enabled * 0.3'f, 1.0'f)

let window = newWindow("CaC Metal post regression", ivec2(Width, Height))
initMetal(window)
let
  scene = newProgram(toShader(sceneVertex, metalMSL, shaderVertex),
    toShader(sceneFragment, metalMSL, shaderFragment))
  glow = newProgram(toShader(sceneVertex, metalMSL, shaderVertex),
    toShader(glowFragment, metalMSL, shaderFragment))
  projection = perspective(42.0'f, Width.float32 / Height.float32, 0.1'f, 100.0'f)
var effects = initPostFx()
effects.settings.enabled = true
effects.settings.fxaa = false
effects.settings.vignette = 0
effects.settings.saturation = 1
effects.settings.contrast = 0

proc captureFrame(ao, bloom, addGlow: bool,
    size = ivec2(Width, Height)): Image =
  ## Renders one controlled combination of scene and post effects.
  effects.settings.occlusion = ao
  effects.settings.bloom = bloom
  beginFrame(size.x, size.y, color(0, 0, 0, 1))
  effects.beginScene(size, 0.1, 100)
  clear(color(0, 0, 0, 1))
  draw(scene, nil, 3, DrawState(depthTest: true, depthWrite: true))
  if effects.beginMaterialNormals():
    effects.endMaterialNormals()
  effects.applyOcclusion(projection)
  if addGlow:
    draw(glow, nil, 3, DrawState(blend: Additive))
  effects.present(size)
  endFrame(false)
  captureImage()

let
  plain = captureFrame(false, false, false)
  occluded = captureFrame(true, false, false)
  unbloomed = captureFrame(false, false, true)
  bloomed = captureFrame(false, true, true)
doAssert plain[Width div 2, Height div 4].g <
  plain[Width div 2, Height * 3 div 4].g, "Post must preserve vertical texture orientation"
var darkened, spread = 0
for y in 0 ..< Height:
  for x in 0 ..< Width:
    if occluded[x, y].r.int < plain[x, y].r.int - 2:
      inc darkened
    if bloomed[x, y].r.int > unbloomed[x, y].r.int + 2 and
      (x < Width * 7 div 10 or x > Width * 8 div 10):
        inc spread
doAssert darkened > Height, "Depth discontinuities must receive occlusion"
doAssert spread > Height, "Bloom must spread light beyond the emissive rectangle"
let resized = captureFrame(true, true, true, ivec2(96, 64))
doAssert resized.width == 96 and resized.height == 64,
  "Post targets must resize with the caller's frame"
discard captureFrame(true, true, true)
when PostLayerControls:
  for layer in PostLayer:
    effects.layer = layer
    discard captureFrame(true, true, true)
effects.dispose()
destroy(scene)
destroy(glow)
shutdownMetal()
echo "PASS: Metal post orientation, ", darkened,
  " occluded pixels, ", spread, " bloom pixels, and all diagnostic layers."
