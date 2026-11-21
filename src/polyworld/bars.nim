## Pixel-aligned geometry for bars with horizontally uniform texture bodies.

import
  std/math,
  vmath

type
  BarRect* = object
    position*, size*: Vec2
  BarSlice* = object
    bounds*: BarRect
    sourcePosition*, sourceSize*: Vec2

proc barBounds*(position, size: Vec2, scale: float32): BarRect =
  ## Aligns a nonempty bar to framebuffer pixels.
  if size.x <= 0 or size.y <= 0:
    return
  let scale = max(scale, 0.001'f)
  result.position = vec2(round(position.x * scale),
    round(position.y * scale)) / scale
  result.size = vec2(round(size.x * scale), round(size.y * scale)) / scale

proc barFill*(track: BarRect, ratio, scale: float32): BarRect =
  ## Insets a positive fill inside a pixel-aligned track.
  if ratio <= 0 or track.size.x <= 0 or track.size.y <= 0:
    return
  let
    scale = max(scale, 0.001'f)
    width = round(track.size.x * scale).int
    height = round(track.size.y * scale).int
  if width <= 0 or height <= 0:
    return
  let
    inset = round(min(3.0'f, track.size.y / 6) * scale).int
    insetX = min(inset, (width - 1) div 2)
    insetY = min(inset, (height - 1) div 2)
    innerWidth = width - insetX * 2
    fillWidth = clamp(round(innerWidth.float32 * ratio).int, 1, innerWidth)
  result.position = track.position + vec2(insetX.float32, insetY.float32) / scale
  result.size = vec2(fillWidth.float32, (height - insetY * 2).float32) / scale

proc barSlices*(bounds: BarRect, sourceSize: Vec2,
    sourceCap, scale: float32): array[3, BarSlice] =
  ## Fits fixed texture caps inside pixel-aligned bounds without overlap.
  if bounds.size.x <= 0 or bounds.size.y <= 0 or
      sourceSize.x <= 0 or sourceSize.y <= 0:
    return
  let
    scale = max(scale, 0.001'f)
    width = round(bounds.size.x * scale).int
    cap = clamp(sourceCap, 0.0'f, sourceSize.x / 2)
    capPixels = min(width div 2,
      round(cap * bounds.size.y / sourceSize.y * scale).int)
    capWidth = capPixels.float32 / scale
    centerWidth = bounds.size.x - capWidth * 2
    offsets = [0.0'f, capWidth, bounds.size.x - capWidth]
    widths = [capWidth, centerWidth, capWidth]
    # A single texel column avoids atlas mip bleeding when the body is tiny.
    sourceOffsets = [0.0'f, floor(sourceSize.x / 2) + 0.5'f,
      sourceSize.x - cap]
    sourceWidths = [cap, 0.0'f, cap]
  for i in 0 ..< result.len:
    result[i] = BarSlice(
      bounds: BarRect(position: bounds.position + vec2(offsets[i], 0),
        size: vec2(widths[i], bounds.size.y)),
      sourcePosition: vec2(sourceOffsets[i], 0),
      sourceSize: vec2(sourceWidths[i], sourceSize.y)
    )
