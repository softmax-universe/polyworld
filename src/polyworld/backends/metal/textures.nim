import
  metal4, pixie,
  common, ../../[assets, texturedata]

const TextureType2DArray = 3'u

type
  Texture* = MetalTexture
  TextureArray* = Texture

objc:
  proc setTextureType(self: MTLTextureDescriptor, x: uint) =
    ## Selects the native texture shape.
  proc setArrayLength(self: MTLTextureDescriptor, x: uint) =
    ## Allocates one native slice per texture-array layer.
  proc arrayLength(self: MTLTexture): uint =
    ## Reads the native texture-array layer count.
  proc replaceRegion(
    self: MTLTexture, x: MTLRegion, mipmapLevel: uint, slice: uint,
    withBytes: pointer, bytesPerRow: uint, bytesPerImage: uint
  ) =
    ## Uploads one complete mip level of one array slice.

proc deleteTexture*(texture: var Texture) =
  ## Releases an owned texture and clears the caller's handle.
  if texture != nil:
    destroy(texture)
    texture = nil

proc textureId*(texture: Texture): uint =
  ## Returns a stable resource key while this texture is alive.
  if texture == nil: 0'u else: cast[uint](texture.handle)

proc allocateTexture(
  width, height, layers, mipCount: int, format: MTLPixelFormat,
  linear, repeat, arrayTexture: bool
): Texture =
  ## Allocates CPU-uploadable native storage on the renderer's shared device.
  if width <= 0 or height <= 0 or layers <= 0 or mipCount <= 0:
    raise newException(AssetError, "Invalid Metal texture dimensions.")
  if metalRenderer == nil or metalRenderer.ctx.device.isNil:
    raise newException(AssetError, "Initialize Metal before creating textures.")
  let descriptor = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
    format, width.uint, height.uint, mipCount > 1
  )
  descriptor.setUsage(MTLTextureUsageShaderRead)
  descriptor.setStorageMode(MTLStorageModeShared)
  descriptor.setMipmapLevelCount(mipCount.uint)
  if arrayTexture:
    descriptor.setTextureType(TextureType2DArray)
    descriptor.setArrayLength(layers.uint)
  let handle = metalRenderer.ctx.device.newTextureWithDescriptor(descriptor)
  if handle.isNil:
    raise newException(AssetError, "Could not allocate a Metal texture.")
  try:
    result = textureFromNative(
      handle, width, height, format, ownsHandle = true,
      linear = linear, repeat = repeat
    )
  except:
    handle.release()
    raise

proc uploadArrayLevel(
  texture: TextureArray, layer, level, width, height: int, data: pointer
) =
  ## Copies complete RGBA pixels into one mip of an allocated native slice.
  texture.handle.replaceRegion(
    MTLRegion(
      origin: MTLOrigin(x: 0, y: 0, z: 0),
      size: MTLSize(width: width.uint, height: height.uint, depth: 1)
    ),
    level.uint, layer.uint, data, (width * 4).uint, (width * height * 4).uint
  )

proc loadTerrainTextures*(
  paths: openArray[string], forceRgba = false
): tuple[texture: TextureArray, compressed: bool] =
  ## Uploads authored terrain mips as linear RGBA with independent height alpha.
  let
    source = readTerrainTextures(paths)
    info = source.infos[0]
  result.texture = allocateTexture(
    info.width, info.height, source.files.len, info.levelCount,
    MTLPixelFormatRGBA8Unorm, linear = true, repeat = true,
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
    MTLPixelFormatRGBA8Unorm, linear = true, repeat = repeat,
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
    layer >= texture.handle.arrayLength().int or
    levels.len > texture.handle.mipmapLevelCount().int or
    levels[0].width != texture.width or levels[0].height != texture.height:
      raise newException(AssetError, "Invalid texture array layer.")
  for level, mip in levels:
    uploadArrayLevel(
      texture, layer, level, mip.width, mip.height, mip.data[0].addr
    )

proc updateDataTexture(
  texture: var Texture, width, height, bytesPerPixel: int,
  data: pointer, format: MTLPixelFormat, linear: bool
) =
  ## Replaces data storage while preserving resources used by queued draws.
  var replacement = allocateTexture(
    width, height, 1, 1, format, linear = linear, repeat = false,
    arrayTexture = false
  )
  try:
    replacement.handle.replaceRegion(
      MTLRegion(
        origin: MTLOrigin(x: 0, y: 0, z: 0),
        size: MTLSize(width: width.uint, height: height.uint, depth: 1)
      ),
      0, data, (width * bytesPerPixel).uint
    )
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
    MTLPixelFormatRGBA32Float, false
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
    MTLPixelFormatR32Float, linear
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
    texture, width, height, 1, unsafeAddr pixels[0], MTLPixelFormatR8Unorm,
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
    texture, width, height, 2, unsafeAddr pixels[0], MTLPixelFormatRG8Unorm,
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
    texture, width, height, 4, unsafeAddr pixels[0], MTLPixelFormatRGBA8Unorm,
    linear
  )

proc createRgba8Texture*(
  width, height: int, pixels: openArray[uint8], linear = true
): Texture =
  ## Creates a four-channel normalized byte texture.
  updateRgba8Texture(result, width, height, pixels, linear)
