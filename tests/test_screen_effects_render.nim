## Native GPU regression for Shady screen-door bodies and distortions.
## Run from the repository root; no game assets are required.

import
  std/importutils,
  opengl, vmath, windy,
  polyworld/[distortions, xraybodies]

const Bayer = [
  0, 8, 2, 10,
  12, 4, 14, 6,
  3, 11, 1, 9,
  15, 7, 13, 5
]

privateAccess(DistortionRenderer)

proc clearRectangle(x, y, width, height: int32, depth: float64) =
  ## Clears one rectangular silhouette at a known scene depth.
  glEnable(GL_SCISSOR_TEST)
  glScissor(x, y, width, height)
  glClearDepth(depth)
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
  glDisable(GL_SCISSOR_TEST)
  glClearDepth(1)

proc checkXray(size: IVec2) =
  ## Checks dither coverage, pixel origin and visibility against scene depth.
  var xray = initXrayBodies(XrayBodySettings(
    enabled: true,
    coverage: 0.5,
    cell: 1,
    clearance: 0
  ))
  defer:
    xray.closeXrayBodies()
  for cell in [1, 3]:
    xray.settings.cell = cell.float32
    for coverage in [0.0'f, 0.25'f, 0.5'f, 1.0'f]:
      xray.settings.coverage = coverage
      glBindFramebuffer(GL_FRAMEBUFFER, 0)
      glViewport(0, 0, size.x, size.y)
      glDepthMask(GL_TRUE)
      glClearColor(0, 0, 0, 1)
      # The lower half hides the body; the upper half leaves it visible.
      clearRectangle(0, 0, size.x, size.y, 0.8)
      clearRectangle(0, 0, size.x, size.y div 2, 0.4)
      doAssert xray.beginXrayBodies(size)
      glClearColor(1, 0, 0, 1)
      clearRectangle(8, 8, size.x - 16, size.y - 16, 0.6)
      xray.finishXrayBodies(scale(vec3(1.0'f)))
      var pixels = newSeq[uint8](size.x * size.y * 4)
      glReadPixels(
        0,
        0,
        size.x,
        size.y,
        GL_RGBA,
        GL_UNSIGNED_BYTE,
        pixels[0].addr
      )
      for y in 0 ..< size.y:
        for x in 0 ..< size.x:
          let
            threshold = Bayer[
              ((y div cell) mod 4) * 4 + ((x div cell) mod 4)
            ].float32
            expected = x >= 8 and x < size.x - 8 and y >= 8 and
              y < size.y div 2 and
              (threshold + 0.5'f) / 16.0'f < coverage
          doAssert (pixels[(y * size.x + x) * 4] > 200) == expected,
            "Xray mismatch at " & $x & "," & $y & ", cell " & $cell &
            ", coverage " & $coverage
      doAssert glGetError() == GL_NO_ERROR
  echo "Xray pattern, cell size, coverage, screen origin and depth passed"

proc checkDistortions(size: IVec2) =
  ## Compiles, links and renders every distortion kind against a scene copy.
  var renderer: DistortionRenderer
  defer:
    renderer.close()
  for kind in DistortionKind:
    glBindFramebuffer(GL_FRAMEBUFFER, 0)
    glViewport(0, 0, size.x, size.y)
    glDepthMask(GL_TRUE)
    glClearColor(0.2, 0.5, 0.8, 1)
    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
    let items = [Distortion(
      kind: kind,
      center: vec3(0),
      radius: 0.5,
      strength: 0.1,
      age: 0.5,
      life: 1,
      seed: 3
    )]
    renderer.drawDistortions(
      items,
      scale(vec3(1.0'f)),
      vec3(0, 0, 3),
      vec3(1, 0, 0),
      vec3(0, 1, 0),
      size,
      1.0'f
    )
    doAssert renderer.ready and not renderer.unavailable,
      "Distortions must render rather than skip an unavailable scene copy"
    doAssert glGetError() == GL_NO_ERROR
  echo "All distortion kinds compiled, linked and rendered"

proc main() =
  ## Runs the effects in a hidden native window with a complete framebuffer.
  let window = newWindow(
    "Shady screen effects regression",
    ivec2(96, 64),
    visible = false,
    vsync = false,
    msaa = msaaDisabled
  )
  defer:
    window.close()
  window.makeContextCurrent()
  loadExtensions()
  pollEvents()
  window.makeContextCurrent()
  glBindFramebuffer(GL_FRAMEBUFFER, 0)
  doAssert glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE
  let size = window.size
  doAssert size.x > 16 and size.y > 16
  checkXray(size)
  checkDistortions(size)

main()
