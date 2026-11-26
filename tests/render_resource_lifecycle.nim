## Run with a current OpenGL context to check renderer resource ownership.
import std/importutils
import chroma, opengl, vmath, windy
import polyworld/[shapes, worldbars]

privateAccess(WorldBarRenderer)
privateAccess(ShapeRenderer)
privateAccess(typeof(default(WorldBarRenderer).gpu))
privateAccess(typeof(default(ShapeRenderer).gpu))

type ResourceHandles = object
  program, vertexArray, vertexBuffer, texture: GLuint

proc handles(bars: WorldBarRenderer): ResourceHandles =
  ## Snapshots the concrete resources owned by the shared billboard pass.
  ResourceHandles(program: bars.gpu.program.handle,
    vertexArray: bars.gpu.program.vao,
    vertexBuffer: bars.gpu.program.stream.handle,
    texture: bars.gpu.whiteTexture.handle)

proc handles(shapes: ShapeRenderer): ResourceHandles =
  ## Snapshots the concrete resources owned by the shared shape pass.
  ResourceHandles(program: shapes.gpu.program.handle,
    vertexArray: shapes.gpu.program.vao,
    vertexBuffer: shapes.gpu.program.stream.handle,
    texture: shapes.gpu.whiteTexture.handle)

proc alive(handles: ResourceHandles, expected: bool) =
  ## Checks driver ownership independently of invalidated host wrappers.
  doAssert (glIsProgram(handles.program) == GL_TRUE) == expected
  doAssert (glIsVertexArray(handles.vertexArray) == GL_TRUE) == expected
  doAssert (glIsBuffer(handles.vertexBuffer) == GL_TRUE) == expected
  doAssert (glIsTexture(handles.texture) == GL_TRUE) == expected

proc activate(bars: var WorldBarRenderer) =
  ## Creates lazy draw resources before inspecting their driver ownership.
  bars.addBillboardQuad(vec3(0), vec2(0), vec2(0.5), rgbx(255, 255, 255, 255))
  bars.draw(mat4(), vec3(1, 0, 0), vec3(0, 1, 0))

proc activate(shapes: var ShapeRenderer) =
  ## Creates lazy draw resources before inspecting their driver ownership.
  shapes.addQuad(vec3(-0.5, -0.5, 0), vec3(0.5, -0.5, 0),
    vec3(0.5, 0.5, 0), vec3(-0.5, 0.5, 0), rgbx(255, 255, 255, 255))
  shapes.draw(mat4())

let window = newWindow("Renderer resource lifetime", ivec2(64),
  visible = false, vsync = false)
window.makeContextCurrent()
loadExtensions()

var emptyBars: WorldBarRenderer
var emptyShapes: ShapeRenderer
emptyBars.closeWorldBarRenderer()
emptyShapes.closeShapeRenderer()

for cycle in 0 ..< 2:
  var
    bars = initWorldBarRenderer()
    peerBars = initWorldBarRenderer()
    shapes = initShapeRenderer()
    peerShapes = initShapeRenderer()
  shapes.texture = peerShapes.gpu.whiteTexture
  bars.activate()
  peerBars.activate()
  shapes.activate()
  peerShapes.activate()
  bars.handles().alive(true)
  shapes.handles().alive(true)
  # Observe deleted handles without treating their copies as resource owners.
  let oldBars = bars.handles()
  let oldShapes = shapes.handles()
  bars.closeWorldBarRenderer()
  shapes.closeShapeRenderer()
  oldBars.alive(false)
  oldShapes.alive(false)
  doAssert bars == WorldBarRenderer()
  doAssert shapes == ShapeRenderer()
  bars.closeWorldBarRenderer()
  shapes.closeShapeRenderer()
  peerBars.handles().alive(true)
  peerShapes.handles().alive(true)
  peerBars.closeWorldBarRenderer()
  peerShapes.closeShapeRenderer()
  doAssert glGetError() == GL_NO_ERROR

echo "Renderer release, repeated close, borrowed textures, and recreation passed"
