## Grounded scenery for the dungeon cutaway and its shadow passes.

import
  std/math,
  chroma, gltf, pixie, vmath,
  polyworld/[assets, groves, pathing, quadterrain, shapes, treegen],
  content, maps

const
  Oak = vec3(0.33, 0.19, 0.10)
  OakEdge = vec3(0.54, 0.32, 0.15)
  Iron = vec3(0.29, 0.32, 0.40)
  Steel = vec3(0.73, 0.78, 0.85)
  Brass = vec3(0.94, 0.70, 0.26)
  Crimson = vec3(0.63, 0.12, 0.20)
  Parchment = vec3(0.88, 0.73, 0.48)
  Ivory = vec3(0.88, 0.84, 0.72)
  Marble = vec3(0.77, 0.81, 0.86)
  Amethyst = vec3(0.67, 0.36, 0.98)
  Turquoise = vec3(0.26, 0.89, 0.88)
  BookColors = [Crimson, vec3(0.17, 0.49, 0.43), vec3(0.25, 0.28, 0.56),
    vec3(0.70, 0.43, 0.19), vec3(0.47, 0.23, 0.43)]
  Tau = 2 * PI.float32

type
  SceneryInstance = object
    pack: PropPack
    name: string
    position: Vec3
    yaw, scale: float32
    tile: TileRef
    castsShadow: bool
    torch: bool
  DungeonArt* = seq[SceneryInstance]

proc triangle(mesh: Primitive, a, b, c, tint: Vec3) =
  let normal = normalize(cross(b - a, c - a))
  for point in [a, b, c]:
    mesh.indices32.add mesh.points.len.uint32
    mesh.points.add point
    mesh.normals.add normal
    mesh.colors.add rgbx(uint8(tint.x * 255), uint8(tint.y * 255),
      uint8(tint.z * 255), 255)

proc quad(mesh: Primitive, a, b, c, d, tint: Vec3) =
  mesh.triangle(a, b, c, tint)
  mesh.triangle(a, c, d, tint)

proc box(mesh: Primitive, x, y, z, width, height, depth: float32,
    tint: Vec3, roll = 0'f32) =
  let
    a = width / 2
    b = height / 2
    c = depth / 2
    center = vec3(x, y + b, z)
    rotation = rotateZ(roll)
    corners = [vec3(-a,-b,-c), vec3(a,-b,-c), vec3(a,b,-c), vec3(-a,b,-c),
      vec3(-a,-b,c), vec3(a,-b,c), vec3(a,b,c), vec3(-a,b,c)]
  for face in [[0,3,2,1], [4,5,6,7], [0,4,7,3], [1,2,6,5],
      [3,7,6,2], [0,1,5,4]]:
    mesh.quad(center + rotation * corners[face[0]],
      center + rotation * corners[face[1]],
      center + rotation * corners[face[2]],
      center + rotation * corners[face[3]], tint)

proc polygon(mesh: Primitive, center, axisU, axisV: Vec3,
    outer, inner: float32, sides: int, tint: Vec3, turn = 0'f32) =
  for side in 0 ..< sides:
    let
      a = turn + Tau * side.float32 / sides.float32
      b = turn + Tau * (side + 1).float32 / sides.float32
      u = axisU * cos(a) + axisV * sin(a)
      v = axisU * cos(b) + axisV * sin(b)
    if inner == 0:
      mesh.triangle(center, center + u * outer, center + v * outer, tint)
    else:
      mesh.quad(center + u * inner, center + u * outer,
        center + v * outer, center + v * inner, tint)

proc gem(mesh: Primitive, x, y, z, radius: float32, tint: Vec3) =
  let middle = vec3(x, y + radius * 0.65, z)
  for i in 0 ..< 6:
    let
      a = Tau * i.float32 / 6
      b = Tau * (i + 1).float32 / 6
      u = middle + vec3(radius * cos(a), 0, radius * sin(a))
      v = middle + vec3(radius * cos(b), 0, radius * sin(b))
      shade = tint * (0.68 + 0.08 * (i mod 5).float32)
    mesh.triangle(u, middle + vec3(0, radius * 1.22, 0), v, shade)
    mesh.triangle(u, v, vec3(x, y, z), shade * 0.76)

proc book(mesh: Primitive, x, y, z, w, h, d: float32, tint: Vec3) =
  mesh.box(x, y, z, w, h, d, tint)
  mesh.box(x, y + h * 0.14, z + d * 0.49, w * 0.77, h * 0.72,
    0.014, Parchment)
  mesh.box(x - w * 0.33, y + h * 0.78, z + d * 0.50, w * 0.13,
    h * 0.07, 0.018, Brass)

proc rack(mesh: Primitive, height: float32, tint: Vec3) =
  for x in [-0.36'f32, 0.36]:
    mesh.box(x, 0, -0.09, 0.09, height, 0.35, tint)
    mesh.box(x, height - 0.09, -0.09, 0.12, 0.10, 0.39, OakEdge)
  mesh.box(0, 0.12, -0.04, 0.81, 0.10, 0.36, tint)
  mesh.box(0, height - 0.26, -0.20, 0.81, 0.11, 0.13, tint)

proc sword(mesh: Primitive, x, y, z, roll: float32) =
  let rotation = rotateZ(roll)
  let center = vec3(x, y + 0.26, z)
  mesh.box(x, y + 0.08, z, 0.09, 0.36, 0.045, Steel, roll)
  mesh.triangle(center + rotation * vec3(-0.045, 0.18, 0.022),
    center + rotation * vec3(0.045, 0.18, 0.022),
    center + rotation * vec3(0, 0.29, 0.022), Steel)
  mesh.box(x, y + 0.08, z + 0.008, 0.19, 0.055, 0.08, Brass, roll)
  mesh.box(x, y - 0.08, z, 0.055, 0.16, 0.06, OakEdge, roll)

proc bust(mesh: Primitive, y: float32, tint, accent: Vec3) =
  mesh.box(0, y, 0, 0.46, 0.44, 0.27, tint)
  for side in [-1'f32, 1]:
    mesh.box(side * 0.27, y + 0.29, 0, 0.20, 0.14, 0.33,
      accent, side * 0.22)
  mesh.box(0, y + 0.42, 0, 0.25, 0.25, 0.24, accent)
  mesh.box(0, y + 0.50, 0.129, 0.18, 0.041, 0.027, tint * 0.43)

proc segment(mesh: Primitive, a, b: Vec3, width: float32, tint: Vec3) =
  ## A thin strip on the floor.
  let side = normalize(cross(vec3(0, 1, 0), b - a)) * (width * 0.5)
  mesh.quad(a - side, b - side, b + side, a + side, tint)

proc rounded(mesh: Primitive, center, size, tint: Vec3) =
  ## Low-poly ellipsoid with closed poles and gently graded facets.
  const Bands = 6
  const Sides = 12
  proc point(row, side: int): Vec3 =
    let
      lat = PI.float32 * row.float32 / Bands.float32
      angle = Tau * side.float32 / Sides.float32
    center + vec3(size.x * sin(lat) * cos(angle),
      size.y * cos(lat), size.z * sin(lat) * sin(angle))
  for row in 0 ..< Bands:
    for side in 0 ..< Sides:
      let
        a = point(row, side)
        b = point(row + 1, side)
        c = point(row + 1, side + 1)
        d = point(row, side + 1)
        shade = tint * (0.86 + 0.12 * (Bands - row).float32 / Bands.float32)
      if row > 0:
        mesh.triangle(a, d, b, shade)
      if row < Bands - 1:
        mesh.triangle(d, c, b, shade)

proc ringArc(mesh: Primitive, x, y, z, radius, width: float32,
    tint: Vec3, segments: int, heightScale = 1'f32) =
  ## Beveled-looking masonry wedges or iron links in the vertical plane.
  for i in 0 ..< segments:
    let
      a = PI.float32 * i.float32 / segments.float32
      b = PI.float32 * (i + 1).float32 / segments.float32
      u = vec3(cos(a), sin(a) * heightScale, 0)
      v = vec3(cos(b), sin(b) * heightScale, 0)
      center = vec3(x, y, z)
      p = center + u * radius
      q = center + v * radius
      r = center + v * (radius + width)
      t = center + u * (radius + width)
      back = vec3(0, 0, -0.17)
      shade = tint * (0.86 + 0.06 * (i mod 3).float32)
    mesh.quad(p, t, r, q, shade)
    mesh.quad(p + back, q + back, r + back, t + back, shade)
    mesh.quad(q, p, p + back, q + back, shade * 0.80)
    mesh.quad(t, r, r + back, t + back, shade * 0.95)
    if i == 0:
      mesh.quad(p, t, t + back, p + back, shade * 0.72)
    if i == segments - 1:
      mesh.quad(q, q + back, r + back, r, shade * 0.72)

proc skull(mesh: Primitive, x, y, z, size: float32) =
  let
    bone = Ivory
    shadow = vec3(0.16, 0.12, 0.10)
  mesh.rounded(vec3(x, y + size * 0.55, z),
    vec3(size * 0.53, size * 0.56, size * 0.50), bone)
  mesh.rounded(vec3(x, y + size * 0.25, z + size * 0.26),
    vec3(size * 0.39, size * 0.25, size * 0.26), bone)
  for side in [-1'f32, 1]:
    mesh.rounded(vec3(x + side * size * 0.20, y + size * 0.49,
      z + size * 0.44), vec3(size * 0.15, size * 0.14, size * 0.07), shadow)
  mesh.triangle(vec3(x, y + size * 0.38, z + size * 0.519),
    vec3(x - size * 0.058, y + size * 0.24, z + size * 0.526),
    vec3(x + size * 0.058, y + size * 0.24, z + size * 0.526), shadow)
  for i in -2 .. 2:
    mesh.box(x + i.float32 * size * 0.105, y + size * 0.09,
      z + size * 0.49, size * 0.088, size * 0.115, size * 0.084, bone)

type ProfileRing = tuple[y, xRadius, zRadius, zOffset: float32]

const
  ChapelStone = vec3(0.86, 0.77, 0.66)
  ChapelIvory = vec3(0.97, 0.89, 0.78)
  ChapelGold = vec3(0.92, 0.65, 0.21)

proc loft(mesh: Primitive, base: Vec3, profile: openArray[ProfileRing],
    sides: int, tint: Vec3, pleated = false) =
  ## Rings create continuous carved profiles and faceted stone shafts.
  proc point(ring: ProfileRing, side: int): Vec3 =
    let
      angle = (side.float32 + 0.5) * Tau / sides.float32
      fold = if pleated and side mod 2 == 1: 0.88'f32 else: 1'f32
    base + vec3(cos(angle) * ring.xRadius * fold, ring.y,
      ring.zOffset + sin(angle) * ring.zRadius * fold)
  for row in 0 ..< profile.high:
    for side in 0 ..< sides:
      let
        a = point(profile[row], side)
        b = point(profile[row + 1], side)
        c = point(profile[row + 1], side + 1)
        d = point(profile[row], side + 1)
      mesh.quad(a, b, c, d, tint)
  for side in 0 ..< sides:
    let
      bottom = profile[0]
      top = profile[^1]
    if bottom.xRadius > 0 and bottom.zRadius > 0:
      mesh.triangle(base + vec3(0, bottom.y, bottom.zOffset),
        point(bottom, side), point(bottom, side + 1), tint)
    if top.xRadius > 0 and top.zRadius > 0:
      mesh.triangle(base + vec3(0, top.y, top.zOffset),
        point(top, side + 1), point(top, side), tint)

proc molding(mesh: Primitive, center: Vec3, path: openArray[Vec2],
    width: float32, tint: Vec3) =
  ## Raised ribbon of stone on a front face, with a bright beveled edge.
  for i in 0 ..< path.high:
    let
      a = path[i]
      b = path[i + 1]
      direction = normalize(b - a)
      side = vec3(-direction.y, direction.x, 0) * width * 0.5
      first = center + vec3(a.x, a.y, 0)
      last = center + vec3(b.x, b.y, 0)
      bevel = vec3(0, 0, width * 0.31)
    mesh.quad(first - side, last - side, last + bevel, first + bevel, tint * 0.73)
    mesh.quad(first + bevel, last + bevel, last + side, first + side, tint)

proc jewel(mesh: Primitive, center: Vec3, radius: float32) =
  let
    right = vec3(1, 0, 0)
    up = vec3(0, 1, 0)
    front = vec3(0, 0, 1)
    crown = center + front * (radius * 0.40)
    tint = [vec3(0.16, 0.84, 0.91), vec3(0.09, 0.59, 0.72),
      vec3(0.07, 0.34, 0.51), vec3(0.16, 0.68, 0.75)]
    corners = [right * radius, up * radius, -right * radius, -up * radius]
  mesh.polygon(center, right, up, radius * 1.26, 0, 4, ChapelGold)
  for i in 0 ..< 4:
    mesh.triangle(center + corners[i] + front * 0.006,
      center + corners[(i + 1) mod 4] + front * 0.006, crown, tint[i])

proc pointedOpening(mesh: Primitive, x, z, bottom, spring, halfWidth,
    rise, thickness: float32, tint: Vec3) =
  ## Two curved halves meet at the peak of the Gothic opening.
  for side in [-1'f32, 1]:
    mesh.box(x + side * (halfWidth + thickness * 0.5), bottom, z - 0.08,
      thickness, spring - bottom, 0.16, tint)
    var points: seq[Vec2]
    for i in 0 .. 9:
      let t = i.float32 / 9
      points.add vec2(side * (halfWidth + thickness * 0.5) * (1 - t * t),
        spring + rise * t)
    if side < 0:
      for i in countdown(points.high, 1):
        mesh.molding(vec3(x, 0, z), [points[i], points[i - 1]], thickness, tint)
    else:
      mesh.molding(vec3(x, 0, z), points, thickness, tint)

proc cup(mesh: Primitive, center: Vec3, scale: float32) =
  const Rim = 0.105'f32
  let gold = ChapelGold
  mesh.loft(center, [
    (0'f32, 0.076'f32 * scale, 0.076'f32 * scale, 0'f32),
    (0.021'f32 * scale, 0.076'f32 * scale, 0.076'f32 * scale, 0'f32),
    (0.048'f32 * scale, 0.025'f32 * scale, 0.025'f32 * scale, 0'f32),
    (0.106'f32 * scale, 0.027'f32 * scale, 0.027'f32 * scale, 0'f32),
    (0.125'f32 * scale, 0.064'f32 * scale, 0.064'f32 * scale, 0'f32),
    (0.177'f32 * scale, 0.089'f32 * scale, 0.089'f32 * scale, 0'f32),
    (0.202'f32 * scale, Rim * scale, Rim * scale, 0'f32)],
    12, gold)
  mesh.polygon(center + vec3(0, 0.203 * scale, 0),
    vec3(1, 0, 0), vec3(0, 0, -1), 0.084 * scale, 0, 12, gold * 0.40,
    Tau / 24)

proc chapelColumn(mesh: Primitive) =
  let
    stone = ChapelStone
    ivory = ChapelIvory
    origin = vec3(0)
  mesh.box(0, 0, 0, 0.73, 0.105, 0.73, stone)
  mesh.box(0, 0.104, 0, 0.70, 0.032, 0.70, ChapelGold)
  mesh.box(0, 0.136, 0, 0.62, 0.28, 0.62, stone)
  mesh.box(0, 0.408, 0, 0.68, 0.065, 0.68, ivory)
  mesh.loft(origin, [(0.473'f32, 0.344'f32, 0.344'f32, 0'f32),
    (0.55'f32, 0.29'f32, 0.29'f32, 0'f32)], 8, ChapelGold)
  mesh.loft(origin, [(0.55'f32, 0.278'f32, 0.278'f32, 0'f32),
    (0.60'f32, 0.235'f32, 0.235'f32, 0'f32),
    (1.87'f32, 0.212'f32, 0.212'f32, 0'f32),
    (1.92'f32, 0.256'f32, 0.256'f32, 0'f32)], 8, ivory)
  mesh.loft(origin, [(1.92'f32, 0.275'f32, 0.275'f32, 0'f32),
    (2.00'f32, 0.325'f32, 0.325'f32, 0'f32)], 8, ChapelGold)
  mesh.box(0, 2.0, 0, 0.57, 0.072, 0.57, stone)
  mesh.box(0, 2.072, 0, 0.68, 0.13, 0.68, ivory)
  for turn in 0 ..< 4:
    let first = mesh.points.len
    mesh.jewel(vec3(0, 0.28, 0.313), 0.091)
    let rotation = rotateY(turn.float32 * Tau / 4)
    for i in first ..< mesh.points.len:
      mesh.points[i] = rotation * mesh.points[i]
      mesh.normals[i] = rotation * mesh.normals[i]

proc chapelRunner(mesh, fabric: Primitive, design: int32) =
  let
    right = vec3(1, 0, 0)
    north = vec3(0, 0, -1)
    gold = vec3(0.91, 0.58, 0.20)
    cloth = vec3(0.59, 0.105, 0.145)
    capStart = (design and 4) != 0
    capEnd = (design and 8) != 0
    start = if capStart: -0.42'f32 else: -0.5'f32
    finish = if capEnd: 0.42'f32 else: 0.5'f32
    depth = finish - start
    z = (start + finish) * 0.5
  fabric.box(0, 0.008, z, 1.68, 0.015, depth, vec3(1))
  for point in fabric.points:
    fabric.uvs.add vec2((point.x + 0.84) / 1.68, point.z + 0.5)
  # The thin edge and embroidery keep their own thread colors.
  for side in [-1'f32, 1]:
    mesh.box(side * 0.836, 0.008, z, 0.008, 0.013, depth, cloth)
  for side in [-1'f32, 1]:
    mesh.box(side * 0.793, 0.023, z, 0.088, 0.005, depth, gold)
    mesh.box(side * 0.694, 0.023, z, 0.022, 0.005, depth, gold)
  if capStart:
    mesh.box(0, 0.023, start + 0.038, 1.59, 0.005, 0.076, gold)
    mesh.box(0, 0.023, start + 0.106, 1.38, 0.005, 0.019, gold)
  if capEnd:
    mesh.box(0, 0.023, finish - 0.038, 1.59, 0.005, 0.076, gold)
    mesh.box(0, 0.023, finish - 0.106, 1.38, 0.005, 0.019, gold)
  let y = 0.032'f32
  case design and 3
  of 1:
    # Four pointed leaves radiate from the center of the gold stem.
    for i in 0 ..< 4:
      let
        rotation = rotateY(i.float32 * Tau / 4)
        points = [vec3(0), vec3(0.096, 0, 0.134), vec3(0, 0, 0.343),
          vec3(-0.096, 0, 0.134), vec3(0)]
      for j in 0 ..< 4:
        mesh.segment(vec3(0, y, 0) + rotation * points[j],
          vec3(0, y, 0) + rotation * points[j + 1], 0.022, gold)
    for side in [-1'f32, 1]:
      mesh.segment(vec3(0, y, side * 0.343),
        vec3(0, y, if side < 0: start else: finish), 0.022, gold)
  of 2:
    mesh.segment(vec3(0, y, start), vec3(0, y, -0.098), 0.022, gold)
    mesh.polygon(vec3(0, y, 0), right, north, 0.109, 0.068, 4, gold)
    mesh.segment(vec3(0, y, 0.098), vec3(0, y, finish), 0.022, gold)
  else:
    mesh.segment(vec3(0, y, start), vec3(0, y, finish), 0.022, gold)

proc chapelAltar(mesh: Primitive, span: int32) =
  let
    first = mesh.points.len
    ivory = ChapelIvory
    stone = ChapelStone
    gold = ChapelGold
  # Low dais, two steps, recessed frontal and a heavy molded tabletop.
  mesh.box(0, 0.012, 0.30, 2.94, 0.105, 1.71, stone)
  mesh.box(0, 0.117, 0.21, 2.78, 0.040, 1.51, ivory)
  mesh.box(0, 0.157, 0.12, 2.64, 0.124, 1.27, stone)
  mesh.box(0, 0.278, 0.05, 2.35, 0.085, 0.99, ivory)
  mesh.box(0, 0.282, 0.631, 1.30, 0.019, 0.28, gold)
  mesh.box(0, 0.301, 0.631, 1.20, 0.007, 0.20, Crimson)
  mesh.polygon(vec3(0, 0.311, 0.631), vec3(1, 0, 0), vec3(0, 0, -1),
    0.091, 0.063, 4, gold)
  mesh.box(0, 0.355, -0.01, 2.21, 0.67, 0.84, stone)
  mesh.box(0, 0.397, 0.414, 1.96, 0.54, 0.049, stone * 0.86)
  for x in [-1.01'f32, 1.01]:
    mesh.box(x, 0.36, 0.414, 0.09, 0.64, 0.096, ivory)
  for y in [0.382'f32, 0.936]:
    mesh.box(0, y, 0.444, 2.03, 0.052, 0.063, ivory)
  mesh.box(0, 1.009, 0.006, 2.32, 0.062, 0.97, ivory)
  mesh.box(0, 1.071, 0.006, 2.43, 0.112, 1.05, ivory)
  mesh.box(0, 1.033, 0.498, 2.31, 0.027, 0.032, stone)

  # Mirrored acanthus scrolls curl outward from the turquoise medallion.
  for side in [-1'f32, 1]:
    for row in [-1'f32, 1]:
      var path: seq[Vec2]
      for i in 0 .. 26:
        let
          t = i.float32 / 26
          angle = (0.30 + 1.29 * t) * Tau
          radius = 0.255 * (1 - t) + 0.027
        path.add vec2(side * (0.67 + cos(angle) * radius),
          row * (0.10 + sin(angle) * radius * 0.59))
      path.insert(vec2(side * 0.23, row * 0.015), 0)
      mesh.molding(vec3(0, 0.666, 0.447), path, 0.039, ivory)
      mesh.molding(vec3(0, 0.666, 0.448), [
        vec2(side * 0.26, row * 0.047), vec2(side * 0.39, row * 0.142),
        vec2(side * 0.55, row * 0.180), vec2(side * 0.81, row * 0.187)],
        0.029, ivory)
  mesh.jewel(vec3(0, 0.673, 0.48), 0.198)
  if span > 1:
    # Pointed reredos and gilded shrine emblem above the tabletop.
    mesh.box(0, 0.22, -0.49, 2.20, 1.34, 0.045, stone)
    mesh.pointedOpening(0, -0.414, 0.23, 1.47, 0.96, 0.65, 0.15, ivory)
    mesh.pointedOpening(0, -0.376, 0.27, 1.45, 0.75, 0.49, 0.044, gold)
    mesh.molding(vec3(0, 0, -0.351), [
      vec2(0, 1.21), vec2(0, 1.63), vec2(0, 1.99)], 0.053, gold)
    mesh.molding(vec3(0, 0, -0.351), [
      vec2(-0.39, 1.61), vec2(0, 1.68), vec2(0.39, 1.61)], 0.046, gold)
    mesh.jewel(vec3(0, 1.78, -0.337), 0.124)
    for x in [-0.87'f32, 0.87]:
      mesh.jewel(vec3(x, 1.34, -0.326), 0.075)
  # Gilded top cloth and two molded candle holders.
  mesh.box(0, 1.181, 0.06, 0.89, 0.018, 0.63, gold)
  mesh.box(0, 1.2, 0.06, 0.79, 0.007, 0.53, vec3(0.91, 0.73, 0.48))
  for x in [-0.85'f32, 0.85]:
    mesh.cup(vec3(x, 1.181, 0.16), 0.88)
    mesh.box(x, 1.352, 0.16, 0.089, 0.25, 0.092, ivory)
    mesh.gem(x, 1.596, 0.16, 0.047, gold)

  if span == 1:
    # Compact altar keeps the same carving on narrow end walls.
    for i in first ..< mesh.points.len:
      let point = mesh.points[i]
      mesh.points[i] = vec3(point.x * 0.33, point.y, point.z)
      let normal = mesh.normals[i]
      mesh.normals[i] = normalize(vec3(normal.x / 0.33, normal.y, normal.z))

proc chapelStatue(mesh: Primitive, pose: int32) =
  let
    ivory = ChapelIvory
    stone = ChapelStone
    gold = ChapelGold
    right = vec3(1, 0, 0)
    up = vec3(0, 1, 0)
    base = vec3(0)
  mesh.box(0, 0, 0, 0.70, 0.09, 0.66, stone)
  mesh.box(0, 0.09, 0, 0.66, 0.03, 0.62, gold)
  mesh.box(0, 0.12, 0, 0.56, 0.25, 0.53, stone)
  mesh.box(0, 0.37, 0, 0.67, 0.082, 0.60, ivory)
  mesh.jewel(vec3(0, 0.246, 0.27), 0.084)
  for x in [-0.09'f32, 0.09]:
    mesh.rounded(vec3(x, 0.485, 0.109), vec3(0.075, 0.04, 0.121), stone)
  mesh.loft(base, [(0.49'f32, 0.245'f32, 0.172'f32, 0'f32),
    (0.69'f32, 0.221'f32, 0.152'f32, -0.018'f32),
    (0.96'f32, 0.169'f32, 0.118'f32, -0.020'f32),
    (1.25'f32, 0.154'f32, 0.127'f32, -0.020'f32),
    (1.48'f32, 0.213'f32, 0.142'f32, -0.022'f32),
    (1.57'f32, 0.108'f32, 0.10'f32, -0.031'f32)],
    16, ivory, pleated = true)

  # Separate cloak edges, a shadowed hood, face and folded sleeves.
  for side in [-1'f32, 1]:
    mesh.molding(vec3(0, 0, 0.143), [vec2(side * 0.055, 0.51),
      vec2(side * 0.145, 0.67), vec2(side * 0.096, 0.95),
      vec2(side * 0.108, 1.18), vec2(side * 0.154, 1.46)],
      0.018, gold * 0.83)
    mesh.rounded(vec3(side * 0.164, 1.385, 0.071),
      vec3(0.096, 0.157, 0.108), stone)
    mesh.rounded(vec3(side * 0.105, 1.301, 0.167),
      vec3(0.111, 0.078, 0.086), ivory)
  mesh.loft(base, [(1.425'f32, 0.156'f32, 0.12'f32, -0.034'f32),
    (1.62'f32, 0.136'f32, 0.125'f32, -0.019'f32),
    (1.79'f32, 0.116'f32, 0.100'f32, -0.020'f32),
    (1.91'f32, 0.025'f32, 0.028'f32, -0.050'f32)],
    12, stone)
  mesh.rounded(vec3(0, 1.709, 0.096), vec3(0.102, 0.131, 0.059), stone * 0.51)
  mesh.rounded(vec3(0, 1.682, 0.133), vec3(0.067, 0.100, 0.046), ivory)
  mesh.rounded(vec3(0, 1.677, 0.174), vec3(0.020, 0.032, 0.027), ivory)
  mesh.pointedOpening(0, 0.177, 1.571, 1.740, 0.090, 0.120, 0.027, ivory)
  for side in [-1'f32, 1]:
    mesh.box(side * 0.028, 1.700, 0.174, 0.027, 0.009, 0.009, stone * 0.62)
  if pose == 0:
    for side in [-1'f32, 1]:
      mesh.rounded(vec3(side * 0.029, 1.362, 0.246),
        vec3(0.029, 0.108, 0.030), ivory)
  else:
    mesh.box(0, 1.215, 0.228, 0.216, 0.148, 0.076, stone, 0.05)
    mesh.polygon(vec3(0, 1.283, 0.27), right, up, 0.057, 0, 4, gold)
    for side in [-1'f32, 1]:
      mesh.rounded(vec3(side * 0.104, 1.297, 0.245),
        vec3(0.047, 0.047, 0.052), ivory)

const
  NicheSill = 0.56'f32
  NicheSpring = 0.976'f32
  NicheWidth = 0.216'f32
  NicheRise = 0.266'f32
  NicheDepth = 0.25'f32

proc chapelWallRecesses*(dungeon: Dungeon): seq[WallRecess] =
  for decor in dungeon.decor:
    if decor.kind != GobletNicheDecor:
      continue
    var
      x = int(decor.tile.x)
      z = int(decor.tile.z)
    case decor.facing
    of East: dec x
    of South: dec z
    of West: inc x
    of North: inc z
    result.add WallRecess(layer: int(decor.tile.level), x: x, z: z,
      facing: decor.facing.ord, base: levelBase(int(decor.tile.level)).float32 /
        HeightSteps, bottom: NicheSill, spring: NicheSpring, rise: NicheRise,
      halfWidth: NicheWidth, depth: NicheDepth)

proc gobletNiche(mesh: Primitive) =
  ## The terrain mesh supplies the back, ceiling, and sides of the recess.
  ## Only the thin trim sits in front of the wall plane at z = -0.5.
  const Face = -0.5'f32
  let
    stone = ChapelStone
    ivory = ChapelIvory
    trim = 0.047'f32
  for side in [-1'f32, 1]:
    mesh.box(side * (NicheWidth + trim * 0.5), NicheSill, Face - 0.004,
      trim, NicheSpring - NicheSill, 0.038, stone)
    var points: seq[Vec2]
    for i in 0 .. 12:
      let
        t = i.float32 / 12
        x = side * (NicheWidth + trim * 0.50) * (1 - t * t)
      points.add vec2(x, NicheSpring + (NicheRise + 0.021) * t)
    if side > 0:
      mesh.molding(vec3(0, 0, Face + 0.011), points, trim, ivory)
    else:
      for i in countdown(points.high, 1):
        mesh.molding(vec3(0, 0, Face + 0.011),
          [points[i], points[i - 1]], trim, ivory)
  mesh.box(0, NicheSill - 0.038, Face - 0.086, 0.52, 0.039, 0.24, ivory)
  mesh.cup(vec3(0, NicheSill + 0.006, Face - 0.13), 0.86)

proc wallColor(theme: RoomTheme): Vec3 =
  case theme
  of ArmoryTheme: vec3(0.39, 0.47, 0.61)
  of LibraryTheme: vec3(0.47, 0.33, 0.23)
  of DungeonTheme: vec3(0.40, 0.39, 0.38)
  of TempleTheme: vec3(0.89, 0.81, 0.69)
  of NoRoomTheme: Iron

proc decorName(kind: DecorKind, theme: RoomTheme, span: int32): string =
  case kind
  of ArchDecor: $kind & $theme & $span
  of WallTrimDecor: $kind & $theme
  of ShelvesDecor, WeaponsDecor, AltarDecor, RugDecor, StatueDecor:
    $kind & $span
  else: $kind

proc oldHallsNode(kind: DecorKind, theme = NoRoomTheme, span = 0'i32,
    cloth: Image = nil, thread: Image = nil): Node =
  let
    mesh = Primitive(mode: TrianglesMode,
      material: Material(baseColorFactor: color(1, 1, 1, 1)))
    right = vec3(1, 0, 0)
    up = vec3(0, 1, 0)
    north = vec3(0, 0, -1)
  var fabric: Primitive
  case kind
  of HeraldryDecor:
    mesh.box(0, 0, -0.19, 0.12, 1.72, 0.12, Oak)
    mesh.box(0, 1.65, -0.10, 1.29, 0.065, 0.08, Brass)
    mesh.box(0, 0.65, -0.08, 1.08, 0.99, 0.045, Crimson)
    mesh.triangle(vec3(-0.54, 0.65, -0.055), vec3(0, 0.38, -0.055),
      vec3(0.54, 0.65, -0.055), Crimson)
    for x in [-0.50'f32, 0.50]:
      mesh.box(x, 0.65, -0.051, 0.027, 0.99, 0.019, Brass)
    mesh.polygon(vec3(0, 1.18, -0.044), right, up, 0.315, 0, 5, Brass)
    mesh.polygon(vec3(0, 1.18, -0.040), right, up, 0.272, 0, 5,
      Crimson * 0.72)
    mesh.box(0, 1.02, -0.041, 0.05, 0.31, 0.014, Ivory)
    mesh.box(0, 1.10, -0.037, 0.19, 0.04, 0.014, Brass)
  of WeaponsDecor:
    mesh.rack(1.47, Oak)
    for i in -1 .. 1:
      let x = i.float32 * 0.24
      case span
      of 1:
        mesh.box(x, 0.16, 0.015, 0.040, 1.10, 0.045, OakEdge)
        mesh.triangle(vec3(x - 0.061, 1.12, 0.03),
          vec3(x + 0.061, 1.12, 0.03), vec3(x, 1.48, 0.03), Steel)
      of 2:
        mesh.box(x, 0.15, 0.02, 0.046, 1.13, 0.049, OakEdge)
        mesh.polygon(vec3(x + 0.04, 1.16, 0.061), right, up, 0.15, 0, 5,
          Steel, 0.4)
      else:
        mesh.sword(x, 0.64 + 0.05 * abs(i).float32, 0.04, -i.float32 * 0.16)
  of ArmorDecor:
    mesh.rack(1.29, Oak)
    mesh.bust(0.42, Iron, Steel)
    mesh.box(0, 0.50, 0.148, 0.37, 0.064, 0.035, Brass)
  of TargetDecor:
    for x in [-0.25'f32, 0.25]:
      mesh.box(x, 0, -0.06, 0.11, 1.1, 0.14, Oak, -x * 0.6)
    for i, tint in [OakEdge, Ivory, Crimson, Ivory, Crimson]:
      mesh.polygon(vec3(0, 0.94, i.float32 * 0.006), right, up,
        0.43 - i.float32 * 0.078, 0, 16, tint)
  of ShelvesDecor:
    let height = if span == 1: 1.20'f32 else: 1.84'f32
    for x in [-0.46'f32, 0.46]:
      mesh.box(x, 0, 0, 0.08, height, 0.52, OakEdge)
      mesh.box(x, height - 0.09, 0, 0.095, 0.10, 0.54, Oak)
    mesh.box(0, height - 0.07, 0, 1, 0.07, 0.54, OakEdge)
    mesh.box(0, 0.03, 0, 1, 0.13, 0.52, Oak)
    let rows = if span == 1: 3 else: 4
    for row in 0 ..< rows:
      let y = 0.15 + row.float32 * (height - 0.18) / rows.float32
      mesh.box(0, y, 0, 0.91, 0.052, 0.51, OakEdge)
      for column in 0 .. 6:
        let
          x = -0.369 + column.float32 * 0.122
          h = 0.17 + ((row * 3 + column) mod 5).float32 * 0.027
          tint = BookColors[(column + row * 2) mod BookColors.len]
        mesh.book(x, y + 0.054, 0.10, 0.109, h, 0.26, tint)
        if span == 1:
          mesh.book(x, y + 0.054, -0.13, 0.104, h, 0.22,
            BookColors[(column + row + 2) mod BookColors.len])
      if span == 0:
        mesh.box(0, y, -0.233, 0.91, (height - 0.18) / rows.float32,
          0.053, Oak * 0.74)
  of BooksDecor, BookMoundDecor:
    let stacks = if kind == BooksDecor: 2 else: 5
    for stack in 0 ..< stacks:
      let
        angle = stack.float32 * 2.4
        radius = if kind == BooksDecor: 0.19'f32 else: 0.36'f32
        x = cos(angle) * radius
        z = sin(angle) * radius
        height = if kind == BooksDecor: 6 + stack * 3 else: 2 + stack mod 3
      for i in 0 ..< height:
        mesh.book(x + sin(i.float32 * 1.6) * 0.065, i.float32 * 0.061,
          z + cos(i.float32 * 1.2) * 0.068, 0.46 - i.float32 * 0.012, 0.06,
          0.31, BookColors[(i + stack) mod BookColors.len])
    if kind == BookMoundDecor:
      for x in [-0.15'f32, 0.15]:
        mesh.box(x, 0.14, 0.17, 0.32, 0.047, 0.36, Parchment, x * 1.3)
        for i in 0 .. 3:
          mesh.box(x, 0.18, 0.06 + i.float32 * 0.061, 0.19,
            0.006, 0.008, OakEdge, x * 1.3)
  of CircleDecor:
    for (radius, width, tint) in [(1.18'f32, 0.016'f32, Amethyst),
        (1.11'f32, 0.016'f32, Amethyst), (0.90'f32, 0.020'f32, Turquoise),
        (0.84'f32, 0.012'f32, Turquoise), (0.44'f32, 0.016'f32, Amethyst)]:
      mesh.polygon(vec3(0, 0.024, 0), right, north, radius, radius - width, 64, tint)
    proc runePoint(radius, angle: float32): Vec3 =
      vec3(cos(angle) * radius, 0.026, sin(angle) * radius)
    for i in 0 ..< 6:
      let a = i.float32 * Tau / 6
      mesh.segment(runePoint(0.91, a), runePoint(0.91, a + Tau / 3),
        0.019, Turquoise)
    for i in 0 ..< 20:
      let
        angle = i.float32 * Tau / 20
        p = runePoint(1.00, angle)
        q = runePoint(1.065, angle - 0.025)
        r = runePoint(0.955, angle + 0.025)
      mesh.segment(q, r, 0.017, Amethyst)
      mesh.segment(p, runePoint(1.04, angle + 0.043), 0.016, Ivory)
    for i in 0 ..< 8:
      let a = i.float32 * Tau / 8
      let tip = runePoint(if i mod 2 == 0: 0.33 else: 0.23, a)
      mesh.triangle(tip, runePoint(0.087, a + 0.38),
        runePoint(0.087, a - 0.38), Turquoise)
  of BonesDecor:
    for i in 0 .. 3:
      let
        x = i.float32 * 0.15 - 0.25
        z = (i mod 2).float32 * 0.25 - 0.23
      mesh.rounded(vec3(x, 0.06, z), vec3(0.19, 0.043, 0.048), Ivory)
      for side in [-1'f32, 1]:
        mesh.rounded(vec3(x + side * 0.145, 0.06, z),
          vec3(0.061, 0.055, 0.059), Ivory)
    mesh.skull(0.18, 0.01, 0.19, 0.42)
    mesh.skull(-0.25, 0, 0.23, 0.27)
  of ShacklesDecor:
    let rust = vec3(0.46, 0.26, 0.16)
    mesh.box(0, 1.13, -0.49, 0.37, 0.49, 0.11, rust * 0.67)
    mesh.box(0, 1.48, -0.15, 0.20, 0.16, 0.88, rust)
    for (x, z, links) in [(-0.055'f32, -0.10'f32, 8),
        (0.055'f32, 0.21'f32, 11)]:
      for i in 0 ..< links:
        let y = 1.46 - i.float32 * 0.083
        if i mod 2 == 0:
          mesh.polygon(vec3(x, y, z), right, up, 0.061, 0.036, 10, rust)
        else:
          mesh.polygon(vec3(x, y, z), north, up, 0.061, 0.035, 10, rust * 0.77)
      mesh.polygon(vec3(x, 1.43 - links.float32 * 0.083, z), right, up,
        0.102, 0.071, 14, rust)
  of PrisonRackDecor:
    for x in [-0.33'f32, 0.33]:
      for side in [-1'f32, 1]:
        mesh.box(x, 0, side * 0.19, 0.11, 0.69, 0.13, OakEdge,
          -x * 0.45)
    mesh.box(0, 0.46, 0, 0.86, 0.093, 0.14, Oak)
    for i in -7 .. 7:
      mesh.polygon(vec3(i.float32 * 0.046, 0.51, 0), up, north,
        0.12, 0.087, 12, Parchment * 0.78)
    mesh.box(0.46, 0.33, 0.043, 0.069, 0.23, 0.081, Iron, 0.48)
  of AltarDecor:
    mesh.chapelAltar(span)
  of StatueDecor:
    mesh.chapelStatue(span)
  of GemsDecor:
    mesh.box(0, 0, 0, 0.66, 0.086, 0.58, Marble * 0.72)
    mesh.gem(-0.14, 0.086, 0.07, 0.17, Amethyst)
    mesh.gem(0.12, 0.086, -0.04, 0.14, Turquoise)
    mesh.gem(0.14, 0.086, 0.14, 0.074, Brass)
  of RugDecor:
    fabric = Primitive(mode: TrianglesMode,
      material: Material(baseColor: cloth, baseColorFactor: color(1, 1, 1, 1)))
    mesh.material.baseColor = thread
    mesh.chapelRunner(fabric, span)
  of ColumnDecor:
    mesh.chapelColumn()
  of GobletNicheDecor:
    mesh.gobletNiche()
  of PewDecor, BrokenPewDecor:
    for x in [-0.45'f32, 0.45]:
      mesh.box(x, 0, 0, 0.13, 0.63, 0.43, OakEdge)
    if kind == PewDecor:
      mesh.box(0, 0.29, 0.02, 0.90, 0.078, 0.37, Oak)
      mesh.box(0, 0.39, -0.17, 0.91, 0.28, 0.07, OakEdge)
      mesh.box(0, 0.67, -0.17, 1.01, 0.045, 0.10, Oak)
    else:
      mesh.box(-0.28, 0.29, 0.02, 0.38, 0.079, 0.34, Oak, -0.17)
      mesh.box(0.28, 0.43, -0.17, 0.33, 0.22, 0.079, OakEdge, 0.21)
      mesh.box(0.04, 0.042, 0.16, 0.55, 0.065, 0.19, OakEdge, 0.12)
  of GateDecor:
    let rust = vec3(0.44, 0.27, 0.19)
    mesh.ringArc(0, 0.96, -0.32, 0.36, 0.14, Iron, 9)
    for i in -3 .. 3:
      mesh.box(i.float32 * 0.105, 0.08, -0.407, 0.043, 1.05, 0.07, rust)
    for y in [0.20'f32, 0.64, 1.05]:
      mesh.box(0, y, -0.367, 0.79, 0.061, 0.065, Iron)
    mesh.box(0.19, 0.57, -0.316, 0.17, 0.19, 0.059, rust)
  of BenchDecor:
    for x in [-0.37'f32, 0.37]:
      mesh.box(x, 0, 0, 0.13, 0.64, 0.40, Oak)
    mesh.box(0, 0.63, 0, 0.94, 0.12, 0.52, OakEdge)
    mesh.box(-0.19, 0.75, 0.03, 0.28, 0.12, 0.17, Iron, 0.15)
    mesh.box(0.22, 0.75, 0.04, 0.15, 0.022, 0.30, Crimson)
  of CrateDecor:
    mesh.box(0, 0, 0, 0.57, 0.48, 0.56, Oak)
    for y in [0.04'f32, 0.40]:
      mesh.box(0, y, 0, 0.60, 0.067, 0.60, OakEdge)
    for x in [-0.24'f32, 0.24]:
      mesh.box(x, 0.10, 0.286, 0.053, 0.30, 0.039, Iron)
  of PracticeLineDecor:
    mesh.box(0, 0.017, 0, 1, 0.012, 0.038, Brass)
    mesh.polygon(vec3(0, 0.032, 0), right, north, 0.067, 0, 4, Brass)
  of WallTrimDecor:
    let stone = wallColor(theme)
    mesh.box(0, 0, -0.45, 0.27, 1.50, 0.17, stone)
    mesh.box(0, 0, -0.42, 0.35, 0.13, 0.24, stone * 0.81)
    mesh.box(0, 1.39, -0.42, 0.36, 0.15, 0.25, stone)
    case theme
    of TempleTheme:
      mesh.box(0, 1.31, -0.40, 0.37, 0.05, 0.29, Brass)
      mesh.polygon(vec3(0, 1.14, -0.351), right, up, 0.09, 0, 4, Turquoise)
    of ArmoryTheme, LibraryTheme:
      mesh.box(0, 0.16, -0.382, 0.21, 1.17, 0.06, OakEdge)
      mesh.box(0, 1.19, -0.35, 0.26, 0.065, 0.07, Iron)
    else:
      mesh.box(0, 1.11, -0.377, 0.28, 0.093, 0.08, Iron)
  of TorchDecor:
    mesh.box(0, 0.84, -0.47, 0.14, 0.38, 0.09, Iron)
    mesh.box(0, 0.89, -0.31, 0.077, 0.38, 0.077, Oak)
    mesh.box(0, 1.11, -0.32, 0.13, 0.062, 0.27, Iron)
    mesh.rounded(vec3(0, 1.20, -0.24), vec3(0.111, 0.08, 0.101), Brass)
  of ArchDecor:
    let
      stone = wallColor(theme)
      radius = span.float32 * 0.5 - 0.10
      crown = 0.23'f32
      spring = if theme == TempleTheme: 1.42'f32 else: 1.55'f32
      rise = if theme == TempleTheme: min(radius * 0.55, 0.54'f32)
        else: min(radius, 0.86'f32)
    # Broad openings in the Temple read as open colonnades. Frame the ends
    # with piers and leave the span clear.
    for side in [-1'f32, 1]:
      let x = side * (radius + crown * 0.50)
      mesh.box(x, 0.0, -0.47, 0.35, 0.14, 0.41, stone * 0.84)
      for row in 0 ..< 5:
        mesh.box(x, 0.14 + row.float32 * (spring - 0.14) / 5,
          -0.47, 0.27, (spring - 0.14) / 5 + 0.002, 0.32,
          stone * (0.85 + (row mod 3).float32 * 0.055))
      mesh.box(x, spring - 0.08, -0.46, 0.38, 0.11, 0.40, stone)
      if theme == TempleTheme:
        mesh.box(x, spring - 0.087, -0.46, 0.37, 0.023, 0.39, ChapelGold)
    if theme != TempleTheme or span <= 3:
      mesh.ringArc(0, spring, -0.31, radius, crown, stone,
        max(7, span * 4), heightScale = rise / radius)
      mesh.box(0, spring + rise - 0.035, -0.312, 0.19, 0.13, 0.065,
        stone * 0.92)
  of MarbleBorderDecor:
    let stone = vec3(0.26, 0.23, 0.26)
    mesh.box(0, 0.004, -0.36, 1, 0.009, 0.30, stone)
    mesh.box(0, 0.013, -0.204, 1, 0.008, 0.027, Brass)
    mesh.segment(vec3(-0.39, 0.015, -0.48), vec3(-0.22, 0.015, -0.29),
      0.012, Marble * 0.63)
  of TreeDecor, RockDecor, BushDecor:
    doAssert false
  result = Node(name: decorName(kind, theme, span), visible: true,
    scale: vec3(1), rot: quat(0, 0, 0, 1), mesh: Mesh(primitives: @[mesh]))
  if fabric != nil:
    result.mesh.primitives.add fabric

proc loadDungeonArt*(dungeon: Dungeon): DungeonArt =
  const RunnerTexture = staticRead("textures/chapel-runner.png")
  var
    oldHalls, runners: seq[Node]
    names: seq[string]
    cloth, thread: Image
  for decor in dungeon.decor:
    if decor.kind < HeraldryDecor:
      continue
    let name = decorName(decor.kind, decor.theme, decor.span)
    if name notin names:
      names.add name
      if decor.kind == RugDecor:
        if cloth == nil:
          cloth = decodeImage(RunnerTexture)
          thread = newImage(1, 1)
          thread.fill(rgba(255, 255, 255, 255))
        runners.add oldHallsNode(decor.kind, decor.theme, decor.span, cloth, thread)
      else:
        oldHalls.add oldHallsNode(decor.kind, decor.theme, decor.span)
  let
    interior = createPropPack(oldHalls)
    carpet = createPropPack(runners, textureSize = 256, repeatTexture = true)
  var grove: Grove
  var bushes: PropPack
  if dungeon.rooms[SurfaceLevel].len > 0:
    grove = generateGrove(dungeon.seed.int, {LightTree, LightRock})
    let materials = treegen.loadMaterials(1)
    var nodes: seq[Node]
    for i in 0 .. 2:
      var settings = treegen.preset(10 + i, seed = 201 + i * 41)
      settings.leafColor = LeafColors[i]
      let tint = materials.copyMaterials()
      tint.tint(settings)
      let node = treeNode(generateGeometry(settings), tint)
      node.name = "Bush" & $i
      nodes.add node
    bushes = createPropPack(nodes, textureSize = GeneratorTextureSize,
      repeatTexture = true)
  for decor in dungeon.decor:
    let
      tile = decor.tile
      center = tileCenter(int(tile.level), int(tile.x), int(tile.z))
      yaw =
        case decor.facing
        of South: 0'f32
        of East: PI.float32 / 2
        of North: PI.float32
        of West: -PI.float32 / 2
    let
      position = center + rotateY(yaw) * vec3(decor.alongEighths.float32 / 8, 0, 0)
      name = decorName(decor.kind, decor.theme, decor.span)
    var instance = SceneryInstance(pack: interior, name: name,
      position: position, yaw: yaw, scale: 1, tile: tile,
      castsShadow: decor.kind notin {RugDecor, CircleDecor, PracticeLineDecor,
        MarbleBorderDecor},
      torch: decor.kind == TorchDecor)
    case decor.kind
    of TreeDecor:
      instance.pack = grove.trees
      instance.name = modelName(LightTree, decor.variant.int mod BrushVariants)
      instance.scale = 1.0 + (decor.variant mod 4).float32 * 0.11
    of RockDecor:
      instance.pack = grove.rocks
      instance.name = modelName(LightRock, decor.variant.int mod BrushVariants)
      instance.scale = 0.38 + (decor.variant mod 5).float32 * 0.040
    of RugDecor:
      instance.pack = carpet
    of CircleDecor:
      instance.scale = if decor.span >= 2: 1.78'f32 else: 0.96'f32
    of BushDecor:
      instance.pack = bushes
      instance.name = "Bush" & $(decor.variant mod 3)
      instance.scale = 0.48 + (decor.variant mod 4).float32 * 0.09
    else:
      discard
    result.add instance

iterator visibleScenery(art: DungeonArt, level: int): SceneryInstance =
  for instance in art:
    if int(instance.tile.level) == level:
      yield instance

proc drawDungeonArt*(art: DungeonArt, level: int, viewProjection: Mat4) =
  for instance in art.visibleScenery(level):
    drawProp(instance.pack, instance.name, instance.position, instance.yaw,
      instance.scale, viewProjection)

proc drawDungeonArtDepth*(art: DungeonArt, level: int) =
  for instance in art.visibleScenery(level):
    if instance.castsShadow:
      drawPropSunDepth(instance.pack, instance.name, instance.position,
        instance.yaw, instance.scale)


proc softGlow(renderer: var ShapeRenderer, center, horizontal, vertical: Vec3,
    strength: uint8) =
  const Rim = rgbx(255, 128, 42, 0)
  let bright = rgbx(255, 152, 48, strength)
  for i in 0 ..< 14:
    let
      a = Tau * i.float32 / 14
      b = Tau * (i + 1).float32 / 14
      p = center + horizontal * cos(a) + vertical * sin(a)
      q = center + horizontal * cos(b) + vertical * sin(b)
    renderer.addTriangle([center, p, q], [bright, Rim, Rim])

proc addTorchlight*(art: DungeonArt, renderer: var ShapeRenderer,
    level: int, cameraRight: Vec3, ticks: float32,
    seen: proc(tile: TileRef): bool) =
  ## Flickering flames, soft light on the nearby wall and a pool on the floor.
  let up = vec3(0, 1, 0)
  for torch in art.visibleScenery(level):
    if not torch.torch or not seen(torch.tile):
      continue
    let
      rotation = rotateY(torch.yaw)
      front = rotation * vec3(0, 0, 1)
      side = rotation * vec3(1, 0, 0)
      phase = ticks * 0.48 + torch.position.x * 3.8 + torch.position.z * 1.6
      flicker = sin(phase) * 0.13 + sin(phase * 1.73) * 0.06
      flame = torch.position + front * -0.232 + up * 1.25
      light = uint8(48 + flicker * 70)
      right = cameraRight * 0.099
      tip = flame + up * (0.26 + flicker * 0.32) + right * flicker
    renderer.softGlow(torch.position - front * 0.49 + up * 0.97,
      side * 0.83, up * 0.77, light)
    renderer.softGlow(torch.position + front * 0.25 + up * 0.025,
      side * 1.20, front * 1.50, light)
    renderer.softGlow(flame + up * 0.105, cameraRight * 0.25,
      up * 0.31, uint8(86 + flicker * 70))
    renderer.addTriangle([flame - right, flame + right, tip],
      [rgbx(255, 112, 25, 218), rgbx(255, 166, 42, 239), rgbx(255, 197, 68, 104)])
    renderer.addTriangle(flame - right * 0.46, flame + right * 0.51,
      flame + up * (0.16 + flicker * 0.20), rgbx(255, 237, 156, 238))
