## Shady stages for the courtyard's ambient occlusion and post effects.

import shady, vmath

const OcclusionTaps = 16

var
  depthTexture: Uniform[Sampler2D]
  normalTexture: Uniform[Sampler2D]
  occlusionTexture: Uniform[Sampler2D]
  sceneTexture: Uniform[Sampler2D]
  beforeTexture: Uniform[Sampler2D]
  sourceTexture: Uniform[Sampler2D]
  bloomTexture: Uniform[Sampler2D]
  colorTexture: Uniform[Sampler2D]
  otherTexture: Uniform[Sampler2D]
  inverseProjection: Uniform[Mat4]
  texel: Uniform[Vec2]
  projectionScale: Uniform[Vec2]
  projectionY: Uniform[float32]
  direction: Uniform[Vec2]
  tint: Uniform[Vec3]
  radius, intensity, bias, normalDetail: Uniform[float32]
  sharpness, near, far: Uniform[float32]
  threshold, vfxWeight, useVfx: Uniform[float32]
  useFxaa, bloomStrength: Uniform[float32]
  vignette, vignetteStart, vignetteEnd: Uniform[float32]
  saturation, contrast, scale: Uniform[float32]
  mode: Uniform[int32]

proc postVertex*(gl_Position: var Vec4, uv: var Vec2) =
  ## Covers the framebuffer with a triangle generated from the vertex ID.
  let corner = vec2(
    float32((gl_VertexID mod 2) * 2),
    float32((gl_VertexID div 2) * 2)
  )
  uv = corner
  gl_Position = vec4(corner.x * 2.0'f - 1.0'f,
    corner.y * 2.0'f - 1.0'f, 0.0'f, 1.0'f)

proc viewPosition(point: Vec2): Vec3 =
  ## Reconstructs at a depth texel's center to preserve flat surface normals.
  let
    snapped = (floor(point / texel) + 0.5'f) * texel
    depth = texture(depthTexture, snapped).x
    view = inverseProjection *
      vec4(snapped.x * 2.0'f - 1.0'f,
        (snapped.y * 2.0'f - 1.0'f) * projectionY,
        depth * 2.0'f - 1.0'f, 1.0'f)
  result = view.xyz / view.w

proc viewNormal(point: Vec2, center: Vec3): Vec3 =
  ## Chooses each neighbor closest in depth to keep silhouettes sharp.
  let
    right = viewPosition(point + vec2(texel.x, 0.0'f)) - center
    left = center - viewPosition(point - vec2(texel.x, 0.0'f))
    up = viewPosition(point + vec2(0.0'f, texel.y)) - center
    down = center - viewPosition(point - vec2(0.0'f, texel.y))
    dx = if abs(right.z) < abs(left.z): right else: left
    dy = if abs(up.z) < abs(down.z): up else: down
  result = normalize(cross(dx, dy)) * projectionY

proc surfaceNormal(point: Vec2, center: Vec3, detail: float32): Vec3 =
  ## Blends mapped surface relief into the depth-reconstructed normal.
  let
    geometric = viewNormal(point, center)
    surface = texture(normalTexture, point)
  if surface.w < 0.5'f:
    return geometric
  result = normalize(mix(
    geometric, normalize(surface.xyz * 2.0'f - 1.0'f), detail
  ))

proc postHash(point: Vec2): float32 =
  ## Rotates occlusion taps with deterministic screen-space noise.
  result = fract(52.9829189'f *
    fract(dot(point, vec2(0.06711056'f, 0.00583715'f))))

proc postOcclusion*(gl_FragCoord: Vec4, fragColor: var Vec4) =
  ## Samples a hemisphere around one depth texel at half resolution.
  let
    base = (floor(gl_FragCoord.xy) * 2.0'f + 0.5'f) * texel
    depth = texture(depthTexture, base).x
  if depth >= 1.0'f:
    fragColor = vec4(1.0'f)
    return
  let
    center = viewPosition(base)
    normal = surfaceNormal(base, center, normalDetail)
    uvRadius = 0.5'f * projectionScale * radius / max(-center.z, 0.1'f)
    spin = postHash(gl_FragCoord.xy) * 6.2831853'f
  var occlusion = 0.0'f
  for i in 0 ..< OcclusionTaps:
    let
      distance = (float32(i) + 0.5'f) / float32(OcclusionTaps)
      angle = float32(i) * 2.3999632'f + spin
      offset = vec2(cos(angle), sin(angle)) * distance * uvRadius
      delta = viewPosition(base + offset) - center
      distance2 = dot(delta, delta)
      falloff = max(0.0'f, 1.0'f - distance2 / (radius * radius))
      cosine = dot(delta, normal) * inversesqrt(distance2 + 0.0001'f)
    occlusion += falloff * max(0.0'f, cosine - bias)
  let ao = clamp(
    1.0'f - intensity * occlusion / float32(OcclusionTaps), 0.0'f, 1.0'f
  )
  fragColor = vec4(ao, ao, ao, 1.0'f)

proc linearDepth(point: Vec2): float32 =
  ## Converts sampled projection depth to distance along the view axis.
  let ndc = texture(depthTexture, point).x * 2.0'f - 1.0'f
  result = 2.0'f * near * far / (far + near - ndc * (far - near))

proc postBlur*(uv: Vec2, fragColor: var Vec4) =
  ## Smooths occlusion without crossing a large scene-depth discontinuity.
  let centerDepth = linearDepth(uv)
  var
    total = 0.0'f
    weights = 0.0'f
  for i in -4 .. 4:
    let
      point = uv + direction * float32(i)
      difference = abs(linearDepth(point) - centerDepth) / centerDepth
      weight = exp(-float32(i * i) / 12.0'f) *
        max(0.0'f, 1.0'f - difference * sharpness)
    total += texture(occlusionTexture, point).x * weight
    weights += weight
  let ao = total / max(weights, 0.0001'f)
  fragColor = vec4(ao, ao, ao, 1.0'f)

proc postMultiply*(uv: Vec2, fragColor: var Vec4) =
  ## Applies the configured occlusion tint as a multiplicative scene pass.
  let ao = texture(occlusionTexture, uv).x
  fragColor = vec4(mix(tint, vec3(1.0'f), ao), 1.0'f)

proc bright(point: Vec2): Vec3 =
  ## Extracts VFX additions and scene highlights with a soft threshold.
  let
    scene = texture(sceneTexture, point).xyz
    vfx = max(scene - texture(beforeTexture, point).xyz, 0.0'f) * useVfx
    peak = max(scene.x, max(scene.y, scene.z))
    knee = clamp(
      (peak - threshold) / max(1.0'f - threshold, 0.0001'f), 0.0'f, 1.0'f
    )
  result = vfx * vfxWeight + scene * knee * knee

proc postPrefilter*(uv: Vec2, fragColor: var Vec4) =
  ## Reduces the bright source into the first bloom level.
  var color = bright(uv) * 0.5'f
  color += bright(uv + texel * vec2(-1.0'f, -1.0'f)) * 0.125'f
  color += bright(uv + texel * vec2(1.0'f, -1.0'f)) * 0.125'f
  color += bright(uv + texel * vec2(-1.0'f, 1.0'f)) * 0.125'f
  color += bright(uv + texel * vec2(1.0'f, 1.0'f)) * 0.125'f
  fragColor = vec4(color, 1.0'f)

proc postDown*(uv: Vec2, fragColor: var Vec4) =
  ## Downsamples the bloom chain with a center-weighted diagonal filter.
  var color = texture(sourceTexture, uv).xyz * 4.0'f
  color += texture(sourceTexture, uv + texel * vec2(-1.0'f, -1.0'f)).xyz
  color += texture(sourceTexture, uv + texel * vec2(1.0'f, -1.0'f)).xyz
  color += texture(sourceTexture, uv + texel * vec2(-1.0'f, 1.0'f)).xyz
  color += texture(sourceTexture, uv + texel * vec2(1.0'f, 1.0'f)).xyz
  fragColor = vec4(color / 8.0'f, 1.0'f)

proc postUp*(uv: Vec2, fragColor: var Vec4) =
  ## Upsamples bloom with the existing eight-tap reconstruction filter.
  var color =
    texture(sourceTexture, uv + texel * vec2(-2.0'f, 0.0'f)).xyz
  color += texture(sourceTexture, uv + texel * vec2(2.0'f, 0.0'f)).xyz
  color += texture(sourceTexture, uv + texel * vec2(0.0'f, -2.0'f)).xyz
  color += texture(sourceTexture, uv + texel * vec2(0.0'f, 2.0'f)).xyz
  color += texture(sourceTexture, uv + texel * vec2(-1.0'f, -1.0'f)).xyz * 2.0'f
  color += texture(sourceTexture, uv + texel * vec2(1.0'f, -1.0'f)).xyz * 2.0'f
  color += texture(sourceTexture, uv + texel * vec2(-1.0'f, 1.0'f)).xyz * 2.0'f
  color += texture(sourceTexture, uv + texel * vec2(1.0'f, 1.0'f)).xyz * 2.0'f
  fragColor = vec4(color / 12.0'f, 1.0'f)

proc sampleScene(point: Vec2): Vec3 =
  ## Samples the scene before bloom and color grading.
  result = texture(sceneTexture, point).xyz

proc luminance(color: Vec3): float32 =
  ## Measures brightness with the existing FXAA luminance coefficients.
  result = dot(color, vec3(0.299'f, 0.587'f, 0.114'f))

proc fxaa(point: Vec2): Vec3 =
  ## Runs the FXAA 3.11 console filter along the local luminance edge.
  let middle = sampleScene(point)
  if useFxaa < 0.5'f:
    return middle
  let
    nw = luminance(sampleScene(point + vec2(-1.0'f, -1.0'f) * texel))
    ne = luminance(sampleScene(point + vec2(1.0'f, -1.0'f) * texel))
    sw = luminance(sampleScene(point + vec2(-1.0'f, 1.0'f) * texel))
    se = luminance(sampleScene(point + vec2(1.0'f, 1.0'f) * texel))
    lm = luminance(middle)
    lumaMin = min(lm, min(min(nw, ne), min(sw, se)))
    lumaMax = max(lm, max(max(nw, ne), max(sw, se)))
  if lumaMax - lumaMin < max(0.0312'f, lumaMax * 0.125'f):
    return middle
  var direction = vec2(-((nw + ne) - (sw + se)), (nw + sw) - (ne + se))
  let
    reduce = max((nw + ne + sw + se) * 0.03125'f, 1.0'f / 128.0'f)
    scale = 1.0'f / (min(abs(direction.x), abs(direction.y)) + reduce)
  direction = clamp(direction * scale, vec2(-8.0'f), vec2(8.0'f)) * texel
  let
    a = 0.5'f * (
      sampleScene(point + direction * (1.0'f / 3.0'f - 0.5'f)) +
      sampleScene(point + direction * (2.0'f / 3.0'f - 0.5'f))
    )
    b = a * 0.5'f + 0.25'f * (
      sampleScene(point - direction * 0.5'f) +
      sampleScene(point + direction * 0.5'f)
    )
    lb = luminance(b)
  result = if lb < lumaMin or lb > lumaMax: a else: b

proc postFinal*(uv: Vec2, gl_FragCoord: Vec4, fragColor: var Vec4) =
  ## Composes antialiasing, bloom, grading, vignette and one-bit dither.
  var color = fxaa(uv)
  color += texture(bloomTexture, uv).xyz * bloomStrength
  let luma = luminance(color)
  color = mix(vec3(luma), color, saturation)
  color = mix(color, color * color * (3.0'f - 2.0'f * color), contrast)
  let
    centered = (uv - 0.5'f) * vec2(texel.y / texel.x, 1.0'f)
    edge = smoothstep(vignetteStart, vignetteEnd, length(centered) * 1.3'f)
  color *= 1.0'f - vignette * edge
  let noise =
    fract(sin(dot(gl_FragCoord.xy, vec2(12.9898'f, 78.233'f))) * 43758.5453'f)
  color += (noise - 0.5'f) / 255.0'f
  fragColor = vec4(clamp(color, 0.0'f, 1.0'f), 1.0'f)

proc postLayer*(uv: Vec2, fragColor: var Vec4) =
  ## Displays the selected intermediate layer for post-processing diagnostics.
  var color = texture(colorTexture, uv).xyz * scale
  let depth = texture(depthTexture, uv).x
  if mode == 1:
    let
      ndc = depth * 2.0'f - 1.0'f
      distance = 2.0'f * near * far / (far + near - ndc * (far - near))
    color =
      if depth >= 1.0'f:
        vec3(0.0'f)
      else:
        vec3(1.0'f - 0.85'f *
          clamp((distance - 5.0'f) / 30.0'f, 0.0'f, 1.0'f))
  elif mode == 2:
    let center = viewPosition(uv)
    color =
      if depth >= 1.0'f:
        vec3(0.0'f)
      else:
        surfaceNormal(uv, center, 1.0'f) * 0.5'f + 0.5'f
  elif mode == 3:
    color = max(color - texture(otherTexture, uv).xyz, 0.0'f) * 2.0'f
  fragColor = vec4(clamp(color, 0.0'f, 1.0'f), 1.0'f)
