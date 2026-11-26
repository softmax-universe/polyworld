## Shared Shady programs for world cards and cached HUD faces.

import shady, vmath

var
  cardViewProjection*: Uniform[Mat4]
  cardAtlasSize: Uniform[Vec2]
  cardAtlasSampler: Uniform[Sampler2D]
  hudViewportSize: Uniform[Vec2]
  hudTint: Uniform[Vec4]
  hudSampler: Uniform[Sampler2D]

proc cardVertex*(position: Vec3, uv: Vec2, tint: Vec4,
    gl_Position: var Vec4, fragmentUv: var Vec2, fragmentTint: var Vec4) =
  ## Projects world cards and normalizes their atlas pixel coordinates.
  gl_Position = cardViewProjection * vec4(position, 1)
  fragmentUv = uv / cardAtlasSize
  fragmentTint = tint

proc cardFragment*(fragmentUv: Vec2, fragmentTint: Vec4,
    outputColor: var Vec4) =
  ## Applies card brightness and damage flash while retaining surface alpha.
  let surface = texture(cardAtlasSampler, fragmentUv)
  if surface.a < 0.01'f:
    discardFragment()
  outputColor = vec4(mix(surface.rgb * fragmentTint.rgb,
    vec3(1.0, 0.025, 0.045) * surface.a, fragmentTint.w * 0.88'f), surface.a)

proc hudVertex*(position: Vec2, uv: Vec2, gl_Position: var Vec4,
    fragmentUv: var Vec2) =
  ## Projects HUD face positions measured from the framebuffer's top left.
  gl_Position = vec4(position.x / hudViewportSize.x * 2 - 1,
    1 - position.y / hudViewportSize.y * 2, 0, 1)
  fragmentUv = uv

proc hudFragment*(fragmentUv: Vec2, outputColor: var Vec4) =
  ## Applies the HUD tint to the cached face texture.
  outputColor = texture(hudSampler, fragmentUv) * hudTint
