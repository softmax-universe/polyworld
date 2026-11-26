## Pixel coverage for Metal AO across camera modes, resizing, and MSAA.

import
  pixie, shady, vmath, windy,
  polyworld/screenocclusions,
  polyworld/backends/metal/common,
  polyworld/backends/shaders/screenocclusions as occlusionShaders

type
  Fixture = object
    program, depthProgram: MetalProgram
    vertexBuffer: MetalBuffer
    vertices: seq[Vec3]

proc fixtureVertex(
    position: Vec3,
    viewProjection: Uniform[Mat4],
    gl_Position: var Vec4
) =
  ## Transforms the fixture geometry with its camera matrix.
  gl_Position = viewProjection * vec4(position, 1)

proc fixtureFragment(color: Uniform[Vec3], fragColor: var Vec4) =
  ## Colors geometry without lighting so AO is independently observable.
  fragColor = vec4(color, 1)

proc depthFragment(
    sceneDepth: Uniform[Sampler2D],
    gl_FragCoord: Vec4,
    fragColor: var Vec4
) =
  ## Encodes sampled depth across color channels for exact before/after checks.
  let depth = texelFetch(sceneDepth, ivec2(gl_FragCoord.xy), 0).r
  fragColor = vec4(depth, fract(depth * 255'f), fract(depth * 65025'f), 1)

proc initFixture(): Fixture =
  ## Creates a floor and box renderer without importing game assets.
  result.program = newProgram(
    toShader(fixtureVertex, metalMSL, shaderVertex),
    toShader(fixtureFragment, metalMSL, shaderFragment),
    VertexLayout(stride: sizeof(Vec3), attributes: @[
      VertexAttribute(name: "position", format: Float3, offset: 0)
    ])
  )
  result.vertexBuffer = newBuffer([vec3(0)])
  result.depthProgram = newProgram(
    toShader(occlusionShaders.fullscreenVertex, metalMSL, shaderVertex),
    toShader(depthFragment, metalMSL, shaderFragment)
  )

proc quad(fixture: var Fixture, a, b, c, d: Vec3) =
  ## Adds two opaque triangles with shared positions.
  fixture.vertices.add [a, b, c, a, c, d]

proc draw(fixture: var Fixture, viewProjection: Mat4, color: Vec3) =
  ## Writes unlit geometry and depth so only AO can change the colors.
  fixture.program.setUniform("viewProjection", viewProjection)
  fixture.program.setUniform("color", color)
  updateBuffer(fixture.vertexBuffer, fixture.vertices)
  draw(fixture.program, fixture.vertexBuffer, fixture.vertices.len,
    DrawState(depthTest: true, depthWrite: true, depthCompare: Less))
  fixture.vertices.setLen(0)

proc captureDepth(fixture: Fixture): Image =
  ## Reads depth through a separate color target without touching scene depth.
  let
    scene = metalRenderer.target
    readback = newRenderTarget(scene.width, scene.height, depth = false)
  pushTarget(readback)
  fixture.depthProgram.bindTexture("sceneDepth", scene.depth)
  draw(fixture.depthProgram, nil, 3)
  result = captureTargetImage()
  popTarget()
  destroy(readback)

proc checkOcclusion(samples: int) =
  ## Exercises contacts, body protection, disabling, and resized targets.
  let window = newWindow("Metal AO verification", ivec2(480, 320),
    visible = false)
  initMetal(window)
  var
    fixture = initFixture()
    occlusion = initScreenOcclusion()
  defer:
    occlusion.closeScreenOcclusion()
    destroy(fixture.vertexBuffer)
    destroy(fixture.program)
    destroy(fixture.depthProgram)
    shutdownMetal()
    window.close()

  for requestedSize in [ivec2(480, 320), ivec2(514, 318)]:
    let size = requestedSize
    window.size = size
    pollEvents()
    doAssert window.size == size
    for orthographic in [false, true]:
      let
        aspect = size.x.float32 / size.y.float32
        projection =
          if orthographic: ortho(-4'f * aspect, 4'f * aspect, -4'f, 4'f,
            0.1'f, 50'f)
          else: perspective(45'f, aspect, 0.1'f, 50'f)
        view = lookAt(vec3(4, 5, 7), vec3(0, 0.5, 0), vec3(0, 1, 0))
        vp = projection * view

      proc frame(enabled: bool, body: float32,
          captureBodies = true): tuple[before, after: Image] =
        ## Separates static floor depth from a box standing on that floor.
        occlusion.settings.enabled = enabled
        occlusion.settings.bodyOcclusion = body
        beginFrame(size.x, size.y, color(0.06, 0.08, 0.1, 1))
        let scene = newRenderTarget(size.x, size.y, samples = samples,
          stencil = true)
        pushTarget(scene)
        clear(color(0.06, 0.08, 0.1, 1))
        fixture.quad(vec3(-4, 0, -4), vec3(-4, 0, 4),
          vec3(4, 0, 4), vec3(4, 0, -4))
        fixture.draw(vp, vec3(0.8))
        if captureBodies:
          occlusion.captureGround(size)
        for x in [-0.7'f, 0.7'f]:
          fixture.quad(vec3(x, 0, -0.7), vec3(x, 1.8, -0.7),
            vec3(x, 1.8, 0.7), vec3(x, 0, 0.7))
        for z in [-0.7'f, 0.7'f]:
          fixture.quad(vec3(-0.7, 0, z), vec3(-0.7, 1.8, z),
            vec3(0.7, 1.8, z), vec3(0.7, 0, z))
        fixture.quad(vec3(-0.7, 1.8, -0.7), vec3(-0.7, 1.8, 0.7),
          vec3(0.7, 1.8, 0.7), vec3(0.7, 1.8, -0.7))
        fixture.draw(vp, vec3(0.6, 0.7, 0.85))
        result.before = captureTargetImage()
        let sceneDepth = fixture.captureDepth()
        occlusion.applyScreenOcclusion(size, projection)
        doAssert metalRenderer.target == scene,
          "AO must restore the active render target"
        result.after = captureTargetImage()
        doAssert fixture.captureDepth().data == sceneDepth.data,
          "AO must preserve scene depth for subsequent world rendering"
        popTarget()
        endFrame(present = false)
        destroy(scene)

      let
        disabled = frame(false, 1)
        full = frame(true, 1)
        protected = frame(true, 0)
        withoutGround = frame(true, 0, false)
      doAssert disabled.before.data == disabled.after.data,
        "Disabled AO must preserve the entire scene"
      doAssert full.before.data == disabled.before.data
      doAssert withoutGround.after.data == full.after.data,
        "Ground capture must not leak from the previous frame"
      var groundDarkened, bodyDarkened, groundUnchanged, skyUnchanged: int
      for i, pixel in full.before.data:
        let
          shaded = full.after.data[i]
          masked = protected.after.data[i]
          ground = pixel.r == 204 and pixel.g == 204 and pixel.b == 204
          body = pixel.r == 153 and pixel.g in [178'u8, 179'u8] and
            pixel.b == 217
        if ground:
          if shaded.r.int < pixel.r.int - 3:
            inc groundDarkened
          elif shaded == pixel:
            inc groundUnchanged
          doAssert shaded == masked,
            "Protecting bodies must retain their contact shadows on ground"
        elif body:
          if shaded.r.int < pixel.r.int - 3:
            inc bodyDarkened
          doAssert masked == pixel,
            "Zero body occlusion must preserve character colors"
        elif pixel.r < 25 and pixel.b < 30:
          if shaded == pixel:
            inc skyUnchanged
      doAssert groundDarkened > 200, "Contacts must visibly darken the floor"
      doAssert bodyDarkened > 100, "Body strength must control visible shading"
      doAssert groundUnchanged > 2000, "Distant floor must stay unchanged"
      doAssert skyUnchanged > 2000, "Background must stay unchanged"
      echo "PASS Metal screen AO samples=", samples, " ", size,
        " ortho=", orthographic,
        ": ", groundDarkened, " ground / ", bodyDarkened, " body pixels"

checkOcclusion(1)
checkOcclusion(4)
