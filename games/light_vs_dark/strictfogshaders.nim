## Current-sight reconstruction and compositing shared by every backend.

import shady, vmath

proc strictFogVertex*(gl_Position: var Vec4, uv: var Vec2) =
  ## Covers the viewport with one triangle and matching texture coordinates.
  let point = vec2(
    float32((gl_VertexID mod 2) * 2),
    float32((gl_VertexID div 2) * 2)
  )
  uv = point
  gl_Position = vec4(point * 2.0'f - 1.0'f, vec2(0.0'f, 1.0'f))

proc strictFogFragment*(
    uv: Vec2,
    color: var Vec4,
    groundColor, groundDepth, currentSight: Uniform[Sampler2D],
    inverseView: Uniform[Mat4],
    mapSide: Uniform[float32],
    textureYTransform: Uniform[Vec2]
) =
  ## Restores ground outside current sight after later scene passes.
  let
    sampleUv = vec2(uv.x, uv.y * textureYTransform.x + textureYTransform.y)
    depth = texture(groundDepth, sampleUv).r
    point = inverseView * vec4(uv * 2.0'f - 1.0'f,
      vec2(depth * 2.0'f - 1.0'f, 1.0'f))
    cell = floor(point.xz / point.w + mapSide * 0.5'f)
    inside = cell.x >= 0.0'f and cell.y >= 0.0'f and
      cell.x < mapSide and cell.y < mapSide
  if depth < 1.0'f and inside and
    texelFetch(currentSight, ivec2(cell), 0).r > 0.5'f:
      discardFragment()
  color = texture(groundColor, sampleUv)
