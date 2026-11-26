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

var textureArrayRevision*: uint64

proc uploadArrayLevel(texture: Texture, layer, level, width, height: int, data: pointer) =
  inc textureArrayRevision
  texture.handle.uploadLevel(layer, level, width, height, 4, data)

proc loadTerrainTextures*(
  paths: openArray[string], forceRgba = false
): tuple[texture: TextureArray, compressed: bool] =
  ## Uploads authored terrain mips as linear RGBA with independent height alpha.
  let plan = prepareTerrainTextures(paths)
  result.texture = allocateTexture(
    plan.width, plan.height, plan.layerCount, plan.levelCount,
    Rgba8, linear = true, repeat = true,
    arrayTexture = true
  )
  try:
    for upload in plan.textureUploads():
      uploadArrayLevel(
        result.texture, upload.layer, upload.level,
        upload.width, upload.height, upload.data()
      )
  except:
    deleteTexture(result.texture)
    raise

proc createTextureArray*(
  layers: seq[seq[Image]], repeat: bool
): TextureArray =
  ## Uploads explicit RGBA mip chains without modifying their alpha channels.
  let plan = prepareTextureArray(layers)
  result = allocateTexture(
    plan.width, plan.height, plan.layerCount, plan.levelCount,
    Rgba8, linear = true, repeat = repeat,
    arrayTexture = true
  )
  try:
    for upload in plan.textureUploads():
      uploadArrayLevel(
        result, upload.layer, upload.level,
        upload.width, upload.height, upload.data()
      )
  except:
    deleteTexture(result)
    raise

proc updateTextureArrayLayer*(
  texture: TextureArray, layer: int, levels: seq[Image]
) =
  ## Replaces one allocated array layer with its explicit RGBA mip chain.
  let plan = prepareTextureArray(@[levels])
  if texture == nil or layer < 0 or
    layer >= texture.handle.layers or
    plan.levelCount > texture.handle.mipLevels or
    plan.width != texture.width or plan.height != texture.height:
      raise newException(AssetError, "Invalid texture array layer.")
  for upload in plan.textureUploads():
    uploadArrayLevel(
      texture, layer, upload.level, upload.width, upload.height, upload.data()
    )

proc updateDataTexture(
  texture: var Texture, width, height, bytesPerPixel: int,
  data: pointer, format: TextureFormat, linear: bool
) =
  ## Replaces data storage while preserving resources used by queued draws.
  if texture != nil and texture.width == width and texture.height == height and texture.pixelFormat == format:
    texture.handle.uploadLevel(0, 0, width, height, bytesPerPixel, data)
    texture.setTextureSampling(linear)
    return
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
