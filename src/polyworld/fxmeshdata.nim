## Procedural VFX meshes driven by one fx shader.
## The CPU builds shapes with VFX-friendly polyflow, shape-default UVs, and
## packed per-vertex animation coordinates. One shader pair then animates
## every effect: UV scroll, dissolve, twist, wave, ripple, pulse, spin, and
## expand. Shape topology is ported from PudinKiller's VFXMeshLab (MIT).

import
  std/[math, tables],
  jsony, vmath,
  fxshapes

export fxshapes

const
  MinimumDimension = 0.0001'f
  FullArcThreshold = 359.999'f
  MaximumSegments = 128
  FxTextureSize* = 256
  Tau = 6.28318530718'f
type
  FxMeshError* = object of CatchableError

  FxAxis* = enum
    XAxis
    YAxis
    ZAxis

  FxPivot* = enum
    CenterPivot
    StartPivot
    EndPivot

  ArcOrigin* = enum
    InnerOrigin
    MiddleOrigin
    OuterOrigin

  FxTexture* = enum
    SoftTexture
    NoiseTexture
    StreakTexture
    CellTexture
    CheckerTexture
    SolidTexture

  GradientSource* = enum
    LifeGradient
    AxisGradient
    RadialGradient
    AngleGradient

  SweepSource* = enum
    SweepU
    SweepV
    SweepAxis
    SweepRadial
    SweepAngle

  BlendMode* = enum
    AlphaBlend
    AdditiveBlend

  FxUniform* = enum
    ViewProjectionUniform
    ModelUniform
    TimeUniform
    LifeUniform
    AlphaUniform
    DissolveUniform
    DissolveEdgeUniform
    SpinSpeedUniform
    TwistAngleUniform
    WaveAmpUniform
    WaveFreqUniform
    WaveSpeedUniform
    RippleAmpUniform
    RippleFreqUniform
    RippleSpeedUniform
    InflateUniform
    PulseAmpUniform
    PulseSpeedUniform
    ExpandStartUniform
    ExpandEndUniform
    ExpandPowerUniform
    SweepSourceUniform
    SweepBandUniform
    SweepSoftUniform
    UvScaleUniform
    ScrollUniform
    NoiseScaleUniform
    GradientSourceUniform
    StartColorUniform
    EndColorUniform
    EdgeColorUniform
    PatternUniform
    NoiseUniform
    EdgeFadeUniform
    EdgeShapeUniform

  FxSettings* = object
    name*: string
    shape*: FxShape
    axis*: FxAxis
    pivot*: FxPivot
    radius*: float32
    innerRadius*: float32
    topRadius*: float32
    thickness*: float32
    width*: float32
    length*: float32
    height*: float32
    size*: Vec3
    arcDegrees*: float32
    angleOffset*: float32
    turns*: float32
    pitch*: float32
    planeCount*: int
    radialSegments*: int
    heightSegments*: int
    widthSegments*: int
    lengthSegments*: int
    capStart*: bool
    capEnd*: bool
    widthStart*: float32
    widthEnd*: float32
    widthPower*: float32
    arcCrescent*: float32
    arcPower*: float32
    arcOrigin*: ArcOrigin
    taper*: float32
    bend*: float32
    noiseAmp*: float32
    noiseFreq*: float32
    noiseSeed*: int
    spherize*: float32
    flatten*: float32
    falloffPower*: float32
    duration*: float32
    loop*: bool
    spinSpeed*: float32
    twistAngle*: float32
    waveAmp*: float32
    waveFreq*: float32
    waveSpeed*: float32
    rippleAmp*: float32
    rippleFreq*: float32
    rippleSpeed*: float32
    inflate*: float32
    pulseAmp*: float32
    pulseSpeed*: float32
    expandStart*: float32
    expandEnd*: float32
    expandPower*: float32
    sweepSource*: SweepSource
    sweepBand*: float32
    sweepSoft*: float32
    texture*: FxTexture
    blendMode*: BlendMode
    gradientSource*: GradientSource
    uvScale*: Vec2
    scroll*: Vec2
    noiseScale*: float32
    startColor*: Vec4
    endColor*: Vec4
    edgeColor*: Vec4
    fadeIn*: float32
    fadeOut*: float32
    dissolveIn*: float32
    dissolveOut*: float32
    dissolveEdge*: float32
  MeshDraft = object
    positions: seq[Vec3]
    uvs: seq[Vec2]
    triangles: seq[int]
const FxUniformNames*: array[FxUniform, string] = [
  "uViewProjection",
  "uModel",
  "uTime",
  "uLifeT",
  "uAlpha",
  "uDissolve",
  "uDissolveEdge",
  "uSpinSpeed",
  "uTwistAngle",
  "uWaveAmp",
  "uWaveFreq",
  "uWaveSpeed",
  "uRippleAmp",
  "uRippleFreq",
  "uRippleSpeed",
  "uInflate",
  "uPulseAmp",
  "uPulseSpeed",
  "uExpandStart",
  "uExpandEnd",
  "uExpandPower",
  "uSweepSource",
  "uSweepBand",
  "uSweepSoft",
  "uUvScale",
  "uScroll",
  "uNoiseScale",
  "uGradientSource",
  "uStartColor",
  "uEndColor",
  "uEdgeColor",
  "uPattern",
  "uNoise",
  "uEdgeFade",
  "uEdgeShape"
]

## Preset serialization

proc parseHook(source: string, index: var int, value: var Vec2) =
  ## Deserializes a two-component vector from a JSON array.
  var components: array[2, float32]
  source.parseHook(index, components)
  value = vec2(components[0], components[1])

proc parseHook(source: string, index: var int, value: var Vec3) =
  ## Deserializes a three-component vector from a JSON array.
  var components: array[3, float32]
  source.parseHook(index, components)
  value = vec3(components[0], components[1], components[2])

proc parseHook(source: string, index: var int, value: var Vec4) =
  ## Deserializes a four-component vector from a JSON array.
  var components: array[4, float32]
  source.parseHook(index, components)
  value = vec4(components[0], components[1], components[2], components[3])

proc dumpHook(json: var string, value: Vec2) {.used.} =
  ## Serializes a two-component vector as a JSON array.
  json.dumpHook([value.x, value.y])

proc dumpHook(json: var string, value: Vec3) {.used.} =
  ## Serializes a three-component vector as a JSON array.
  json.dumpHook([value.x, value.y, value.z])

proc dumpHook(json: var string, value: Vec4) {.used.} =
  ## Serializes a four-component vector as a JSON array.
  json.dumpHook([value.x, value.y, value.z, value.w])

proc loadFxSettings*(path: string): FxSettings {.raises: [FxMeshError].} =
  ## Deserializes one complete JSON fx definition with jsony.
  var source: string
  try:
    source = readFile(path)
  except IOError as error:
    raise newException(FxMeshError, "Unable to read " & path & ": " & error.msg)
  try:
    result = source.fromJson(FxSettings)
  except ValueError as error:
    raise newException(FxMeshError, path & ": " & error.msg)
  if result.name.len == 0:
    raise newException(FxMeshError, path & ": name cannot be empty")

## Shape math helpers

proc finite(value, fallback: float32): float32 =
  ## Replaces NaN or infinite values with a safe fallback.
  if value != value or abs(value) == Inf:
    fallback
  else:
    value

proc positive(value: float32): float32 =
  ## Clamps a dimension to a small positive magnitude.
  max(MinimumDimension, abs(finite(value, 1.0'f)))

proc nonNegative(value: float32): float32 =
  ## Clamps a dimension to zero or above.
  max(0.0'f, abs(finite(value, 0.0'f)))

proc segmentCount(value, minimum: int): int =
  ## Clamps a resolution control to its topological minimum and global cap.
  clamp(value, minimum, MaximumSegments)

proc sanitizeArcDegrees(value: float32): float32 =
  ## Keeps arc sweeps inside one full turn and away from zero.
  result = clamp(finite(value, 360.0'f), -360.0'f, 360.0'f)
  if abs(result) < MinimumDimension:
    result = if result < 0.0'f: -MinimumDimension else: MinimumDimension

proc degreesToRadians(value: float32): float32 =
  ## Converts degrees to radians with a finite fallback.
  finite(value, 0.0'f) * PI / 180.0'f

proc evaluateWidth(s: FxSettings, t: float32): float32 =
  ## Evaluates the parametric width profile along the main axis.
  let
    power = max(finite(s.widthPower, 1.0'f), 0.01'f)
    value = mix(s.widthStart, s.widthEnd, pow(clamp(t, 0.0'f, 1.0'f), power))
  max(MinimumDimension, abs(finite(value, 1.0'f)))

proc evaluateWidthProfileU(u, widthScale: float32): float32 =
  ## Preserve-texel-density U so tapered rows keep one affine mapping.
  0.5'f + (u - 0.5'f) * widthScale

proc evaluateArcWidth(s: FxSettings, t: float32): float32 =
  ## Evaluates the angular width profile that makes crescents and slashes.
  let
    power = max(finite(s.arcPower, 1.0'f), 0.01'f)
    curved = pow(max(sin(PI * clamp(t, 0.0'f, 1.0'f)), 0.0'f), power)
  clamp(mix(1.0'f, curved, clamp(s.arcCrescent, 0.0'f, 1.0'f)), 0.0'f, 1.0'f)

proc arcOrigin01(origin: ArcOrigin): float32 =
  ## Maps the crescent collapse origin to an inner-to-outer fraction.
  case origin
  of InnerOrigin: 0.0'f
  of MiddleOrigin: 0.5'f
  of OuterOrigin: 1.0'f

proc stableRandom(index: int): float32 =
  ## Produces a repeatable zero-to-one random value per vertex index.
  var value = cast[uint32](index) + 0x9E3779B9'u32
  value = value xor (value shr 16)
  value = value * 0x7FEB352D'u32
  value = value xor (value shr 15)
  value = value * 0x846CA68B'u32
  value = value xor (value shr 16)
  (value and 0x00FFFFFF'u32).float32 / 16777215.0'f

proc hashNoise(x, y, z, seed: int): float32 =
  ## Hashes a lattice point to a repeatable minus-one-to-one value.
  var hash = cast[uint32](seed)
  hash = hash xor cast[uint32](x) * 0x8DA6B343'u32
  hash = hash xor cast[uint32](y) * 0xD8163841'u32
  hash = hash xor cast[uint32](z) * 0xCB1AB31F'u32
  hash = hash xor (hash shr 16)
  hash = hash * 0x7FEB352D'u32
  hash = hash xor (hash shr 15)
  hash = hash * 0x846CA68B'u32
  hash = hash xor (hash shr 16)
  (hash and 0x00FFFFFF'u32).float32 / 8388607.5'f - 1.0'f

proc smoothCurve(value: float32): float32 =
  ## Cubic smoothstep interpolation weight.
  value * value * (3.0'f - 2.0'f * value)

proc valueNoise(position: Vec3, seed: int): float32 =
  ## Trilinearly interpolated lattice value noise.
  let
    x0 = floor(position.x).int
    y0 = floor(position.y).int
    z0 = floor(position.z).int
    tx = smoothCurve(position.x - x0.float32)
    ty = smoothCurve(position.y - y0.float32)
    tz = smoothCurve(position.z - z0.float32)
    x00 = mix(hashNoise(x0, y0, z0, seed), hashNoise(x0 + 1, y0, z0, seed), tx)
    x10 = mix(
      hashNoise(x0, y0 + 1, z0, seed),
      hashNoise(x0 + 1, y0 + 1, z0, seed),
      tx
    )
    x01 = mix(
      hashNoise(x0, y0, z0 + 1, seed),
      hashNoise(x0 + 1, y0, z0 + 1, seed),
      tx
    )
    x11 = mix(
      hashNoise(x0, y0 + 1, z0 + 1, seed),
      hashNoise(x0 + 1, y0 + 1, z0 + 1, seed),
      tx
    )
  mix(mix(x00, x10, ty), mix(x01, x11, ty), tz)

proc fractalNoise(position: Vec3, frequency: float32, seed: int): float32 =
  ## Four-octave deterministic fractal value noise.
  var
    octaveFrequency = max(frequency, 0.01'f)
    amplitude = 1.0'f
    total = 0.0'f
    weight = 0.0'f
  for octave in 0 ..< 4:
    let offset = vec3(
      octave.float32 * 19.19'f,
      octave.float32 * -7.73'f,
      octave.float32 * 13.17'f
    )
    total += valueNoise(
      position * octaveFrequency + offset,
      seed + octave * 1013
    ) * amplitude
    weight += amplitude
    octaveFrequency *= 2.0'f
    amplitude *= 0.5'f
  total / weight

## Mesh draft

proc addVertex(draft: var MeshDraft, position: Vec3, uv: Vec2): int =
  ## Appends one vertex with its shape-default UV and returns its index.
  result = draft.positions.len
  draft.positions.add position
  draft.uvs.add uv

proc addTriangle(draft: var MeshDraft, a, b, c: int) =
  ## Appends one triangle by vertex indices.
  draft.triangles.add a
  draft.triangles.add b
  draft.triangles.add c

proc bounds(draft: MeshDraft): tuple[low, high: Vec3] =
  ## Returns the axis-aligned bounds of the draft positions.
  result.low = vec3(float32.high, float32.high, float32.high)
  result.high = vec3(float32.low, float32.low, float32.low)
  for position in draft.positions:
    result.low = min(result.low, position)
    result.high = max(result.high, position)
  if draft.positions.len == 0:
    result.low = vec3(0.0'f)
    result.high = vec3(0.0'f)

## Shape generators. All shapes are authored around a canonical Y axis; the
## selected main axis becomes a model-matrix rotation at draw time so the
## shader can animate in one consistent space.

proc addRadialStrip(
  draft: var MeshDraft,
  innerStart, outerStart, radialSegments: int,
  positiveWinding: bool
) =
  ## Connects two concentric vertex rings with a quad strip.
  for segment in 0 ..< radialSegments:
    let
      a = innerStart + segment
      b = outerStart + segment
      c = a + 1
      d = b + 1
    if positiveWinding:
      draft.addTriangle(a, c, b)
      draft.addTriangle(b, c, d)
    else:
      draft.addTriangle(a, b, c)
      draft.addTriangle(b, d, c)

proc generateQuad(s: FxSettings, draft: var MeshDraft) =
  ## Flat subdivided card in the XZ plane with a width profile along Z.
  let
    width = positive(s.width)
    length = positive(s.length)
    widthSegments = segmentCount(s.widthSegments, 1)
    lengthSegments = segmentCount(s.lengthSegments, 1)
  for y in 0 .. lengthSegments:
    let
      v = y.float32 / lengthSegments.float32
      z = mix(-length * 0.5'f, length * 0.5'f, v)
      widthScale = evaluateWidth(s, v)
      rowWidth = width * widthScale
    for x in 0 .. widthSegments:
      let u = x.float32 / widthSegments.float32
      discard draft.addVertex(
        vec3(mix(-rowWidth * 0.5'f, rowWidth * 0.5'f, u), 0.0'f, z),
        vec2(evaluateWidthProfileU(u, widthScale), v)
      )
  let stride = widthSegments + 1
  for y in 0 ..< lengthSegments:
    for x in 0 ..< widthSegments:
      let
        a = y * stride + x
        b = a + 1
        c = a + stride
        d = c + 1
      draft.addTriangle(a, c, b)
      draft.addTriangle(b, c, d)

proc generateDisc(
  s: FxSettings,
  draft: var MeshDraft,
  requestedArcDegrees: float32
) =
  ## Filled fan of concentric rings with planar-polar UVs.
  let
    radialSegments = segmentCount(s.radialSegments, 3)
    radiusSegments = segmentCount(s.widthSegments, 1)
    radius = positive(s.radius)
    arcDegrees = sanitizeArcDegrees(requestedArcDegrees)
    angleOffset = degreesToRadians(s.angleOffset)
    arcRadians = degreesToRadians(arcDegrees)
    positiveWinding = arcRadians >= 0.0'f
    center = draft.addVertex(vec3(0.0'f), vec2(0.5'f, 0.5'f))
  var previousRing = -1
  for ring in 1 .. radiusSegments:
    let
      radialT = ring.float32 / radiusSegments.float32
      ringRadius = radius * radialT
      ringStart = draft.positions.len
    for segment in 0 .. radialSegments:
      let
        angularT = segment.float32 / radialSegments.float32
        angle = angleOffset + arcRadians * angularT
        cosine = cos(angle)
        sine = sin(angle)
      discard draft.addVertex(
        vec3(cosine * ringRadius, 0.0'f, sine * ringRadius),
        vec2(0.5'f + cosine * radialT * 0.5'f, 0.5'f + sine * radialT * 0.5'f)
      )
    if ring == 1:
      for segment in 0 ..< radialSegments:
        let
          current = ringStart + segment
          next = current + 1
        if positiveWinding:
          draft.addTriangle(center, next, current)
        else:
          draft.addTriangle(center, current, next)
    else:
      draft.addRadialStrip(
        previousRing,
        ringStart,
        radialSegments,
        positiveWinding
      )
    previousRing = ringStart

proc generateRing(s: FxSettings, draft: var MeshDraft, partialArc: bool) =
  ## Flat annulus with angular U and inner-to-outer radial V.
  let
    radialSegments = segmentCount(s.radialSegments, 3)
    radiusSegments = segmentCount(s.widthSegments, 1)
    firstRadius = nonNegative(s.innerRadius)
    secondRadius = positive(s.radius)
    innerRadius = min(firstRadius, secondRadius)
    arcDegrees = if partialArc: sanitizeArcDegrees(s.arcDegrees) else: 360.0'f
  var outerRadius = max(firstRadius, secondRadius)
  if outerRadius - innerRadius < MinimumDimension:
    outerRadius = innerRadius + MinimumDimension
  if innerRadius < MinimumDimension:
    generateDisc(s, draft, arcDegrees)
    return
  let
    arcRadians = degreesToRadians(arcDegrees)
    angleOffset = degreesToRadians(s.angleOffset)
    positiveWinding = arcRadians >= 0.0'f
    stride = radialSegments + 1
  for ring in 0 .. radiusSegments:
    let
      radialT = ring.float32 / radiusSegments.float32
      ringRadius = mix(innerRadius, outerRadius, radialT)
    for segment in 0 .. radialSegments:
      let
        angularT = segment.float32 / radialSegments.float32
        angle = angleOffset + arcRadians * angularT
      discard draft.addVertex(
        vec3(cos(angle) * ringRadius, 0.0'f, sin(angle) * ringRadius),
        vec2(angularT, radialT)
      )
  for ring in 0 ..< radiusSegments:
    draft.addRadialStrip(
      ring * stride,
      (ring + 1) * stride,
      radialSegments,
      positiveWinding
    )

proc addVariableArcStrip(
  draft: var MeshDraft,
  currentStart: int,
  currentCollapsed: bool,
  nextStart: int,
  nextCollapsed: bool,
  radiusSegments: int,
  positiveWinding: bool
) =
  ## Connects two arc columns, fanning where a column collapses to a point.
  if currentCollapsed and nextCollapsed:
    return
  for ring in 0 ..< radiusSegments:
    if currentCollapsed:
      if positiveWinding:
        draft.addTriangle(currentStart, nextStart + ring, nextStart + ring + 1)
      else:
        draft.addTriangle(currentStart, nextStart + ring + 1, nextStart + ring)
    elif nextCollapsed:
      if positiveWinding:
        draft.addTriangle(currentStart + ring, nextStart, currentStart + ring + 1)
      else:
        draft.addTriangle(currentStart + ring, currentStart + ring + 1, nextStart)
    else:
      let
        a = currentStart + ring
        b = a + 1
        c = nextStart + ring
        d = c + 1
      if positiveWinding:
        draft.addTriangle(a, c, b)
        draft.addTriangle(b, c, d)
      else:
        draft.addTriangle(a, b, c)
        draft.addTriangle(b, d, c)

proc generateArc(s: FxSettings, draft: var MeshDraft) =
  ## Partial annulus, optionally tapering to crescent points along its sweep.
  if s.arcCrescent <= MinimumDimension:
    generateRing(s, draft, true)
    return
  let
    angularSegments = segmentCount(s.radialSegments, 3)
    radiusSegments = segmentCount(s.widthSegments, 1)
    firstRadius = max(nonNegative(s.innerRadius), MinimumDimension)
    secondRadius = positive(s.radius)
    innerRadius = min(firstRadius, secondRadius)
  var outerRadius = max(firstRadius, secondRadius)
  if outerRadius - innerRadius < MinimumDimension:
    outerRadius = innerRadius + MinimumDimension
  let
    widthOriginRadius = mix(innerRadius, outerRadius, arcOrigin01(s.arcOrigin))
    arcRadians = degreesToRadians(sanitizeArcDegrees(s.arcDegrees))
    angleOffset = degreesToRadians(s.angleOffset)
    positiveWinding = arcRadians >= 0.0'f
  var
    starts = newSeq[int](angularSegments + 1)
    collapsed = newSeq[bool](angularSegments + 1)
  for segment in 0 .. angularSegments:
    let
      angularT = segment.float32 / angularSegments.float32
      widthFactor = evaluateArcWidth(s, angularT)
      angle = angleOffset + arcRadians * angularT
      cosine = cos(angle)
      sine = sin(angle)
    starts[segment] = draft.positions.len
    collapsed[segment] = widthFactor <= MinimumDimension
    if collapsed[segment]:
      discard draft.addVertex(
        vec3(cosine * widthOriginRadius, 0.0'f, sine * widthOriginRadius),
        vec2(angularT, 0.5'f)
      )
      continue
    for ring in 0 .. radiusSegments:
      let
        radialT = ring.float32 / radiusSegments.float32
        baseRadius = mix(innerRadius, outerRadius, radialT)
        ringRadius = mix(widthOriginRadius, baseRadius, widthFactor)
      discard draft.addVertex(
        vec3(cosine * ringRadius, 0.0'f, sine * ringRadius),
        vec2(angularT, radialT)
      )
  for segment in 0 ..< angularSegments:
    draft.addVariableArcStrip(
      starts[segment],
      collapsed[segment],
      starts[segment + 1],
      collapsed[segment + 1],
      radiusSegments,
      positiveWinding
    )

proc addCircleCap(
  draft: var MeshDraft,
  y, radius: float32,
  radialSegments: int,
  angleOffset, arcRadians: float32,
  facesUp: bool
) =
  ## Adds one triangle-fan cap with planar-polar UVs.
  let center = draft.addVertex(vec3(0.0'f, y, 0.0'f), vec2(0.5'f, 0.5'f))
  let ringStart = draft.positions.len
  for segment in 0 .. radialSegments:
    let
      u = segment.float32 / radialSegments.float32
      angle = angleOffset + u * arcRadians
      cosine = cos(angle)
      sine = sin(angle)
    discard draft.addVertex(
      vec3(cosine * radius, y, sine * radius),
      vec2(0.5'f + cosine * 0.5'f, 0.5'f + sine * 0.5'f)
    )
  for segment in 0 ..< radialSegments:
    let
      current = ringStart + segment
      next = current + 1
    if facesUp == (arcRadians >= 0.0'f):
      draft.addTriangle(center, next, current)
    else:
      draft.addTriangle(center, current, next)

proc generateFrustum(
  s: FxSettings,
  draft: var MeshDraft,
  bottomRadius, topRadius: float32
) =
  ## Cone or cylinder shell with cylindrical UVs, caps, and a width profile.
  let
    radialSegments = segmentCount(s.radialSegments, 3)
    heightSegments = segmentCount(s.heightSegments, 1)
    height = positive(s.height)
    angleOffset = degreesToRadians(s.angleOffset)
    arcRadians = degreesToRadians(sanitizeArcDegrees(s.arcDegrees))
    positiveWinding = arcRadians >= 0.0'f
    stride = radialSegments + 1
  var rowRadii = newSeq[float32](heightSegments + 1)
  for row in 0 .. heightSegments:
    let
      v = row.float32 / heightSegments.float32
      y = mix(-height * 0.5'f, height * 0.5'f, v)
      radius = mix(bottomRadius, topRadius, v) * evaluateWidth(s, v)
    rowRadii[row] = radius
    for segment in 0 .. radialSegments:
      let
        u = segment.float32 / radialSegments.float32
        angle = angleOffset + u * arcRadians
      discard draft.addVertex(
        vec3(cos(angle) * radius, y, sin(angle) * radius),
        vec2(u, v)
      )
  for row in 0 ..< heightSegments:
    let
      lowerRadius = rowRadii[row]
      upperRadius = rowRadii[row + 1]
    for segment in 0 ..< radialSegments:
      let
        a = row * stride + segment
        b = a + 1
        c = a + stride
        d = c + 1
      if lowerRadius < MinimumDimension and upperRadius < MinimumDimension:
        continue
      if lowerRadius < MinimumDimension:
        if positiveWinding:
          draft.addTriangle(a, c, d)
        else:
          draft.addTriangle(a, d, c)
      elif upperRadius < MinimumDimension:
        if positiveWinding:
          draft.addTriangle(a, c, b)
        else:
          draft.addTriangle(a, b, c)
      elif positiveWinding:
        draft.addTriangle(a, c, b)
        draft.addTriangle(b, c, d)
      else:
        draft.addTriangle(a, b, c)
        draft.addTriangle(b, d, c)
  if s.capStart and rowRadii[0] >= MinimumDimension:
    draft.addCircleCap(
      -height * 0.5'f,
      rowRadii[0],
      radialSegments,
      angleOffset,
      arcRadians,
      false
    )
  if s.capEnd and rowRadii[heightSegments] >= MinimumDimension:
    draft.addCircleCap(
      height * 0.5'f,
      rowRadii[heightSegments],
      radialSegments,
      angleOffset,
      arcRadians,
      true
    )

proc addTubeRing(
  draft: var MeshDraft,
  radius, y: float32,
  radialSegments: int,
  angleOffset, arcRadians, v: float32,
  inner: bool
) =
  ## Adds one tube wall ring; inner walls mirror U so texture flow matches.
  for segment in 0 .. radialSegments:
    let
      angularT = segment.float32 / radialSegments.float32
      angle = angleOffset + angularT * arcRadians
    discard draft.addVertex(
      vec3(cos(angle) * radius, y, sin(angle) * radius),
      vec2(if inner: 1.0'f - angularT else: angularT, v)
    )

proc addAnnulusCap(
  draft: var MeshDraft,
  y, innerRadius, outerRadius: float32,
  radialSegments: int,
  angleOffset, arcRadians: float32,
  facesUp: bool
) =
  ## Adds one flat ring cap between the tube walls.
  let innerStart = draft.positions.len
  for segment in 0 .. radialSegments:
    let
      angularT = segment.float32 / radialSegments.float32
      angle = angleOffset + angularT * arcRadians
      cosine = cos(angle)
      sine = sin(angle)
    discard draft.addVertex(
      vec3(cosine * innerRadius, y, sine * innerRadius),
      vec2(
        0.5'f + cosine * innerRadius / outerRadius * 0.5'f,
        0.5'f + sine * innerRadius / outerRadius * 0.5'f
      )
    )
  let outerStart = draft.positions.len
  for segment in 0 .. radialSegments:
    let
      angularT = segment.float32 / radialSegments.float32
      angle = angleOffset + angularT * arcRadians
      cosine = cos(angle)
      sine = sin(angle)
    discard draft.addVertex(
      vec3(cosine * outerRadius, y, sine * outerRadius),
      vec2(0.5'f + cosine * 0.5'f, 0.5'f + sine * 0.5'f)
    )
  for segment in 0 ..< radialSegments:
    let
      a = innerStart + segment
      b = outerStart + segment
      c = a + 1
      d = b + 1
    if facesUp == (arcRadians >= 0.0'f):
      draft.addTriangle(a, c, b)
      draft.addTriangle(b, c, d)
    else:
      draft.addTriangle(a, b, c)
      draft.addTriangle(b, d, c)

proc generateTube(s: FxSettings, draft: var MeshDraft) =
  ## Hollow cylinder: outer wall, inner wall, and optional annulus caps.
  let
    radialSegments = segmentCount(s.radialSegments, 3)
    heightSegments = segmentCount(s.heightSegments, 1)
    height = positive(s.height)
    firstRadius = nonNegative(s.innerRadius)
    secondRadius = positive(s.radius)
    innerRadius = min(firstRadius, secondRadius)
  var outerRadius = max(firstRadius, secondRadius)
  if outerRadius - innerRadius < MinimumDimension:
    outerRadius = innerRadius + MinimumDimension
  if innerRadius < MinimumDimension:
    generateFrustum(s, draft, outerRadius, outerRadius)
    return
  let
    angleOffset = degreesToRadians(s.angleOffset)
    arcRadians = degreesToRadians(sanitizeArcDegrees(s.arcDegrees))
    positiveWinding = arcRadians >= 0.0'f
  var
    outerStarts = newSeq[int](heightSegments + 1)
    innerStarts = newSeq[int](heightSegments + 1)
    outerRadii = newSeq[float32](heightSegments + 1)
    innerRadii = newSeq[float32](heightSegments + 1)
  for row in 0 .. heightSegments:
    let
      v = row.float32 / heightSegments.float32
      y = mix(-height * 0.5'f, height * 0.5'f, v)
      widthFactor = evaluateWidth(s, v)
    outerRadii[row] = outerRadius * widthFactor
    innerRadii[row] = innerRadius * widthFactor
    outerStarts[row] = draft.positions.len
    draft.addTubeRing(
      outerRadii[row], y, radialSegments, angleOffset, arcRadians, v, false
    )
    innerStarts[row] = draft.positions.len
    draft.addTubeRing(
      innerRadii[row], y, radialSegments, angleOffset, arcRadians, v, true
    )
  for row in 0 ..< heightSegments:
    for segment in 0 ..< radialSegments:
      var
        a = outerStarts[row] + segment
        b = a + 1
        c = outerStarts[row + 1] + segment
        d = c + 1
      if positiveWinding:
        draft.addTriangle(a, c, b)
        draft.addTriangle(b, c, d)
      else:
        draft.addTriangle(a, b, c)
        draft.addTriangle(b, d, c)
      a = innerStarts[row] + segment
      b = a + 1
      c = innerStarts[row + 1] + segment
      d = c + 1
      if positiveWinding:
        draft.addTriangle(a, b, c)
        draft.addTriangle(b, d, c)
      else:
        draft.addTriangle(a, c, b)
        draft.addTriangle(b, c, d)
  if s.capStart:
    draft.addAnnulusCap(
      -height * 0.5'f,
      innerRadii[0],
      outerRadii[0],
      radialSegments,
      angleOffset,
      arcRadians,
      false
    )
  if s.capEnd:
    draft.addAnnulusCap(
      height * 0.5'f,
      innerRadii[heightSegments],
      outerRadii[heightSegments],
      radialSegments,
      angleOffset,
      arcRadians,
      true
    )

proc addSphereStrip(
  draft: var MeshDraft,
  lowerStart, upperStart, longitudeSegments: int
) =
  ## Connects two latitude rings with a quad strip.
  for longitude in 0 ..< longitudeSegments:
    let
      a = lowerStart + longitude
      b = a + 1
      c = upperStart + longitude
      d = c + 1
    draft.addTriangle(a, c, b)
    draft.addTriangle(b, c, d)

proc generateSphere(s: FxSettings, draft: var MeshDraft) =
  ## Latitude-longitude sphere with a radial profile scale per latitude.
  let
    longitudeSegments = segmentCount(s.radialSegments, 3)
    latitudeSegments = segmentCount(s.heightSegments, 2)
    radius = positive(s.radius)
    angleOffset = degreesToRadians(s.angleOffset)
    bottomPole = draft.addVertex(vec3(0.0'f, -radius, 0.0'f), vec2(0.5'f, 0.0'f))
  var
    firstRing = -1
    previousRing = -1
  for latitude in 1 ..< latitudeSegments:
    let
      v = latitude.float32 / latitudeSegments.float32
      phi = -PI * 0.5'f + PI * v
      y = sin(phi) * radius
      ringRadius = cos(phi) * radius * evaluateWidth(s, v)
      ringStart = draft.positions.len
    for longitude in 0 .. longitudeSegments:
      let
        u = longitude.float32 / longitudeSegments.float32
        theta = angleOffset + u * Tau
      discard draft.addVertex(
        vec3(cos(theta) * ringRadius, y, sin(theta) * ringRadius),
        vec2(u, v)
      )
    if firstRing < 0:
      firstRing = ringStart
    if previousRing >= 0:
      draft.addSphereStrip(previousRing, ringStart, longitudeSegments)
    previousRing = ringStart
  let topPole = draft.addVertex(vec3(0.0'f, radius, 0.0'f), vec2(0.5'f, 1.0'f))
  for longitude in 0 ..< longitudeSegments:
    draft.addTriangle(bottomPole, firstRing + longitude, firstRing + longitude + 1)
    draft.addTriangle(previousRing + longitude, topPole, previousRing + longitude + 1)

proc generateHemisphere(s: FxSettings, draft: var MeshDraft) =
  ## Upper half sphere from the equator with an optional equator cap.
  let
    longitudeSegments = segmentCount(s.radialSegments, 3)
    latitudeSegments = segmentCount(s.heightSegments, 1)
    radius = positive(s.radius)
    angleOffset = degreesToRadians(s.angleOffset)
  var previousRing = -1
  for latitude in 0 ..< latitudeSegments:
    let
      v = latitude.float32 / latitudeSegments.float32
      phi = PI * 0.5'f * v
      y = sin(phi) * radius
      ringRadius = cos(phi) * radius * evaluateWidth(s, v)
      ringStart = draft.positions.len
    for longitude in 0 .. longitudeSegments:
      let
        u = longitude.float32 / longitudeSegments.float32
        theta = angleOffset + u * Tau
      discard draft.addVertex(
        vec3(cos(theta) * ringRadius, y, sin(theta) * ringRadius),
        vec2(u, v)
      )
    if previousRing >= 0:
      draft.addSphereStrip(previousRing, ringStart, longitudeSegments)
    previousRing = ringStart
  let topPole = draft.addVertex(vec3(0.0'f, radius, 0.0'f), vec2(0.5'f, 1.0'f))
  for longitude in 0 ..< longitudeSegments:
    draft.addTriangle(previousRing + longitude, topPole, previousRing + longitude + 1)
  if s.capEnd:
    draft.addCircleCap(
      0.0'f,
      radius * evaluateWidth(s, 0.0'f),
      longitudeSegments,
      angleOffset,
      Tau,
      false
    )

proc addTorusCap(
  draft: var MeshDraft,
  theta, majorRadius, tubeRadius: float32,
  tubeSegments: int,
  normalAlongTangent: float32
) =
  ## Seals one open end of a partial torus sweep with a fan.
  let
    radial = vec3(cos(theta), 0.0'f, sin(theta))
    centerPosition = radial * majorRadius
    center = draft.addVertex(centerPosition, vec2(0.5'f, 0.5'f))
    ringStart = draft.positions.len
  for tube in 0 .. tubeSegments:
    let
      v = tube.float32 / tubeSegments.float32
      phi = v * Tau
      cosine = cos(phi)
      sine = sin(phi)
    discard draft.addVertex(
      centerPosition + radial * (cosine * tubeRadius) +
        vec3(0.0'f, sine * tubeRadius, 0.0'f),
      vec2(0.5'f + cosine * 0.5'f, 0.5'f + sine * 0.5'f)
    )
  for tube in 0 ..< tubeSegments:
    let
      current = ringStart + tube
      next = current + 1
    if normalAlongTangent > 0.0'f:
      draft.addTriangle(center, current, next)
    else:
      draft.addTriangle(center, next, current)

proc generateTorus(s: FxSettings, draft: var MeshDraft) =
  ## Torus with a tube profile scale along the sweep and optional end caps.
  let
    majorSegments = segmentCount(s.radialSegments, 3)
    tubeSegments = segmentCount(s.heightSegments, 3)
    majorRadius = positive(s.radius)
    tubeRadius = positive(s.thickness)
    arcDegrees = sanitizeArcDegrees(s.arcDegrees)
    arcRadians = degreesToRadians(arcDegrees)
    angleOffset = degreesToRadians(s.angleOffset)
    positiveWinding = arcRadians >= 0.0'f
    tubeStride = tubeSegments + 1
  for major in 0 .. majorSegments:
    let
      u = major.float32 / majorSegments.float32
      theta = angleOffset + arcRadians * u
      radial = vec3(cos(theta), 0.0'f, sin(theta))
      center = radial * majorRadius
      profileU =
        if abs(arcDegrees) >= FullArcThreshold and major == majorSegments:
          0.0'f
        else:
          u
      currentTubeRadius = tubeRadius * evaluateWidth(s, profileU)
    for tube in 0 .. tubeSegments:
      let
        v = tube.float32 / tubeSegments.float32
        phi = v * Tau
      discard draft.addVertex(
        center + radial * (cos(phi) * currentTubeRadius) +
          vec3(0.0'f, sin(phi) * currentTubeRadius, 0.0'f),
        vec2(u, v)
      )
  for major in 0 ..< majorSegments:
    for tube in 0 ..< tubeSegments:
      let
        a = major * tubeStride + tube
        b = a + 1
        c = a + tubeStride
        d = c + 1
      if positiveWinding:
        draft.addTriangle(a, b, c)
        draft.addTriangle(b, d, c)
      else:
        draft.addTriangle(a, c, b)
        draft.addTriangle(b, c, d)
  if abs(arcDegrees) < FullArcThreshold:
    if s.capStart:
      draft.addTorusCap(
        angleOffset,
        majorRadius,
        tubeRadius * evaluateWidth(s, 0.0'f),
        tubeSegments,
        -sign(arcRadians)
      )
    if s.capEnd:
      draft.addTorusCap(
        angleOffset + arcRadians,
        majorRadius,
        tubeRadius * evaluateWidth(s, 1.0'f),
        tubeSegments,
        sign(arcRadians)
      )

proc addBoxFace(
  draft: var MeshDraft,
  origin, uVector, vVector: Vec3,
  uSegments, vSegments: int
) =
  ## Adds one subdivided box face with planar UVs.
  let
    start = draft.positions.len
    stride = uSegments + 1
  for vIndex in 0 .. vSegments:
    let v = vIndex.float32 / vSegments.float32
    for uIndex in 0 .. uSegments:
      let u = uIndex.float32 / uSegments.float32
      discard draft.addVertex(origin + uVector * u + vVector * v, vec2(u, v))
  for vIndex in 0 ..< vSegments:
    for uIndex in 0 ..< uSegments:
      let
        a = start + vIndex * stride + uIndex
        b = a + 1
        c = a + stride
        d = c + 1
      draft.addTriangle(a, b, c)
      draft.addTriangle(b, d, c)

proc generateBox(s: FxSettings, draft: var MeshDraft) =
  ## Subdivided box with a cross-section scale profile along its height.
  let
    size = vec3(positive(s.size.x), positive(s.size.y), positive(s.size.z))
    half = size * 0.5'f
    xSegments = segmentCount(s.widthSegments, 1)
    ySegments = segmentCount(s.heightSegments, 1)
    zSegments = segmentCount(s.lengthSegments, 1)
  draft.addBoxFace(
    vec3(half.x, -half.y, -half.z),
    vec3(0.0'f, size.y, 0.0'f),
    vec3(0.0'f, 0.0'f, size.z),
    ySegments,
    zSegments
  )
  draft.addBoxFace(
    vec3(-half.x, -half.y, half.z),
    vec3(0.0'f, size.y, 0.0'f),
    vec3(0.0'f, 0.0'f, -size.z),
    ySegments,
    zSegments
  )
  draft.addBoxFace(
    vec3(-half.x, half.y, half.z),
    vec3(size.x, 0.0'f, 0.0'f),
    vec3(0.0'f, 0.0'f, -size.z),
    xSegments,
    zSegments
  )
  draft.addBoxFace(
    vec3(-half.x, -half.y, -half.z),
    vec3(size.x, 0.0'f, 0.0'f),
    vec3(0.0'f, 0.0'f, size.z),
    xSegments,
    zSegments
  )
  draft.addBoxFace(
    vec3(-half.x, -half.y, half.z),
    vec3(size.x, 0.0'f, 0.0'f),
    vec3(0.0'f, size.y, 0.0'f),
    xSegments,
    ySegments
  )
  draft.addBoxFace(
    vec3(half.x, -half.y, -half.z),
    vec3(-size.x, 0.0'f, 0.0'f),
    vec3(0.0'f, size.y, 0.0'f),
    xSegments,
    ySegments
  )
  for vertex in 0 ..< draft.positions.len:
    var position = draft.positions[vertex]
    let
      heightT = clamp(
        (position.y + half.y) / max(size.y, MinimumDimension),
        0.0'f,
        1.0'f
      )
      crossSectionScale = evaluateWidth(s, heightT)
    position.x *= crossSectionScale
    position.z *= crossSectionScale
    draft.positions[vertex] = position

proc addAxialPlane(
  s: FxSettings,
  draft: var MeshDraft,
  widthDirection: Vec3,
  width, length: float32,
  widthSegments, lengthSegments: int
) =
  ## Adds one strip standing along Y with a width profile per row.
  let
    start = draft.positions.len
    stride = widthSegments + 1
  for row in 0 .. lengthSegments:
    let
      v = row.float32 / lengthSegments.float32
      y = mix(-length * 0.5'f, length * 0.5'f, v)
      widthScale = evaluateWidth(s, v)
      rowWidth = width * widthScale
    for column in 0 .. widthSegments:
      let
        u = column.float32 / widthSegments.float32
        across = mix(-rowWidth * 0.5'f, rowWidth * 0.5'f, u)
      discard draft.addVertex(
        widthDirection * across + vec3(0.0'f, y, 0.0'f),
        vec2(evaluateWidthProfileU(u, widthScale), v)
      )
  for row in 0 ..< lengthSegments:
    for column in 0 ..< widthSegments:
      let
        a = start + row * stride + column
        b = a + 1
        c = a + stride
        d = c + 1
      draft.addTriangle(a, b, c)
      draft.addTriangle(b, d, c)

proc generateRibbon(s: FxSettings, draft: var MeshDraft) =
  ## Single tapered strip for trails and streaks.
  addAxialPlane(
    s,
    draft,
    vec3(1.0'f, 0.0'f, 0.0'f),
    positive(s.width),
    positive(s.length),
    segmentCount(s.widthSegments, 1),
    segmentCount(s.lengthSegments, 1)
  )

proc generateCrossPlanes(s: FxSettings, draft: var MeshDraft) =
  ## Several strips rotated around the axis for volumetric cards.
  let
    planeCount = segmentCount(s.planeCount, 2)
    angleOffset = degreesToRadians(s.angleOffset)
    width = positive(s.width)
    length = positive(s.length)
    widthSegments = segmentCount(s.widthSegments, 1)
    lengthSegments = segmentCount(s.lengthSegments, 1)
  for plane in 0 ..< planeCount:
    let angle = angleOffset + PI * plane.float32 / planeCount.float32
    addAxialPlane(
      s,
      draft,
      vec3(cos(angle), 0.0'f, sin(angle)),
      width,
      length,
      widthSegments,
      lengthSegments
    )

proc generateHelix(s: FxSettings, draft: var MeshDraft) =
  ## Spiraling strip with along-length V for coils and energy trails.
  var turns = finite(s.turns, 1.0'f)
  if abs(turns) < MinimumDimension:
    turns = MinimumDimension
  let
    turnsForDensity = max(1, ceil(abs(turns)).int)
    lengthSegments = segmentCount(s.lengthSegments, 3) * turnsForDensity
    widthSegments = segmentCount(s.widthSegments, 1)
    radius = positive(s.radius)
    width = positive(s.width)
    pitch = finite(s.pitch, 0.25'f)
    angleOffset = degreesToRadians(s.angleOffset)
    totalAngle = turns * Tau
    totalHeight = abs(turns) * pitch
    stride = widthSegments + 1
  for row in 0 .. lengthSegments:
    let
      v = row.float32 / lengthSegments.float32
      angle = angleOffset + totalAngle * v
      radial = vec3(cos(angle), 0.0'f, sin(angle))
      center = radial * radius +
        vec3(0.0'f, mix(-totalHeight * 0.5'f, totalHeight * 0.5'f, v), 0.0'f)
      widthScale = evaluateWidth(s, v)
      rowWidth = width * widthScale
    for column in 0 .. widthSegments:
      let
        u = column.float32 / widthSegments.float32
        across = mix(-rowWidth * 0.5'f, rowWidth * 0.5'f, u)
      discard draft.addVertex(
        center + radial * across,
        vec2(evaluateWidthProfileU(u, widthScale), v)
      )
  let positiveWinding = totalAngle >= 0.0'f
  for row in 0 ..< lengthSegments:
    for column in 0 ..< widthSegments:
      let
        a = row * stride + column
        b = a + 1
        c = a + stride
        d = c + 1
      if positiveWinding:
        draft.addTriangle(a, c, b)
        draft.addTriangle(b, c, d)
      else:
        draft.addTriangle(a, b, c)
        draft.addTriangle(b, d, c)

## Ground area-of-effect telegraphs. All are flat in the XZ plane with the
## caster at the origin and travel UVs: U runs across the shape while V runs
## from the caster edge to the far edge, proportional to distance, so sweep
## reveals and V scroll move magic outward at a constant speed. Their V also
## replaces the packed along-axis coordinate, so SweepAxis and AxisGradient
## follow the flow on these otherwise flat meshes.

proc generateAoeSector(
  s: FxSettings,
  draft: var MeshDraft,
  requestedArcDegrees: float32
) =
  ## Flat sector centered on the facing angle. Zero inner radius makes a
  ## pizza slice with its point at the caster; a positive inner radius cuts
  ## the point off into an arc band. A full sweep makes the circle nova.
  ## The collapsed inner ring of a slice leaves one degenerate triangle per
  ## quad, which renders as a clean fan and is skipped by normal welding.
  let
    angularSegments = segmentCount(s.radialSegments, 3)
    ringSegments = segmentCount(s.widthSegments, 1)
    outerRadius = positive(s.radius)
    innerRadius = min(
      nonNegative(s.innerRadius),
      outerRadius - MinimumDimension
    )
    arcRadians = degreesToRadians(sanitizeArcDegrees(requestedArcDegrees))
    startAngle = degreesToRadians(s.angleOffset) - arcRadians * 0.5'f
    positiveWinding = arcRadians >= 0.0'f
    stride = angularSegments + 1
  for ring in 0 .. ringSegments:
    let
      v = ring.float32 / ringSegments.float32
      ringRadius = mix(innerRadius, outerRadius, v)
    for segment in 0 .. angularSegments:
      let
        u = segment.float32 / angularSegments.float32
        angle = startAngle + arcRadians * u
      discard draft.addVertex(
        vec3(cos(angle) * ringRadius, 0.0'f, sin(angle) * ringRadius),
        vec2(u, v)
      )
  for ring in 0 ..< ringSegments:
    draft.addRadialStrip(
      ring * stride,
      (ring + 1) * stride,
      angularSegments,
      positiveWinding
    )

proc aoeFacing(s: FxSettings): tuple[along, across: Vec3] =
  ## Ground travel basis: the facing angle spins the shape around Y.
  let angle = degreesToRadians(s.angleOffset)
  result.along = vec3(cos(angle), 0.0'f, sin(angle))
  result.across = vec3(-sin(angle), 0.0'f, cos(angle))

proc generateAoeLine(s: FxSettings, draft: var MeshDraft) =
  ## Flat cast strip starting at the caster and running out along the
  ## facing direction, with the shared width profile for trapezoid beams.
  let
    width = positive(s.width)
    length = positive(s.length)
    widthSegments = segmentCount(s.widthSegments, 1)
    lengthSegments = segmentCount(s.lengthSegments, 1)
    (along, across) = aoeFacing(s)
    stride = widthSegments + 1
  for row in 0 .. lengthSegments:
    let
      v = row.float32 / lengthSegments.float32
      widthScale = evaluateWidth(s, v)
      rowWidth = width * widthScale
    for column in 0 .. widthSegments:
      let u = column.float32 / widthSegments.float32
      discard draft.addVertex(
        along * (v * length) + across * ((u - 0.5'f) * rowWidth),
        vec2(evaluateWidthProfileU(u, widthScale), v)
      )
  for row in 0 ..< lengthSegments:
    for column in 0 ..< widthSegments:
      let
        a = row * stride + column
        b = a + 1
        c = a + stride
        d = c + 1
      draft.addTriangle(a, c, b)
      draft.addTriangle(b, c, d)

proc generateAoeCapsule(s: FxSettings, draft: var MeshDraft) =
  ## Flat stadium: a strip with a half circle over each end, like a swipe
  ## between two circles. Planar UVs keep V proportional to distance from
  ## the caster-side tip so magic crosses the caps and the body at one
  ## speed, and the zero-width tip rows collapse into harmless fans.
  let
    capRadius = positive(s.width) * 0.5'f
    length = positive(s.length)
    capSegments = segmentCount(s.radialSegments, 3)
    widthSegments = segmentCount(s.widthSegments, 1)
    lengthSegments = segmentCount(s.lengthSegments, 1)
    totalLength = length + capRadius * 2.0'f
    (along, across) = aoeFacing(s)
    stride = widthSegments + 1
  var rows: seq[tuple[travel, halfWidth: float32]]
  for i in 0 .. capSegments:
    let phi = i.float32 / capSegments.float32 * PI.float32 * 0.5'f
    rows.add((-capRadius * cos(phi), capRadius * sin(phi)))
  for i in 1 .. lengthSegments:
    rows.add((length * i.float32 / lengthSegments.float32, capRadius))
  for i in 1 .. capSegments:
    let phi = i.float32 / capSegments.float32 * PI.float32 * 0.5'f
    rows.add((length + capRadius * sin(phi), capRadius * cos(phi)))
  for (travel, halfWidth) in rows:
    let v = (travel + capRadius) / totalLength
    for column in 0 .. widthSegments:
      let
        u = column.float32 / widthSegments.float32
        offset = (u - 0.5'f) * 2.0'f * halfWidth
      discard draft.addVertex(
        along * travel + across * offset,
        vec2(0.5'f + offset / capRadius * 0.5'f, v)
      )
  for row in 0 ..< rows.len - 1:
    for column in 0 ..< widthSegments:
      let
        a = row * stride + column
        b = a + 1
        c = a + stride
        d = c + 1
      draft.addTriangle(a, c, b)
      draft.addTriangle(b, c, d)

proc applyPivot(s: FxSettings, draft: var MeshDraft) =
  ## Moves the pivot to the bounds center, start, or end of the main axis.
  ## Ground AoE shapes keep their caster edge on the origin, so recentering
  ## would break where a cast starts.
  if draft.positions.len == 0 or s.shape in AoeShapes:
    return
  let
    box = draft.bounds()
    center = (box.low + box.high) * 0.5'f
  var pivotPoint = center
  case s.pivot
  of CenterPivot:
    discard
  of StartPivot:
    pivotPoint.y = box.low.y
  of EndPivot:
    pivotPoint.y = box.high.y
  for i in 0 ..< draft.positions.len:
    draft.positions[i] -= pivotPoint

## Static build modifiers, evaluated taper, bend, noise, spherize, flatten.

proc falloffWeight(
  s: FxSettings,
  position: Vec3,
  low, high: Vec3,
  maximumRadius: float32
): float32 =
  ## Weights a modifier along the main axis, or radially for flat shapes.
  let axisExtent = high.y - low.y
  var t: float32
  if axisExtent > MinimumDimension:
    t = (position.y - low.y) / axisExtent
  else:
    let
      center = (low + high) * 0.5'f
      radial = length(vec2(position.x - center.x, position.z - center.z))
    t =
      if maximumRadius <= MinimumDimension: 0.0'f
      else: radial / maximumRadius
  pow(clamp(t, 0.0'f, 1.0'f), max(finite(s.falloffPower, 1.0'f), 0.01'f))

proc maximumRadius(draft: MeshDraft, center: Vec3): float32 =
  ## Largest distance from the axis over all vertices.
  for position in draft.positions:
    result = max(
      result,
      length(vec2(position.x - center.x, position.z - center.z))
    )

proc applyModifiers(s: FxSettings, draft: var MeshDraft) =
  ## Applies the enabled static deformations in a fixed order.
  if draft.positions.len == 0:
    return

  template modifierSetup(body: untyped) =
    ## Recomputes bounds shared by one modifier pass, then runs it.
    block:
      let
        box {.inject.} = draft.bounds()
        center {.inject.} = (box.low + box.high) * 0.5'f
        radiusLimit {.inject.} = draft.maximumRadius(center)
      body

  if abs(s.taper) > MinimumDimension:
    modifierSetup:
      for i in 0 ..< draft.positions.len:
        let
          position = draft.positions[i]
          weight = falloffWeight(s, position, box.low, box.high, radiusLimit)
          scale = 1.0'f + s.taper * weight
        draft.positions[i] = vec3(
          center.x + (position.x - center.x) * scale,
          position.y,
          center.z + (position.z - center.z) * scale
        )

  if abs(s.bend) > MinimumDimension:
    modifierSetup:
      let
        axisLength = box.high.y - box.low.y
        totalRadians = degreesToRadians(s.bend)
      if axisLength > MinimumDimension:
        let baseCenter = vec3(center.x, box.low.y, center.z)
        for i in 0 ..< draft.positions.len:
          let
            position = draft.positions[i]
            weight = falloffWeight(s, position, box.low, box.high, radiusLimit)
            fromBase = position - baseCenter
            curvature = totalRadians * weight / axisLength
          if abs(curvature) <= MinimumDimension:
            continue
          let
            radius = 1.0'f / curvature
            theta = fromBase.y * curvature
            curvedAxis = (radius + fromBase.x) * sin(theta)
            curvedRadial = (radius + fromBase.x) * cos(theta) - radius
          draft.positions[i] = baseCenter +
            vec3(curvedRadial, curvedAxis, fromBase.z)

  if abs(s.noiseAmp) > MinimumDimension:
    modifierSetup:
      for i in 0 ..< draft.positions.len:
        let
          position = draft.positions[i]
          weight = falloffWeight(s, position, box.low, box.high, radiusLimit)
          noise = fractalNoise(position, s.noiseFreq, s.noiseSeed)
          radial = vec3(position.x - center.x, 0.0'f, position.z - center.z)
          radialLength = length(radial)
          direction =
            if radialLength > MinimumDimension: radial / radialLength
            else: vec3(1.0'f, 0.0'f, 0.0'f)
        draft.positions[i] = position +
          direction * (noise * s.noiseAmp * weight)

  if abs(s.spherize) > MinimumDimension:
    modifierSetup:
      let extents = (box.high - box.low) * 0.5'f
      let sphereRadius = max(extents.x, max(extents.y, extents.z))
      if sphereRadius > MinimumDimension:
        for i in 0 ..< draft.positions.len:
          let
            position = draft.positions[i]
            direction = position - center
            directionLength = length(direction)
          if directionLength <= MinimumDimension:
            continue
          let
            target = center + direction / directionLength * sphereRadius
            weight = falloffWeight(s, position, box.low, box.high, radiusLimit)
          draft.positions[i] = mix(position, target, s.spherize * weight)

  if abs(s.flatten) > MinimumDimension:
    modifierSetup:
      for i in 0 ..< draft.positions.len:
        let
          position = draft.positions[i]
          weight = falloffWeight(s, position, box.low, box.high, radiusLimit)
        draft.positions[i] = vec3(
          position.x,
          mix(position.y, center.y, s.flatten * weight),
          position.z
        )

proc weldKey(position: Vec3): (int, int, int) =
  ## Quantizes a position so coincident seam vertices share one key.
  (
    int(round(position.x * 8192.0'f)),
    int(round(position.y * 8192.0'f)),
    int(round(position.z * 8192.0'f))
  )

proc computeNormals(draft: MeshDraft): seq[Vec3] =
  ## Area-weighted smooth vertex normals, welded across coincident seam
  ## vertices so inflate and pulse never split UV seams, with an upward
  ## fallback for degenerate vertices.
  result = newSeq[Vec3](draft.positions.len)
  var welded: Table[(int, int, int), Vec3]
  var i = 0
  while i + 2 < draft.triangles.len:
    let
      a = draft.triangles[i]
      b = draft.triangles[i + 1]
      c = draft.triangles[i + 2]
      normal = cross(
        draft.positions[b] - draft.positions[a],
        draft.positions[c] - draft.positions[a]
      )
    if dot(normal, normal) > MinimumDimension * MinimumDimension:
      welded.mgetOrPut(weldKey(draft.positions[a]), vec3(0.0'f)) += normal
      welded.mgetOrPut(weldKey(draft.positions[b]), vec3(0.0'f)) += normal
      welded.mgetOrPut(weldKey(draft.positions[c]), vec3(0.0'f)) += normal
    i += 3
  for index in 0 ..< result.len:
    let accumulated = welded.getOrDefault(
      weldKey(draft.positions[index]),
      vec3(0.0'f)
    )
    let normalLength = length(accumulated)
    result[index] =
      if normalLength > MinimumDimension: accumulated / normalLength
      else: vec3(0.0'f, 1.0'f, 0.0'f)

proc buildFxMesh*(s: FxSettings): tuple[
  vertices: seq[float32],
  indices: seq[uint32]
] =
  ## Generates, deforms, and packs the complete interleaved fx mesh.
  ## Layout per vertex: position 3, normal 3, uv 2, fx data 4.
  var draft: MeshDraft
  case s.shape
  of QuadShape: generateQuad(s, draft)
  of DiscShape: generateDisc(s, draft, s.arcDegrees)
  of RingShape: generateRing(s, draft, false)
  of ArcShape: generateArc(s, draft)
  of ConeShape:
    generateFrustum(s, draft, positive(s.radius), nonNegative(s.topRadius))
  of CylinderShape:
    generateFrustum(s, draft, positive(s.radius), positive(s.radius))
  of TubeShape: generateTube(s, draft)
  of SphereShape: generateSphere(s, draft)
  of HemisphereShape: generateHemisphere(s, draft)
  of TorusShape: generateTorus(s, draft)
  of BoxShape: generateBox(s, draft)
  of RibbonShape: generateRibbon(s, draft)
  of CrossPlanesShape: generateCrossPlanes(s, draft)
  of HelixShape: generateHelix(s, draft)
  of AoeCircleShape: generateAoeSector(s, draft, 360.0'f)
  of AoeLineShape: generateAoeLine(s, draft)
  of AoeConeShape: generateAoeSector(s, draft, s.arcDegrees)
  of AoeCapsuleShape: generateAoeCapsule(s, draft)

  applyModifiers(s, draft)
  applyPivot(s, draft)

  ## Packed animation coordinates are normalized against the final bounds,
  ## so later deformations stretch the data instead of reprojecting it.
  let
    normals = draft.computeNormals()
    box = draft.bounds()
    center = (box.low + box.high) * 0.5'f
    axisExtent = box.high.y - box.low.y
    radiusLimit = draft.maximumRadius(center)
    ## Ground AoE shapes are flat, so their travel V doubles as the packed
    ## along-axis coordinate and SweepAxis and AxisGradient follow the flow.
    travelShape = s.shape in AoeShapes
  result.vertices = newSeqOfCap[float32](draft.positions.len * 12)
  for i in 0 ..< draft.positions.len:
    let
      position = draft.positions[i]
      alongAxis =
        if travelShape:
          draft.uvs[i].y
        elif axisExtent > MinimumDimension:
          clamp((position.y - box.low.y) / axisExtent, 0.0'f, 1.0'f)
        else:
          0.5'f
      radial = length(vec2(position.x - center.x, position.z - center.z))
      radialT =
        if radiusLimit > MinimumDimension:
          clamp(radial / radiusLimit, 0.0'f, 1.0'f)
        else:
          0.0'f
      angular = arctan2(position.z - center.z, position.x - center.x) / Tau + 0.5'f
    result.vertices.add position.x
    result.vertices.add position.y
    result.vertices.add position.z
    result.vertices.add normals[i].x
    result.vertices.add normals[i].y
    result.vertices.add normals[i].z
    result.vertices.add draft.uvs[i].x
    result.vertices.add draft.uvs[i].y
    result.vertices.add alongAxis
    result.vertices.add radialT
    result.vertices.add angular
    result.vertices.add stableRandom(i)
  result.indices = newSeqOfCap[uint32](draft.triangles.len)
  for index in draft.triangles:
    result.indices.add index.uint32

proc fxGeometryKey*(s: FxSettings): auto =
  ## Every field that requires a mesh rebuild when it changes.
  (
    s.shape, s.axis, s.pivot, s.radius, s.innerRadius, s.topRadius,
    s.thickness, s.width, s.length, s.height, s.size, s.arcDegrees,
    s.angleOffset, s.turns, s.pitch, s.planeCount, s.radialSegments,
    s.heightSegments, s.widthSegments, s.lengthSegments, s.capStart,
    s.capEnd, s.widthStart, s.widthEnd, s.widthPower, s.arcCrescent,
    s.arcPower, s.arcOrigin, s.taper, s.bend, s.noiseAmp, s.noiseFreq,
    s.noiseSeed, s.spherize, s.flatten, s.falloffPower
  )

## Procedural pattern textures

proc tileableNoise(u, v: float32, periodX, periodY, seed: int): float32 =
  ## Bilinear lattice noise that wraps seamlessly at the texture edges.
  let
    x = u * periodX.float32
    y = v * periodY.float32
    x0 = floor(x).int
    y0 = floor(y).int
    tx = smoothCurve(x - x0.float32)
    ty = smoothCurve(y - y0.float32)
  template wrapped(px, py: int): float32 =
    hashNoise(((px) mod periodX + periodX) mod periodX,
      ((py) mod periodY + periodY) mod periodY, 0, seed)
  let
    a = mix(wrapped(x0, y0), wrapped(x0 + 1, y0), tx)
    b = mix(wrapped(x0, y0 + 1), wrapped(x0 + 1, y0 + 1), tx)
  mix(a, b, ty) * 0.5'f + 0.5'f

proc tileableFbm(u, v: float32, periodX, periodY, seed: int): float32 =
  ## Four-octave tileable fractal noise in the zero-to-one range.
  var
    total = 0.0'f
    weight = 0.0'f
    amplitude = 1.0'f
    px = periodX
    py = periodY
  for octave in 0 ..< 4:
    total += tileableNoise(u, v, px, py, seed + octave * 1013) * amplitude
    weight += amplitude
    amplitude *= 0.5'f
    px *= 2
    py *= 2
  total / weight

proc cellPattern(u, v: float32, grid, seed: int): float32 =
  ## Tileable Worley-style cellular pattern, bright at feature points.
  let
    px = u * grid.float32
    py = v * grid.float32
    cx = floor(px).int
    cy = floor(py).int
  var best = 8.0'f
  for oy in -1 .. 1:
    for ox in -1 .. 1:
      let
        cellX = cx + ox
        cellY = cy + oy
        wrapX = ((cellX mod grid) + grid) mod grid
        wrapY = ((cellY mod grid) + grid) mod grid
        jitterX = hashNoise(wrapX, wrapY, 1, seed) * 0.5'f + 0.5'f
        jitterY = hashNoise(wrapX, wrapY, 2, seed) * 0.5'f + 0.5'f
        featureX = cellX.float32 + jitterX
        featureY = cellY.float32 + jitterY
        distance = length(vec2(px - featureX, py - featureY))
      best = min(best, distance)
  let value = clamp(1.0'f - best, 0.0'f, 1.0'f)
  value * value

proc patternValue(kind: FxTexture, u, v: float32): float32 =
  ## Evaluates one procedural pattern at a texture coordinate.
  case kind
  of SolidTexture:
    1.0'f
  of SoftTexture:
    let d = length(vec2(u - 0.5'f, v - 0.5'f)) * 2.0'f
    smoothCurve(clamp(1.0'f - d, 0.0'f, 1.0'f))
  of NoiseTexture:
    tileableFbm(u, v, 6, 6, 1234)
  of StreakTexture:
    pow(tileableFbm(u, v, 24, 3, 777), 1.5'f)
  of CellTexture:
    cellPattern(u, v, 8, 5150)
  of CheckerTexture:
    let
      cellX = int(u * 8.0'f) mod 8
      cellY = int(v * 8.0'f) mod 8
    if (cellX + cellY) mod 2 == 0: 0.9'f else: 0.35'f

proc buildFxPattern*(kind: FxTexture): seq[uint8] =
  ## Builds one RGBA grayscale procedural pattern for every backend.
  result = newSeq[uint8](FxTextureSize * FxTextureSize * 4)
  for y in 0 ..< FxTextureSize:
    for x in 0 ..< FxTextureSize:
      let
        u = (x.float32 + 0.5'f) / FxTextureSize.float32
        v = (y.float32 + 0.5'f) / FxTextureSize.float32
        value = uint8(clamp(patternValue(kind, u, v), 0.0'f, 1.0'f) * 255.0'f)
        offset = (y * FxTextureSize + x) * 4
      result[offset] = value
      result[offset + 1] = value
      result[offset + 2] = value
      result[offset + 3] = value

proc defaultFxSettings*(): FxSettings =
  ## Returns a complete cylinder-ready fx definition.
  result.name = "fx"
  result.shape = CylinderShape
  result.axis = YAxis
  result.pivot = StartPivot
  result.radius = 1
  result.innerRadius = 0.7
  result.height = 1
  result.size = vec3(1, 1, 1)
  result.arcDegrees = 360
  result.turns = 3
  result.pitch = 0.4
  result.planeCount = 3
  result.radialSegments = 32
  result.heightSegments = 8
  result.widthSegments = 8
  result.lengthSegments = 16
  result.width = 1
  result.length = 2
  result.thickness = 0.3
  result.widthStart = 1
  result.widthEnd = 1
  result.widthPower = 1
  result.arcPower = 1
  result.falloffPower = 1
  result.duration = 1
  result.loop = true
  result.expandStart = 1
  result.expandEnd = 1
  result.expandPower = 1
  result.uvScale = vec2(1, 1)
  result.noiseScale = 1
  result.startColor = vec4(1, 1, 1, 1)
  result.endColor = vec4(1, 1, 1, 0)
  result.edgeColor = vec4(1, 1, 1, 1)

proc fxLife*(elapsed, duration: float32, loop: bool): float32 =
  ## Returns where an effect sits inside its duration.
  let length = max(duration, 0.01'f32)
  if loop:
    let wrapped = elapsed / length
    wrapped - floor(wrapped)
  else:
    clamp(elapsed / length, 0, 1)

proc fxSmoothstep*(edge0, edge1, value: float32): float32 =
  ## CPU smoothstep matching the shader function.
  let t = clamp(
    (value - edge0) / max(edge1 - edge0, 0.0001'f32),
    0,
    1
  )
  t * t * (3.0'f32 - 2.0'f32 * t)

proc fxAlpha*(settings: FxSettings, life: float32): float32 =
  ## Returns the faded opacity for one life fraction.
  result = 1
  if settings.fadeIn > 0.0001'f32:
    result *= fxSmoothstep(0, settings.fadeIn, life)
  if settings.fadeOut > 0.0001'f32:
    result *= 1.0'f32 - fxSmoothstep(
      1.0'f32 - settings.fadeOut,
      1.0'f32,
      life
    )

proc fxDissolve*(settings: FxSettings, life: float32): float32 =
  ## Returns the dissolve threshold for one life fraction.
  if settings.dissolveIn > 0.001'f32:
    result = max(result, 1.0'f32 - life / settings.dissolveIn)
  if settings.dissolveOut > 0.001'f32:
    result = max(
      result,
      (life - (1.0'f32 - settings.dissolveOut)) / settings.dissolveOut
    )
  result = clamp(result, 0, 1)

proc fxModel*(axis: FxAxis): Mat4 =
  ## Orients the authored Y-axis mesh onto the requested main axis.
  case axis
  of XAxis:
    rotateZ(-PI.float32 * 0.5'f32)
  of YAxis:
    mat4()
  of ZAxis:
    rotateX(PI.float32 * 0.5'f32)

proc fxEdgeFade*(settings: FxSettings): Vec4 =
  ## Softens open UV boundaries without fading closed angular seams.
  case settings.shape
  of QuadShape, RibbonShape, CrossPlanesShape, AoeLineShape:
    result = vec4(0.08'f)
  of RingShape, ArcShape, AoeCircleShape, AoeConeShape:
    result.z = if settings.innerRadius > MinimumDimension: 0.12'f else: 0
    result.w = 0.12'f
    if settings.shape in {ArcShape, AoeConeShape} and
      abs(settings.arcDegrees) < FullArcThreshold:
        result.x = 0.08'f
        result.y = 0.08'f
  of CylinderShape, ConeShape, TubeShape:
    result.z = 0.06'f
    result.w = 0.14'f
  else:
    discard

proc fxEdgeShape*(settings: FxSettings): Vec2 =
  ## Describes the analytic edge fade for circular and capsule effects.
  case settings.shape
  of DiscShape:
    vec2(1, 0)
  of AoeCapsuleShape:
    vec2(2, 1 + settings.length / max(settings.width, MinimumDimension))
  else:
    vec2(0)
