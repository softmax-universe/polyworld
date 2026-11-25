## GPU uploads and draws the shared solid card geometry.

import shady, vmath
import polyworld/backends/passes/common
import ../../tableshaders

type
  SolidRenderer* = object
    program: ShaderProgram
    vertexBuffer: VertexBuffer
    vertices*: seq[float32]

proc initSolidRenderer*(): SolidRenderer =
  ## Creates the solid pipeline without allocating an empty vertex buffer.
  result.program = newProgram(
    nativeStage(solidVertex, shaderVertex),
    nativeStage(solidFragment, shaderFragment),
    VertexLayout(stride: 10 * sizeof(float32), attributes: @[
      VertexAttribute(name: "position", format: Float3, offset: 0),
      VertexAttribute(name: "normal", format: Float3,
        offset: 3 * sizeof(float32)),
      VertexAttribute(name: "color", format: Float4,
        offset: 6 * sizeof(float32))
    ])
  )

proc draw*(renderer: var SolidRenderer, viewProjection: Mat4) =
  ## Uploads the frame's slabs and renders opaque depth-tested triangles.
  if renderer.vertices.len == 0:
    return
  if renderer.vertexBuffer.isNil:
    renderer.vertexBuffer = newBuffer(renderer.vertices)
  else:
    updateBuffer(renderer.vertexBuffer, renderer.vertices)
  renderer.program.setUniform("solidViewProjection", viewProjection)
  renderer.program.setUniform("solidLightDirection",
    normalize(vec3(-0.5, 1.0, 0.65)))
  draw(renderer.program, renderer.vertexBuffer, renderer.vertices.len div 10,
    DrawState(depthTest: true, depthWrite: true, depthCompare: Less))
