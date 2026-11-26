## Material sampling and environment cubemap uploads.
import pixie, gltf, common, ../../texturesampling
import windy/platforms/apple/objc as nativeObjc

proc uploadTexture*(image: Image, sampler: TextureSampler,
    fallback: MetalTexture): MetalTexture =
  ## Preserves glTF's straight texture bytes and authored sampling behavior.
  if image == nil:
    return fallback
  let state = sampler.samplingState()
  result = newTexture(image, mipmaps = state.mipmaps)
  result.setTextureSampling(state)

objc:
  proc replaceRegion(self: MTLTexture, x: MTLRegion,
    mipmapLevel, slice: uint, withBytes: pointer,
    bytesPerRow, bytesPerImage: uint)

proc newCubeTexture*(faces: array[6, Image]): MetalTexture =
  ## Uploads a complete cubemap mip chain into the engine's shared device.
  let pool = nativeObjc.NSAutoreleasePool.new()
  defer: pool.release()
  if faces[0] == nil:
    raise newException(PolyworldMetalError, "Cubemap images cannot be nil.")
  let size = faces[0].width
  for face in faces:
    if face == nil or face.width != size or face.height != size:
      raise newException(PolyworldMetalError,
        "Cubemap faces must be equally sized square images.")
  let descriptor = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
    MTLPixelFormatRGBA8Unorm, size.uint, size.uint, true)
  common.setTextureType(descriptor, 5)
  descriptor.setUsage(MTLTextureUsageShaderRead)
  let texture = metalRenderer.ctx.device.newTextureWithDescriptor(descriptor)
  checkNil(texture, "Could not create the character environment cubemap.")
  result = textureFromNative(texture, size, size,
    MTLPixelFormatRGBA8Unorm, ownsHandle = true)
  for face, image in faces:
    var
      level = image
      mip = 0'u
    while true:
      texture.replaceRegion(
        MTLRegion(size: MTLSize(width: level.width.uint,
          height: level.height.uint, depth: 1)),
        mip, face.uint, level.data[0].addr,
        (level.width * 4).uint, (level.width * level.height * 4).uint)
      if level.width == 1:
        break
      let next = newImage(max(level.width div 2, 1),
        max(level.height div 2, 1))
      for y in 0 ..< next.height:
        for x in 0 ..< next.width:
          var channels: array[4, uint32]
          for dy in 0 ..< 2:
            for dx in 0 ..< 2:
              let pixel = level.data[(y * 2 + dy) * level.width + x * 2 + dx]
              channels[0] += pixel.r.uint32
              channels[1] += pixel.g.uint32
              channels[2] += pixel.b.uint32
              channels[3] += pixel.a.uint32
          next.data[y * next.width + x] = rgbx(
            (channels[0] div 4).uint8, (channels[1] div 4).uint8,
            (channels[2] div 4).uint8, (channels[3] div 4).uint8)
      level = next
      inc mip
