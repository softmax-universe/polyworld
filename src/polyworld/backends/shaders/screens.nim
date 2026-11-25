## Coordinate transforms shared by screen-space shaders.

import shady, vmath

proc screenCoordinates*(position, yTransform: Vec2): Vec2 =
  ## Converts the vertical coordinate between logical and texture origins.
  vec2(position.x, position.y * yTransform.x + yTransform.y)

proc fullscreenPosition*(gl_Position: var Vec4) =
  ## Covers the target with one triangle generated from the vertex index.
  let corner = vec2(
    float32((gl_VertexID mod 2) * 2),
    float32((gl_VertexID div 2) * 2)
  )
  gl_Position = vec4(
    corner.x * 2.0'f - 1.0'f,
    corner.y * 2.0'f - 1.0'f,
    0.0'f,
    1.0'f
  )
