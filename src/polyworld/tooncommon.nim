## Shared toon shaders, palette settings, and prepared CPU geometry.

import
  std/[math, sets],
  vmath, chroma, pixie, shady, gltf,
  frustums

var
  toonModel: Uniform[Mat4]
  toonNormalMatrix: Uniform[Mat3]
  toonView: Uniform[Mat4]
  toonProj: Uniform[Mat4]
  toonUseSkinning: Uniform[bool]
  toonPackedParts: Uniform[bool]
  toonJointMatrices: Uniform[array[128, Mat4]]
  toonLightDirection: Uniform[Vec3]   # direction the light travels
  toonCameraPosition: Uniform[Vec3]
  toonBaseColorTexture: Uniform[Sampler2d]
  toonBaseColorFactor: Uniform[Vec4]
  toonEmissiveTexture: Uniform[Sampler2d]
  toonEmissiveFactor: Uniform[Vec3]
  toonAlphaCutoff: Uniform[float32]
  toonRamp: Uniform[Sampler2d]
  toonHighlightColor: Uniform[Vec4]
  toonShadowColor: Uniform[Vec4]
  toonRimColor: Uniform[Vec4]
  toonUnlit: Uniform[bool]           # always in the highlight band
  toonTint: Uniform[Vec4]
  toonGlaze: Uniform[Vec4]           # laid over the colour by its alpha
  toonLightingMode: Uniform[int32]
  toonPerPixelLighting: Uniform[bool]
  toonNeutralMaterial: Uniform[bool]
  # Sun shadow map sampling, fed from polyworld/shadows each frame. Two
  # maps at neighbouring quantized sun steps, cross-faded by toonShadowStep
  # so shadows dissolve toward the next sun position instead of shimmering.
  toonShadowMvp0: Uniform[Mat4]
  toonShadowMvp1: Uniform[Mat4]
  toonShadowMap0: Uniform[Sampler2dShadow]
  toonShadowMap1: Uniform[Sampler2dShadow]
  toonShadowStep: Uniform[float32]
  toonShadowsOn: Uniform[float32]
  toonShadowStrength: Uniform[float32]
  toonShadowBias: Uniform[float32]
  toonShadowTexel: Uniform[float32]
  toonShadowSoftness: Uniform[float32]
  toonShadingStrength: Uniform[float32]
  toonLightLevel: Uniform[float32]

proc toonLitFraction0(worldPos: Vec3): float32 =
  ## Raw lit fraction from the first shadow step, 0 shadowed .. 1 clear: a
  ## 3x3 grid of hardware-PCF taps, each itself bilinearly filtered by the
  ## comparison sampler. Positions outside the map count as lit.
  result = 1.0'f
  let
    shadowCoord: Vec4 = toonShadowMvp0 * vec4(worldPos, 1.0'f)
    su = shadowCoord.x * 0.5'f + 0.5'f
    sv = shadowCoord.y * 0.5'f + 0.5'f
    sd = shadowCoord.z * 0.5'f + 0.5'f - toonShadowBias
  if su > 0.0'f and su < 1.0'f and sv > 0.0'f and sv < 1.0'f and sd < 1.0'f:
    let spread = toonShadowTexel * toonShadowSoftness
    var lit = 0.0'f32
    lit = lit + texture(toonShadowMap0, vec3(su - spread, sv - spread, sd))
    lit = lit + texture(toonShadowMap0, vec3(su, sv - spread, sd))
    lit = lit + texture(toonShadowMap0, vec3(su + spread, sv - spread, sd))
    lit = lit + texture(toonShadowMap0, vec3(su - spread, sv, sd))
    lit = lit + texture(toonShadowMap0, vec3(su, sv, sd))
    lit = lit + texture(toonShadowMap0, vec3(su + spread, sv, sd))
    lit = lit + texture(toonShadowMap0, vec3(su - spread, sv + spread, sd))
    lit = lit + texture(toonShadowMap0, vec3(su, sv + spread, sd))
    lit = lit + texture(toonShadowMap0, vec3(su + spread, sv + spread, sd))
    result = lit / 9.0'f

proc toonLitFraction1(worldPos: Vec3): float32 =
  ## The same for the second shadow step.
  result = 1.0'f
  let
    shadowCoord: Vec4 = toonShadowMvp1 * vec4(worldPos, 1.0'f)
    su = shadowCoord.x * 0.5'f + 0.5'f
    sv = shadowCoord.y * 0.5'f + 0.5'f
    sd = shadowCoord.z * 0.5'f + 0.5'f - toonShadowBias
  if su > 0.0'f and su < 1.0'f and sv > 0.0'f and sv < 1.0'f and sd < 1.0'f:
    let spread = toonShadowTexel * toonShadowSoftness
    var lit = 0.0'f32
    lit = lit + texture(toonShadowMap1, vec3(su - spread, sv - spread, sd))
    lit = lit + texture(toonShadowMap1, vec3(su, sv - spread, sd))
    lit = lit + texture(toonShadowMap1, vec3(su + spread, sv - spread, sd))
    lit = lit + texture(toonShadowMap1, vec3(su - spread, sv, sd))
    lit = lit + texture(toonShadowMap1, vec3(su, sv, sd))
    lit = lit + texture(toonShadowMap1, vec3(su + spread, sv, sd))
    lit = lit + texture(toonShadowMap1, vec3(su - spread, sv + spread, sd))
    lit = lit + texture(toonShadowMap1, vec3(su, sv + spread, sd))
    lit = lit + texture(toonShadowMap1, vec3(su + spread, sv + spread, sd))
    result = lit / 9.0'f

proc sunShadowFactor(worldPos: Vec3): float32 =
  ## How lit by the sun a fragment is, cross-fading between the two
  ## quantized sun steps. The result already folds in the shadow strength.
  result = 1.0'f
  if toonShadowsOn > 0.5'f:
    var lit = toonLitFraction0(worldPos)
    if toonShadowStep > 0:
      lit = mix(lit, toonLitFraction1(worldPos), toonShadowStep)
    result = 1.0'f - (1.0'f - lit) * toonShadowStrength

proc toonVert(
  vertexPosition: Vec3,
  vertexColor: Vec4,
  vertexNormal: Vec3,
  vertexUV: Vec2,
  vertexTangent: Vec4,
  vertexJoints: UVec4,
  vertexWeights: Vec4,
  vertexUV1: Vec2,
  gl_Position: var Vec4,
  worldPos: var Vec3,
  color: var Vec4,
  normal: var Vec3,
  uv: var Vec2,
  lightIntensity: var float32,
  parts: var Vec2,
  emission: var Vec4
) =
  var skin = mat4(1.0'f)
  if toonUseSkinning:
    skin =
      vertexWeights.x * toonJointMatrices[vertexJoints.x.int] +
      vertexWeights.y * toonJointMatrices[vertexJoints.y.int] +
      vertexWeights.z * toonJointMatrices[vertexJoints.z.int] +
      vertexWeights.w * toonJointMatrices[vertexJoints.w.int]
  let
    skinnedPosition = skin * vec4(vertexPosition, 1.0'f)
    skinnedNormal = (skin * vec4(vertexNormal, 0.0'f)).xyz
  worldPos = (toonModel * skinnedPosition).xyz
  color = vertexColor
  uv = vertexUV
  parts = vertexUV1
  emission = vertexTangent
  normal = normalize(toonNormalMatrix * skinnedNormal)
  # Step 1: Lambert from the one light, computed per vertex like the
  # GameCube did and interpolated across the triangle.
  let toLight: Vec3 = normalize(-toonLightDirection)
  lightIntensity = max(dot(normal, toLight), 0.0'f)
  gl_Position = toonProj * toonView * vec4(worldPos, 1.0'f)

proc glazed(color: Vec4): Vec4 =
  ## Lays `toonGlaze` over a finished colour by its alpha, keeping the
  ## colour's light and dark, so a body can read as made of something else.
  let shade = dot(color.rgb, vec3(0.3'f, 0.59'f, 0.11'f))
  result = vec4(mix(color.rgb, toonGlaze.rgb * (0.45'f + 0.9'f * shade),
    toonGlaze.a), color.a)

proc toonFrag(
  worldPos: Vec3,
  color: Vec4,
  normal: Vec3,
  uv: Vec2,
  lightIntensity: float32,
  parts: Vec2,
  emission: Vec4,
  fragColor: var Vec4
) =
  var albedo: Vec4 = texture(toonBaseColorTexture, uv) * toonBaseColorFactor * color
  let cutoff = if toonPackedParts: parts.y else: toonAlphaCutoff
  if albedo.a < cutoff:
    discardFragment()
  if toonPackedParts and emission.w < 0.5'f and not gl_FrontFacing:
    discardFragment()
  var n: Vec3 = normalize(normal)
  if not gl_FrontFacing:
    n = -n
  if toonLightingMode == 3:
    fragColor = vec4(n * 0.5'f + vec3(0.5'f), albedo.a) * toonTint
    return
  if toonNeutralMaterial:
    albedo = vec4(0.8'f, 0.8'f, 0.8'f, albedo.a)
  if toonUnlit or (toonPackedParts and parts.x > 0.5'f) or
    toonLightingMode == 2:
    fragColor = glazed(albedo * toonTint)
    return
  var lambert = lightIntensity
  if toonPerPixelLighting or toonLightingMode == 1:
    lambert = max(dot(n, normalize(-toonLightDirection)), 0.0'f)
  # Step 2: the intensity — scaled by the sun shadow test, flattened by the
  # shading strength when the sky is dark — is a texture coordinate into
  # the ramp.
  let
    sunFactor = sunShadowFactor(worldPos)
    intensity =
      (1.0'f - toonShadingStrength +
        lambert * sunFactor * toonShadingStrength) * toonLightLevel
  var band = texture(toonRamp, vec2(intensity, 0.5'f)).r
  if toonLightingMode == 1:
    band = clamp(intensity, 0.0'f, 1.0'f)
  # Step 3: two hand-picked colours, then the albedo on top.
  var lit: Vec3 = mix(toonShadowColor.rgb, toonHighlightColor.rgb, band)
  let
    eye: Vec3 = normalize(toonCameraPosition - worldPos)
    facing = 1.0'f - abs(dot(eye, n))
    rim = facing * facing * facing * facing
  lit = mix(lit, toonRimColor.rgb, rim * toonRimColor.a)
  var emissive: Vec3 = texture(toonEmissiveTexture, uv).rgb * toonEmissiveFactor
  if toonPackedParts:
    emissive = emission.xyz
  if toonNeutralMaterial:
    emissive = vec3(0.0'f)
  fragColor = glazed(vec4(lit * albedo.rgb + emissive, albedo.a) * toonTint)

## Sun depth pass: the same skinned vertex path projected by the sun's
## light matrix instead of the camera, with the base color's alpha cutout
## kept, so characters cast correct shadows into the shared sun map
## (polyworld/shadows). Attribute names match the gltf convention, so the
## primitives' existing vertex arrays bind unchanged.

var toonDepthLightMvp: Uniform[Mat4]

proc toonDepthVert(
  vertexPosition: Vec3,
  vertexColor: Vec4,
  vertexUV: Vec2,
  vertexUV1: Vec2,
  vertexJoints: UVec4,
  vertexWeights: Vec4,
  gl_Position: var Vec4,
  uv: var Vec2,
  parts: var Vec2,
  opacity: var float32
) =
  var skin = mat4(1.0'f)
  if toonUseSkinning:
    skin =
      vertexWeights.x * toonJointMatrices[vertexJoints.x.int] +
      vertexWeights.y * toonJointMatrices[vertexJoints.y.int] +
      vertexWeights.z * toonJointMatrices[vertexJoints.z.int] +
      vertexWeights.w * toonJointMatrices[vertexJoints.w.int]
  # Match toonVert and the world-space bounds even when weights sum to
  # slightly less or more than one.
  let worldPos = (toonModel * (skin * vec4(vertexPosition, 1.0'f))).xyz
  gl_Position = toonDepthLightMvp * vec4(worldPos, 1.0'f)
  uv = vertexUV
  parts = vertexUV1
  opacity = vertexColor.a

proc toonDepthCutout(uv: Vec2, parts: Vec2, opacity: float32) =
  let albedo: Vec4 = texture(toonBaseColorTexture, uv) * toonBaseColorFactor
  let
    cutoff = if toonPackedParts: parts.y else: toonAlphaCutoff
    alpha = if toonPackedParts: albedo.a * opacity else: albedo.a
  if alpha < cutoff:
    discardFragment()

proc toonDepthFrag(uv: Vec2, parts: Vec2, opacity: float32, fragColor: var Vec4) =
  toonDepthCutout(uv, parts, opacity)
  fragColor = vec4(1.0'f, 1.0'f, 1.0'f, 1.0'f)

## Background: a full-screen sky-to-ground gradient in the palette's
## colours, so the character is not floating in a void of another palette.

var
  toonSkyColor: Uniform[Vec4]       # top of the screen
  toonHorizonColor: Uniform[Vec4]   # at horizonHeight
  toonGroundColor: Uniform[Vec4]    # bottom of the screen
  toonHorizonHeight: Uniform[float32]  # 0 bottom .. 1 top

proc toonBackgroundVert(
  vertexPosition: Vec3,
  gl_Position: var Vec4,
  screenY: var float32
) =
  screenY = vertexPosition.y * 0.5'f + 0.5'f
  gl_Position = vec4(vertexPosition.x, vertexPosition.y, 1.0'f, 1.0'f)

proc toonBackgroundFrag(screenY: float32, fragColor: var Vec4) =
  let horizon = clamp(toonHorizonHeight, 0.01'f, 0.99'f)
  if screenY > horizon:
    let t = (screenY - horizon) / (1.0'f - horizon)
    fragColor = mix(toonHorizonColor, toonSkyColor, t)
  else:
    let t = screenY / horizon
    fragColor = mix(toonGroundColor, toonHorizonColor, t)

when defined(useDirectX) or defined(useVulkan):
  import polyworld/backends/native/stages

const
  ToonShaderTarget =
    when defined(useMetal4):
      metalMSL
    elif defined(emscripten):
      glsl3WebGL
    else:
      glsl4Desktop

template toonStage(fn, stage: untyped): string =
  when defined(useDirectX) or defined(useVulkan):
    nativeStage(fn, stage)
  else:
    toShader(fn, ToonShaderTarget, stage)

const
  ToonVertSrc* = toonStage(toonVert, shaderVertex)
  ToonFragSrc* = toonStage(toonFrag, shaderFragment)
  ToonDepthVertSrc* = toonStage(toonDepthVert, shaderVertex)
  ToonDepthFragSrc* =
    when defined(useDirectX) or defined(useVulkan): toonStage(toonDepthCutout, shaderFragment)
    else: toonStage(toonDepthFrag, shaderFragment)
  ToonBackgroundVertSrc* = toonStage(toonBackgroundVert, shaderVertex)
  ToonBackgroundFragSrc* = toonStage(toonBackgroundFrag, shaderFragment)

## Light

# The toon light travels this way: from the upper front-left at a low angle
# (about 25 degrees), so it rakes across characters and terrain. A light
# from nearly overhead puts every surface a top-down camera can see in the
# lit band, which reads as flat.
const ToonLightDirection* = normalize(vec3(0.7, -0.4, -0.6))

## Palettes

type ToonPalette* = object
  name*: string
  highlight*: Color
  shadow*: Color

proc palette(name, highlight, shadow: string): ToonPalette =
  ToonPalette(
    name: name,
    highlight: parseHtmlColor("#" & highlight),
    shadow: parseHtmlColor("#" & shadow)
  )

# Highlight/shadow pairs per time of day and weather.
const ToonPalettes* = [
  palette("Day", "FFFFFF", "A39892"),
  palette("Morning", "F0EAE3", "BCB7CB"),
  palette("Afternoon", "D8C37F", "B09070"),
  palette("Evening", "8D8C9A", "7E7885"),
  palette("Dusk", "A19AA3", "746676"),
  palette("Night", "879EB5", "5D6E99"),
  palette("Day rainy", "ADBBB7", "8E978D"),
  palette("Morning rainy", "B8BDB8", "9AA494"),
  palette("Afternoon rainy", "999187", "888177"),
  palette("Evening rainy", "8E877D", "7A7368"),
  palette("Dusk rainy", "90887A", "746676"),
  palette("Night rainy", "4B6690", "4C595A"),
]

proc mix*(a, b: ToonPalette, t: float32): ToonPalette =
  ToonPalette(
    name: (if t < 0.5: a.name else: b.name),
    highlight: mix(a.highlight, b.highlight, t),
    shadow: mix(a.shadow, b.shadow, t)
  )

# The sunny palettes laid along a 24 hour day: hour -> index into
# ToonPalettes. Dusk doubles as dawn.
const DayCycle = [
  (0.0'f32, 5), (4.0'f32, 5), (6.0'f32, 4), (8.0'f32, 1), (11.0'f32, 0),
  (15.0'f32, 0), (17.0'f32, 2), (19.0'f32, 3), (20.5'f32, 4), (22.0'f32, 5),
  (24.0'f32, 5),
]

proc paletteAtHour*(hour: float32): ToonPalette =
  ## The palette for a time of day, blending between the sunny palettes:
  ## night until 4, dawn at 6, morning at 8, full day 11 to 15, afternoon at
  ## 17, evening at 19, dusk at 20:30, night from 22. Hours wrap.
  let h = ((hour mod 24) + 24) mod 24
  for i in 0 ..< DayCycle.len - 1:
    let (h0, p0) = DayCycle[i]
    let (h1, p1) = DayCycle[i + 1]
    if h <= h1:
      let t = if h1 > h0: (h - h0) / (h1 - h0) else: 0'f32
      return mix(ToonPalettes[p0], ToonPalettes[p1], t)
  ToonPalettes[DayCycle[^1][1]]

## Ramp

const RampWidth = 256

proc rampImage*(shadowEnd = 0.47'f32, highlightStart = 0.53'f32): Image =
  ## The shading ramp: black, a short linear rise, white. Both edges are
  ## fractions of the full intensity range.
  result = newImage(RampWidth, 1)
  for x in 0 ..< RampWidth:
    let
      t = x.float32 / (RampWidth - 1).float32
      v = clamp((t - shadowEnd) / max(highlightStart - shadowEnd, 0.001'f32), 0, 1)
      byte = (v * 255).round.uint8
    result.data[x] = rgbx(byte, byte, byte, 255)

type
  ToonLighting* = enum
    BandedLighting, SmoothLighting, UnlitLighting, NormalLighting

  ToonMeshPose* = object
    node*: Node
    unlit*: bool
    packedParts*: bool
    transform*: Mat4
    normal*: Mat3
    joints*: seq[Mat4]
    boundsNode: Node
    boundsMesh: Mesh
    boundsPrimitives: seq[Primitive]
    geometryVersions: seq[uint64]
    bindBounds: seq[AABounds]
    boundsJointCount: int
    boundsValid: bool
    weightScale: float32
    weightMinimum: float32

  ToonPose* = object
    meshes*: seq[ToonMeshPose]
    meshCount*: int
    bounds*: AABounds
    boundsValid*: bool

  ToonSettings* = object of RootObj
    transform*: Mat4             ## model transform applied above the root
    view*, proj*: Mat4
    cameraPosition*: Vec3
    tint*: Color                 ## multiplies the final colour
    glaze*: Color                ## laid over the final colour by its alpha
    lightDirection*: Vec3        ## direction the light travels
    highlightColor*: Color
    shadowColor*: Color
    rimColor*: Color             ## alpha is the rim strength
    lighting*: ToonLighting      ## Selects bands, smooth light, or inspection.
    perPixelLighting*: bool      ## Evaluates Lambert after normal interpolation.
    neutralMaterial*: bool       ## Uses gray albedo while retaining cutouts.
    unlitNodes*: HashSet[string] ## mesh nodes drawn always full-bright
    skyColor*, horizonColor*, groundColor*: Color  ## background gradient
    horizonHeight*: float32      ## where the horizon sits, 0 bottom .. 1 top

proc setPalette*(ctx: auto, palette: ToonPalette) =
  ## Sets the character colours and derives a background from them: the
  ## horizon glows with the highlight, the sky above cools toward the shadow
  ## colour, the ground below is the shadow colour darkened a little.
  ctx.highlightColor = palette.highlight
  ctx.shadowColor = palette.shadow
  ctx.horizonColor = mix(palette.highlight, palette.shadow, 0.25)
  ctx.skyColor = mix(palette.highlight, palette.shadow, 0.8)
  ctx.groundColor = palette.shadow * 0.8
  ctx.groundColor.a = 1
  ctx.horizonHeight = 0.42

proc prepareBindBounds(mesh: var ToonMeshPose, node: Node) =
  ## Caches geometry boxes per joint, including only its weighted vertices.
  var changed = mesh.boundsNode != node or mesh.boundsMesh != node.mesh or
    mesh.geometryVersions.len != node.mesh.primitives.len or
    mesh.boundsJointCount != mesh.joints.len
  if not changed:
    for i, primitive in node.mesh.primitives:
      if mesh.boundsPrimitives[i] != primitive or
        mesh.geometryVersions[i] != primitive.geometryVersion:
        changed = true
        break
  if not changed:
    return
  mesh.boundsNode = node
  mesh.boundsMesh = node.mesh
  mesh.boundsJointCount = mesh.joints.len
  mesh.geometryVersions.setLen(node.mesh.primitives.len)
  mesh.boundsPrimitives.setLen(node.mesh.primitives.len)
  for i, primitive in node.mesh.primitives:
    mesh.geometryVersions[i] = primitive.geometryVersion
    mesh.boundsPrimitives[i] = primitive
  mesh.bindBounds.setLen(max(mesh.joints.len, 1))
  for bounds in mesh.bindBounds.mitems:
    bounds = emptyBounds()
  mesh.boundsValid = true
  mesh.weightScale = 1
  mesh.weightMinimum = 1
  for primitive in node.mesh.primitives:
    if mesh.joints.len > 0 and
      (primitive.jointIds.len != primitive.points.len or
      primitive.jointWeights.len != primitive.points.len):
        mesh.boundsValid = false
        return
    for i, point in primitive.points:
      for axis in 0 ..< 3:
        if classify(point[axis]) in {fcNan, fcInf, fcNegInf}:
          mesh.boundsValid = false
          return
      if mesh.joints.len == 0:
        mesh.bindBounds[0].extend(point)
        continue
      var sum = 0.0'f
      for j in 0 ..< 4:
        let
          weight = primitive.jointWeights[i][j]
          joint = primitive.jointIds[i][j].int
        if weight < 0 or classify(weight) in {fcNan, fcInf, fcNegInf}:
          mesh.boundsValid = false
          return
        sum += weight
        if weight == 0:
          continue
        if joint >= mesh.joints.len:
          mesh.boundsValid = false
          return
        mesh.bindBounds[joint].extend(point)
      mesh.weightScale = max(mesh.weightScale, sum)
      mesh.weightMinimum = min(mesh.weightMinimum, sum)

proc posedBounds(mesh: var ToonMeshPose, node: Node): AABounds =
  ## Bounds the convex combination of joint-transformed vertex positions.
  mesh.prepareBindBounds(node)
  result = emptyBounds()
  if not mesh.boundsValid:
    return
  var local = emptyBounds()
  if mesh.joints.len == 0:
    local = mesh.bindBounds[0]
  else:
    for i, bounds in mesh.bindBounds:
      local.extend(bounds.transformed(mesh.joints[i]))
    # Include zero and expand for weights whose sum is not exactly one.
    local.extend(vec3(0))
    local.min *= mesh.weightScale
    local.max *= mesh.weightScale
  result = local.transformed(mesh.transform)
  if mesh.joints.len > 0:
    # Skin weights scale model translation as well as local positions.
    let
      lower = mesh.transform.pos * (mesh.weightMinimum - 1)
      upper = mesh.transform.pos * (mesh.weightScale - 1)
    result.min += min(lower, upper)
    result.max += max(lower, upper)
  # Leave room for floating-point roundoff at the clipping planes.
  result.min -= vec3(0.001'f)
  result.max += vec3(0.001'f)

proc prepareMeshPoses(
  node, root: Node,
  pose: var ToonPose,
  unlitParts: openArray[string]
) =
  ## Reuses mesh slots even when visibility temporarily hides some nodes.
  if not node.visible:
    return
  if node.mesh != nil:
    if pose.meshCount == pose.meshes.len:
      pose.meshes.add ToonMeshPose()
    let index = pose.meshCount
    inc pose.meshCount
    let mesh = addr pose.meshes[index]
    mesh.node = node
    mesh.unlit = node.name in unlitParts
    mesh.packedParts = false
    mesh.transform = node.mat
    mesh.normal = node.mat.normalMatrix
    root.skinMatricesInto(node, mesh.joints)
    pose.bounds.extend(mesh[].posedBounds(node))
    pose.boundsValid = pose.boundsValid and mesh.boundsValid
  for child in node.nodes:
    prepareMeshPoses(child, root, pose, unlitParts)

proc prepareToonPose*(
  pose: var ToonPose,
  root: Node,
  transform: Mat4,
  unlitParts: openArray[string] = [],
  merged: Node = nil
) =
  ## Captures active meshes in retained storage for all drawing passes.
  root.updateTransforms(transform)
  pose.bounds = emptyBounds()
  pose.boundsValid = true
  pose.meshCount = 0
  if merged == nil:
    prepareMeshPoses(root, root, pose, unlitParts)
  else:
    merged.mat = root.mat
    prepareMeshPoses(merged, root, pose, [])
    pose.meshes[0].packedParts = true
