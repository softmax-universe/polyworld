## Shady stages for the courtyard's stone, cloth, lanterns and static shadows.

import std/math
import shady, vmath

const ShaderTarget =
  when defined(useMetal4): metalMSL
  elif defined(emscripten): glsl3WebGL
  else: glsl3Desktop

var
  viewProjection, lightMatrix, normalView: Uniform[Mat4]
  time, normalStrength, slopeBroad, scaleBroad, lampIntensity: Uniform[float32]
  arenaRadius, balconyLampRadius, balconyLampHalfAngle: Uniform[float32]
  cameraSide, stageYaw: Uniform[float32]
  cameraEye, firstLamp, secondLamp: Uniform[Vec3]
  playerCount: Uniform[int]
  normalsOnly: Uniform[bool]
  shadowMap: Uniform[Sampler2DShadow]
  stoneNormalMap: Uniform[Sampler2D]

proc courtyardVertex(
  position, normal, color: Vec3,
  material: float32,
  uv: Vec2,
  worldPosition, worldNormal, surfaceColor: var Vec3,
  shadowPosition: var Vec4,
  surfaceUv: var Vec2,
  surfaceMaterial: var int,
  gl_Position: var Vec4
) =
  ## Moves cloth vertices while preserving the static shadow projection.
  var point = position
  if material > 2.5'f and material < 3.5'f:
    let wave = sin(point.x * 4.3'f + time * 1.35'f + uv.y * 3.0'f)
    point.z += wave * 0.075'f * uv.y * uv.y
    point.x += sin(time * 0.85'f + uv.y * 4.2'f) * 0.025'f * uv.y
  worldPosition = point
  worldNormal = normal
  surfaceColor = color
  surfaceMaterial = int(material)
  surfaceUv = uv
  shadowPosition = lightMatrix * vec4(point, 1.0)
  gl_Position = viewProjection * vec4(point, 1.0)

proc stoneSlope(uv: Vec2): Vec2 =
  ## Reads linear, repeated normal data as slopes for triplanar mapping.
  let broad = texture(stoneNormalMap, uv / max(scaleBroad, 0.01'f)).xyz *
    2.0'f - 1.0'f
  result = broad.xy / max(broad.z, 0.45'f) * slopeBroad * normalStrength

proc stoneNormal(point, normal: Vec3): Vec3 =
  ## Blends world-aligned slopes without requiring mesh tangent attributes.
  let signs = vec3(
    if normal.x >= 0: 1.0'f else: -1.0'f,
    if normal.y >= 0: 1.0'f else: -1.0'f,
    if normal.z >= 0: 1.0'f else: -1.0'f
  )
  var weights = pow(abs(normal), vec3(4))
  weights /= max(dot(weights, vec3(1)), 0.0001'f)
  let
    x = stoneSlope(vec2(-signs.x * point.z, point.y))
    y = stoneSlope(vec2(point.x, -signs.y * point.z))
    z = stoneSlope(vec2(signs.z * point.x, point.y))
    slope = vec3(0, x.y, -signs.x * x.x) * weights.x +
      vec3(y.x, 0, -signs.y * y.y) * weights.y +
      vec3(signs.z * z.x, z.y, 0) * weights.z
  result = normalize(normal + slope - normal * dot(slope, normal))

proc stoneHash(point: Vec3): float32 =
  ## Hashes a lattice point into repeatable stone grain.
  var value = fract(point * 0.1031'f)
  value += dot(value, value.yzx + 33.33'f)
  result = fract((value.x + value.y) * value.z)

proc stoneNoise(point: Vec3): float32 =
  ## Interpolates smooth noise from the eight surrounding lattice samples.
  let cell = floor(point)
  var blend = fract(point)
  blend = blend * blend * (3.0'f - 2.0'f * blend)
  result = mix(
    mix(
      mix(stoneHash(cell), stoneHash(cell + vec3(1, 0, 0)), blend.x),
      mix(stoneHash(cell + vec3(0, 1, 0)),
        stoneHash(cell + vec3(1, 1, 0)), blend.x),
      blend.y
    ),
    mix(
      mix(stoneHash(cell + vec3(0, 0, 1)),
        stoneHash(cell + vec3(1, 0, 1)), blend.x),
      mix(stoneHash(cell + vec3(0, 1, 1)),
        stoneHash(cell + vec3(1, 1, 1)), blend.x),
      blend.y
    ),
    blend.z
  )

proc visibility(normal, light: Vec3, shadowPosition: Vec4): float32 =
  ## Filters static sun visibility with bias from the geometric normal.
  let point = shadowPosition.xyz / shadowPosition.w * 0.5'f + 0.5'f
  if point.z > 1 or point.z < 0 or point.x < 0 or point.y < 0 or
    point.x > 1 or point.y > 1:
      return 1.0'f
  let bias = max(0.00030'f,
    0.0010'f * (1.0'f - max(0.0'f, dot(normal, light))))
  var total = 0.0'f
  for y in -1 .. 1:
    for x in -1 .. 1:
      total += texture(shadowMap, vec3(
        point.xy + vec2(x.float32, y.float32) * 1.35'f / 2048.0'f,
        point.z - bias
      ))
  result = total / 9.0'f

proc lamp(point, normal, source: Vec3, phase: float32): Vec3 =
  ## Matches the warm, flickering lantern light used by courtyard heroes.
  let
    delta = source - point
    distance = length(delta)
    flicker = 0.96'f + 0.025'f * sin(time * 5.1'f + phase) +
      0.018'f * sin(time * 8.3'f + phase)
  result = vec3(1.0, 0.45, 0.115) *
    (lampIntensity / (1.0'f + distance * distance * 1.2'f)) *
    (0.18'f + 0.82'f * max(0.0'f, dot(normal, normalize(delta)))) * flicker

proc atan(y, x: float32): float32 =
  ## Maps the two-argument GLSL angle function to its Nim equivalent.
  result = arctan2(y, x)

proc courtyardFragment(
  worldPosition, worldNormal, surfaceColor: Vec3,
  shadowPosition: Vec4,
  surfaceUv: Vec2,
  surfaceMaterial: int,
  outputColor: var Vec4
) =
  ## Shades courtyard materials and optionally records their view normals.
  let
    point = worldPosition
    geometricNormal: Vec3 = normalize(worldNormal)
    material = surfaceMaterial.float32
    grain = stoneNoise(point * 37.0'f)
    broad = stoneNoise(point * 2.4'f) * 0.64'f +
      stoneNoise(point * 8.6'f) * 0.36'f
  var
    normal: Vec3 = geometricNormal
    base = surfaceColor
  if material < 0.5'f or material > 4.5'f:
    base *= 0.845'f + broad * 0.28'f + grain * 0.06'f
    let pore = smoothstep(0.73'f, 0.88'f, stoneNoise(point * 71.0'f))
    base *= 1.0'f - pore * 0.06'f
    var edge = max(smoothstep(8.4'f, 10.2'f, abs(point.x)),
      smoothstep(5.6'f, 8.5'f, abs(point.z)))
    if arenaRadius > 0:
      edge = smoothstep(arenaRadius - 1.6'f, arenaRadius + 0.1'f,
        length(point.xz))
    let moss = smoothstep(0.55'f, 0.76'f, broad) * edge *
      (0.35'f + 0.45'f * max(normal.y, 0.0'f))
    base = mix(base, vec3(0.20, 0.235, 0.105), moss * 0.50'f)
    if material < 0.5'f:
      normal = stoneNormal(point, normal)
  elif material < 1.5'f:
    base *= 0.88'f + grain * 0.20'f
  elif material < 2.5'f:
    base *= 0.90'f + broad * 0.18'f
  elif material < 3.5'f:
    let
      uv = surfaceUv
      motif = (uv - vec2(0.5, 0.47)) * vec2(1.0, 1.55)
      diamond = abs(motif.x) / 0.25'f + abs(motif.y) / 0.35'f
      frame = 1.0'f - smoothstep(0.022'f, 0.033'f, abs(diamond - 1.0'f))
      vertical = max(abs(motif.x) / 0.055'f + abs(motif.y) / 0.29'f,
        abs(motif.x) / 0.19'f + abs(motif.y) / 0.075'f)
      compass = 1.0'f - smoothstep(0.96'f, 1.04'f, vertical)
      hem = min(min(uv.x, 1.0'f - uv.x), 1.0'f - uv.y)
      border = 1.0'f - smoothstep(0.006'f, 0.012'f, abs(hem - 0.036'f))
    base = mix(base, vec3(0.63, 0.48, 0.245), max(max(frame, compass), border))
    base *= 0.90'f + 0.10'f * sin(uv.x * 14.0'f + uv.y * 2.0'f)
    base *= 0.97'f + 0.03'f * sin(uv.x * 770.0'f) * sin(uv.y * 900.0'f)
    normal = normalize(cross(dFdx(point), dFdy(point)))
    if dot(normal, cameraEye - point) < 0:
      normal = -normal
  if normalsOnly:
    outputColor = vec4(normalize(mat3(normalView) * normal) * 0.5'f + 0.5'f, 1)
    return
  let
    light: Vec3 = normalize(vec3(-0.48'f * cameraSide, 0.85, 0.35'f * cameraSide))
    sun = visibility(geometricNormal, light, shadowPosition)
    diffuse = max(0.0'f, dot(normal, light))
    ambient: Vec3 = mix(vec3(0.33, 0.35, 0.39), vec3(0.62, 0.64, 0.68),
      max(0.0'f, normal.y))
  var lighting = ambient + vec3(0.67, 0.53, 0.36) * diffuse * sun
  if arenaRadius > 0:
    let
      cosine = cos(stageYaw)
      sine = sin(stageYaw)
      localPoint = vec3(point.x * cosine - point.z * sine, point.y,
        point.x * sine + point.z * cosine)
      localNormal = vec3(normal.x * cosine - normal.z * sine, normal.y,
        normal.x * sine + normal.z * cosine)
      count = playerCount.float32
      stepAngle = 6.28318530718'f / count
      nearest = floor(atan(-localPoint.x, localPoint.z + 0.00001'f) /
        stepAngle + 0.5'f)
    for offset in -1 .. 1:
      if playerCount != 2 or offset != 1:
        let
          seat = fmod(nearest + offset.float32, count)
          yaw = seat * stepAngle
        for endpoint in 0 .. 1:
          let
            side = (endpoint * 2 - 1).float32
            angle = side * balconyLampHalfAngle - yaw
            source = vec3(sin(angle) * balconyLampRadius, 1.25,
              cos(angle) * balconyLampRadius)
          lighting += lamp(localPoint, localNormal, source, seat * 2.0'f + side)
  else:
    lighting += lamp(point, normal, firstLamp, 0.0)
    lighting += lamp(point, normal, secondLamp, 2.0)
  var lit = base * lighting
  if material > 0.5'f and material < 1.5'f:
    let halfway: Vec3 = normalize(light + normalize(cameraEye - point))
    lit += vec3(0.20, 0.15, 0.06) *
      pow(max(0.0'f, dot(normal, halfway)), 24.0'f) * sun
  if material > 3.5'f and material < 4.5'f:
    lit = vec3(1.0, 0.68, 0.25) * (0.95'f + 0.04'f * sin(time * 6.0'f))
  let
    sceneScale =
      if arenaRadius > 0: 11.5'f / max(arenaRadius, 11.5'f)
      else: 1.0'f
    depth = max(0.0'f, -point.z * cameraSide * sceneScale - 8.0'f)
    fog = 1.0'f - exp(-depth * 0.055'f)
    mist = vec3(0.035, 0.055, 0.10)
  lit = mix(lit, mist, fog)
  let edgeShade = 1.0'f -
    smoothstep(6.8'f, 14.0'f, length(point.xz) * sceneScale) * 0.18'f
  outputColor = vec4(lit * edgeShade, 1.0)

proc courtyardDepthVertex(position: Vec3, gl_Position: var Vec4) =
  ## Projects the unmoving geometry into the static sun depth maps.
  gl_Position = lightMatrix * vec4(position, 1.0)

proc courtyardDepthFragment() =
  ## Writes only the rasterizer's depth for the static sun maps.
  discard

const
  CourtyardVertexSource* =
    toShader(courtyardVertex, ShaderTarget, shaderVertex)
  CourtyardFragmentSource* =
    toShader(courtyardFragment, ShaderTarget, shaderFragment)
  CourtyardDepthVertexSource* =
    toShader(courtyardDepthVertex, ShaderTarget, shaderVertex)
  CourtyardDepthFragmentSource* =
    toShader(courtyardDepthFragment, ShaderTarget, shaderFragment)
