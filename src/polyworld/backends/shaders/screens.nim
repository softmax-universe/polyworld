## Coordinate transforms shared by screen-space shaders.

import shady, vmath

var
  screenTextureYTransform: Uniform[Vec2]
  copySource: Uniform[Sampler2D]

proc screenCoordinates*(position, yTransform: Vec2): Vec2 =
  ## Converts the vertical coordinate between logical and texture origins.
  vec2(position.x, position.y * yTransform.x + yTransform.y)

proc fullscreenCorner*(index: int32): Vec2 =
  ## Generates the three corners of an oversized fullscreen triangle.
  vec2(
    float32((index mod 2) * 2),
    float32((index div 2) * 2)
  )

proc fullscreenClipPosition*(corner: Vec2): Vec4 =
  ## Maps a fullscreen triangle corner into clip coordinates.
  vec4(
    corner.x * 2.0'f - 1.0'f,
    corner.y * 2.0'f - 1.0'f,
    0.0'f,
    1.0'f
  )

proc fullscreenPosition*(gl_Position: var Vec4) =
  ## Covers the target with one triangle generated from the vertex index.
  gl_Position = fullscreenClipPosition(fullscreenCorner(gl_VertexID))

proc fullscreenVertex*(gl_Position: var Vec4, uv: var Vec2) =
  ## Covers the target with bottom-left logical sampling coordinates.
  let corner = fullscreenCorner(gl_VertexID)
  uv = corner
  gl_Position = fullscreenClipPosition(corner)

proc fullscreenTextureVertex*(gl_Position: var Vec4, uv: var Vec2) =
  ## Covers the target with the caller's texture-coordinate orientation.
  let corner = fullscreenCorner(gl_VertexID)
  uv = screenCoordinates(corner, screenTextureYTransform)
  gl_Position = fullscreenClipPosition(corner)

proc copyFragment*(uv: Vec2, fragColor: var Vec4) =
  ## Resamples a source texture for a fullscreen copy or reduction.
  fragColor = texture(copySource, uv)
