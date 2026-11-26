## Run with a current OpenGL context to check renderer resource ownership.
import std/importutils
import opengl, vmath, windy
import polyworld/[shapes, worldbars]

privateAccess(WorldBarRenderer)
privateAccess(ShapeRenderer)
privateAccess(typeof(default(WorldBarRenderer).gpu))
privateAccess(typeof(default(ShapeRenderer).gpu))

proc alive(bars: WorldBarRenderer, expected: bool) =
  ## Checks whether all owned world-bar resources remain alive.
  doAssert (glIsProgram(bars.gpu.program) == GL_TRUE) == expected
  doAssert (glIsVertexArray(bars.gpu.vertexArray) == GL_TRUE) == expected
  doAssert (glIsBuffer(bars.gpu.vertexBuffer) == GL_TRUE) == expected
  doAssert (glIsTexture(bars.gpu.whiteTexture) == GL_TRUE) == expected

proc alive(shapes: ShapeRenderer, expected: bool) =
  doAssert (glIsProgram(shapes.gpu.program) == GL_TRUE) == expected
  doAssert (glIsVertexArray(shapes.gpu.vertexArray) == GL_TRUE) == expected
  doAssert (glIsBuffer(shapes.gpu.vertexBuffer) == GL_TRUE) == expected
  doAssert (glIsTexture(shapes.gpu.whiteTexture) == GL_TRUE) == expected

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
  bars.alive(true)
  shapes.alive(true)
  # Observe deleted handles without treating the copies as resource owners.
  let oldBars = bars
  let oldShapes = shapes
  bars.closeWorldBarRenderer()
  shapes.closeShapeRenderer()
  oldBars.alive(false)
  oldShapes.alive(false)
  doAssert bars == WorldBarRenderer()
  doAssert shapes == ShapeRenderer()
  bars.closeWorldBarRenderer()
  shapes.closeShapeRenderer()
  peerBars.alive(true)
  peerShapes.alive(true)
  peerBars.closeWorldBarRenderer()
  peerShapes.closeShapeRenderer()
  doAssert glGetError() == GL_NO_ERROR

echo "Renderer release, repeated close, borrowed textures, and recreation passed"
