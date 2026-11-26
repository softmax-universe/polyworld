## Verifies shared shape, billboard, and particle passes with GPU readback.

import
  pixie, vmath, windy,
  polyworld/[shapes, worldbars, particles, particleshaders],
  polyworld/backends/passes/common

proc illuminated(image: Image): int =
  ## Counts pixels touched by a visible effect against black.
  for pixel in image.data:
    if pixel.r > 4 or pixel.g > 4 or pixel.b > 4:
      inc result

let window = newWindow("Shared effects verification", ivec2(128), visible = false)
when defined(useMetal4):
  initMetal(window)
elif defined(useDirectX) or defined(useVulkan):
  initNative(window)
  template captureImage(): Image = captureTargetImage()
else:
  window.makeContextCurrent()
  loadExtensions()
  initNative(window)
  let fixtureTarget = newRenderTarget(128, 128)
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
var
  shape = initShapeRenderer()
  bars = initWorldBarRenderer()
  system = initParticleSystem()

shape.addQuad(
  vec3(-0.9, -0.8, 0),
  vec3(-0.1, -0.8, 0),
  vec3(-0.1, 0.8, 0),
  vec3(-0.9, 0.8, 0),
  rgbx(255, 0, 0, 254)
)
bars.addBillboardQuad(
  vec3(0.1, -0.8, 0), vec2(0), vec2(0.8, 1.6), rgbx(0, 255, 0, 255)
)
beginFrame(128, 128, color(0, 0, 0, 1))
shape.draw(mat4(), opaque = true)
bars.draw(mat4(), vec3(1, 0, 0), vec3(0, 1, 0))
let solidImage = captureImage()
doAssert solidImage[32, 64].r > 250
doAssert solidImage[32, 64].g == 0
doAssert solidImage[96, 64].g > 250
doAssert solidImage[96, 64].r == 0

# A billboard behind opaque geometry must remain hidden.
bars.clear()
bars.addBillboardQuad(
  vec3(-0.9, -0.8, 0.5), vec2(0), vec2(0.8, 1.6), rgbx(0, 255, 0, 255)
)
bars.draw(mat4(), vec3(1, 0, 0), vec3(0, 1, 0))
let depthImage = captureImage()
doAssert depthImage[32, 64].r > 250
doAssert depthImage[32, 64].g == 0

# Both textured shape geometry and colored billboards borrow the same atlas.
let atlasImage = newImage(2, 2)
atlasImage.fill(rgba(0, 0, 255, 255))
let atlas = newTexture(atlasImage, linear = false)
shape.texture = atlas
shape.clear()
shape.addQuad(
  vec3(-0.9, -0.8, 0), vec3(-0.1, -0.8, 0),
  vec3(-0.1, 0.8, 0), vec3(-0.9, 0.8, 0), rgbx(255, 255, 255, 254)
)
bars.clear()
bars.addBillboardQuad(
  vec3(0.1, -0.8, 0), vec2(0), vec2(0.8, 1.6),
  rgbx(255, 255, 255, 255), vec2(0), vec2(1), ColorTexture
)
beginFrame(128, 128, color(0, 0, 0, 1))
shape.draw(mat4(), opaque = true)
bars.draw(mat4(), vec3(1, 0, 0), vec3(0, 1, 0), atlas)
let atlasResult = captureImage()
doAssert atlasResult[32, 64].b > 250
doAssert atlasResult[32, 64].r == 0
doAssert atlasResult[96, 64].b > 250
doAssert atlasResult[96, 64].r == 0

# Every semantic effect must encode successfully with its native blend mode.
for kind in ParticleEffectKind:
  system.emitParticleBurst(kind, vec3(0))
system.advanceParticles(0.2)
beginFrame(128, 128, color(0, 0, 0, 1))
system.drawParticles(mat4(), vec3(1, 0, 0), vec3(0, 1, 0), vec3(0, 0, 1))
doAssert captureImage().illuminated > 0

# Exact sight clipping hides particles while ownership can bypass that mask.
system.clearParticles()
system.emitParticleBurst(CombatSparks, vec3(0), owner = 3)
system.advanceParticles(0.2)
let hidden = [0'u8, 0, 0, 0]
beginFrame(128, 128, color(0, 0, 0, 1))
system.drawParticles(
  mat4(), vec3(1, 0, 0), vec3(0, 1, 0), vec3(0, 0, 1),
  hidden, 2, vec2(-1), clipToSight = true
)
doAssert captureImage().illuminated == 0
let visible = [255'u8, 255, 255, 255]
beginFrame(128, 128, color(0, 0, 0, 1))
system.drawParticles(
  mat4(), vec3(1, 0, 0), vec3(0, 1, 0), vec3(0, 0, 1),
  visible, 2, vec2(-1), clipToSight = true
)
doAssert captureImage().illuminated > 0
beginFrame(128, 128, color(0, 0, 0, 1))
system.drawParticles(
  mat4(), vec3(1, 0, 0), vec3(0, 1, 0), vec3(0, 0, 1),
  hidden, 2, vec2(-1), viewer = 3, clipToSight = true
)
doAssert captureImage().illuminated > 0

endFrame(false)
shape.closeShapeRenderer()
shape.closeShapeRenderer()
bars.closeWorldBarRenderer()
bars.closeWorldBarRenderer()
system.closeParticles()
system.closeParticles()
when defined(useMetal4):
  doAssert not atlas.handle.isNil
elif defined(useDirectX) or defined(useVulkan):
  doAssert atlas.handle != nil
else:
  doAssert atlas.handle != 0
atlas.destroy()
when defined(useMetal4):
  shutdownMetal()
elif defined(useDirectX) or defined(useVulkan):
  shutdownNative()
else:
  fixtureTarget.destroy()
window.close()
echo "Shared shapes, bars, atlas, scene depth, particles, and sight clipping passed"
