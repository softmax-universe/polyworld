import
  flatty/binny, gltf/ktx2, pixie,
  assets

type TerrainTextureData* = object
  files*: seq[string]
  infos*: seq[Ktx2TextureInfo]

proc decode565(value: uint16): array[3, uint8] =
  ## Expands RGB565 endpoints into straight RGB bytes.
  [
    uint8((((value.int shr 11) and 31) * 255 + 15) div 31),
    uint8((((value.int shr 5) and 63) * 255 + 31) div 63),
    uint8(((value.int and 31) * 255 + 15) div 31)
  ]

proc decodeBc3*(data: string, info: Ktx2TextureInfo, level: int): string =
  ## Decodes a validated BC3 mip without multiplying RGB by its height channel.
  if info.vkFormat != VkFormatBc3UnormBlock or level < 0 or
    level >= info.levelCount:
      raise newException(AssetError, "Expected a valid linear BC3 mip level.")
  let
    width = max(1, info.width shr level)
    height = max(1, info.height shr level)
    blocksWide = (width + 3) div 4
    blocksHigh = (height + 3) div 4
    start = info.levels[level].byteOffset
    size = blocksWide * blocksHigh * 16
  if start < 0 or size > data.len - start or
    info.levels[level].byteLength != size:
      raise newException(AssetError, "Invalid BC3 level length.")
  result = newString(width * height * 4)
  for y in 0 ..< blocksHigh:
    for x in 0 ..< blocksWide:
      let
        offset = start + (y * blocksWide + x) * 16
        alphaBits = data.readUint64(offset) shr 16
        colorBits = data.readUint32(offset + 12)
      var
        alphas: array[8, uint8]
        colors: array[4, array[3, uint8]]
      alphas[0] = data[offset].ord.uint8
      alphas[1] = data[offset + 1].ord.uint8
      if alphas[0] > alphas[1]:
        for i in 1 .. 6:
          alphas[i + 1] = uint8(
            ((7 - i) * alphas[0].int + i * alphas[1].int) div 7
          )
      else:
        for i in 1 .. 4:
          alphas[i + 1] = uint8(
            ((5 - i) * alphas[0].int + i * alphas[1].int) div 5
          )
        alphas[6] = 0
        alphas[7] = 255
      colors[0] = decode565(data.readUint16(offset + 8))
      colors[1] = decode565(data.readUint16(offset + 10))
      for channel in 0 ..< 3:
        colors[2][channel] = uint8(
          (2 * colors[0][channel].int + colors[1][channel].int) div 3
        )
        colors[3][channel] = uint8(
          (colors[0][channel].int + 2 * colors[1][channel].int) div 3
        )
      for j in 0 ..< 4:
        for i in 0 ..< 4:
          let
            pixel = j * 4 + i
            px = x * 4 + i
            py = y * 4 + j
          if px >= width or py >= height:
            continue
          let
            destination = (py * width + px) * 4
            color = colors[int((colorBits shr (pixel * 2)) and 3)]
            alpha = alphas[int((alphaBits shr (pixel * 3)) and 7)]
          for channel in 0 ..< 3:
            result[destination + channel] = char(color[channel])
          result[destination + 3] = char(alpha)

proc readTerrainTextures*(paths: openArray[string]): TerrainTextureData =
  ## Reads compatible linear terrain mip chains before allocating GPU storage.
  if paths.len == 0:
    raise newException(AssetError, "Terrain texture array cannot be empty.")
  for path in paths:
    try:
      let
        bytes = readFile(path)
        info = parseKtx2(bytes)
      if info.vkFormat != VkFormatBc3UnormBlock:
        raise newException(AssetError, "Terrain requires linear BC3: " & path)
      if result.infos.len > 0 and (info.width != result.infos[0].width or
        info.height != result.infos[0].height or
        info.levelCount != result.infos[0].levelCount):
          raise newException(AssetError, "Mismatched terrain KTX2 layers.")
      result.files.add bytes
      result.infos.add info
    except AssetError:
      raise
    except CatchableError as error:
      raise newException(AssetError, "Cannot load " & path & ": " & error.msg)

proc validateTexturePixels*(width, height, channels, count: int) =
  ## Requires complete nonempty texture data before a native upload.
  if width <= 0 or height <= 0 or channels <= 0 or
    width > high(int) div height div channels or
    count != width * height * channels:
      raise newException(AssetError, "Invalid texture dimensions or data size.")

proc validateTextureLevels*(levels: openArray[Image]) =
  ## Requires equally sized pixels and a correctly halved mip chain.
  if levels.len == 0 or levels[0] == nil:
    raise newException(AssetError, "Texture mip chain cannot be empty.")
  var
    largest = max(levels[0].width, levels[0].height)
    maximumLevels = 1
  while largest > 1:
    largest = largest shr 1
    inc maximumLevels
  if levels.len > maximumLevels:
    raise newException(AssetError, "Texture mip chain exceeds its dimensions.")
  for level, mip in levels:
    if mip == nil or mip.width != max(1, levels[0].width shr level) or
      mip.height != max(1, levels[0].height shr level):
        raise newException(AssetError, "Invalid texture mip dimensions.")
    validateTexturePixels(mip.width, mip.height, 1, mip.data.len)

proc validateTextureArray*(layers: seq[seq[Image]]) =
  ## Requires complete array layers with matching dimensions and mip counts.
  if layers.len == 0:
    raise newException(AssetError, "Texture array cannot be empty.")
  for levels in layers:
    validateTextureLevels(levels)
    if levels.len != layers[0].len or
      levels[0].width != layers[0][0].width or
      levels[0].height != layers[0][0].height:
        raise newException(AssetError, "Texture array layers must match.")
