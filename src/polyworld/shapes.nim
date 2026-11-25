## World-space filled shapes for graphical clients.

import
  std/math,
  chroma, shady, vmath

when defined(useDirectX):
  {.error: "Polyworld DirectX backend is not implemented.".}
elif defined(useVulkan):
  {.error: "Polyworld Vulkan backend is not implemented.".}
elif defined(useMetal4):
  include backends/metal/shapes_types
else:
  include backends/opengl/shapes_types

const
  VertexFloats = 9
  DefaultHalfWidth* = 0.12'f
  DefaultAlpha* = 128'u8
  CircleSides* = 24
  HexagonSides* = 6
  MiterLimit = 2.5'f

type
  ShapeError* = object of CatchableError
  ShapeRenderer* = object
    ## Batches colored, optionally textured triangles in world space.
    gpu: ShapeGpu
    texture*: ShapeTexture
    vertices: seq[float32]

var
  shapeViewProjection: Uniform[Mat4]
  shapeSampler: Uniform[Sampler2d]

proc shapeVertex(
    gl_Position: var Vec4,
    fragmentColor: var Vec4,
    fragmentUv: var Vec2,
    worldPosition: Vec3,
    texturePosition: Vec2,
    vertexColor: Vec4
) =
  ## Transforms one shape vertex by the camera matrix.
  gl_Position = shapeViewProjection * vec4(worldPosition, 1)
  fragmentColor = vertexColor
  fragmentUv = texturePosition

proc shapeFragment(
    fragColor: var Vec4,
    fragmentColor: Vec4,
    fragmentUv: Vec2
) =
  ## Tints one sampled texel by the vertex color.
  fragColor = texture(shapeSampler, fragmentUv) * fragmentColor

proc clear*(renderer: var ShapeRenderer) =
  ## Starts one empty batch while retaining its vertex allocation.
  renderer.vertices.setLen(0)

proc tint(color: ColorRGBX): ColorRGBX =
  ## Uses half alpha when the caller passed a fully opaque color.
  if color.a == 255:
    rgbx(color.r, color.g, color.b, DefaultAlpha)
  else:
    color

proc writeVertex(
    vertices: var seq[float32],
    offset: int,
    position: Vec3,
    uv: Vec2,
    color: tuple[r, g, b, a: float32]
) {.inline.} =
  ## Writes into storage reserved once for the complete primitive.
  vertices[offset] = position.x
  vertices[offset + 1] = position.y
  vertices[offset + 2] = position.z
  vertices[offset + 3] = uv.x
  vertices[offset + 4] = uv.y
  vertices[offset + 5] = color.r
  vertices[offset + 6] = color.g
  vertices[offset + 7] = color.b
  vertices[offset + 8] = color.a

proc vertexColor(color: ColorRGBX): tuple[r, g, b, a: float32] {.inline.} =
  const ByteScale = 1.0'f / 255.0'f
  let painted = tint(color)
  (painted.r.float32 * ByteScale, painted.g.float32 * ByteScale,
    painted.b.float32 * ByteScale, painted.a.float32 * ByteScale)

proc addTriangle*(
    renderer: var ShapeRenderer,
    a,
    b,
    c: Vec3,
    color: ColorRGBX,
    uvA = vec2(0, 0),
    uvB = vec2(1, 0),
    uvC = vec2(0.5, 1)
) =
  ## Adds one world-space triangle.
  let
    painted = vertexColor(color)
    first = renderer.vertices.len
  renderer.vertices.setLen(first + 3 * VertexFloats)
  renderer.vertices.writeVertex(first, a, uvA, painted)
  renderer.vertices.writeVertex(first + VertexFloats, b, uvB, painted)
  renderer.vertices.writeVertex(first + 2 * VertexFloats, c, uvC, painted)

proc addTriangle*(
    renderer: var ShapeRenderer,
    points: array[3, Vec3],
    colors: array[3, ColorRGBX]
) =
  ## Adds a triangle with independent vertex colors for soft fades.
  let first = renderer.vertices.len
  renderer.vertices.setLen(first + 3 * VertexFloats)
  for i in 0 ..< 3:
    renderer.vertices.writeVertex(
      first + i * VertexFloats,
      points[i],
      vec2(0.5),
      vertexColor(colors[i])
    )

proc addQuad*(
    renderer: var ShapeRenderer,
    a,
    b,
    c,
    d: Vec3,
    color: ColorRGBX,
    uvA = vec2(0, 0),
    uvB = vec2(1, 0),
    uvC = vec2(1, 1),
    uvD = vec2(0, 1)
) =
  ## Adds one quad as two triangles. `a-b-c-d` is the corner winding.
  let
    painted = vertexColor(color)
    first = renderer.vertices.len
  renderer.vertices.setLen(first + 6 * VertexFloats)
  renderer.vertices.writeVertex(first, a, uvA, painted)
  renderer.vertices.writeVertex(first + VertexFloats, b, uvB, painted)
  renderer.vertices.writeVertex(first + 2 * VertexFloats, c, uvC, painted)
  renderer.vertices.writeVertex(first + 3 * VertexFloats, a, uvA, painted)
  renderer.vertices.writeVertex(first + 4 * VertexFloats, c, uvC, painted)
  renderer.vertices.writeVertex(first + 5 * VertexFloats, d, uvD, painted)

proc rotateY(offset: Vec3, angle: float32): Vec3 =
  ## Rotates an XZ offset around Y.
  let
    cosine = cos(angle)
    sine = sin(angle)
  vec3(
    offset.x * cosine - offset.z * sine,
    offset.y,
    offset.x * sine + offset.z * cosine
  )

proc addSquare*(
    renderer: var ShapeRenderer,
    center: Vec3,
    size: float32,
    color: ColorRGBX,
    angle = 0.0'f
) =
  ## Adds a filled XZ square. `size` is the full edge length.
  let h = size * 0.5'f
  renderer.addQuad(
    center + rotateY(vec3(-h, 0, -h), angle),
    center + rotateY(vec3(h, 0, -h), angle),
    center + rotateY(vec3(h, 0, h), angle),
    center + rotateY(vec3(-h, 0, h), angle),
    color
  )

proc addPolygon*(
    renderer: var ShapeRenderer,
    center: Vec3,
    radius: float32,
    sides: int,
    color: ColorRGBX,
    angle = 0.0'f
) =
  ## Adds a filled regular polygon in the XZ plane.
  if sides < 3 or radius <= 0:
    return
  let step = TAU / sides.float32
  for i in 0 ..< sides:
    let
      a0 = angle + step * i.float32
      a1 = angle + step * (i + 1).float32
      p0 = center + vec3(cos(a0) * radius, 0, sin(a0) * radius)
      p1 = center + vec3(cos(a1) * radius, 0, sin(a1) * radius)
    renderer.addTriangle(
      center,
      p0,
      p1,
      color,
      vec2(0.5, 0.5),
      vec2(cos(a0) * 0.5'f + 0.5'f, sin(a0) * 0.5'f + 0.5'f),
      vec2(cos(a1) * 0.5'f + 0.5'f, sin(a1) * 0.5'f + 0.5'f)
    )

proc addCircle*(
    renderer: var ShapeRenderer,
    center: Vec3,
    radius: float32,
    color: ColorRGBX,
    sides = CircleSides
) =
  ## Adds a filled XZ circle as a regular polygon.
  renderer.addPolygon(center, radius, sides, color)

proc addHexagon*(
    renderer: var ShapeRenderer,
    center: Vec3,
    radius: float32,
    color: ColorRGBX,
    angle = 0.0'f
) =
  ## Adds a filled XZ hexagon.
  renderer.addPolygon(center, radius, HexagonSides, color, angle)

proc flatNormal(a, b: Vec3): Vec3 =
  ## Returns the unit left-hand XZ normal of one segment, or zero.
  let
    d = vec3(b.x - a.x, 0, b.z - a.z)
    len2 = lengthSq(d)
  if len2 < 1e-10'f:
    return vec3(0)
  let inv = 1.0'f / sqrt(len2)
  vec3(-d.z * inv, 0, d.x * inv)

proc compactPoints(points: openArray[Vec3]): seq[Vec3] =
  ## Drops consecutive points that sit on top of each other.
  for point in points:
    if result.len == 0 or lengthSq(point - result[^1]) >= 1e-8'f:
      result.add point

proc addPolyline*(
    renderer: var ShapeRenderer,
    points: openArray[Vec3],
    color: ColorRGBX,
    halfWidth = DefaultHalfWidth
) =
  ## Adds a flat ribbon with mitered joins and beveled sharp corners.
  let pts = compactPoints(points)
  if pts.len < 2 or halfWidth <= 0:
    return
  var
    leftIn = newSeq[Vec3](pts.len)
    rightIn = newSeq[Vec3](pts.len)
    leftOut = newSeq[Vec3](pts.len)
    rightOut = newSeq[Vec3](pts.len)
  let startN = flatNormal(pts[0], pts[1])
  leftIn[0] = pts[0] + startN * halfWidth
  rightIn[0] = pts[0] - startN * halfWidth
  leftOut[0] = leftIn[0]
  rightOut[0] = rightIn[0]
  let endN = flatNormal(pts[^2], pts[^1])
  leftIn[^1] = pts[^1] + endN * halfWidth
  rightIn[^1] = pts[^1] - endN * halfWidth
  leftOut[^1] = leftIn[^1]
  rightOut[^1] = rightIn[^1]
  for i in 1 ..< pts.len - 1:
    let
      n0 = flatNormal(pts[i - 1], pts[i])
      n1 = flatNormal(pts[i], pts[i + 1])
    if lengthSq(n0) < 1e-10'f or lengthSq(n1) < 1e-10'f:
      let n = if lengthSq(n0) > 0: n0 else: n1
      leftIn[i] = pts[i] + n * halfWidth
      rightIn[i] = pts[i] - n * halfWidth
      leftOut[i] = leftIn[i]
      rightOut[i] = rightIn[i]
      continue
    let combined = n0 + n1
    if lengthSq(combined) < 1e-8'f:
      leftIn[i] = pts[i] + n0 * halfWidth
      rightIn[i] = pts[i] - n0 * halfWidth
      leftOut[i] = pts[i] + n1 * halfWidth
      rightOut[i] = pts[i] - n1 * halfWidth
      continue
    let
      bisector = normalize(combined)
      denom = dot(bisector, n0)
    if denom > 1.0'f / MiterLimit:
      let miter = bisector * (halfWidth / denom)
      leftIn[i] = pts[i] + miter
      rightIn[i] = pts[i] - miter
      leftOut[i] = leftIn[i]
      rightOut[i] = rightIn[i]
    else:
      leftIn[i] = pts[i] + n0 * halfWidth
      rightIn[i] = pts[i] - n0 * halfWidth
      leftOut[i] = pts[i] + n1 * halfWidth
      rightOut[i] = pts[i] - n1 * halfWidth
      let turn = n0.x * n1.z - n0.z * n1.x
      if turn > 0:
        renderer.addTriangle(
          pts[i] - n0 * halfWidth,
          pts[i] - n1 * halfWidth,
          pts[i],
          color
        )
      else:
        renderer.addTriangle(
          pts[i] + n0 * halfWidth,
          pts[i] + n1 * halfWidth,
          pts[i],
          color
        )
  var traveled = 0.0'f
  var total = 0.0'f
  for i in 0 ..< pts.len - 1:
    total += length(pts[i + 1] - pts[i])
  if total < 1e-8'f:
    return
  for i in 0 ..< pts.len - 1:
    let
      span = length(pts[i + 1] - pts[i])
      u0 = traveled / total
      u1 = (traveled + span) / total
    renderer.addQuad(
      leftOut[i],
      leftIn[i + 1],
      rightIn[i + 1],
      rightOut[i],
      color,
      vec2(u0, 0),
      vec2(u1, 0),
      vec2(u1, 1),
      vec2(u0, 1)
    )
    traveled += span

proc addLine*(
    renderer: var ShapeRenderer,
    a,
    b: Vec3,
    color: ColorRGBX,
    halfWidth = DefaultHalfWidth
) =
  ## Adds one flat ribbon segment in the XZ plane.
  renderer.addPolyline([a, b], color, halfWidth)

when defined(useDirectX):
  {.error: "Polyworld DirectX backend is not implemented.".}
elif defined(useVulkan):
  {.error: "Polyworld Vulkan backend is not implemented.".}
elif defined(useMetal4):
  include backends/metal/shapes
else:
  include backends/opengl/shapes
