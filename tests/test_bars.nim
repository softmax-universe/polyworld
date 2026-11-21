import
  std/math,
  vmath,
  polyworld/bars

const
  Tolerance = 0.0001'f
  Scales = [0.25'f, 0.5'f, 1.0'f, 1.25'f, 2.0'f, 4.0'f]
  Widths = [0.1'f, 0.4'f, 1.0'f, 2.0'f, 3.0'f, 9.0'f, 10.0'f,
    11.0'f, 12.0'f, 61.3'f, 240.0'f]
  Heights = [0.1'f, 0.4'f, 1.0'f, 2.0'f, 3.0'f, 4.0'f, 6.0'f,
    12.0'f, 18.0'f, 23.0'f, 29.0'f]

proc close(a, b: float32): bool =
  ## Compares geometry despite floating-point pixel conversions.
  abs(a - b) < Tolerance

proc aligned(bounds: BarRect, scale: float32): bool =
  ## Checks both edges against the framebuffer pixel grid.
  for point in [bounds.position, bounds.position + bounds.size]:
    let pixel = point * scale
    if not close(pixel.x, round(pixel.x)) or
      not close(pixel.y, round(pixel.y)):
        return false
  true

proc contained(inner, outer: BarRect): bool =
  ## Checks that a rectangle stays within the requested bar.
  let
    innerEnd = inner.position + inner.size
    outerEnd = outer.position + outer.size
  inner.size.x >= 0 and inner.size.y >= 0 and
    inner.position.x >= outer.position.x - Tolerance and
    inner.position.y >= outer.position.y - Tolerance and
    innerEnd.x <= outerEnd.x + Tolerance and
    innerEnd.y <= outerEnd.y + Tolerance

echo "Testing empty and pixel-aligned bar bounds"
block:
  for scale in Scales:
    for size in [vec2(0, 6), vec2(6, 0), vec2(-1, 6), vec2(6, -1)]:
      doAssert barBounds(vec2(12, 20), size, scale).size == vec2(0)
    for width in Widths:
      for height in Heights:
        let
          bounds = barBounds(vec2(-12.3, 20.2), vec2(width, height), scale)
          shifted = barBounds(vec2(12.8, 20.7), vec2(width, height), scale)
        doAssert aligned(bounds, scale)
        doAssert bounds.size == shifted.size
        doAssert abs(bounds.size.x - width) <= 0.5'f / scale + Tolerance
        doAssert abs(bounds.size.y - height) <= 0.5'f / scale + Tolerance

echo "Testing tiny fills remain inside their tracks"
block:
  for scale in Scales:
    for width in Widths:
      for height in Heights:
        let track = barBounds(vec2(12.2, 20.3), vec2(width, height), scale)
        doAssert barFill(track, 0, scale).size == vec2(0)
        doAssert barFill(track, -1, scale).size == vec2(0)
        var previousWidth = 0.0'f
        for ratio in [0.0001'f, 0.01'f, 0.1'f, 0.5'f, 1.0'f, 2.0'f]:
          let fill = barFill(track, ratio, scale)
          if track.size.x <= 0 or track.size.y <= 0:
            doAssert fill.size == vec2(0)
            continue
          doAssert contained(fill, track)
          doAssert aligned(fill, scale)
          doAssert fill.size.x * scale >= 1 - Tolerance
          doAssert fill.size.y * scale >= 1 - Tolerance
          doAssert fill.size.x >= previousWidth
          previousWidth = fill.size.x
        doAssert barFill(track, 1, scale) == barFill(track, 2, scale)

echo "Testing textured slices cover bars without overlapping"
block:
  for scale in Scales:
    for width in Widths:
      for height in Heights:
        let bounds = barBounds(vec2(12.2, 20.3), vec2(width, height), scale)
        for source in [(size: vec2(65, 29), cap: 7.0'f),
            (size: vec2(59, 23), cap: 5.0'f)]:
          let slices = barSlices(bounds, source.size, source.cap, scale)
          if bounds.size.x <= 0 or bounds.size.y <= 0:
            for slice in slices:
              doAssert slice.bounds.size == vec2(0)
            continue
          var nextX = bounds.position.x
          for slice in slices:
            doAssert contained(slice.bounds, bounds)
            doAssert aligned(slice.bounds, scale)
            doAssert close(slice.bounds.position.x, nextX)
            doAssert close(slice.bounds.position.y, bounds.position.y)
            doAssert close(slice.bounds.size.y, bounds.size.y)
            nextX += slice.bounds.size.x
          doAssert close(nextX, bounds.position.x + bounds.size.x)
          doAssert slices[0].sourcePosition == vec2(0)
          doAssert slices[0].sourceSize == vec2(source.cap, source.size.y)
          doAssert slices[2].sourcePosition ==
            vec2(source.size.x - source.cap, 0)
          doAssert slices[2].sourceSize == slices[0].sourceSize
          doAssert slices[1].sourceSize == vec2(0, source.size.y)
          doAssert close(slices[1].sourcePosition.x,
            floor(source.size.x / 2) + 0.5'f)
          doAssert slices[1].sourcePosition.y == 0

echo "Testing source density preserves destination geometry"
block:
  for scale in Scales:
    for width in Widths:
      let bounds = barBounds(vec2(12, 20), vec2(width, 6), scale)
      for cap in [5.0'f, 10.0'f]:
        let
          ordinary = barSlices(bounds, vec2(59, 23), cap, scale)
          dense = barSlices(bounds, vec2(118, 46), cap * 2, scale)
        for i in 0 ..< ordinary.len:
          doAssert ordinary[i].bounds == dense[i].bounds
          if bounds.size.x > 0 and bounds.size.y > 0:
            doAssert dense[i].sourceSize == ordinary[i].sourceSize * 2

echo "Bar geometry tests passed"
