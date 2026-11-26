## Shared distortion shapes, billboard geometry and Shady shader sources.

import shady, vmath

const
  VertexFloats* = 9 ## Position 3, corner 2, kind, progress, shift pixels, seed.

type
  DistortionError* = object of CatchableError

  DistortionKind* = enum
    ShockwaveDistortion, HeatDistortion, ShieldDistortion

  Distortion* = object
    kind*: DistortionKind
    center*: Vec3     ## World position.
    radius*: float32  ## World units out to the edge of the effect.
    strength*: float32
      ## Peak shift as a share of the effect's radius on screen: 0.05 is gentle.
    age*, life*: float32  ## Seconds; the distortion is gone once age reaches life.
    seed*: float32    ## Varies heat ripples between sources.

var
  viewMatrix: Uniform[Mat4]
  scene: Uniform[Sampler2d]
  viewportSize: Uniform[Vec2]
  clock: Uniform[float32]
  shiftScale: Uniform[Vec2]

proc distortionVertex*(
    position: Vec3,
    corner: Vec2,
    params: Vec4,
    local: var Vec2,
    shape: var Vec4,
    gl_Position: var Vec4
) =
  ## Projects the distortion quad while preserving its local coordinates.
  local = corner
  shape = params
  gl_Position = viewMatrix * vec4(position, 1.0'f)

proc distortionFragment*(
    gl_FragCoord: Vec4,
    local: Vec2,
    shape: Vec4,
    color: var Vec4
) =
  ## Samples the finished scene through a shockwave, haze, or shield.
  let d = length(local)
  if d >= 1.0'f:
    discardFragment()
  let
    outward =
      if d > 0.0001'f:
        local / d
      else:
        vec2(0.0'f)
    kind = int(shape.x + 0.5'f)
    progress = clamp(shape.y, 0.0'f, 1.0'f)
    pixels = shape.z
    seed = shape.w
  var
    shift = vec2(0.0'f)
    mask = 0.0'f
  if kind == 0:
    # A ring races outward and pushes the picture away from its center.
    let
      ring = exp(-pow((d - progress) / 0.13'f, 2.0'f))
      fade = 1.0'f - progress
    shift = outward * ring * fade
    mask = clamp(ring * fade * 2.0'f, 0.0'f, 1.0'f)
  elif kind == 1:
    # Rising ripples swell in and then fade, strongest in the middle.
    let
      fade = (1.0'f - d) * (1.0'f - progress) *
        min(1.0'f, progress * 6.0'f)
      p = local * 3.5'f + vec2(seed, seed * 1.7'f)
      rise = clock * 3.0'f
    shift = vec2(
      sin(p.y * 4.0'f - rise + sin(p.x * 3.1'f + seed)),
      cos(p.x * 4.7'f + rise * 0.8'f + p.y * 1.3'f)
    ) * fade * 0.5'f
    mask = clamp(fade * 3.0'f, 0.0'f, 1.0'f)
  else:
    # A bubble magnifies its middle and bends harder at its rim.
    let rim = pow(d, 8.0'f)
    shift = -outward * (d * (1.0'f - d) * 0.6'f + rim * 0.8'f)
    mask = 1.0'f - smoothstep(0.92'f, 1.0'f, d)
  let uv = gl_FragCoord.xy / viewportSize +
    shift * shiftScale * pixels / viewportSize
  color = vec4(texture(scene, uv).rgb, mask)

proc age*(distortions: var seq[Distortion], seconds: float32) =
  ## Advances every distortion and drops the finished ones.
  var kept = 0
  for item in distortions.mitems:
    item.age += seconds
    if item.age < item.life:
      distortions[kept] = item
      inc kept
  distortions.setLen(kept)

proc project(point: Vec3, viewMatrix: Mat4, size: IVec2): Vec2 =
  ## Projects a point to pixels to measure the distortion radius.
  let clip = viewMatrix * vec4(point, 1)
  if clip.w <= 0:
    return vec2(-1e6)
  vec2(
    (clip.x / clip.w + 1) * 0.5 * size.x.float32,
    (clip.y / clip.w + 1) * 0.5 * size.y.float32
  )

proc buildDistortionVertices*(
    floats: var seq[float32],
    distortions: openArray[Distortion],
    viewMatrix: Mat4,
    eye, right, up: Vec3,
    size: IVec2
) =
  ## Builds camera-facing quads pulled forward by each distortion radius.
  floats.setLen(0)
  for item in distortions:
    if item.life <= 0 or item.radius <= 0:
      continue
    let
      toEye = eye - item.center
      lift =
        if length(toEye) > 1e-6:
          normalize(toEye) * min(item.radius, length(toEye) * 0.5)
        else:
          vec3(0)
      center = item.center + lift
      onScreen = length(
        project(item.center + right * item.radius, viewMatrix, size) -
        project(item.center, viewMatrix, size))
      pixels = item.strength * onScreen
      params = [item.kind.ord.float32, item.age / item.life, pixels, item.seed]
      sideways = right * item.radius
      upward = up * item.radius
    for (u, v) in [(-1'f, -1'f), (1'f, -1'f), (1'f, 1'f),
        (-1'f, -1'f), (1'f, 1'f), (-1'f, 1'f)]:
      let at = center + sideways * u + upward * v
      floats.add [at.x, at.y, at.z, u, v]
      floats.add params
