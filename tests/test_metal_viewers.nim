## Exercises application-owned frames with embedded Silky UI.

import
  std/os,
  chroma, pixie, silky, vmath, windy,
  silky/drawers/metal4 as silkyMetal,
  polyworld/renderer,
  polyworld/backends/metal/common as metal

let atlasPath = getTempDir() / "polyworld-metal-viewer-atlas.png"
newAtlasBuilder(32, 0).write(atlasPath)
let
  window = newWindow("Polyworld Metal composition", ivec2(128, 96),
    visible = defined(visibleMetalTest))
initRenderer(window)
let
  sk = newGameUi(window, atlasPath)
  secondUi = newGameUi(window, atlasPath)
  firstAtlas = sk.atlasTexture()
  secondAtlas = secondUi.atlasTexture()
doAssert not firstAtlas.handle.isNil
doAssert not secondAtlas.handle.isNil
removeFile(atlasPath)

proc overlay(sk: Silky, window: Window) =
  ## Draws a visible UI square over an existing scene.
  sk.uiScale = 1
  sk.beginUi(window, window.size)
  sk.drawRect(vec2(8, 8), vec2(24, 24), rgbx(255, 0, 0, 255))
  sk.finishUi()

for size in [ivec2(128, 96), ivec2(96, 128)]:
  window.size = size
  pollEvents()
  clearFrame(color(0, 0, 1, 1))
  sk.overlay(window)
  let image = renderer.readFrameImage(size.x, size.y)
  doAssert image[16, 16].r == 255
  doAssert image[50, 50].b == 255
  sk.overlay(window)
  let again = renderer.readFrameImage(size.x, size.y)
  doAssert again[16, 16].r == 255
  doAssert again[50, 50].b == 255
  window.presentRenderer()

let target = metal.newRenderTarget(96, 128, samples = 4, stencil = true)
pushFrameTarget(target)
clearFrame(color(0, 1, 0, 1))
sk.overlay(window)
# Opening a later engine encoder must not overwrite UI with an old MSAA image.
renderer.setRenderViewport(window.size)
let composed = renderer.readFrameImage(96, 128)
doAssert composed[16, 16].r == 255
doAssert composed[50, 50].g == 255
popFrameTarget()
metal.destroy(target)
window.presentRenderer()
silkyMetal.close(sk.drawer)
silkyMetal.close(secondUi.drawer)
shutdownRenderer()
window.close()
echo "Embedded Metal UI, resize, multiple passes and MSAA composition passed"
