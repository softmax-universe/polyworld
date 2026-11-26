## Shared world-space billboard bars for Polyworld graphical clients.

import
  std/math,
  chroma, shady, vmath

include backends/passes/worldbars_types

const
  VertexFloats = 12
  DefaultGap* = 0.045'f
  DefaultBorder* = 0.035'f
  DefaultDamageHoldSeconds* = 1.25'f
  DefaultDamageFadeSeconds* = 0.75'f

type
  WorldBarError* = object of CatchableError

  BillboardTexture* = enum
    MaskTexture, ColorTexture

  WorldBarRenderer* = object
    gpu: WorldBarGpu
    vertices: seq[float32]

  WorldResourceBar* = object
    value*: float32
    maximum*: float32
    delayedValue*: float32
    height*: float32
    color*: ColorRGBX
    showDamageTrail*: bool

  DamageTrail = object
    id: int32
    observedValue: float32
    delayedValue: float32
    holdSeconds: float32
    seenFrame: int

  DamageTrailTracker* = object
    trails: seq[DamageTrail]
    frame: int

var
  barViewProjection: Uniform[Mat4]
  barCameraRight: Uniform[Vec3]
  barCameraUp: Uniform[Vec3]
  barTexture: Uniform[Sampler2D]

proc barVertex(
    gl_Position: var Vec4,
    fragmentColor: var Vec4,
    fragmentUv: var Vec2,
    fragmentTextureMode: var float32,
    worldCenter: Vec3,
    billboardOffset: Vec2,
    vertexColor: Vec4,
    vertexUv: Vec2,
    vertexTextureMode: float32
) =
  ## Transforms one bar vertex into a camera-facing world-space plane.
  let position = worldCenter +
    barCameraRight * billboardOffset.x +
    barCameraUp * billboardOffset.y
  gl_Position = barViewProjection * vec4(position, 1)
  fragmentColor = vertexColor
  fragmentUv = vertexUv
  fragmentTextureMode = vertexTextureMode

proc barFragment(
    fragColor: var Vec4,
    fragmentColor: Vec4,
    fragmentUv: Vec2,
    fragmentTextureMode: float32
) =
  ## Draws solid bars, tinted font masks, or colored atlas images.
  fragColor = fragmentColor
  if fragmentUv.x >= 0:
    let texel = texture(barTexture, fragmentUv)
    if fragmentTextureMode > 0.5'f:
      # The atlas is premultiplied, while these bars use straight alpha.
      fragColor.xyz = fragColor.xyz * texel.xyz / max(texel.w, 0.00001'f)
    fragColor.w *= texel.w

proc clear*(renderer: var WorldBarRenderer) =
  ## Starts one empty bar batch while retaining its vertex allocation.
  renderer.vertices.setLen(0)

proc addVertex(
    renderer: var WorldBarRenderer,
    center: Vec3,
    offset: Vec2,
    color: ColorRGBX,
    uv: Vec2,
    textureMode: BillboardTexture
) =
  ## Adds one interleaved billboard vertex to the dynamic mesh.
  const ByteScale = 1.0'f / 255.0'f
  renderer.vertices.add center.x
  renderer.vertices.add center.y
  renderer.vertices.add center.z
  renderer.vertices.add offset.x
  renderer.vertices.add offset.y
  renderer.vertices.add color.r.float32 * ByteScale
  renderer.vertices.add color.g.float32 * ByteScale
  renderer.vertices.add color.b.float32 * ByteScale
  renderer.vertices.add color.a.float32 * ByteScale
  renderer.vertices.add uv.x
  renderer.vertices.add uv.y
  renderer.vertices.add textureMode.ord.float32

proc addBillboardQuad*(
    renderer: var WorldBarRenderer,
    center: Vec3,
    offset,
    size: Vec2,
    color: ColorRGBX,
    uv = vec2(-1),
    uvSize = vec2(0),
    textureMode = MaskTexture
) =
  ## Adds one camera-facing colored rectangle as two mesh triangles.
  let
    bottomLeft = offset
    bottomRight = offset + vec2(size.x, 0)
    topLeft = offset + vec2(0, size.y)
    topRight = offset + size
  for (position, texcoord) in [
    (bottomLeft, uv + vec2(0, uvSize.y)),
    (bottomRight, uv + uvSize),
    (topRight, uv + vec2(uvSize.x, 0)),
    (bottomLeft, uv + vec2(0, uvSize.y)),
    (topRight, uv + vec2(uvSize.x, 0)),
    (topLeft, uv)
  ]:
    renderer.addVertex(center, position, color, texcoord, textureMode)

proc addBillboardRing*(
    renderer: var WorldBarRenderer,
    center: Vec3,
    offset: Vec2,
    radius, thickness, fraction: float32,
    color: ColorRGBX
) =
  ## Adds a clockwise countdown arc starting at the top of a billboard.
  const Segments = 48
  let count = int(ceil(clamp(fraction, 0.0'f, 1.0'f) * Segments.float32))
  for i in 0 ..< count:
    let
      first = min(i.float32 / Segments.float32, fraction) * 2 * PI.float32
      last = min((i + 1).float32 / Segments.float32, fraction) * 2 * PI.float32
      a = vec2(sin(first), cos(first))
      b = vec2(sin(last), cos(last))
    for point in [a * radius, b * radius, b * (radius - thickness),
        a * radius, b * (radius - thickness), a * (radius - thickness)]:
      renderer.addVertex(center, offset + point, color, vec2(-1), MaskTexture)

proc addResourceBars*(
    renderer: var WorldBarRenderer,
    anchor: Vec3,
    width: float32,
    bars: openArray[WorldResourceBar],
    gap = DefaultGap,
    border = DefaultBorder
) =
  ## Adds an extensible top-down stack of billboard resource bars.
  var top = 0.0'f
  for bar in bars:
    let
      left = -width * 0.5'f
      bottom = top - bar.height
      ratio =
        if bar.maximum <= 0:
          0.0'f
        else:
          clamp(bar.value / bar.maximum, 0.0'f, 1.0'f)
      delayedRatio =
        if bar.maximum <= 0:
          0.0'f
        else:
          clamp(bar.delayedValue / bar.maximum, ratio, 1.0'f)
    renderer.addBillboardQuad(
      anchor,
      vec2(left - border, bottom - border),
      vec2(width + border * 2, bar.height + border * 2),
      rgbx(5, 7, 10, 240)
    )
    renderer.addBillboardQuad(
      anchor,
      vec2(left, bottom),
      vec2(width, bar.height),
      rgbx(28, 31, 36, 225)
    )
    if bar.showDamageTrail and delayedRatio > ratio:
      renderer.addBillboardQuad(
        anchor,
        vec2(left, bottom),
        vec2(width * delayedRatio, bar.height),
        rgbx(245, 243, 232, 255)
      )
    if ratio > 0:
      renderer.addBillboardQuad(
        anchor,
        vec2(left, bottom),
        vec2(width * ratio, bar.height),
        bar.color
      )
    top = bottom - gap

proc healthColor*(value, maximum: float32): ColorRGBX =
  ## Returns green, yellow, or red for the current health percentage.
  let ratio =
    if maximum <= 0:
      0.0'f
    else:
      clamp(value / maximum, 0.0'f, 1.0'f)
  if ratio > 0.6'f:
    rgbx(62, 201, 92, 255)
  elif ratio > 0.3'f:
    rgbx(238, 195, 55, 255)
  else:
    rgbx(224, 66, 63, 255)

proc beginFrame*(tracker: var DamageTrailTracker) =
  ## Begins one frame of damage-trail observations.
  inc tracker.frame

proc delayedValue*(
    tracker: var DamageTrailTracker,
    id: int32,
    current,
    maximum,
    dt: float32,
    holdSeconds = DefaultDamageHoldSeconds,
    fadeSeconds = DefaultDamageFadeSeconds
): float32 =
  ## Retains recently lost health, then eases its white trail downward.
  var trailIndex = -1
  for index, trail in tracker.trails:
    if trail.id == id:
      trailIndex = index
      break
  if trailIndex < 0:
    tracker.trails.add DamageTrail(
      id: id,
      observedValue: current,
      delayedValue: current,
      seenFrame: tracker.frame
    )
    trailIndex = tracker.trails.high
  let trail = tracker.trails[trailIndex].addr
  trail.seenFrame = tracker.frame
  if current < trail.observedValue:
    trail.delayedValue = max(trail.delayedValue, trail.observedValue)
    trail.holdSeconds = holdSeconds
  elif current > trail.observedValue:
    trail.delayedValue = max(trail.delayedValue, current)
  trail.observedValue = current
  if trail.holdSeconds > 0:
    trail.holdSeconds = max(trail.holdSeconds - dt, 0.0'f)
  elif trail.delayedValue > current:
    let amount = min(dt / max(fadeSeconds, 0.001'f), 1.0'f)
    trail.delayedValue += (current - trail.delayedValue) * amount
    if trail.delayedValue - current < 0.5'f:
      trail.delayedValue = current
  trail.delayedValue = clamp(
    trail.delayedValue,
    current,
    max(maximum, current)
  )
  trail.delayedValue

proc finishFrame*(tracker: var DamageTrailTracker) =
  ## Removes damage-trail state for units absent from the current frame.
  var writeIndex = 0
  for readIndex in 0 ..< tracker.trails.len:
    if tracker.trails[readIndex].seenFrame == tracker.frame:
      if writeIndex != readIndex:
        tracker.trails[writeIndex] = tracker.trails[readIndex]
      inc writeIndex
  tracker.trails.setLen(writeIndex)

include backends/passes/worldbars
