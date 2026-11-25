## Shared procedural stars and nebulae, authored once in Shady.

import
  std/math,
  shady, vmath

when defined(useDirectX) or defined(useVulkan):
  import polyworld/backends/native/stages

const
  SkyPi = 3.14159265359'f
  SkyShaderTarget =
    when defined(useMetal4): metalMSL
    elif defined(emscripten):
      glsl3WebGL
    else:
      glsl3Desktop

var
  inverseViewProjection: Uniform[Mat4]
  cameraEye: Uniform[Vec3]
  time, skyBrightness: Uniform[float32]

proc atan(y, x: float32): float32 =
  ## Supplies the two-argument GLSL atan signature to Shady.
  arctan2(y, x)

proc skyHash(point: Vec2): Vec3 =
  ## Produces stable random values for one star cell.
  var q: Vec3 = fract(vec3(point.x, point.y, point.x) *
    vec3(0.1031'f, 0.1030'f, 0.0973'f))
  q += vec3(dot(q, q.yxz + vec3(33.33'f)))
  result = fract((q.xxy + q.yzz) * q.zyx)

proc cloudHash(point: Vec3): float32 =
  ## Hashes a lattice corner for the nebula volume.
  var p: Vec3 = fract(point * 0.1031'f)
  p += vec3(dot(p, p.yzx + vec3(33.33'f)))
  result = fract((p.x + p.y) * p.z)

proc cloudNoise(point: Vec3): float32 =
  ## Interpolates the eight surrounding nebula lattice values.
  let i: Vec3 = floor(point)
  var f: Vec3 = fract(point)
  f = f * f * (vec3(3.0'f) - 2.0'f * f)
  result = mix(
    mix(
      mix(cloudHash(i), cloudHash(i + vec3(1, 0, 0)), f.x),
      mix(cloudHash(i + vec3(0, 1, 0)),
        cloudHash(i + vec3(1, 1, 0)), f.x),
      f.y
    ),
    mix(
      mix(cloudHash(i + vec3(0, 0, 1)),
        cloudHash(i + vec3(1, 0, 1)), f.x),
      mix(cloudHash(i + vec3(0, 1, 1)),
        cloudHash(i + vec3(1, 1, 1)), f.x),
      f.y
    ),
    f.z
  )

proc cloudLayers(point: Vec3): float32 =
  ## Samples a sphere in 3D so the nebula has no longitude seam.
  result = 0.0'f
  var
    p: Vec3 = point
    weight = 0.5333'f
  for i in 0 ..< 4:
    result += cloudNoise(p) * weight
    p = p * 2.03'f + vec3(13.1'f, 7.7'f, 19.3'f)
    weight *= 0.5'f

proc stars(
    position: Vec2,
    cells, fill, brightness, layer: float32
): Vec3 =
  ## Filters neighboring stars with camera parallax and timed twinkling.
  result = vec3(0.0'f)
  let wave: Vec2 = vec2(sin(time * 0.12'f + layer),
    cos(time * 0.095'f + layer * 1.7'f))
  var uv: Vec2 = position + wave * (0.00065'f + layer * 0.00030'f)
  uv += time * vec2(0.00030'f, 0.000035'f) * (1.0'f + layer * 0.65'f)
  uv += cameraEye.xz * (0.000006'f + layer * 0.000010'f)
  let
    grid: Vec2 = uv * cells
    cell: Vec2 = floor(grid)
    local: Vec2 = fract(grid)
    pixel = max(length(fwidth(grid)), 0.005'f)
  for y in -1 .. 1:
    for x in -1 .. 1:
      let neighbor: Vec2 = vec2(x.float32, y.float32)
      var id: Vec2 = cell + neighbor
      id.x = fmod(id.x, cells)
      let random: Vec3 = skyHash(id + vec2(layer * 79.1'f))
      if random.z <= fill:
        let
          delta: Vec2 = neighbor + vec2(0.15'f) + random.xy * 0.70'f - local
          radius = 1.5'f * (0.030'f + pow(random.x, 10.0'f) * 0.054'f)
          effective = max(radius, pixel * 0.48'f)
          distanceSquared = dot(delta, delta)
          core = exp(-distanceSquared / (effective * effective))
          energy = min(1.0'f, radius * radius / (pixel * pixel * 0.13'f))
          haloRadius = max(radius * 7.0'f, pixel * 0.9'f)
        var halo = exp(-distanceSquared / (haloRadius * haloRadius)) * 0.075'f
        # Compact support prevents new glows appearing at star-cell boundaries.
        halo *= 1.0'f - smoothstep(0.70'f, 1.0'f, sqrt(distanceSquared))
        let twinkle = 0.72'f +
          0.22'f * sin(time * (0.65'f + random.y * 0.80'f) + random.x * 71.0'f) +
          0.06'f * sin(time * 0.37'f + random.y * 34.0'f)
        var glint = 0.0'f
        if random.x > 0.985'f:
          let a: Vec2 = abs(delta) / effective
          glint = (exp(-a.x * a.x * 42.0'f - a.y * a.y * 0.45'f) +
            exp(-a.y * a.y * 42.0'f - a.x * a.x * 0.45'f)) * 0.16'f
        let tint: Vec3 = mix(vec3(0.72'f, 0.80'f, 1.0'f),
          vec3(1.0'f, 0.91'f, 0.85'f), random.y)
        result += tint * (core + halo + glint) * energy * brightness *
          3.0'f * twinkle

proc nightSkyVertex(gl_Position: var Vec4, skyUv: var Vec2) =
  ## Expands the fullscreen triangle to the far clip plane.
  skyUv = vec2(((gl_VertexID mod 2) * 2).float32,
    ((gl_VertexID div 2) * 2).float32)
  gl_Position = vec4(skyUv * 2.0'f - vec2(1.0'f), vec2(1.0'f))

proc nightSkyFragment(outputColor: var Vec4, skyUv: Vec2) =
  ## Shades the seamless nebula volume and three star shells.
  let
    farPoint: Vec4 = inverseViewProjection *
      vec4(skyUv * 2.0'f - vec2(1.0'f), vec2(1.0'f))
    ray: Vec3 = normalize(farPoint.xyz / farPoint.w - cameraEye)
    uv: Vec2 = vec2(atan(ray.z, ray.x) / (2.0'f * SkyPi) + 0.5'f,
      asin(clamp(ray.y, -1.0'f, 1.0'f)) / SkyPi + 0.5'f)
  var drift: Vec3 = time * vec3(-0.012'f, 0.004'f, 0.006'f)
  drift += vec3(sin(time * 0.045'f), cos(time * 0.038'f),
    sin(time * 0.031'f)) * 0.12'f
  let
    p: Vec3 = ray * 6.0'f + drift + cameraEye * 0.0015'f
    warp: Vec3 = vec3(cloudNoise(p * 0.65'f),
      cloudNoise(p * 0.65'f + vec3(17.3'f)),
      cloudNoise(p * 0.65'f - vec3(9.1'f)))
    dust = cloudLayers(p + warp * 2.2'f)
    wisps = cloudLayers(p * 2.4'f - drift * 0.7'f + warp)
    belt = exp(-pow((uv.y - 0.29'f +
      0.07'f * sin(uv.x * 4.0'f * SkyPi + time * 0.012'f)) * 5.5'f, 2.0'f))
    density = smoothstep(0.24'f, 0.78'f, dust) * belt
    rose = smoothstep(0.32'f, 0.76'f,
      cloudNoise(p * 0.7'f + vec3(4, 9, 2)))
    filaments = smoothstep(0.43'f, 0.80'f, wisps) * density
    breath = 0.94'f + 0.06'f * sin(time * 0.18'f + dust * 8.0'f)
  var sky: Vec3 = vec3(0.012'f, 0.019'f, 0.049'f)
  sky += vec3(0.065'f, 0.10'f, 0.23'f) * (0.30'f + dust * 0.70'f) * belt
  sky += mix(vec3(0.11'f, 0.12'f, 0.31'f),
    vec3(0.36'f, 0.16'f, 0.32'f), rose) * density * breath
  sky += mix(vec3(0.17'f, 0.22'f, 0.40'f),
    vec3(0.52'f, 0.29'f, 0.40'f), rose) * filaments
  sky += stars(uv, 420.0'f, 0.32'f, 0.68'f, 0.0'f)
  sky += stars(uv, 210.0'f, 0.22'f, 1.00'f, 1.0'f)
  sky += stars(uv, 85.0'f, 0.15'f, 1.45'f, 2.0'f)
  outputColor = vec4(sky * skyBrightness, 1.0'f)

const
  NightSkyVertexSource* =
    (when defined(useDirectX) or defined(useVulkan): nativeStage(nightSkyVertex, shaderVertex)
     else: toShader(nightSkyVertex, SkyShaderTarget, shaderVertex))
  NightSkyFragmentSource* =
    (when defined(useDirectX) or defined(useVulkan): nativeStage(nightSkyFragment, shaderFragment)
     else: toShader(nightSkyFragment, SkyShaderTarget, shaderFragment))
