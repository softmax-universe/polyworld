## Metal pixel regressions for screen-door bodies and scene distortions.

import
  chroma, pixie, shady, vmath, windy,
  polyworld/[distortions, xraybodies],
  polyworld/backends/metal/common

const
  Width = 96
  Height = 64
  Bayer = [
    0, 8, 2, 10,
    12, 4, 14, 6,
    3, 11, 1, 9,
    15, 7, 13, 5
  ]

var
  tint: Uniform[Vec4]
  gradient: Uniform[float32]
  dimensions: Uniform[Vec2]

proc rectangleVertex(position: Vec3, gl_Position: var Vec4) =
  ## Projects explicit clip-space rectangles at a known device depth.
  gl_Position = vec4(position, 1.0'f)

proc rectangleFragment(gl_FragCoord: Vec4, output: var Vec4) =
  ## Produces either a solid rectangle or a coordinate-marked scene.
  if gradient > 0.5'f:
    let uv = gl_FragCoord.xy / dimensions
    output = vec4(uv.x, uv.y, 0.25'f, 0.6'f)
  else:
    output = tint

proc rectangle(
    program: MetalProgram,
    left, bottom, width, height: int,
    depth: float32,
    tint: Vec4,
    gradient = false
) =
  ## Draws an axis-aligned rectangle expressed in lower-left pixel space.
  let
    x0 = left.float32 / Width.float32 * 2.0'f - 1.0'f
    y0 = bottom.float32 / Height.float32 * 2.0'f - 1.0'f
    x1 = (left + width).float32 / Width.float32 * 2.0'f - 1.0'f
    y1 = (bottom + height).float32 / Height.float32 * 2.0'f - 1.0'f
    z = depth * 2.0'f - 1.0'f
    vertices = [
      vec3(x0, y0, z), vec3(x1, y0, z), vec3(x1, y1, z),
      vec3(x0, y0, z), vec3(x1, y1, z), vec3(x0, y1, z)
    ]
    buffer = newBuffer(vertices)
  defer:
    destroy(buffer)
  program.setUniform("tint", tint)
  program.setUniform("gradient", if gradient: 1.0'f else: 0.0'f)
  program.setUniform("dimensions", vec2(Width.float32, Height.float32))
  draw(program, buffer, vertices.len, DrawState(
    depthTest: true, depthWrite: true, depthCompare: Always
  ))

proc finishPixels(target: RenderTarget): Image =
  ## Resolves an offscreen scene into the frame target for native readback.
  popTarget()
  copyTarget(target, metalRenderer.frameTarget, depth = false)
  endFrame(present = false)
  captureImage()

proc checkXray(program: MetalProgram, target: RenderTarget) =
  ## Verifies exact Bayer pixels, cell sizes and hidden-surface depth tests.
  var xray = initXrayBodies(XrayBodySettings(
    enabled: true, coverage: 0.5, cell: 1, clearance: 0
  ))
  defer:
    xray.closeXrayBodies()
  for cell in [1, 3]:
    xray.settings.cell = cell.float32
    for coverage in [0.0'f, 0.25'f, 0.5'f, 1.0'f]:
      xray.settings.coverage = coverage
      beginFrame(Width, Height, color(0, 0, 0, 1))
      pushTarget(target)
      clear(color(0, 0, 0, 1))
      rectangle(program, 0, 0, Width, Height, 0.8'f, vec4(0, 0, 0, 1))
      rectangle(program, 0, 0, Width, Height div 2,
        0.4'f, vec4(0, 0, 0, 1))
      doAssert xray.beginXrayBodies(ivec2(Width, Height))
      rectangle(program, 8, 8, Width - 16, Height - 16,
        0.6'f, vec4(1, 0, 0, 1))
      xray.finishXrayBodies(scale(vec3(1.0'f)))
      let pixels = finishPixels(target)
      for y in 0 ..< Height:
        for x in 0 ..< Width:
          let
            lowerY = Height - y - 1
            threshold = Bayer[
              ((lowerY div cell) mod 4) * 4 + ((x div cell) mod 4)
            ].float32
            expected = x >= 8 and x < Width - 8 and lowerY >= 8 and
              lowerY < Height div 2 and
              (threshold + 0.5'f) / 16.0'f < coverage
          doAssert (pixels[x, y].r > 200) == expected,
            "Metal Xray mismatch at " & $x & "," & $y & ", cell " & $cell &
            ", coverage " & $coverage & ", samples " & $target.samples
  echo "Metal Xray pixels passed with ", target.samples, " samples"

proc distortionPixels(
    program: MetalProgram,
    renderer: var DistortionRenderer,
    target: RenderTarget,
    kind: DistortionKind,
    blocked, drawEffect: bool
): Image =
  ## Draws one distortion over a coordinate-marked opaque or occluding scene.
  beginFrame(Width, Height, color(0, 0, 0, 1))
  pushTarget(target)
  clear(color(0, 0, 0, 1))
  rectangle(program, 0, 0, Width, Height,
    if blocked: 0.4'f else: 0.95'f, vec4(1), gradient = true)
  if drawEffect:
    let items = [Distortion(
      kind: kind, center: vec3(0), radius: 0.8, strength: 0.3,
      age: 0.5, life: 1, seed: 3
    )]
    renderer.drawDistortions(
      items,
      scale(vec3(1.0'f)),
      vec3(0, 0, 3),
      vec3(1, 0, 0),
      vec3(0, 1, 0),
      ivec2(Width, Height),
      1.0'f,
      source = target
    )
  finishPixels(target)

proc checkDistortions(program: MetalProgram, target: RenderTarget) =
  ## Checks every effect, scene orientation, destination alpha and occlusion.
  var renderer: DistortionRenderer
  defer:
    renderer.close()
  let original = distortionPixels(program, renderer, target,
    ShockwaveDistortion, blocked = false, drawEffect = false)
  for kind in DistortionKind:
    let
      pixels = distortionPixels(program, renderer, target, kind,
        blocked = false, drawEffect = true)
      blocked = distortionPixels(program, renderer, target, kind,
        blocked = true, drawEffect = true)
    var changed = 0
    for y in 0 ..< Height:
      for x in 0 ..< Width:
        doAssert blocked[x, y] == original[x, y],
          "A distortion drew through an occluding scene surface"
        doAssert pixels[x, y].a == original[x, y].a,
          "A distortion changed the destination scene alpha"
        if pixels[x, y] != original[x, y]:
          inc changed
        if x < 8 or x >= Width - 8 or y < 5 or y >= Height - 5:
          doAssert pixels[x, y] == original[x, y],
            "A distortion changed pixels outside its circular billboard"
    doAssert changed > 20, "The distortion did not warp the scene: " & $kind
    if kind == ShockwaveDistortion:
      doAssert pixels[67, 32].r > original[67, 32].r,
        "The shockwave must push the right side outward"
      doAssert pixels[48, 19].g < original[48, 19].g,
        "The shockwave must push the upper side upward"
    elif kind == ShieldDistortion:
      doAssert pixels[67, 32].r < original[67, 32].r,
        "The shield must pull the right side inward"
      doAssert pixels[48, 19].g > original[48, 19].g,
        "The shield must pull the upper side toward its center"
  echo "Metal distortion pixels passed with ", target.samples, " samples"

proc main() =
  ## Executes the GPU regressions with single-sample and multisample targets.
  let window = newWindow("Metal screen effects regression",
    ivec2(Width, Height), visible = false, vsync = false)
  defer:
    window.close()
  initMetal(window)
  defer:
    shutdownMetal()
  let program = newProgram(
    toShader(rectangleVertex, metalMSL, shaderVertex),
    toShader(rectangleFragment, metalMSL, shaderFragment),
    VertexLayout(stride: sizeof(Vec3), attributes: @[
      VertexAttribute(name: "position", format: Float3, offset: 0)
    ])
  )
  defer:
    destroy(program)
  beginFrame(Width, Height, color(0, 0, 0, 1))
  endFrame(present = false)
  for samples in [1, 4]:
    let target = newRenderTarget(Width, Height, samples = samples,
      colorFormat = metalRenderer.frameTarget.color.pixelFormat)
    checkXray(program, target)
    checkDistortions(program, target)
    destroy(target)

main()
