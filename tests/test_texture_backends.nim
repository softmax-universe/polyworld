import
  std/[os, tempfiles],
  gltf/ktx2, pixie, vmath, windy,
  polyworld/[assets, textures]

when defined(useMetal4):
  import metal4, polyworld/backends/metal/common

  objc:
    proc getBytes(
      self: MTLTexture, x: pointer, bytesPerRow, bytesPerImage: uint,
      fromRegion: MTLRegion, mipmapLevel, slice: uint
    ) =
      ## Reads an explicit mip and slice for exact pixel verification.
else:
  import opengl

proc readPixels[T](
  texture: Texture, width, height, channels: int,
  layers = 1, layer = 0, level = 0, arrayTexture = false
): seq[T] =
  ## Reads native storage to verify format, row alignment, mips and slices.
  result = newSeq[T](width * height * channels)
  when defined(useMetal4):
    waitForGpu()
    texture.handle.getBytes(
      result[0].addr, (width * channels * sizeof(T)).uint,
      (width * height * channels * sizeof(T)).uint,
      MTLRegion(
        origin: MTLOrigin(),
        size: MTLSize(width: width.uint, height: height.uint, depth: 1)
      ),
      level.uint, layer.uint
    )
  else:
    let
      target = if arrayTexture: GL_TEXTURE_2D_ARRAY else: GL_TEXTURE_2D
      format = case channels
        of 1: GL_RED
        of 2: GL_RG
        else: GL_RGBA
    var pixels = newSeq[T](result.len * layers)
    glBindTexture(target, texture)
    glPixelStorei(GL_PACK_ALIGNMENT, 1)
    glGetTexImage(
      target, level.GLint, format,
      when T is float32: cGL_FLOAT else: GL_UNSIGNED_BYTE,
      pixels[0].addr
    )
    glBindTexture(target, 0)
    doAssert glGetError() == GL_NO_ERROR
    copyMem(result[0].addr, pixels[layer * result.len].addr,
      result.len * sizeof(T))

proc bytes(image: Image): seq[uint8] =
  ## Reads packed RGBA bytes without alpha conversion.
  result = newSeq[uint8](image.data.len * 4)
  copyMem(result[0].addr, image.data[0].addr, result.len)

proc chain(color: ColorRGBX): seq[Image] =
  ## Builds a nonsquare explicit mip chain with independent height alpha.
  for size in [ivec2(3, 2), ivec2(1, 1)]:
    let image = newImage(size.x, size.y)
    image.fill(color)
    result.add image

let window = newWindow("Texture backend tests", ivec2(32),
  visible = false, vsync = false)
when defined(useMetal4):
  initMetal(window)
else:
  window.makeContextCurrent()
  loadExtensions()

echo "Testing array mips, independent alpha and layer updates"
block:
  let
    first = chain(rgbx(200, 100, 50, 37))
    second = chain(rgbx(20, 40, 80, 180))
    replacement = chain(rgbx(90, 80, 70, 60))
  var texture = createTextureArray(@[first, second], repeat = true)
  doAssert textureId(texture) != 0
  for layer, levels in @[first, second]:
    for level, image in levels:
      doAssert readPixels[uint8](
        texture, image.width, image.height, 4, layers = 2,
        layer = layer, level = level, arrayTexture = true
      ) == bytes(image)
  updateTextureArrayLayer(texture, 1, replacement)
  for level, image in replacement:
    doAssert readPixels[uint8](
      texture, image.width, image.height, 4, layers = 2,
      layer = 1, level = level, arrayTexture = true
    ) == bytes(image)
  doAssert readPixels[uint8](
    texture, 3, 2, 4, layers = 2, arrayTexture = true
  ) == bytes(first[0])
  deleteTexture(texture)
  deleteTexture(texture)
  doAssert textureId(texture) == 0

echo "Testing odd byte rows and resized data textures"
block:
  let
    red = @[1'u8, 2, 3, 4, 5, 6]
    rg = @[1'u8, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
    rgba = bytes(chain(rgbx(240, 30, 20, 10))[0])
  var
    redTexture = createR8Texture(3, 2, red)
    rgTexture = createRg8Texture(3, 2, rg)
    rgbaTexture = createRgba8Texture(3, 2, rgba)
  doAssert readPixels[uint8](redTexture, 3, 2, 1) == red
  doAssert readPixels[uint8](rgTexture, 3, 2, 2) == rg
  doAssert readPixels[uint8](rgbaTexture, 3, 2, 4) == rgba
  updateR8Texture(redTexture, 1, 1, [255'u8])
  updateRg8Texture(rgTexture, 1, 1, [80'u8, 120])
  updateRgba8Texture(rgbaTexture, 1, 1, [50'u8, 60, 70, 80])
  doAssert readPixels[uint8](redTexture, 1, 1, 1) == @[255'u8]
  doAssert readPixels[uint8](rgTexture, 1, 1, 2) == @[80'u8, 120]
  doAssert readPixels[uint8](rgbaTexture, 1, 1, 4) == @[50'u8, 60, 70, 80]
  deleteTexture(redTexture)
  deleteTexture(rgTexture)
  deleteTexture(rgbaTexture)

echo "Testing floating-point terrain records and shore fields"
block:
  let values = @[0.25'f, -1, 3.5, 7, 9, 0.125, 2, 4]
  var
    records = createRgba32fTexture(2, 1, values)
    shore = createR32fTexture(4, 2, values)
  doAssert readPixels[float32](records, 2, 1, 4) == values
  doAssert readPixels[float32](shore, 4, 2, 1) == values
  updateRgba32fTexture(records, 1, 1, values.toOpenArray(0, 3))
  updateR32fTexture(shore, 2, 1, values.toOpenArray(0, 1))
  doAssert readPixels[float32](records, 1, 1, 4) == values[0 .. 3]
  doAssert readPixels[float32](shore, 2, 1, 1) == values[0 .. 1]
  deleteTexture(records)
  deleteTexture(shore)

echo "Testing authored BC3 terrain mip uploads"
block:
  let
    directory = createTempDir("polyworld-textures-", "")
    path = directory / "terrain.ktx2"
    image = newImage(8, 8)
  image.fill(rgbx(210, 120, 80, 32))
  let
    encoded = encodeKtx2Image(image, VkFormatBc3UnormBlock,
      straightAlpha = true)
    info = parseKtx2(encoded)
  writeFile(path, encoded)
  var loaded = loadTerrainTextures([path], forceRgba = true)
  doAssert not loaded.compressed
  for level in 0 ..< info.levelCount:
    let
      pixels = readPixels[uint8](
        loaded.texture, max(1, info.width shr level),
        max(1, info.height shr level), 4, level = level, arrayTexture = true
      )
      decoded = decodeBc3(encoded, info, level)
    doAssert pixels.len == decoded.len
    for i, value in pixels:
      doAssert value == decoded[i].ord.uint8
  deleteTexture(loaded.texture)
  removeFile(path)
  removeDir(directory)

echo "Testing invalid upload inputs"
block:
  var rejected = false
  try:
    discard createTextureArray(@[], repeat = false)
  except AssetError:
    rejected = true
  doAssert rejected
  rejected = false
  try:
    discard createR8Texture(3, 2, [1'u8])
  except AssetError:
    rejected = true
  doAssert rejected

when defined(useMetal4):
  shutdownMetal()
window.close()
echo "Texture backend storage and lifecycle passed"
