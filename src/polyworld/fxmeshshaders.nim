## Shared Shady programs for procedural visual effects.

import shady, vmath

var
  uViewProjection: Uniform[Mat4]
  uModel: Uniform[Mat4]
  uTime: Uniform[float32]
  uLifeT: Uniform[float32]
  uAlpha: Uniform[float32]
  uDissolve: Uniform[float32]
  uDissolveEdge: Uniform[float32]
  uSpinSpeed: Uniform[float32]
  uTwistAngle: Uniform[float32]
  uWaveAmp: Uniform[float32]
  uWaveFreq: Uniform[float32]
  uWaveSpeed: Uniform[float32]
  uRippleAmp: Uniform[float32]
  uRippleFreq: Uniform[float32]
  uRippleSpeed: Uniform[float32]
  uInflate: Uniform[float32]
  uPulseAmp: Uniform[float32]
  uPulseSpeed: Uniform[float32]
  uExpandStart: Uniform[float32]
  uExpandEnd: Uniform[float32]
  uExpandPower: Uniform[float32]
  uSweepSource: Uniform[int32]
  uSweepBand: Uniform[float32]
  uSweepSoft: Uniform[float32]
  uUvScale: Uniform[Vec2]
  uScroll: Uniform[Vec2]
  uNoiseScale: Uniform[float32]
  uGradientSource: Uniform[int32]
  uStartColor: Uniform[Vec4]
  uEndColor: Uniform[Vec4]
  uEdgeColor: Uniform[Vec4]
  uPattern: Uniform[Sampler2D]
  uNoise: Uniform[Sampler2D]
  uEdgeFade: Uniform[Vec4]
  uEdgeShape: Uniform[Vec2]

proc fxVertex*(
  gl_Position: var Vec4,
  vertPos: Vec3,
  vertNormal: Vec3,
  vertUv: Vec2,
  vertData: Vec4,
  fragmentUv: var Vec2,
  fragmentData: var Vec4
) =
  ## Animates one vertex in the canonical Y-axis space, then orients it.
  ## vertData packs along-axis, radial distance, angle, and a random value.
  fragmentUv = vertUv
  fragmentData = vertData
  var position: Vec3 = vertPos
  let axisT = vertData.x
  ## Inflate and pulse push along the authored normal. The pulse phase is
  ## shared by every vertex so duplicated seam vertices stay welded.
  let push = uInflate + uPulseAmp * sin(uTime * uPulseSpeed)
  position += vertNormal * push
  ## Wave displaces sideways, phased along the main axis.
  position.x += sin(
    axisT * uWaveFreq * 6.2831853'f + uTime * uWaveSpeed
  ) * uWaveAmp
  ## Radial ripple displaces along the axis, phased by radial distance.
  position.y += sin(
    vertData.y * uRippleFreq * 6.2831853'f - uTime * uRippleSpeed
  ) * uRippleAmp
  ## Twist rotates progressively along the axis while spin turns everything.
  let
    angle = 0.0174533'f * uTwistAngle * (axisT - 0.5'f) + uSpinSpeed * uTime
    cosine = cos(angle)
    sine = sin(angle)
  position = vec3(
    position.x * cosine - position.z * sine,
    position.y,
    position.x * sine + position.z * cosine
  )
  ## Expand scales the whole mesh over the effect life.
  let expand = mix(
    uExpandStart,
    uExpandEnd,
    pow(clamp(uLifeT, 0.0'f, 1.0'f), max(uExpandPower, 0.01'f))
  )
  position = position * expand
  gl_Position = uViewProjection * (uModel * vec4(position, 1.0'f))

proc fxFragment*(
  fragmentUv: Vec2,
  fragmentData: Vec4,
  fragColor: var Vec4
) =
  ## Shades every effect: scrolled pattern, gradient, dissolve, edge glow.
  let
    uv: Vec2 = fragmentUv * uUvScale + uScroll * uTime
    pattern = texture(uPattern, uv).x
    noiseUv: Vec2 = fragmentUv * uNoiseScale +
      vec2(uScroll.y, uScroll.x) * (uTime * 0.31'f)
    noiseValue = texture(uNoise, noiseUv).x
  var gradientT = uLifeT
  if uGradientSource == 1'i32:
    gradientT = fragmentData.x
  if uGradientSource == 2'i32:
    gradientT = fragmentData.y
  if uGradientSource == 3'i32:
    gradientT = fragmentData.z
  let color: Vec4 = mix(
    uStartColor,
    uEndColor,
    clamp(gradientT, 0.0'f, 1.0'f)
  )
  var
    rgb: Vec3 = color.xyz
    alpha = color.w * pattern * uAlpha
  ## Sweep reveal: a band travels from coordinate zero to one over the
  ## effect life, with a feathered leading edge in the dissolve edge color
  ## and a trail that fades out over the band length behind it.
  if uSweepBand > 0.0001'f:
    var sweepCoord = fragmentUv.x
    if uSweepSource == 1'i32:
      sweepCoord = fragmentUv.y
    if uSweepSource == 2'i32:
      sweepCoord = fragmentData.x
    if uSweepSource == 3'i32:
      sweepCoord = fragmentData.y
    if uSweepSource == 4'i32:
      sweepCoord = fragmentData.z
    let
      soft = max(uSweepSoft, 0.0001'f)
      head = uLifeT * (1.0'f + uSweepBand + soft)
      age = head - sweepCoord
      edgeIn = clamp(age / (soft * 2.0'f), 0.0'f, 1.0'f)
    ## The leading edge ignores the pattern texture so the blade front is a
    ## solid hot line that trails off into the textured band behind it.
    alpha = mix(color.w * uAlpha, alpha, edgeIn) *
      smoothstep(0.0'f, soft, age) *
      clamp(1.0'f - age / uSweepBand, 0.0'f, 1.0'f)
    rgb = mix(uEdgeColor.xyz, rgb, edgeIn)
  if uDissolve > 0.0001'f:
    if noiseValue < uDissolve:
      discardFragment()
    let edge = smoothstep(
      uDissolve,
      uDissolve + max(uDissolveEdge, 0.0001'f),
      noiseValue
    )
    rgb = mix(uEdgeColor.xyz, rgb, edge)
    alpha = mix(uEdgeColor.w * uAlpha, alpha, edge)
  # Fade authored boundaries independently of scrolling texture coordinates.
  var edgeAlpha = 1.0'f
  if uEdgeFade.x > 0.0'f:
    edgeAlpha *= smoothstep(0.0'f, uEdgeFade.x, fragmentUv.x)
  if uEdgeFade.y > 0.0'f:
    edgeAlpha *= smoothstep(0.0'f, uEdgeFade.y, 1.0'f - fragmentUv.x)
  if uEdgeFade.z > 0.0'f:
    edgeAlpha *= smoothstep(0.0'f, uEdgeFade.z, fragmentUv.y)
  if uEdgeFade.w > 0.0'f:
    edgeAlpha *= smoothstep(0.0'f, uEdgeFade.w, 1.0'f - fragmentUv.y)
  if uEdgeShape.x == 1.0'f:
    edgeAlpha *= smoothstep(0.0'f, 0.12'f,
      1.0'f - length(fragmentUv * 2.0'f - vec2(1.0'f)))
  elif uEdgeShape.x == 2.0'f:
    let
      x = fragmentUv.x * 2.0'f - 1.0'f
      y = abs(fragmentUv.y * 2.0'f - 1.0'f) * uEdgeShape.y
      cap = max(0.0'f, y - (uEdgeShape.y - 1.0'f))
    edgeAlpha *= smoothstep(0.0'f, 0.12'f, 1.0'f - length(vec2(x, cap)))
  alpha *= edgeAlpha
  if alpha < 0.003'f:
    discardFragment()
  fragColor = vec4(rgb, alpha)
