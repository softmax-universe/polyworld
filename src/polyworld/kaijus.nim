import
  std/[math, os, tables],
  chroma, gltf, jsony, pixie, vmath

const
  Tau = 2.0'f * PI.float32
  HeadCenter = vec3(0, 2.96, 0.40)
  EyeOutline = [
    vec2(-0.25, -0.04), vec2(0.02, 0.035), vec2(0.25, 0.14),
    vec2(0.265, 0.0), vec2(0.19, -0.16), vec2(0.04, -0.23),
    vec2(-0.12, -0.20), vec2(-0.23, -0.12)
  ]

type
  KaijugenError* = object of CatchableError
  KaijuHead* = enum
    ClassicHead
  KaijuSpikes* = enum
    DorsalPlates
  KaijuEyes* = enum
    FierceEyes
  KaijuColor* = enum
    Skin, Belly, Spikes, Iris, Claws
  KaijuSettings* = object
    head*: KaijuHead
    spikes*: KaijuSpikes
    eyes*: KaijuEyes
    headSize*, spikeSize*, tailLength*, eyeSize*, facets*: float32
    colors*: array[KaijuColor, Vec3]
  KaijuMaterials* = array[KaijuColor, Material]
  Section = tuple[y, x, width, front, back: float32]
  SweepPoint = object
    center: Vec3
    radius: Vec2
  Patch = enum
    NoPatch, ChestPatch, JawPatch, LegPatch
  Draft = object
    points: seq[Vec3]
    faces: seq[array[3, int]]
    patches: seq[bool]

const
  TorsoProfile: array[10, Section] = [
    (0.55, 0.0, 0.0, 0.28, 0.28),
    (0.64, 0.0, 0.40, 0.60, -0.18),
    (0.93, 0.0, 0.66, 0.84, -0.45),
    (1.25, 0.0, 0.85, 0.93, -0.63),
    (1.58, 0.0, 0.88, 0.88, -0.80),
    (1.91, 0.0, 0.77, 0.71, -0.74),
    (2.19, 0.0, 0.62, 0.46, -0.65),
    (2.44, 0.0, 0.56, 0.30, -0.60),
    (2.57, 0.0, 0.50, 0.24, -0.47),
    (2.80, 0.0, 0.0, 0.08, 0.08)
  ]
  HeadProfile: array[10, Section] = [
    (2.35, 0.0, 0.0, 0.88, 0.88),
    (2.39, 0.0, 0.48, 1.16, 0.0),
    (2.56, 0.0, 0.84, 1.34, -0.22),
    (2.81, 0.0, 0.92, 1.40, -0.37),
    (3.02, 0.0, 0.94, 1.40, -0.43),
    (3.12, 0.0, 0.90, 1.11, -0.43),
    (3.29, 0.0, 0.81, 1.00, -0.38),
    (3.47, 0.0, 0.62, 0.77, -0.25),
    (3.55, 0.0, 0.35, 0.43, -0.07),
    (3.57, 0.0, 0.0, 0.22, 0.22)
  ]
  LegProfile: array[8, Section] = [
    (0.27, 1.02, 0.0, 0.12, 0.12),
    (0.38, 1.02, 0.33, 0.44, -0.15),
    (0.58, 1.01, 0.44, 0.64, -0.34),
    (0.93, 0.96, 0.54, 0.63, -0.50),
    (1.23, 0.90, 0.55, 0.50, -0.53),
    (1.48, 0.76, 0.41, 0.26, -0.45),
    (1.64, 0.69, 0.18, 0.06, -0.28),
    (1.68, 0.68, 0.0, -0.12, -0.12)
  ]
  FootProfile: array[7, Section] = [
    (0.025, 1.07, 0.0, 0.35, 0.35),
    (0.035, 1.07, 0.48, 0.92, -0.13),
    (0.13, 1.06, 0.49, 0.98, -0.17),
    (0.28, 1.05, 0.46, 0.91, -0.18),
    (0.42, 1.03, 0.35, 0.64, -0.12),
    (0.51, 1.02, 0.24, 0.38, -0.06),
    (0.54, 1.02, 0.0, 0.16, 0.16)
  ]

proc classicKaiju*(): KaijuSettings =
  ## Returns the first green kaiju with coral plates and a golden belly.
  KaijuSettings(
    head: ClassicHead, spikes: DorsalPlates, eyes: FierceEyes,
    headSize: 0.92, spikeSize: 1, tailLength: 1, eyeSize: 1, facets: 0.08,
    colors: [
      vec3(0.43, 0.64, 0.28), vec3(1.0, 0.89, 0.46),
      vec3(1.0, 0.34, 0.37), vec3(1.0, 0.80, 0.16),
      vec3(0.16, 0.18, 0.22)
    ]
  )

proc validate*(settings: KaijuSettings) =
  ## Rejects invalid recipes before allocating geometry or touching the GPU.
  for value in [settings.headSize, settings.tailLength, settings.eyeSize]:
    if not (value >= 0.75 and value <= 1.25):
      raise newException(KaijugenError, "Proportions must be 0.75 to 1.25.")
  if not (settings.spikeSize >= 0.4 and settings.spikeSize <= 1.5):
    raise newException(KaijugenError, "Plate size must be 0.4 to 1.5.")
  if not (settings.facets >= 0 and settings.facets <= 1):
    raise newException(KaijugenError, "Faceting must be 0 to 1.")
  for tint in settings.colors:
    for value in [tint.x, tint.y, tint.z]:
      if not (value >= 0 and value <= 1):
        raise newException(KaijugenError, "Color channels must be 0 to 1.")

proc material(name: string, tint: Vec3, unlit = false): Material =
  ## Creates a solid material that works in the toon viewer and GLB exports.
  let white = newImage(1, 1)
  white.fill(color(1, 1, 1, 1))
  Material(
    name: name, baseColor: white,
    baseColorFactor: color(tint.x, tint.y, tint.z),
    baseColorSampler: defaultTextureSampler(), roughnessFactor: 0.85,
    unlit: unlit
  )

proc insideEye(point: Vec2, size: float32): bool =
  ## Tests the convex eye contour for the rasterized iris and clipped pupil.
  result = true
  for i in 0 ..< EyeOutline.len:
    let
      a = EyeOutline[i] * size
      b = EyeOutline[(i + 1) mod EyeOutline.len] * size
      edge = b - a
      delta = point - a
    if edge.x * delta.y - edge.y * delta.x > 0:
      return false

proc eyeTexture(glints: bool): Image =
  ## Draws an almond eye with its pupil clipped by the slanted upper lid.
  const Resolution = 256
  result = newImage(Resolution, Resolution)
  for y in 0 ..< Resolution:
    for x in 0 ..< Resolution:
      let point = vec2(
        (x.float32 / (Resolution - 1).float32 - 0.5'f) * 0.60'f,
        0.18'f - y.float32 / (Resolution - 1).float32 * 0.46'f
      )
      if not insideEye(point, 1):
        continue
      let
        pupil = pow((point.x + 0.07'f) / 0.08'f, 2) +
          pow((point.y + 0.065'f) / 0.18'f, 2) < 1
        glint = pow((point.x - 0.015'f) / 0.043'f, 2) +
          pow((point.y + 0.015'f) / 0.043'f, 2) < 1
        smallGlint = pow((point.x + 0.115'f) / 0.018'f, 2) +
          pow((point.y + 0.155'f) / 0.022'f, 2) < 1
      if glints:
        if glint or smallGlint:
          result[x, y] = rgbx(255, 255, 243, 255)
      else:
        let value =
          if pupil or not insideEye(point - vec2(0, -0.003), 0.96):
            25'u8
          else:
            255'u8
        result[x, y] = rgbx(value, value, value, 255)

proc kaijuMaterials*(settings: KaijuSettings): KaijuMaterials =
  ## Creates independent tint slots for the five editable body colors.
  settings.validate()
  for slot in KaijuColor:
    result[slot] = material($slot, settings.colors[slot], slot == Iris)
  result[Iris].baseColor = eyeTexture(false)
  result[Iris].alphaMode = MaskAlphaMode
  result[Iris].alphaCutoff = 0.5

proc tint*(materials: KaijuMaterials, settings: KaijuSettings) =
  ## Updates material factors without rebuilding the model geometry.
  for slot in KaijuColor:
    let rgb = settings.colors[slot]
    materials[slot].baseColorFactor = color(rgb.x, rgb.y, rgb.z)

proc node(name: string): Node =
  ## Creates a visible node with explicit identity transforms.
  Node(
    name: name, visible: true, baseVisible: true,
    scale: vec3(1), baseScale: vec3(1),
    rot: quat(0, 0, 0, 1), baseRot: quat(0, 0, 0, 1)
  )

proc part(parent: Node, name: string, surface: Material): Primitive =
  ## Adds one named mesh to a modular body group.
  result = Primitive(mode: TrianglesMode, material: surface)
  let child = node(name)
  child.mesh = Mesh(name: name, primitives: @[result])
  parent.nodes.add child

proc triangle(
  mesh: Primitive,
  positions, normals: array[3, Vec3],
  facets: float32
) =
  ## Appends a nondegenerate outward triangle with adjustable flat normals.
  let crossNormal = cross(positions[1] - positions[0],
    positions[2] - positions[0])
  if length(crossNormal) < 0.000001:
    return
  let normal = normalize(crossNormal)
  for i in 0 ..< 3:
    mesh.points.add positions[i]
    mesh.normals.add normalize(mix(normals[i], normal, facets))

proc face(mesh: Primitive, a, b, c: Vec3) =
  ## Appends a faceted triangle for claws and dorsal plates.
  let normal = normalize(cross(b - a, c - a))
  mesh.triangle([a, b, c], [normal, normal, normal], 1)

proc connect(draft: var Draft, rings, segments: int,
    patches: seq[bool] = @[]) =
  ## Connects shared profile rings with outward triangles.
  for i in 0 ..< rings - 1:
    for j in 0 ..< segments:
      let
        a = i * segments + j
        b = i * segments + (j + 1) mod segments
        c = b + segments
        d = a + segments
        patch = patches.len > 0 and patches[i * segments + j]
      draft.faces.add [a, b, c]
      draft.faces.add [a, c, d]
      draft.patches.add patch
      draft.patches.add patch

proc finish(parent: Node, name: string, draft: Draft,
    surface, accent: Material, facets: float32) =
  ## Computes shared vertex normals before splitting colored surfaces.
  let
    mesh = parent.part(name, surface)
    patch =
      if accent == surface:
        mesh
      else:
        parent.part(name & " color", accent)
  var normals = newSeq[Vec3](draft.points.len)
  for face in draft.faces:
    let normal = cross(draft.points[face[1]] - draft.points[face[0]],
      draft.points[face[2]] - draft.points[face[0]])
    for index in face:
      normals[index] += normal
  var shared: Table[Vec3, Vec3]
  for i, point in draft.points:
    shared[point] = shared.getOrDefault(point) + normals[i]
  for i, point in draft.points:
    normals[i] = shared[point]
  for normal in normals.mitems:
    if length(normal) > 0.000001:
      normal = normalize(normal)
    else:
      normal = vec3(0, 1, 0)
  for i, face in draft.faces:
    let target = if draft.patches[i]: patch else: mesh
    target.triangle(
      [draft.points[face[0]], draft.points[face[1]], draft.points[face[2]]],
      [normals[face[0]], normals[face[1]], normals[face[2]]],
      facets
    )

proc signedPower(value, exponent: float32): float32 =
  ## Preserves the sign while shaping a rounded rectangular section.
  if value < 0:
    -pow(-value, exponent)
  else:
    pow(value, exponent)

proc mouthHeight(x: float32): float32 =
  ## Defines the continuous scalloped boundary between the muzzle and jaw.
  2.82'f - 0.08'f * sin(clamp((abs(x) - 0.12'f) / 0.56'f,
    0.0'f, 1.0'f) * PI.float32) +
    0.13'f * clamp((abs(x) - 0.50'f) / 0.24'f, 0.0'f, 1.0'f)

proc sectionPoint(section: Section, angle, exponent, side: float32,
    mouth = false): Vec3 =
  ## Samples an explicitly shaped horizontal cross-section.
  let
    x = section.x * side + section.width * signedPower(sin(angle), exponent)
    z = (section.front + section.back) * 0.5'f +
      (section.front - section.back) * 0.5'f * signedPower(cos(angle), exponent)
    y = if mouth and cos(angle) > 0: mouthHeight(x) else: section.y
  vec3(x, y, z)

proc shapeHead(position: Vec3): Vec3 =
  ## Sculpts recessed sockets and connected orbital ridges into the skull.
  let
    x = abs(position.x)
    y = position.y
    front = clamp((position.z + 0.10'f) / 0.65'f, 0.0'f, 1.0'f)
    socket = exp(-pow((x - 0.55'f) / 0.25'f, 2) -
      pow((y - 3.12'f) / 0.13'f, 2))
    ridgeY = 3.25'f + (x - 0.55'f) * 0.34'f
    ridge = exp(-pow((x - 0.55'f) / 0.30'f, 4) -
      pow((y - ridgeY) / 0.085'f, 2))
  result = position
  result.z += (ridge * 0.13'f - socket * 0.075'f) * front
  result.y = 2.35'f + (position.y - 2.35'f) * 1.10'f

proc profileDraft(profile: openArray[Section], exponent: float32,
    patch: Patch = NoPatch, side = 1.0'f,
    segments = 32, steps = 3): Draft =
  ## Rounds authored profile transitions while retaining their silhouette.
  var
    draft: Draft
    patches: seq[bool]
  for ring in 0 .. (profile.len - 1) * steps:
    let
      i = min(ring div steps, profile.len - 2)
      t = (ring - i * steps).float32 / steps.float32
    for j in 0 ..< segments:
      let angle = Tau * j.float32 / segments.float32
      var points: array[4, Vec3]
      for k in 0 ..< 4:
        let index = clamp(i + k - 1, 0, profile.high)
        points[k] = sectionPoint(profile[index], angle, exponent, side,
          patch == JawPatch and index == 3)
      let
        a = points[0]
        b = points[1]
        c = points[2]
        d = points[3]
        position = (b * 2 + (c - a) * t +
          (a * 2 - b * 5 + c * 4 - d) * t * t +
          (-a + b * 3 - c * 3 + d) * t * t * t) * 0.5'f
        middle = angle + PI.float32 / segments.float32
        painted = case patch
          of NoPatch: false
          of ChestPatch: cos(middle) > 0.57
          of JawPatch: i < 3 and cos(middle) > 0.35
          of LegPatch:
            cos(middle) > 0.35 and sin(middle) * side < -0.3 and i < 5
      if patch == JawPatch:
        draft.points.add shapeHead(position)
      else:
        draft.points.add position
      patches.add painted
  draft.connect((profile.len - 1) * steps + 1, segments, patches)
  result = draft

proc loft(parent: Node, name: string, profile: openArray[Section],
    surface, accent: Material, facets, exponent: float32,
    patch: Patch = NoPatch, side = 1.0'f) =
  ## Attaches one profiled part and its flush color patch.
  parent.finish(name, profileDraft(profile, exponent, patch, side),
    surface, accent, facets)

proc smoothPath(points: openArray[SweepPoint], steps = 3): seq[SweepPoint] =
  ## Samples a Catmull-Rom centerline and linearly interpolated thickness.
  for i in 0 ..< points.len - 1:
    let
      a = points[max(0, i - 1)].center
      b = points[i].center
      c = points[i + 1].center
      d = points[min(points.high, i + 2)].center
    for j in 0 ..< steps:
      let t = j.float32 / steps.float32
      result.add SweepPoint(
        center: (b * 2 + (c - a) * t +
          (a * 2 - b * 5 + c * 4 - d) * t * t +
          (-a + b * 3 - c * 3 + d) * t * t * t) * 0.5'f,
        radius: mix(points[i].radius, points[i + 1].radius, t)
      )
  result.add points[^1]

proc sweep(parent: Node, name: string, points: openArray[SweepPoint],
    surface, accent: Material, facets: float32, segments = 20,
    underside = false) =
  ## Sweeps elliptical sections with a stable frame along a bent centerline.
  var
    draft: Draft
    patches: seq[bool]
  for i, point in points:
    let
      before = points[max(0, i - 1)].center
      after = points[min(points.high, i + 1)].center
      tangent = normalize(after - before)
      axis = vec3(-1, 0, 0)
      right = normalize(axis - tangent * dot(axis, tangent))
      up = normalize(cross(tangent, right))
      t = i.float32 / points.high.float32
      boundary = 0.35'f + 0.65'f * clamp((t - 0.40'f) / 0.27'f,
        0.0'f, 1.0'f)
      split = segments * 2 div 3
      edge = arcsin(boundary)
    for j in 0 ..< segments:
      let angle =
        if not underside:
          Tau * j.float32 / segments.float32
        elif j <= split:
          -edge + (PI.float32 + edge * 2) * j.float32 / split.float32
        else:
          PI.float32 + edge + (PI.float32 - edge * 2) *
            (j - split).float32 / (segments - split).float32
      draft.points.add point.center + right * (cos(angle) * point.radius.x) +
        up * (sin(angle) * point.radius.y)
      patches.add underside and j >= split
  draft.connect(points.len, segments, patches)
  let cap = draft.points.len
  draft.points.add points[0].center
  for j in 0 ..< segments:
    draft.faces.add [cap, (j + 1) mod segments, j]
    draft.patches.add false
  if points[^1].radius.x > 0 and points[^1].radius.y > 0:
    let
      tip = draft.points.len
      ring = (points.len - 1) * segments
    draft.points.add points[^1].center
    for j in 0 ..< segments:
      draft.faces.add [tip, ring + j, ring + (j + 1) mod segments]
      draft.patches.add false
  parent.finish(name, draft, surface, accent, facets)

proc horn(parent: Node, name: string, base, tip: Vec3,
    width, thickness: float32, surface: Material,
    axis = vec3(1, 0, 0)) =
  ## Forms a thick swept horn with beveled roots and a curved tapered ridge.
  const
    Stations = [0.0'f, 0.13, 0.38, 0.68, 1.0]
    Widths = [0.65'f, 1.0, 0.88, 0.48, 0.0]
  let
    direction = normalize(tip - base)
    across = normalize(axis - direction * dot(axis, direction))
    breadth = normalize(cross(direction, across))
  var draft: Draft
  for i, t in Stations:
    let center = mix(base, tip, t) +
      breadth * (sin(t * PI.float32) * width * 0.23'f)
    for j in 0 ..< 8:
      let angle = Tau * j.float32 / 8
      draft.points.add center +
        across * (cos(angle) * thickness * Widths[i]) +
        breadth * (sin(angle) * width * Widths[i])
  draft.connect(Stations.len, 8)
  let cap = draft.points.len
  draft.points.add base
  for j in 0 ..< 8:
    draft.faces.add [cap, (j + 1) mod 8, j]
    draft.patches.add false
  parent.finish(name, draft, surface, surface, 0.48)

proc talon(parent: Node, name: string, base: Vec3, size, splay,
    curl: float32, surface, collar: Material) =
  ## Builds a broad tapered claw and a coral root that follows its curve.
  let
    bend = base + vec3(splay * 0.3, size * 0.15, size * 0.58)
    tip = base + vec3(splay, -size * curl, size * 1.35)
  const CollarOutline = [
    vec2(-0.85, 0.20), vec2(-0.62, 0.96), vec2(-0.18, 0.55),
    vec2(0.10, 1.02), vec2(0.40, 0.56), vec2(0.70, 0.90),
    vec2(0.87, 0.10), vec2(0.70, -0.05), vec2(-0.70, -0.05)
  ]
  let
    crown = parent.part(name & " coral root", collar)
    front = base + vec3(0, size * 0.25, size * 0.10)
    back = front - vec3(0, 0, size * 0.45)
  for i, point in CollarOutline:
    let
      next = CollarOutline[(i + 1) mod CollarOutline.len]
      a = base + vec3(point.x * size, point.y * size * 0.68,
        size * (0.10'f - point.x * point.x * 0.55'f))
      b = base + vec3(next.x * size, next.y * size * 0.68,
        size * (0.10'f - next.x * next.x * 0.55'f))
      c = b - vec3(0, 0, size * 0.45)
      d = a - vec3(0, 0, size * 0.45)
    crown.face(b, a, front)
    crown.face(d, c, back)
    crown.face(a, b, c)
    crown.face(a, c, d)
  parent.sweep(
    name,
    [SweepPoint(center: base, radius: vec2(size * 0.67, size * 0.65)),
      SweepPoint(center: bend, radius: vec2(size * 0.62, size * 0.60)),
      SweepPoint(center: mix(bend, tip, 0.65'f),
        radius: vec2(size * 0.27, size * 0.25)),
      SweepPoint(center: tip, radius: vec2(0))],
    surface, surface, 0.55, 8
  )

proc headFront(shell: Draft, x, y: float32): float32 =
  ## Intersects the modeled facial triangles so artwork follows each plane.
  result = -1.0'f
  for face in shell.faces:
    let
      a = shell.points[face[0]]
      b = shell.points[face[1]]
      c = shell.points[face[2]]
    if x < min(a.x, min(b.x, c.x)) or
      x > max(a.x, max(b.x, c.x)) or
      y < min(a.y, min(b.y, c.y)) or
      y > max(a.y, max(b.y, c.y)):
        continue
    let determinant = (b.y - c.y) * (a.x - c.x) +
      (c.x - b.x) * (a.y - c.y)
    if abs(determinant) < 0.000001:
      continue
    let
      u = ((b.y - c.y) * (x - c.x) +
        (c.x - b.x) * (y - c.y)) / determinant
      v = ((c.y - a.y) * (x - c.x) +
        (a.x - c.x) * (y - c.y)) / determinant
      w = 1 - u - v
    if u >= -0.001 and v >= -0.001 and w >= -0.001:
      result = max(result, a.z * u + b.z * v + c.z * w)

proc facePoint(shell: Draft, x, y, offset: float32): Vec3 =
  ## Projects a facial detail onto the modeled skull.
  let height = 2.35'f + (y - 2.35'f) * 1.10'f
  vec3(x, height, shell.headFront(x, height) + offset)

proc eyePatch(parent: Node, shell: Draft, name: string,
    side, size, offset: float32,
    surface: Material) =
  ## Fits the slanted eye artwork onto the cheek and orbital plane.
  let mesh = parent.part(name, surface)
  for i in 0 ..< 12:
    for j in 0 ..< 12:
      let
        corners = [
          vec2(i.float32 / 12, j.float32 / 12),
          vec2((i + 1).float32 / 12, j.float32 / 12),
          vec2((i + 1).float32 / 12, (j + 1).float32 / 12),
          vec2(i.float32 / 12, (j + 1).float32 / 12)]
        indices = if side > 0: [0, 2, 1, 0, 3, 2] else: [0, 1, 2, 0, 2, 3]
      for index in indices:
        let
          uv = corners[index]
          point = shell.facePoint(
            side * (0.55'f + (uv.x - 0.5'f) * 0.60'f * size),
            3.14'f + (0.18'f - uv.y * 0.46'f) * size,
            offset
          )
        mesh.points.add point
        mesh.normals.add vec3(0, 0, 1)
        mesh.uvs.add uv
  for i in countup(0, mesh.points.len - 3, 3):
    let normal = normalize(cross(mesh.points[i + 1] - mesh.points[i],
      mesh.points[i + 2] - mesh.points[i]))
    for j in 0 ..< 3:
      mesh.normals[i + j] = normal

proc generateKaiju*(settings: KaijuSettings,
    materials: KaijuMaterials): Node =
  ## Assembles the kaiju from authored profiles and replaceable feature groups.
  settings.validate()
  result = node("Kaiju")
  let
    body = node("Body")
    head = node("Head_Classic")
    dorsal = node("Spikes_Dorsal")
    eyes = node("Eyes_Fierce")
    tail = node("Tail")
    ink = material("Face ink", vec3(0.035, 0.045, 0.035), true)
    white = material("Eye glints", vec3(1), true)
    skin = materials[Skin]
    belly = materials[Belly]
    spikes = materials[Spikes]
    facets = settings.facets
    shell = profileDraft(HeadProfile, 0.80, JawPatch, 1, 24, 2)
  white.baseColor = eyeTexture(true)
  white.alphaMode = MaskAlphaMode
  white.alphaCutoff = 0.5
  result.nodes = @[body, tail, dorsal, head]
  head.nodes.add eyes
  head.pos = HeadCenter * (1 - settings.headSize)
  head.scale = vec3(settings.headSize)
  body.loft("Torso", TorsoProfile, skin, belly, facets, 0.90, ChestPatch)
  head.finish(
    "Skull and jaw",
    shell,
    skin,
    belly,
    min(1.0'f, facets + 0.16'f)
  )
  for side in [-1.0'f, 1.0'f]:
    let suffix = if side < 0: "L" else: "R"
    body.loft(
      "Haunch_" & suffix,
      LegProfile,
      skin,
      belly,
      facets,
      0.86,
      LegPatch,
      side
    )
    body.loft(
      "Foot_" & suffix,
      FootProfile,
      skin,
      skin,
      facets,
      0.80,
      NoPatch,
      side
    )
    let arm = smoothPath([
      SweepPoint(center: vec3(side * 0.49, 2.51, 0.07), radius: vec2(0.23)),
      SweepPoint(center: vec3(side * 0.81, 2.30, 0.22),
        radius: vec2(0.29, 0.31)),
      SweepPoint(center: vec3(side * 1.00, 2.02, 0.46),
        radius: vec2(0.30, 0.31)),
      SweepPoint(center: vec3(side * 0.94, 1.90, 0.81),
        radius: vec2(0.27, 0.25)),
      SweepPoint(center: vec3(side * 0.73, 1.91, 1.14),
        radius: vec2(0.25, 0.22)),
      SweepPoint(center: vec3(side * 0.65, 1.87, 1.32), radius: vec2(0.06)),
      SweepPoint(center: vec3(side * 0.65, 1.87, 1.35), radius: vec2(0))])
    body.sweep("Bent arm_" & suffix, arm, skin, skin, facets)
    for i in 0 ..< 3:
      let
        shift = (i.float32 - 1) * 0.30'f
        size = if i == 1: 0.24'f else: 0.21'f
        foot = vec3(side * 1.07 + shift, 0.17, 0.88 - abs(shift) * 0.18)
        hand = vec3(side * 0.72 + shift * 0.68,
          1.89 + shift * side * 0.30, 1.29 - abs(shift) * 0.30)
      body.sweep(
        "Toe pad_" & suffix & $i,
        [SweepPoint(center: foot - vec3(0, 0, 0.18),
            radius: vec2(size * 0.65, size * 0.68)),
          SweepPoint(center: foot + vec3(0, 0.01, -0.08),
            radius: vec2(size * 0.71, size * 0.73)),
          SweepPoint(center: foot - vec3(0, 0, 0.015),
            radius: vec2(size * 0.52))],
        skin, skin, facets, 12
      )
      body.sweep(
        "Finger pad_" & suffix & $i,
        [SweepPoint(center: hand - vec3(0, -0.03, 0.19),
            radius: vec2(size * 0.54)),
          SweepPoint(center: hand - vec3(0, 0, 0.08),
            radius: vec2(size * 0.62)),
          SweepPoint(center: hand + vec3(0, -0.025, -0.025),
            radius: vec2(size * 0.46))],
        skin, skin, facets, 12
      )
      body.talon(
        "Toe_" & suffix & $i,
        foot,
        size,
        shift * 0.65,
        0.63,
        materials[Claws],
        spikes
      )
      body.talon(
        "Finger_" & suffix & $i,
        hand,
        size * 0.78,
        shift * 0.35,
        1.25,
        materials[Claws],
        spikes
      )
  var stations = @[
    SweepPoint(center: vec3(0, 1.08, -0.45), radius: vec2(0.60, 0.47)),
    SweepPoint(center: vec3(0, 0.93, -1.17), radius: vec2(0.59, 0.52)),
    SweepPoint(center: vec3(0, 0.96, -1.81), radius: vec2(0.51, 0.46)),
    SweepPoint(center: vec3(0, 1.10, -2.36), radius: vec2(0.43, 0.40)),
    SweepPoint(center: vec3(0, 1.48, -2.74), radius: vec2(0.34, 0.34)),
    SweepPoint(center: vec3(0, 1.99, -2.84), radius: vec2(0.25, 0.25)),
    SweepPoint(center: vec3(0, 2.36, -2.74), radius: vec2(0.15, 0.16)),
    SweepPoint(center: vec3(0, 2.60, -2.55), radius: vec2(0))]
  for point in stations.mitems:
    point.center.z = -0.45 + (point.center.z + 0.45) * settings.tailLength
  let tailPoints = smoothPath(stations, 4)
  tail.sweep("Tail curve", tailPoints, skin, belly, facets, 24, true)
  for i in 0 ..< 7:
    let
      index = 3 + i * 3
      point = tailPoints[index]
      tangent = normalize(
        tailPoints[index + 1].center - tailPoints[index - 1].center
      )
      up = normalize(cross(tangent, vec3(-1, 0, 0)))
      base = point.center + up * (point.radius.y * 0.86'f)
      height = (0.57'f - i.float32 * 0.035'f) * settings.spikeSize
    tail.horn(
      "Tail plate " & $i,
      base,
      base + up * height + tangent * 0.11'f,
      0.25'f - i.float32 * 0.018'f,
      0.20'f - i.float32 * 0.016'f,
      spikes
    )
  dorsal.sweep(
    "Embedded dorsal ridge",
    smoothPath([
      SweepPoint(center: vec3(0, 3.08, -0.36), radius: vec2(0.13)),
      SweepPoint(center: vec3(0, 2.62, -0.42), radius: vec2(0.20, 0.22)),
      SweepPoint(center: vec3(0, 2.12, -0.61), radius: vec2(0.20, 0.24)),
      SweepPoint(center: vec3(0, 1.67, -0.88), radius: vec2(0.19, 0.22)),
      SweepPoint(center: vec3(0, 1.34, -1.19), radius: vec2(0.13))
    ]),
    spikes,
    spikes,
    0.32,
    12
  )
  const BackPlates = [
    (vec3(0, 2.92, -0.36), vec3(0, 3.27, -1.18), 0.36'f, 0.25'f),
    (vec3(0, 2.53, -0.48), vec3(0, 2.79, -1.50), 0.40'f, 0.27'f),
    (vec3(0, 2.12, -0.68), vec3(0, 2.42, -1.72), 0.40'f, 0.27'f),
    (vec3(0, 1.71, -0.85), vec3(0, 2.01, -1.85), 0.35'f, 0.24'f),
    (vec3(0, 1.37, -1.10), vec3(0, 1.76, -2.09), 0.28'f, 0.21'f)
  ]
  for i, plate in BackPlates:
    dorsal.horn(
      "Back plate " & $i,
      plate[0],
      plate[0] + (plate[1] - plate[0]) * settings.spikeSize,
      plate[2],
      plate[3],
      spikes
    )
  for i in 0 ..< 3:
    let
      t = i.float32 / 2
      base = vec3(0, 3.52 - t * 0.28, 0.39 - t * 0.75)
    head.horn(
      "Crown horn " & $i,
      base,
      base + vec3(0, 0.65 - 0.09 * t, -0.20 - 0.40 * t) * settings.spikeSize,
      0.24 + 0.04 * t,
      0.23,
      spikes
    )
  for side in [-1.0'f, 1.0'f]:
    for i in 0 ..< 4:
      let
        angle = side * (0.50'f + i.float32 * 0.45'f)
        direction = vec3(sin(angle), cos(angle), 0)
        base = vec3(0, 2.84, -0.22) + direction * 0.65'f
        height = 0.65'f - i.float32 * 0.065'f
      head.horn(
        "Crown fan " & $side & " " & $i,
        base,
        base + (direction * height + vec3(0, 0, -0.25)) * settings.spikeSize,
        0.28,
        0.22,
        spikes,
        vec3(0, 0, 1)
      )
    let suffix = if side < 0: "L" else: "R"
    eyes.eyePatch(
      shell,
      "Iris_" & suffix,
      side,
      settings.eyeSize * 0.72,
      0.012,
      materials[Iris]
    )
    eyes.eyePatch(
      shell,
      "Glint_" & suffix,
      side,
      settings.eyeSize * 0.72,
      0.016,
      white
    )
    let nostril = head.part("Nostril_" & suffix, ink)
    nostril.face(
      shell.facePoint(side * 0.19 - 0.035, 2.905, 0.012),
      shell.facePoint(side * 0.19 + 0.035, 2.905, 0.012),
      shell.facePoint(side * 0.19 + side * 0.009, 2.965, 0.012)
    )
  let smile = head.part("Smile", ink)
  for i in 0 ..< 40:
    if i in 15 .. 24 or i < 6 or i > 33:
      continue
    let
      x0 = -0.72'f + i.float32 * 0.036'f
      x1 = x0 + 0.036'f
      y0 = mouthHeight(x0)
      y1 = mouthHeight(x1)
      width0 = 0.016'f + sin(abs(x0) / 0.72'f * PI.float32) * 0.010'f
      width1 = 0.016'f + sin(abs(x1) / 0.72'f * PI.float32) * 0.010'f
      a = shell.facePoint(x0, y0 - width0, 0.018)
      b = shell.facePoint(x1, y1 - width1, 0.018)
      c = shell.facePoint(x1, y1 + 0.005, 0.018)
      d = shell.facePoint(x0, y0 + 0.005, 0.018)
    smile.face(a, b, c)
    smile.face(a, c, d)
  result.updateTransforms()

proc generateKaiju*(settings: KaijuSettings): Node =
  ## Creates a self-contained kaiju with its own editable materials.
  generateKaiju(settings, kaijuMaterials(settings))

proc saveKaiju*(settings: KaijuSettings, path: string) =
  ## Saves a validated recipe, translating filesystem errors at the boundary.
  settings.validate()
  try:
    createDir(path.parentDir)
    writeFile(path, settings.toJson())
  except IOError, OSError:
    raise newException(KaijugenError, "Cannot save kaiju: " &
      getCurrentExceptionMsg())

proc newHook(settings: var KaijuSettings) =
  ## Supplies the classic defaults for fields missing in older recipes.
  settings = classicKaiju()

proc loadKaiju*(path: string): KaijuSettings =
  ## Loads a recipe and rejects malformed or out-of-range settings.
  try:
    result = readFile(path).fromJson(KaijuSettings)
  except IOError, OSError, JsonError, ValueError:
    raise newException(KaijugenError, "Cannot load kaiju: " &
      getCurrentExceptionMsg())
  result.validate()

proc exportKaiju*(settings: KaijuSettings, path: string) =
  ## Exports the modular mesh and its solid materials as a portable GLB.
  let root = generateKaiju(settings)
  try:
    createDir(path.parentDir)
    root.writeGLB(path)
  except IOError, OSError, GltfError, ValueError:
    raise newException(KaijugenError, "Cannot export kaiju: " &
      getCurrentExceptionMsg())
