## Pixel coverage for Metal selection outlines and occluded silhouettes.

import
  pixie, shady, vmath, windy,
  polyworld/selectionoutlines,
  polyworld/backends/metal/common

type
  RectangleFixture = object
    program: MetalProgram
    vertices: MetalBuffer

proc rectangleVertex(position: Vec3, gl_Position: var Vec4) =
  ## Passes pretransformed rectangle positions to the rasterizer.
  gl_Position = vec4(position, 1)

proc rectangleFragment(tint: Uniform[Vec4], fragColor: var Vec4) =
  ## Writes an opaque fixture mask or wall color.
  fragColor = tint

proc rectangle(
    fixture: RectangleFixture,
    size: IVec2,
    x, y, width, height: int32,
    depth: float32,
    tint: Vec4
) =
  ## Draws a rectangle in lower-left pixel coordinates at a fixed depth.
  let
    left = 2'f * x.float32 / size.x.float32 - 1'f
    right = 2'f * (x + width).float32 / size.x.float32 - 1'f
    bottom = 2'f * y.float32 / size.y.float32 - 1'f
    top = 2'f * (y + height).float32 / size.y.float32 - 1'f
    z = depth * 2'f - 1'f
  updateBuffer(fixture.vertices, [
    vec3(left, bottom, z), vec3(right, bottom, z), vec3(right, top, z),
    vec3(left, bottom, z), vec3(right, top, z), vec3(left, top, z)
  ])
  fixture.program.setUniform("tint", tint)
  draw(fixture.program, fixture.vertices, 6,
    DrawState(depthTest: true, depthWrite: true))

proc pixel(image: Image, x, y: int32): ColorRGBX =
  ## Reads a captured image using the fixture's lower-left coordinates.
  image[x, image.height.int32 - 1 - y]

proc checkOutlines(samples: int) =
  ## Checks partial, full, absent, and empty occlusion at two target sizes.
  let window = newWindow("Metal outline verification", ivec2(320, 240),
    visible = false)
  initMetal(window)
  let fixture = RectangleFixture(
    program: newProgram(
      toShader(rectangleVertex, metalMSL, shaderVertex),
      toShader(rectangleFragment, metalMSL, shaderFragment),
      VertexLayout(stride: sizeof(Vec3), attributes: @[
        VertexAttribute(name: "position", format: Float3, offset: 0)
      ])
    ),
    vertices: newBuffer([vec3(0)])
  )
  var
    outline = initSelectionOutline(OccludedOutline)
    selection = initSelectionOutline()
  defer:
    outline.closeSelectionOutline()
    selection.closeSelectionOutline()
    destroy(fixture.program)
    destroy(fixture.vertices)
    shutdownMetal()
    window.close()

  for size in [ivec2(320, 240), ivec2(160, 120), ivec2(320, 240)]:
    let
      left = size.x div 4
      bottom = size.y div 4
      width = size.x div 2
      height = size.y div 2
      lower = bottom + height div 4
      upper = bottom + height * 3 div 4
    for coverage in 0 .. 2:
      beginFrame(size.x, size.y, color(0, 0, 0, 1))
      let scene = newRenderTarget(size.x, size.y, samples = samples,
          stencil = true)
      pushTarget(scene)
      clear(color(0, 0, 0, 1))
      if coverage > 0:
        fixture.rectangle(size, 0, 0, size.x, size.y * coverage.int32 div 2,
          0.4, vec4(0, 0, 0, 1))
      outline.beginMask(size)
      fixture.rectangle(size, left, bottom, width, height, 0.6, vec4(1))
      outline.drawOutline(vec3(0, 1, 0))
      doAssert metalRenderer.target == scene
      let green = captureTargetImage()
      doAssert (green.pixel(left - 1, lower).g > 200) == (coverage > 0)
      doAssert (green.pixel(left - 1, upper).g > 200) == (coverage == 2)
      doAssert green.pixel(left + width div 2, lower).g == 0,
        "Occlusion must outline the silhouette without filling its interior"

      outline.beginMask(size)
      fixture.rectangle(size, left, bottom, width, height, 0.5, vec4(1))
      outline.drawOutline(vec3(0, 0, 1))
      let blue = captureTargetImage()
      doAssert (blue.pixel(left - 1, lower).b > 200) == (coverage > 0),
        "A second silhouette must still compare against unchanged scene depth"

      selection.beginMask(size)
      fixture.rectangle(size, left, bottom, width, height, 0.6, vec4(1))
      selection.drawOutline(vec3(1, 0, 0))
      doAssert captureTargetImage().pixel(left - 1, upper).r > 200,
        "Selection edges must remain visible regardless of scene depth"
      popTarget()
      endFrame(present = false)
      destroy(scene)

    beginFrame(size.x, size.y, color(0, 0, 0, 1))
    let scene = newRenderTarget(size.x, size.y, samples = samples,
          stencil = true)
    pushTarget(scene)
    clear(color(0, 0, 0, 1))
    fixture.rectangle(size, 0, 0, size.x, size.y, 0.4, vec4(0, 0, 0, 1))
    outline.beginMask(size)
    outline.drawOutline(vec3(0, 1, 0))
    doAssert captureTargetImage().pixel(left - 1, lower).g == 0,
      "An empty mask must not reveal an outline through scenery"
    popTarget()
    endFrame(present = false)
    destroy(scene)
  echo "PASS Metal selection outlines samples=", samples

checkOutlines(1)
checkOutlines(4)
