## Ambient-occlusion math shared by scene and screen-space shader stages.

import shady, vmath

const OcclusionTaps* = 16

proc depthNormal*(right, left, up, down: Vec3): Vec3 =
  ## Chooses depth-nearest neighbors to keep silhouette normals clean.
  let
    dx = if abs(right.z) < abs(left.z): right else: left
    dy = if abs(up.z) < abs(down.z): up else: down
  result = normalize(cross(dx, dy))

proc occlusionHash*(point: Vec2): float32 =
  ## Rotates the sample spiral independently for each framebuffer pixel.
  result = fract(52.9829189'f *
    fract(dot(point, vec2(0.06711056'f, 0.00583715'f))))

proc occlusionOffset*(index, spin: float32, uvRadius: Vec2): Vec2 =
  ## Places one tap on the shared sixteen-sample spiral.
  let
    distance = (index + 0.5'f) / float32(OcclusionTaps)
    angle = index * 2.3999632'f + spin
  result = vec2(cos(angle), sin(angle)) * distance * uvRadius

proc occlusionContribution*(delta, normal: Vec3,
    sampleRadius, cosineBias: float32): float32 =
  ## Weighs a nearby surface by distance falloff and its normal-facing angle.
  let
    distance2 = dot(delta, delta)
    falloff = max(0.0'f,
      1.0'f - distance2 / (sampleRadius * sampleRadius))
    cosine = dot(delta, normal) * inversesqrt(distance2 + 0.0001'f)
  result = falloff * max(0.0'f, cosine - cosineBias)

proc occlusionAmount*(total, strength: float32): float32 =
  ## Converts the summed tap contribution into bounded visibility.
  result = clamp(
    1.0'f - strength * total / float32(OcclusionTaps), 0.0'f, 1.0'f
  )

proc occlusionBlurWeight*(index: int32, difference: float32): float32 =
  ## Combines the blur kernel with the caller's scaled depth discontinuity.
  result = exp(-float32(index * index) / 12.0'f) *
    max(0.0'f, 1.0'f - difference)

proc occlusionTint*(shadowTint: Vec3, ao: float32): Vec4 =
  ## Produces the common multiplicative tint for the sampled visibility.
  result = vec4(mix(shadowTint, vec3(1.0'f), ao), 1.0'f)
