## Sun shadow maps for the polyworld games. One directional light renders
## every caster (terrain, props, trees, characters) into depth maps with
## hardware PCF comparison filtering, and the lit shaders in quadterrain and
## toon darken whatever the light cannot see. A day clock drives the whole
## atmosphere: the sun arcs east to west from 6:00 to 20:00, the moon rides
## the same track at night and shades like a darker sun, and a signed
## horizon band fades the directional light toward the shadow side so the
## sun-to-moon swap does not pop.
##
## A continuously rotating light re-rasterizes every caster edge each frame,
## which boils shadow edges (and the toon band turns that sampling noise
## into binary color flips). So the sun the SHADOW MAPS see is quantized to
## SunStepHours increments — stable for many frames — and every frame
## renders two maps, one at each neighbouring step; receivers sample both
## and cross-fade by the smooth clock, so shadows dissolve from one sun
## position to the next instead of shimmering. Lighting, palette, and
## strengths all use the smooth hour directly. A fixed light needs only
## the first map because it has no cross-fade.
##
## This module owns the depth framebuffers, the light matrices, the sun
## path, and the depth-only shader programs. The mesh modules build their
## own depth vertex arrays against these programs and draw inside the
## sunDepthPasses bracket, using sunDepthPassMvp() as the light transform.
## Ported from experiments/terrain/quadterrain_shadows.nim.

import
  std/os,
  shady, vmath

const
  SunShadowMapSize* =
    when defined(emscripten):
      2048
    else:
      4096
  SunShadowTexel* = 1.0'f / SunShadowMapSize.float32
  SunStepHours* = 0.05'f
    ## The shadow-map sun advances in steps of this many game hours; the
    ## cross-fade between neighbouring steps is what the viewer sees move.

var
  sunShadowsEnabled* = true      ## Master switch; SUN_SHADOWS=0 disables.
  sunAzimuth* = 48.0'f         ## Degrees around the map.
  sunElevation* = 53.0'f       ## Degrees above the horizon.
  sunShadowStrength* = 0.75'f  ## 1: full shadow drops to the shadow band.
  sunShadingStrength* = 1.0'f  ## 1: full directional shading, 0: flat.
  sunShadowBias* = 0.0012'f    ## Depth offset that hides self-shadow acne.
  sunShadowSoftness* = 1.5'f   ## PCF spread in shadow-map texels.
  moonShadowStrength* = 0.4'f  ## Night moon casts like the sun, darker.
  lightLevel* = 1.0'f          ## 1 full sun or moonlight, 0 shadow side.
  solarElevation* = 53.0'f     ## Signed: sun positive, moon negative.
  sunDirection* = normalize(vec3(0.45, 0.8, 0.4))  ## Toward the sun (smooth).
  sunLightMvp0*: Mat4            ## Light view-projection at the earlier step.
  sunLightMvp1*: Mat4            ## The same at the next step.
  sunShadowBlend*: float32       ## 0 at step 0 .. 1 at step 1.
  sunLightRadius = 100.0'f
  sunLightDistance = 170.0'f
  activeDepthMvp: Mat4

## Depth-only shaders: casters need position (plus uv and texture layer for
## alpha-cutout foliage), nothing else.

var
  sunDepthMvp: Uniform[Mat4]
  cutoutTextures: Uniform[Sampler2dArray]
  cutoutCutoff: Uniform[float32]

proc texture(buffer: Uniform[Sampler2dArray], position: Vec3): Vec4 =
  ## Provides Shady with the texture-array builtin signature.
  vec4(0)

proc sunDepthVert(gl_Position: var Vec4, vertPos: Vec3) =
  ## Projects one caster vertex into the sun's clip space.
  gl_Position = sunDepthMvp * vec4(vertPos.x, vertPos.y, vertPos.z, 1.0)

proc sunDepthFrag(fragColor: var Vec4) =
  ## Depth-only target; the color write goes nowhere.
  fragColor = vec4(1.0, 1.0, 1.0, 1.0)

proc sunCutoutDepthVert(
    gl_Position: var Vec4,
    vertPos: Vec3,
    vertUv: Vec3,
    fragUv: var Vec3
) =
  ## Projects a textured caster vertex, keeping uv for the cutout test.
  gl_Position = sunDepthMvp * vec4(vertPos.x, vertPos.y, vertPos.z, 1.0)
  fragUv = vertUv

proc sunCutoutDepthFrag(fragUv: Vec3) =
  ## Alpha-cutout casters (foliage) keep their holes in the shadow map.
  if texture(cutoutTextures, fragUv).w < cutoutCutoff:
    discardFragment()

## Sun rig

proc sunDirectionFor(azimuth, elevation: float32): Vec3 =
  ## Unit direction toward the sun for compass and altitude angles.
  let
    a = azimuth * PI.float32 / 180.0
    e = elevation * PI.float32 / 180.0
  vec3(cos(e) * sin(a), sin(e), cos(e) * cos(a))

proc lightMatrixFor(azimuth, elevation: float32): Mat4 =
  ## The sun camera's orthographic view-projection: centered on the map
  ## origin, sized once (initSunShadows) to cover the whole grid.
  let
    direction = sunDirectionFor(azimuth, elevation)
    view = lookAt(direction * sunLightDistance, vec3(0, 0, 0), vec3(0, 1, 0))
    projection = ortho(
      -sunLightRadius, sunLightRadius, -sunLightRadius, sunLightRadius,
      sunLightDistance - sunLightRadius, sunLightDistance + sunLightRadius)
  projection * view

const HorizonMapFloor = 8.0'f
  ## Keeps the depth-map caster off the ground while the horizon fade
  ## has already killed the directional light.

proc mapElevation(elevation: float32): float32 =
  ## Floors elevation so the shadow map stays valid near the horizon.
  max(elevation, HorizonMapFloor)

proc horizonLight*(signedElev: float32): float32 =
  ## Moonlight below -20°, no directional light from -10° to +10°,
  ## full sun above +20°. The scene stays visible; only the light fades.
  if signedElev <= -20:
    result = 1.0
  elif signedElev < -10:
    result = 1.0 - smoothstep(-20.0'f, -10.0'f, signedElev)
  elif signedElev <= 10:
    result = 0.0
  elif signedElev < 20:
    result = smoothstep(10.0'f, 20.0'f, signedElev)
  else:
    result = 1.0

proc updateSunMatrix*() =
  ## Recomputes the smooth sun direction and points both shadow steps at it
  ## (blend 0) — the manual path when no day clock drives the rig.
  solarElevation = sunElevation
  lightLevel = horizonLight(solarElevation)
  sunDirection = sunDirectionFor(sunAzimuth, mapElevation(sunElevation))
  sunLightMvp0 = lightMatrixFor(sunAzimuth, mapElevation(sunElevation))
  sunLightMvp1 = sunLightMvp0
  sunShadowBlend = 0

proc sunRigAt(hour: float32): tuple[azimuth, elevation, sunUp: float32] =
  ## The sun's place at an hour: it arcs east to west from 6:00 to 20:00,
  ## and the moon rides the same track through the night. Elevation is
  ## allowed to fall through the 10-20° fade so the handoff is dark.
  ## sunUp is 0 at night, 1 at noon.
  let h = ((hour mod 24) + 24) mod 24
  if h >= 6 and h <= 20:
    let t = (h - 6) / 14
    result.sunUp = sin(t * PI.float32)
    result.azimuth = 90 + t * 180
    result.elevation = result.sunUp * 70
  else:
    let sinceSunset = if h > 20: h - 20 else: h + 4
    let t = sinceSunset / 10
    result.sunUp = 0
    result.azimuth = 90 + t * 180
    result.elevation = sin(t * PI.float32) * 45

proc applySunHour*(
  hour: float32, azimuthOffset = 0.0'f, elevationScale = 1.0'f
) =
  ## Drives daylight and moonlight from the clock, with an optional orbit tilt.
  ## Neighboring quantized shadow maps cross-fade to avoid shimmering.
  ## Lighting and both shadow steps use the same azimuth and elevation controls.
  assert elevationScale > 0
  let
    smooth = sunRigAt(hour)
    h = ((hour mod 24) + 24) mod 24
    isDay = h >= 6 and h <= 20
  sunAzimuth = smooth.azimuth + azimuthOffset
  sunElevation = smooth.elevation * elevationScale
  solarElevation =
    if isDay:
      sunElevation
    else:
      -sunElevation
  lightLevel = horizonLight(solarElevation)
  sunDirection = sunDirectionFor(sunAzimuth, mapElevation(sunElevation))
  if isDay:
    let strength =
      0.15'f + 0.7'f * smoothstep(0.0'f, 0.3'f, smooth.sunUp)
    sunShadowStrength = strength
    sunShadingStrength = strength
  else:
    sunShadowStrength = moonShadowStrength
    sunShadingStrength = 0.8'f
  let
    step0 = floor(h / SunStepHours) * SunStepHours
    rig0 = sunRigAt(step0)
    rig1 = sunRigAt(step0 + SunStepHours)
  sunShadowBlend = clamp((h - step0) / SunStepHours, 0.0'f, 1.0'f)
  sunLightMvp0 = lightMatrixFor(
    rig0.azimuth + azimuthOffset,
    mapElevation(rig0.elevation * elevationScale)
  )
  sunLightMvp1 = lightMatrixFor(
    rig1.azimuth + azimuthOffset,
    mapElevation(rig1.elevation * elevationScale)
  )

proc sunDepthPassMvp*(): Mat4 =
  ## Returns the light view-projection of the active shadow pass.
  activeDepthMvp

when defined(useDirectX):
  include backends/directx/shadows
elif defined(useVulkan):
  include backends/vulkan/shadows
elif defined(useMetal4):
  include backends/metal/shadows
else:
  include backends/opengl/shadows
