## Adapts the public GL texture uploads to shared pass resource handles.

import
  pixie,
  textures as legacy,
  passresources, passtypes,
  ../../texturedata

export texturedata

type
  Texture* = GpuImage
  TextureArray* = Texture

proc deleteTexture*(texture: var Texture) =
  ## Releases an owned pass texture and clears the caller's reference.
  texture.destroy()
  texture = nil

proc textureId*(texture: Texture): uint =
  ## Returns the native key while an allocated texture is alive.
  if texture == nil: 0'u else: texture.handle.uint

proc loadTerrainTextures*(paths: openArray[string], forceRgba = false):
    tuple[texture: TextureArray, compressed: bool] =
  ## Wraps the validated native terrain upload without decoding it again.
  var plan: TextureUploadPlan
  let loaded = legacy.loadTerrainTextures(paths, forceRgba, plan)
  result.texture = textureFromNative(loaded.texture, plan.width, plan.height,
    target = GL_TEXTURE_2D_ARRAY, ownsHandle = true, repeat = true,
    layers = plan.layerCount, levels = plan.levelCount)
  result.compressed = loaded.compressed

proc createTextureArray*(layers: seq[seq[Image]], repeat: bool): TextureArray =
  ## Uploads explicit mip chains with the legacy public texture implementation.
  let handle = legacy.createTextureArray(layers, repeat)
  result = textureFromNative(handle, layers[0][0].width, layers[0][0].height,
    target = GL_TEXTURE_2D_ARRAY, ownsHandle = true, repeat = repeat,
    layers = layers.len, levels = layers[0].len)
  let wrap = if repeat: Repeat else: ClampEdge
  result.setTextureSampling(SamplerState(
    minLinear: true, magLinear: true, mipLinear: true, mipmaps: true,
    wrapS: wrap, wrapT: wrap, wrapR: wrap, maxAnisotropy: 8
  ))

proc updateTextureArrayLayer*(texture: TextureArray, layer: int,
    levels: seq[Image]) =
  ## Updates one array layer without changing its native resource identity.
  legacy.updateTextureArrayLayer(texture.handle, layer, levels)

proc updateStorageInfo(texture: Texture, width, height: int,
    format: TextureFormat) =
  ## Keeps the texture description consistent after typed storage updates.
  texture.width = width
  texture.height = height
  texture.pixelFormat = format
  texture.nativeFormat = glFormat(format).internal.GLenum

proc updateRgba32fTexture*(texture: var Texture, width, height: int,
    pixels: openArray[float32]) =
  ## Updates a typed data image through the existing validated upload path.
  var handle = if texture == nil: 0.GLuint else: texture.handle
  legacy.updateRgba32fTexture(handle, width, height, pixels)
  if texture == nil:
    texture = textureFromNative(handle, width, height, Rgba32f,
      ownsHandle = true, linear = false)
  else:
    texture.updateStorageInfo(width, height, Rgba32f)
    texture.setTextureSampling(linear = false)

proc createRgba32fTexture*(width, height: int, pixels: openArray[float32]): Texture =
  ## Creates a typed texture for shared rendering passes.
  updateRgba32fTexture(result, width, height, pixels)

proc updateR32fTexture*(texture: var Texture, width, height: int,
    pixels: openArray[float32], linear = true) =
  ## Updates a typed data image through the existing validated upload path.
  var handle = if texture == nil: 0.GLuint else: texture.handle
  legacy.updateR32fTexture(handle, width, height, pixels, linear)
  if texture == nil:
    texture = textureFromNative(handle, width, height, R32f,
      ownsHandle = true, linear = linear)
  else:
    texture.updateStorageInfo(width, height, R32f)
    texture.setTextureSampling(linear = linear)

proc createR32fTexture*(width, height: int, pixels: openArray[float32], linear = true): Texture =
  ## Creates a typed texture for shared rendering passes.
  updateR32fTexture(result, width, height, pixels, linear)

proc updateR8Texture*(texture: var Texture, width, height: int,
    pixels: openArray[uint8], linear = true) =
  ## Updates a typed data image through the existing validated upload path.
  var handle = if texture == nil: 0.GLuint else: texture.handle
  legacy.updateR8Texture(handle, width, height, pixels, linear)
  if texture == nil:
    texture = textureFromNative(handle, width, height, R8,
      ownsHandle = true, linear = linear)
  else:
    texture.updateStorageInfo(width, height, R8)
    texture.setTextureSampling(linear = linear)

proc createR8Texture*(width, height: int, pixels: openArray[uint8], linear = true): Texture =
  ## Creates a typed texture for shared rendering passes.
  updateR8Texture(result, width, height, pixels, linear)

proc updateRg8Texture*(texture: var Texture, width, height: int,
    pixels: openArray[uint8], linear = true) =
  ## Updates a typed data image through the existing validated upload path.
  var handle = if texture == nil: 0.GLuint else: texture.handle
  legacy.updateRg8Texture(handle, width, height, pixels, linear)
  if texture == nil:
    texture = textureFromNative(handle, width, height, Rg8,
      ownsHandle = true, linear = linear)
  else:
    texture.updateStorageInfo(width, height, Rg8)
    texture.setTextureSampling(linear = linear)

proc createRg8Texture*(width, height: int, pixels: openArray[uint8], linear = true): Texture =
  ## Creates a typed texture for shared rendering passes.
  updateRg8Texture(result, width, height, pixels, linear)

proc updateRgba8Texture*(texture: var Texture, width, height: int,
    pixels: openArray[uint8], linear = true) =
  ## Updates a typed data image through the existing validated upload path.
  var handle = if texture == nil: 0.GLuint else: texture.handle
  legacy.updateRgba8Texture(handle, width, height, pixels, linear)
  if texture == nil:
    texture = textureFromNative(handle, width, height, Rgba8,
      ownsHandle = true, linear = linear)
  else:
    texture.updateStorageInfo(width, height, Rgba8)
    texture.setTextureSampling(linear = linear)

proc createRgba8Texture*(width, height: int, pixels: openArray[uint8], linear = true): Texture =
  ## Creates a typed texture for shared rendering passes.
  updateRgba8Texture(result, width, height, pixels, linear)
