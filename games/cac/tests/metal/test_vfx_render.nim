## Metal regressions for CaC stencil flashes, sprites, and additive effects.

import
  std/os,
  chroma, pixie, shady, vmath, windy,
  polyworld/backends/metal/common,
  ../../core/core, ../../paths, ../../vfx/vfxrenderer

when not defined(useMetal4):
  {.error: "Run this GPU fixture with -d:useMetal4.".}

const Size = 160

proc fixtureVertex(position: Vec3, gl_Position: var Vec4) =
  ## Projects the two flat silhouettes directly into the viewport.
  gl_Position = vec4(position, 1)

proc fixtureFragment(outputColor: var Vec4) =
  ## Makes the stencil fixture blue so its red flash is easy to detect.
  outputColor = vec4(0.08, 0.10, 0.70, 1)

let window = newWindow("CaC Metal effects regression", ivec2(Size),
  visible = false)
initMetal(window)
let fixture = newProgram(
  toShader(fixtureVertex, metalMSL, shaderVertex),
  toShader(fixtureFragment, metalMSL, shaderFragment),
  VertexLayout(stride: sizeof(Vec3), attributes: @[
    VertexAttribute(name: "position", format: Float3, offset: 0)
  ])
)
var effects = initVfxRenderer(artworkRoot() / "vfx/textures")
let silhouettes = newBuffer([
  vec3(-0.9, -0.7, 0), vec3(-0.1, -0.7, 0), vec3(-0.1, 0.7, 0),
  vec3(-0.9, -0.7, 0), vec3(-0.1, 0.7, 0), vec3(-0.9, 0.7, 0),
  vec3(0.1, -0.7, 0), vec3(0.9, -0.7, 0), vec3(0.9, 0.7, 0),
  vec3(0.1, -0.7, 0), vec3(0.9, 0.7, 0), vec3(0.1, 0.7, 0)
])
beginFrame(Size, Size, color(0, 0, 0, 1))
for seat in 0 .. 1:
  draw(fixture, silhouettes, 6,
    DrawState(depthTest: true, depthWrite: true, stencilTest: true,
      stencilWrite: true, stencilReference: seat + 1, stencilCompare: Always),
    first = seat * 6)
effects.drawCharacterFlash(1, 0.5)
let flash = captureImage()
doAssert flash[40, 80].r > 100, "The selected silhouette must flash red"
doAssert flash[40, 80].b < 130, "The flash must alpha blend over the character"
doAssert flash[120, 80].r < 30, "Another character must keep its original color"
doAssert flash[80, 80].r == 0, "The flash must not escape either silhouette"

let
  eye = vec3(0, 4.2, 6.8)
  projection = ortho(-2.65'f, 2.65'f, -2.45'f, 2.45'f, 0.1'f, 30.0'f) *
    lookAt(eye, vec3(0, 0.62, 0), vec3(0, 1, 0))
for kind in [LightningVfx, BubbleVfx, ArrowVfx, ManyArrowsVfx,
    SwordsIntoTheWindVfx, MightyShieldsVfx, SwordAndShieldVfx, MeleeVfx,
    SwordClashVfx, SwordBreakVfx, OozeSplatVfx, ExplosionVfx, StabVfx,
    PrizeVfx]:
  beginFrame(Size, Size, color(0, 0, 0, 1))
  var effect = newVfx(kind, creatureChoice(0, 1), vec3(0), 12345)
  effect.elapsed = min(effect.duration * 0.35'f, 0.4'f)
  effects.clear()
  effects.addEffects([effect], eye)
  effects.draw(projection)
  let image = captureImage()
  var colored = 0
  for pixel in image.data:
    if max(pixel.r, max(pixel.g, pixel.b)) > 8:
      inc colored
  doAssert colored > 3, $kind & " must draw visible pixels on Metal"
  echo kind, ": ", colored, " visible pixels"
effects.dispose()
destroy(silhouettes)
destroy(fixture)
shutdownMetal()
window.close()
echo "CaC Metal stencil and material effects passed"
