## Shared Shady stages for card slabs and solid table geometry.

import shady, vmath

var
  solidViewProjection*: Uniform[Mat4]
  solidLightDirection*: Uniform[Vec3]

proc solidVertex*(
    gl_Position: var Vec4,
    fragmentNormal: var Vec3,
    fragmentColor: var Vec4,
    position: Vec3,
    normal: Vec3,
    color: Vec4
) =
  gl_Position = solidViewProjection * vec4(position, 1)
  fragmentNormal = normal
  fragmentColor = color

proc solidFragment*(
    outputColor: var Vec4,
    fragmentNormal: Vec3,
    fragmentColor: Vec4
) =
  let light =
    0.55'f32 +
    0.45'f32 * max(
      dot(normalize(fragmentNormal), normalize(solidLightDirection)),
      0.0'f32
    )
  outputColor = vec4(fragmentColor.xyz * light, fragmentColor.w)
