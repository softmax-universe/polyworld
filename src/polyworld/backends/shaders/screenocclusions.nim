## Screen-space ambient occlusion for clients that draw straight to the
## window.
##
## Ported from CaC's post pass (games/cac/scene/post.nim): the same
## 16-tap spiral around a depth-reconstructed normal, at half resolution,
## the same depth-aware blur and the same tinted multiply. Three changes fit
## it to a game that keeps drawing into the window's multisampled buffer:
##
## - One blit copies the opaque scene's depth out of the window, so nothing
##   is rerouted offscreen and MSAA stays as it is.
## - The sample radius and the blur's depth edges follow the projection's
##   clip w, so one set of world-unit settings works for perspective and
##   orthographic cameras alike.
## - It darkens the window in place. Call `applyScreenOcclusion` after the
##   opaque pass and before particles, gizmos and the HUD; those stay bright.
##
## Calling `captureGround` between the scenery and the characters marks what
## is drawn after it as bodies: they still cast contact shadows onto the
## ground, but keep only `bodyOcclusion` of their own darkening, so their
## colors stay readable.
##
## Normals come from depth alone: CaC's material-normal replay is left out.
## `screenOcclusionSettings` reads PREFIX=0 (off), PREFIX_RADIUS,
## PREFIX_INTENSITY and PREFIX_BIAS, like CaC's CAC_SSAO variables.

import
  std/[os, strutils],
  shady, vmath,
  screens, occlusions

export screens.fullscreenVertex

type
  ScreenOcclusionError* = object of CatchableError

  ScreenOcclusionSettings* = object
    enabled*: bool
    radius*: float32    ## World units the occlusion looks around a pixel.
    intensity*: float32
    bias*: float32      ## Cosine ignored, hides flat-surface noise.
    tint*: Vec3         ## Color full occlusion fades toward.
    sharpness*: float32
      ## How hard the blur stops at depth gaps, measured against the view's
      ## half height at that depth.
    bodyOcclusion*: float32
      ## Share of its darkening a pixel drawn after `captureGround` keeps.
var
  depthTexture, groundTexture, occlusionTexture: Uniform[Sampler2D]
  inverseProjection: Uniform[Mat4]
  texel, projectionScale, clipW: Uniform[Vec2]
  radius, intensity, bias: Uniform[float32]
  direction, halfSize, depthTexel: Uniform[Vec2]
  depthTerms: Uniform[Vec4]
  edgeScale, bodyOcclusion: Uniform[float32]
  tint: Uniform[Vec3]
  textureYTransform, fragmentYTransform: Uniform[Vec2]

proc viewPosition(p: Vec2): Vec3 =
  ## Reconstructs positions at nearest depth texel centers to avoid row tilts.
  let
    center = (floor(p / texel) + 0.5'f) * texel
    depth = texture(depthTexture, screenCoordinates(center, textureYTransform)).x
    position = inverseProjection *
      vec4(center * 2.0'f - 1.0'f, vec2(depth * 2.0'f - 1.0'f, 1.0'f))
  result = position.xyz / position.w

proc viewNormal(p: Vec2, center: Vec3): Vec3 =
  ## Chooses depth-nearest neighbors to keep silhouette normals clean.
  let
    right = viewPosition(p + vec2(texel.x, 0.0'f)) - center
    left = center - viewPosition(p - vec2(texel.x, 0.0'f))
    up = viewPosition(p + vec2(0.0'f, texel.y)) - center
    down = center - viewPosition(p - vec2(0.0'f, texel.y))
  result = depthNormal(right, left, up, down)

proc occlusionFragment*(gl_FragCoord: Vec4, fragColor: var Vec4) =
  ## Samples a world-sized spiral around a depth-reconstructed surface normal.
  # Pick one full-resolution texel so each half-resolution row rounds alike.
  let
    base = (floor(screenCoordinates(gl_FragCoord.xy, fragmentYTransform)) * 2.0'f + 0.5'f) * texel
    depth = texture(depthTexture, screenCoordinates(base, textureYTransform)).x
  if depth >= 1.0'f:
    fragColor = vec4(1.0'f)
    return
  let
    center = viewPosition(base)
    normal = viewNormal(base, center)
    # Clip w is -z for perspective cameras and 1 for orthographic cameras.
    w = max(clipW.x * center.z + clipW.y, 0.1'f)
    uvRadius = 0.5'f * projectionScale * radius / w
    spin = occlusionHash(screenCoordinates(gl_FragCoord.xy, fragmentYTransform)) * 6.2831853'f
  var occlusion = 0.0'f
  for i in 0 ..< OcclusionTaps:
    let
      offset = occlusionOffset(float32(i), spin, uvRadius)
      delta = viewPosition(base + offset) - center
    occlusion += occlusionContribution(delta, normal, radius, bias)
  let ao = occlusionAmount(occlusion, intensity)
  fragColor = vec4(ao, ao, ao, 1.0'f)

proc viewDepth(p: Vec2): float32 =
  ## Reads positive view depth at the full-resolution texel used for occlusion.
  let
    texelCenter = (floor(p * halfSize) * 2.0'f + 0.5'f) * depthTexel
    ndc = texture(depthTexture, screenCoordinates(texelCenter, textureYTransform)).x * 2.0'f - 1.0'f
  result = -(depthTerms.x * ndc + depthTerms.y) /
    (depthTerms.z * ndc + depthTerms.w)

proc blurFragment*(uv: Vec2, fragColor: var Vec4) =
  ## Smooths occlusion while preserving depth edges for either camera kind.
  let
    centerDepth = viewDepth(uv)
    scale = edgeScale / max(clipW.y - clipW.x * centerDepth, 0.0001'f)
  var
    total = 0.0'f
    weights = 0.0'f
  for i in -4 .. 4:
    let
      p = uv + direction * float32(i)
      difference = abs(viewDepth(p) - centerDepth) * scale
      weight = occlusionBlurWeight(i.int32, difference)
    total += texture(occlusionTexture, screenCoordinates(p, textureYTransform)).x * weight
    weights += weight
  let ao = total / max(weights, 0.0001'f)
  fragColor = vec4(ao, ao, ao, 1.0'f)

proc multiplyFragment*(uv: Vec2, gl_FragCoord: Vec4, fragColor: var Vec4) =
  ## Tints occluded surfaces while retaining configurable body brightness.
  var ao = texture(occlusionTexture, screenCoordinates(uv, textureYTransform)).x
  if ao > 0.996'f:
    discardFragment()
  # Without a ground copy both samplers read the same scene depth texture.
  let pixel = ivec2(gl_FragCoord.x.int32, gl_FragCoord.y.int32)
  if texelFetch(depthTexture, pixel, 0).x <
    texelFetch(groundTexture, pixel, 0).x:
      ao = mix(1.0'f, ao, bodyOcclusion)
  fragColor = occlusionTint(tint, ao)

proc defaultScreenOcclusionSettings*(): ScreenOcclusionSettings =
  ## CaC's tuned values. Its blur sharpness of 40 per unit of relative depth
  ## becomes 15.4 here: its 42 degree camera has a projection scale of 2.6.
  ScreenOcclusionSettings(
    enabled: true,
    radius: 1.501,
    intensity: 3.523,
    bias: 0.08,
    tint: vec3(0.10, 0.10, 0.16),
    sharpness: 15.4,
    bodyOcclusion: 0.25
  )

proc envFlag(name: string, default: bool): bool =
  ## Reads an optional boolean setting from the environment.
  let value = getEnv(name)
  if value.len == 0: default else: value notin ["0", "false", "off", "no"]

proc envFloat(name: string, default: float32): float32 =
  ## Reads an optional numeric setting from the environment.
  try: parseFloat(getEnv(name, $default)).float32
  except ValueError: default

proc screenOcclusionSettings*(
    prefix: string,
    defaults = defaultScreenOcclusionSettings()
): ScreenOcclusionSettings =
  ## Applies PREFIX=0 (off), PREFIX_RADIUS, PREFIX_INTENSITY and PREFIX_BIAS
  ## from the environment over the defaults.
  result = defaults
  result.enabled = envFlag(prefix, defaults.enabled)
  result.radius = envFloat(prefix & "_RADIUS", defaults.radius)
  result.intensity = envFloat(prefix & "_INTENSITY", defaults.intensity)
  result.bias = envFloat(prefix & "_BIAS", defaults.bias)
