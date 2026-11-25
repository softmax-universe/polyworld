## Coordinate transforms shared by screen-space shaders.

import vmath

proc screenCoordinates*(position, yTransform: Vec2): Vec2 =
  ## Converts the vertical coordinate between logical and texture origins.
  vec2(position.x, position.y * yTransform.x + yTransform.y)
