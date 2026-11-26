## Verifies shared card baking, atlas sampling, and queued UI retention.

when defined(saveRenderCaptures):
  import std/os
import pixie, silky, vmath, windy
when defined(useMetal4):
  import silky/drawers/metal4
else:
  import silky/drawers/ogl
import polyworld/backends/passes/common
from polyworld/renderer import initRenderer, drawUiLayer
import ../scene/[cardrenderer, table]
import ../baseset

const
  Width = 800
  Height = 600

let window = newWindow("CaC shared card verification", ivec2(Width, Height),
  visible = false)
initRenderer(window)
when not defined(useMetal4):
  let fixtureTarget = newRenderTarget(Width, Height)
  proc beginFrame(width, height: int, value: Color) =
    ## Clears the hidden offscreen fixture target.
    setTarget(fixtureTarget)
    clear(value)
  proc captureImage(): Image =
    ## Reads the completed fixture in top-left image order.
    captureTargetImage(fixtureTarget)
  proc endFrame(present: bool) =
    ## Completes offscreen GL rendering without presenting a window.
    waitForGpu()
let builder = newAtlasBuilder(5632, 1)
builder.addFaceAssets()
let
  drawer =
    when defined(useMetal4):
      newDrawer(metalRenderer.ctx.device, builder.atlasImage,
        ivec2(Width, Height), MTLPixelFormatRGBA8Unorm)
    else:
      newDrawer(window, builder.atlasImage)
  sk = newSilky(window, builder.atlasImage, builder.atlas, drawer)
  state = FaceState(card: baseCards[3], power: -1, toughness: -1)
  projection = ortho(0.0'f, Width.float32, Height.float32, 0.0'f, -100.0'f, 100.0'f)
var
  cards = initCardRenderer()
  solids = initSolidRenderer()

for frame in 0 .. 1:
  beginFrame(Width, Height, color(0.03, 0.05, 0.08, 1))
  sk.beginUi(window, ivec2(Width, Height))
  sk.drawImage(WhiteTileKey, vec2(4, 4))
  cards.clear()
  cards.addFace(sk, [vec3(420, 50, 0), vec3(420, 475, 0),
    vec3(720, 475, 0), vec3(720, 50, 0)], state)
  sk.drawFace(state, vec2(40, 50), vec2(300, 425))
  cards.addSurface(sk, [vec3(40, 510, 0), vec3(40, 590, 0),
    vec3(100, 590, 0), vec3(100, 510, 0)], CardBackKey)
  cards.draw(sk, projection)
  solids.clear()
  solids.addBox(vec3(600, 540, 0), vec3(100, 40, 10),
    vec4(0.1, 0.7, 0.2, 1))
  solids.draw(projection)
  when defined(useMetal4):
    flushEncoder()
    drawer.setExternalFrame(metalRenderer.commandBuffer,
      metalRenderer.target.color.handle)
  sk.endUi()
  sk.drawHudFaces()
  sk.isolatedDrawing(rect(370, 270, 4, 8)):
    sk.drawRect(vec2(368, 268), vec2(12, 12), rgbx(255, 0, 0, 255))
    sk.drawUiLayer(sk.drawer.layers[0], vec2(Width, Height), 2)
  endFrame(false)
  let image = captureImage()
  doAssert image[8, 8].r > 240, "Face baking lost previously queued UI."
  doAssert image[744, 544].r > 240 and image[744, 544].g < 10,
    "Supplied UI layers must honor their logical scale."
  doAssert image[752, 544].r < 20,
    "Scaled UI layers must retain their clipping bounds."
  var
    changed = 0
    difference = 0
    flippedDifference = 0
  for y in 55 ..< 470:
    for x in 45 ..< 335:
      let
        a = image[x, y]
        b = image[x + 380, y]
      if a.r.int + a.g.int + a.b.int > 80:
        inc changed
      difference += abs(a.r.int - b.r.int) + abs(a.g.int - b.g.int) +
        abs(a.b.int - b.b.int)
      let flipped = image[x + 380, 524 - y]
      flippedDifference += abs(a.r.int - flipped.r.int) +
        abs(a.g.int - flipped.g.int) + abs(a.b.int - flipped.b.int)
  doAssert changed > 60000, "The baked face did not render."
  # World UVs inset by half a texel, so textured edges may interpolate differently.
  doAssert difference < 415 * 290 * 12,
    "World and HUD card face blending differs."
  doAssert flippedDifference > difference * 3,
    "World and HUD card face orientation differs."
  var backPixels = 0
  for y in 512 ..< 588:
    for x in 42 ..< 98:
      let pixel = image[x, y]
      if pixel.r.int + pixel.g.int + pixel.b.int > 70:
        inc backPixels
  doAssert backPixels > 2000, "The shared Silky atlas did not render."
  doAssert image[600, 540].g > image[600, 540].r * 2,
    "The solid card geometry did not render."
  when defined(saveRenderCaptures):
    if frame == 0:
      createDir("tmp/backends")
      image.writeFile("tmp/backends/cac-cards.png")
  echo "Shared cards frame ", frame, ": ", changed,
    " face pixels; consistent world and HUD orientation."
when defined(useMetal4):
  drawer.close()
  shutdownMetal()
else:
  fixtureTarget.destroy()
window.close()
