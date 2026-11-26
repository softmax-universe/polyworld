## Shared Shady stages for CaC material sprites and particles.

import shady, vmath

var
  vfxViewProjection: Uniform[Mat4]
  vfxLightningSampler: Uniform[Sampler2D]
  vfxOozeSampler, vfxOozeDropletSampler: Uniform[Sampler2D]

proc vfxVertex*(position: Vec3, uv: Vec2, ink: Vec4, style: float32,
    dimensions: Vec2, gl_Position: var Vec4, fragmentUv: var Vec2,
    fragmentInk: var Vec4, fragmentStyle: var float32,
    fragmentDimensions: var Vec2) =
  ## Projects world-space effects and forwards material coordinates.
  gl_Position = vfxViewProjection * vec4(position, 1)
  fragmentUv = uv
  fragmentInk = ink
  fragmentStyle = style
  fragmentDimensions = dimensions

proc vfxFragment*(fragmentUv: Vec2, fragmentInk: Vec4,
    fragmentStyle: float32, fragmentDimensions: Vec2,
    outputColor: var Vec4) =
  ## Shades lightning, material sprites, glows, and outlined effects.
  var
    alpha = fragmentInk.a
    light = fragmentInk.rgb
  if fragmentStyle > 5.5'f:
    # Animate the jelly inside its transparent margin. Pixels loaded by Pixie
    # are premultiplied, so recover straight color for SRC_ALPHA blending.
    var uv = fragmentUv
    let edge = sin(uv.y * 3.14159265'f)
    uv.x += sin(uv.y * 11.0'f + fragmentDimensions.x) *
      fragmentDimensions.y * edge
    uv.y += sin(uv.x * 9.0'f - fragmentDimensions.x * 1.3'f) *
      fragmentDimensions.y * 0.5'f * sin(uv.x * 3.14159265'f)
    var slime = texture(vfxOozeSampler, uv)
    if fragmentStyle > 6.5'f:
      slime = texture(vfxOozeDropletSampler, uv)
    light *= slime.rgb / max(slime.a, 0.001'f)
    alpha *= slime.a
    if alpha < 0.003'f: discardFragment()
  elif fragmentStyle > 4.5'f:
    # The mesh supplies the random path. Small ripples and changing branch
    # brightness animate the texture's fine detail without moving its terminals.
    var uv = fragmentUv
    let along = clamp((uv.y - 0.05'f) / 0.9'f, 0.0'f, 1.0'f)
    uv.x += sin(uv.y * 43.0'f + fragmentDimensions.x) *
      sin(along * 3.14159265'f) * 0.006'f
    let
      band = floor(uv.y * 10.0'f)
      bandMix = fract(uv.y * 10.0'f)
      branchSeed = fragmentDimensions.y + floor(uv.x + 0.5'f) * 17.0'f
      lower = fract(sin(band * 127.1'f + branchSeed * 311.7'f) * 43758.5453'f)
      upper = fract(sin((band + 1.0'f) * 127.1'f + branchSeed * 311.7'f) * 43758.5453'f)
      branchLight = mix(lower, upper, bandMix * bandMix * (3.0'f - 2.0'f * bandMix))
      branches = smoothstep(0.08'f, 0.24'f, abs(uv.x - 0.5'f))
    let bolt = texture(vfxLightningSampler, uv)
    # Pixie pixels are premultiplied; SRC_ALPHA additive blending needs this
    # conversion exactly once. Keep the core bright while forks vary softly.
    light *= bolt.rgb / max(bolt.a, 0.001'f)
    alpha *= bolt.a * mix(1.0'f, 0.3'f + branchLight, branches)
  elif fragmentStyle > 3.5'f:
    let r = length(fragmentUv)
    alpha *= exp(-r * r * 8.0'f) * max(0.0'f, 1.0'f - r)
  elif fragmentStyle > 2.5'f:
    let r2 = dot(fragmentUv, fragmentUv)
    if r2 >= 1.0'f: discardFragment()
    let
      depth = sqrt(max(0.0'f, 1.0'f - r2))
      rim = pow(1.0'f - depth, 3.0'f)
      specular = exp(-dot(fragmentUv - vec2(-0.34, -0.42),
        fragmentUv - vec2(-0.34, -0.42)) * 95.0'f)
      edge = exp(-pow(sqrt(r2) - 0.965'f, 2.0'f) * 4200.0'f)
    light = mix(vec3(0.15, 0.73, 1.0), vec3(0.77, 0.38, 1.0),
      clamp(fragmentUv.x * 0.6'f + 0.5'f, 0.0'f, 1.0'f))
    light += vec3(specular * 1.6'f + edge * 0.6'f)
    alpha *= 0.025'f + rim * 0.6'f + edge * 0.75'f + specular
  elif fragmentStyle > 1.5'f:
    let
      q = abs(fragmentUv) - (fragmentDimensions - vec2(0.08))
      distance = length(max(q, vec2(0))) +
        min(max(q.x, q.y), 0.0'f) - 0.08'f
    if distance < -0.045'f: discardFragment()
    let
      haze = exp(-abs(distance) * 11.0'f)
      core = exp(-distance * distance * 2300.0'f)
    alpha *= haze * 0.65'f + core * 0.85'f
    light += vec3(core * 0.32'f)
  elif fragmentStyle > 0.5'f:
    alpha *= exp(-fragmentUv.y * fragmentUv.y * 4.5'f)
  outputColor = vec4(light, alpha)
