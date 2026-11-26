## Exercises native water capture, reflection, and resource recreation.

when not defined(useMetal4):
  {.error: "Compile this native rendering test with -d:useMetal4".}

include ../src/polyworld/waters
import windy

var
  probeColor, probeDepth: Uniform[Sampler2D]

proc probeVertex(gl_Position: var Vec4, point: Vec2, uv: var Vec2) =
  ## Covers the target and addresses native top-left capture coordinates.
  gl_Position = vec4(point.x, point.y, -0.5, 1.0)
  uv = vec2(point.x * 0.5 + 0.5, 0.5 - point.y * 0.5)

proc fillFragment(fragColor: var Vec4) =
  ## Writes a recognizable scene color for the color and depth snapshot.
  fragColor = vec4(0.75, 0.2, 0.1, 1.0)

proc probeFragment(fragColor: var Vec4, uv: Vec2) =
  ## Encodes captured color and depth into independently checked channels.
  fragColor = vec4(texture(probeColor, uv).x,
    texture(probeDepth, uv).x, 0.0, 1.0)

proc checkPixel(image: Image, red, green: int) =
  ## Checks the sampled capture with one byte of quantization tolerance.
  let pixel = image[image.width div 2, image.height div 2]
  doAssert abs(pixel.r.int - red) <= 1, $pixel
  doAssert abs(pixel.g.int - green) <= 1, $pixel
  doAssert pixel.b == 0 and pixel.a == 255, $pixel

let window = newWindow("Metal water regression", ivec2(64),
  visible = false, vsync = false)
initMetal(window)
installWaters()
let
  layout = VertexLayout(stride: 2 * sizeof(float32), attributes: @[
    VertexAttribute(name: "point", format: Float2, offset: 0)
  ])
  fill = newProgram(toShader(probeVertex, metalMSL, shaderVertex),
    toShader(fillFragment, metalMSL, shaderFragment), layout)
  probe = newProgram(toShader(probeVertex, metalMSL, shaderVertex),
    toShader(probeFragment, metalMSL, shaderFragment), layout)
  vertices = newBuffer([-1.0'f, -1, 3, -1, -1, 3])
  water = newProgram(waterShaderOverride.vertex, waterShaderOverride.fragment,
    VertexLayout(stride: 3 * sizeof(float32), attributes: @[
      VertexAttribute(name: "vertPos", format: Float3, offset: 0)
    ]))

for samples in [1, 4]:
  initWaters()
  beginFrame(64, 64, color(0, 0, 0, 1))
  let scene = newRenderTarget(64, 64, samples = samples, stencil = true)
  pushTarget(scene)
  clear(color(0, 0, 0, 1), stencil = true)
  draw(fill, vertices, 3, DrawState(depthTest: true, depthWrite: true))
  captureScene(ivec2(64))
  doAssert metalRenderer.target == scene
  beginReflection(ivec2(64))
  let reflectedTarget = metalRenderer.target
  doAssert reflectedTarget.color.pixelFormat == MTLPixelFormatRGBA16Float
  let sky = color(0.4, 0.2, 0.7, 1)
  drawWaterSky(mat4(), vec3(0, 0, 2), sky, sky, sky)
  endReflection()
  doAssert metalRenderer.target == scene
  popTarget()
  probe.bindTexture("probeColor", sceneCopy.color)
  probe.bindTexture("probeDepth", sceneCopy.depth)
  draw(probe, vertices, 3)
  checkPixel(captureImage(), 191, 64)
  probe.bindTexture("probeColor", reflectedTarget.color)
  probe.bindTexture("probeDepth", reflectedTarget.depth)
  draw(probe, vertices, 3)
  checkPixel(captureImage(), 102, 255)
  endFrame(false)
  destroy(scene)
  destroyWaters()
  destroyWaters()

destroy(water)
destroy(fill)
destroy(probe)
destroy(vertices)
shutdownMetal()
echo "Metal water captures, HDR reflections, MSAA depth and recreation passed"
