import pixie, common, ../../[assets, texturedata]

type
  Texture* = GpuImage
  TextureArray* = Texture

proc deleteTexture*(texture: var Texture) =
  ## Releases an owned texture and clears the caller's handle.
  if texture != nil:
    destroy(texture)
    texture = nil

proc textureId*(texture: Texture): uint =
  ## Returns a stable resource key while this texture is alive.
  if texture == nil: 0'u else: cast[uint](texture.handle)

proc allocateTexture(width, height, layers, mipCount: int, format: TextureFormat,
    linear, repeat, arrayTexture: bool): Texture =
  allocateImage(width, height, format, linear, repeat, layers, mipCount, arrayTexture)

proc uploadArrayLevel(texture: Texture, layer, level, width, height: int, data: pointer) =
  texture.handle.uploadLevel(layer, level, width, height, 4, data)

proc loadTerrainTextures*(
  paths: openArray[string], forceRgba = false
): tuple[texture: TextureArray, compressed: bool] =
  ## Uploads authored terrain mips as linear RGBA with independent height alpha.
  let
    source = readTerrainTextures(paths)
    info = source.infos[0]
  result.texture = allocateTexture(
    info.width, info.height, source.files.len, info.levelCount,
    Rgba8, linear = true, repeat = true,
    arrayTexture = true
  )
  try:
    for layer, bytes in source.files:
      for level in 0 ..< info.levelCount:
        let pixels = decodeBc3(bytes, source.infos[layer], level)
        uploadArrayLevel(
          result.texture, layer, level,
          max(1, info.width shr level), max(1, info.height shr level),
          unsafeAddr pixels[0]
        )
  except:
    deleteTexture(result.texture)
    raise

proc createTextureArray*(
  layers: seq[seq[Image]], repeat: bool
): TextureArray =
  ## Uploads explicit RGBA mip chains without modifying their alpha channels.
  validateTextureArray(layers)
  result = allocateTexture(
    layers[0][0].width, layers[0][0].height, layers.len, layers[0].len,
    Rgba8, linear = true, repeat = repeat,
    arrayTexture = true
  )
  try:
    for layer, levels in layers:
      for level, mip in levels:
        uploadArrayLevel(
          result, layer, level, mip.width, mip.height, mip.data[0].addr
        )
  except:
    deleteTexture(result)
    raise

proc updateTextureArrayLayer*(
  texture: TextureArray, layer: int, levels: seq[Image]
) =
  ## Replaces one allocated array layer with its explicit RGBA mip chain.
  validateTextureLevels(levels)
  if texture == nil or layer < 0 or
    layer >= texture.handle.layers or
    levels.len > texture.handle.mipLevels or
    levels[0].width != texture.width or levels[0].height != texture.height:
      raise newException(AssetError, "Invalid texture array layer.")
  for level, mip in levels:
    uploadArrayLevel(
      texture, layer, level, mip.width, mip.height, mip.data[0].addr
    )

proc updateDataTexture(
  texture: var Texture, width, height, bytesPerPixel: int,
  data: pointer, format: TextureFormat, linear: bool
) =
  ## Replaces data storage while preserving resources used by queued draws.
  var replacement = allocateTexture(
    width, height, 1, 1, format, linear = linear, repeat = false,
    arrayTexture = false
  )
  try:
    replacement.handle.uploadLevel(0, 0, width, height, bytesPerPixel, data)
  except:
    deleteTexture(replacement)
    raise
  deleteTexture(texture)
  texture = replacement

proc updateRgba32fTexture*(
  texture: var Texture, width, height: int, pixels: openArray[float32]
) =
  ## Replaces nearest-filtered RGBA floating-point data records.
  validateTexturePixels(width, height, 4, pixels.len)
  updateDataTexture(
    texture, width, height, 4 * sizeof(float32), unsafeAddr pixels[0],
    Rgba32f, false
  )

proc createRgba32fTexture*(
  width, height: int, pixels: openArray[float32]
): Texture =
  ## Creates nearest-filtered RGBA floating-point data records.
  updateRgba32fTexture(result, width, height, pixels)

proc updateR32fTexture*(
  texture: var Texture, width, height: int, pixels: openArray[float32],
  linear = true
) =
  ## Replaces a single-channel floating-point field.
  validateTexturePixels(width, height, 1, pixels.len)
  updateDataTexture(
    texture, width, height, sizeof(float32), unsafeAddr pixels[0],
    R32f, linear
  )

proc createR32fTexture*(
  width, height: int, pixels: openArray[float32], linear = true
): Texture =
  ## Creates a single-channel floating-point field.
  updateR32fTexture(result, width, height, pixels, linear)

proc updateR8Texture*(
  texture: var Texture, width, height: int, pixels: openArray[uint8],
  linear = true
) =
  ## Replaces a single-channel normalized byte texture.
  validateTexturePixels(width, height, 1, pixels.len)
  updateDataTexture(
    texture, width, height, 1, unsafeAddr pixels[0], R8,
    linear
  )

proc createR8Texture*(
  width, height: int, pixels: openArray[uint8], linear = true
): Texture =
  ## Creates a single-channel normalized byte texture.
  updateR8Texture(result, width, height, pixels, linear)

proc updateRg8Texture*(
  texture: var Texture, width, height: int, pixels: openArray[uint8],
  linear = true
) =
  ## Replaces a two-channel normalized byte texture.
  validateTexturePixels(width, height, 2, pixels.len)
  updateDataTexture(
    texture, width, height, 2, unsafeAddr pixels[0], Rg8,
    linear
  )

proc createRg8Texture*(
  width, height: int, pixels: openArray[uint8], linear = true
): Texture =
  ## Creates a two-channel normalized byte texture.
  updateRg8Texture(result, width, height, pixels, linear)

proc updateRgba8Texture*(
  texture: var Texture, width, height: int, pixels: openArray[uint8],
  linear = true
) =
  ## Replaces a four-channel normalized byte texture.
  validateTexturePixels(width, height, 4, pixels.len)
  updateDataTexture(
    texture, width, height, 4, unsafeAddr pixels[0], Rgba8,
    linear
  )

proc createRgba8Texture*(
  width, height: int, pixels: openArray[uint8], linear = true
): Texture =
  ## Creates a four-channel normalized byte texture.
  updateRgba8Texture(result, width, height, pixels, linear)
