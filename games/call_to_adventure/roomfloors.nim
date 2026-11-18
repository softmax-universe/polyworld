## Tileable color and relief for the three finished Old Halls floors.

import
  std/math,
  chroma, pixie,
  polyworld/quadterrain

type Finish = enum
  PolishedStone, OakPlanks, Marble

proc wave(value: float32): float32 =
  sin(value * (2 * PI.float32))

proc finishTile(finish: Finish): GeneratedTileImages =
  const Size = 256
  result = (newImage(Size, Size), newImage(Size, Size))
  if finish == Marble:
    const MarbleTexture = staticRead("textures/chapel-marble.png")
    result.color = decodeImage(MarbleTexture)
    for y in 0 ..< Size:
      for x in 0 ..< Size:
        let
          dx = min(x mod 128, 128 - x mod 128)
          dy = min(y mod 128, 128 - y mod 128)
          seam = min(dx, dy)
          height = if dx + dy <= 8: 178'u8 elif seam == 0: 93'u8
            elif seam == 1: 153'u8 else: 185'u8
        result.height[x, y] = rgbx(height, height, height, 255)
    return
  for y in 0 ..< Size:
    for x in 0 ..< Size:
      let
        u = x.float32 / Size.float32
        v = y.float32 / Size.float32
        variation = wave(u * 7 + v * 9) * wave(u * 11 - v * 6)
      var
        relief = 0'f32
        red, green, blue: float32
      case finish
      of PolishedStone:
        let
          seam = min(x mod (Size div 2), y mod (Size div 2))
          blockShade = ((x div (Size div 2)) xor (y div (Size div 2))).float32
          vein = pow(abs(wave(u * 2 + v + 0.11 * wave(v * 3) +
            0.05 * wave(u * 5 - v * 2))), 16)
        relief = if seam == 0: 60'f32 elif seam == 1: 144'f32 else: 193'f32
        let tone = 121'f32 + 6 * blockShade + 3 * variation - 8 * vein
        (red, green, blue) = (tone + 2, tone + 9, tone + 20)
        if seam == 0:
          (red, green, blue) = (red * 0.54, green * 0.54, blue * 0.54)
        elif seam == 1:
          (red, green, blue) = (red + 11, green + 11, blue + 11)
      of OakPlanks:
        let
          plank = x div 32
          side = x mod 32
          endJoint = (y + plank * 64) mod 128
          grain = wave(u * 39 + 0.16 * wave(v * 3 + u * 2)) +
            0.6 * wave(u * 67 - 0.22 * wave(v * 2 - u * 3))
          tone = 15 * wave(plank.float32 / 8) + 6 * grain + 2 * variation
        relief = 175 + 5 * grain
        (red, green, blue) = (133 + tone, 87 + tone, 55 + tone * 0.72)
        if side == 0 or endJoint == 0:
          (red, green, blue) = (red * 0.42, green * 0.42, blue * 0.42)
          relief = 54
        elif side == 1 or endJoint == 1:
          (red, green, blue) = (red + 15, green + 13, blue + 9)
          relief = 158
      of Marble:
        discard # handled before the loop
      let height = uint8(clamp(relief, 0, 255))
      result.color[x, y] = rgbx(uint8(clamp(red, 0, 255)),
        uint8(clamp(green, 0, 255)), uint8(clamp(blue, 0, 255)), 255)
      result.height[x, y] = rgbx(height, height, height, 255)

proc roomFloorImages*(): array[Finish, GeneratedTileImages] =
  for finish in Finish:
    result[finish] = finishTile(finish)
