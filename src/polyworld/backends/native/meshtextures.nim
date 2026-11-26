## Material sampling and environment cubemap uploads.
import pixie, gltf, common, ../../texturesampling

proc uploadTexture*(image: Image, sampler: TextureSampler,
    fallback: GpuImage): GpuImage =
  ## Preserves glTF's straight texture bytes and authored sampling behavior.
  if image == nil:
    return fallback
  let state = sampler.samplingState()
  result = newTexture(image, mipmaps = state.mipmaps)
  result.setTextureSampling(state)

proc newCubeTexture*(faces: array[6, Image]): GpuImage =
  let size = faces[0].width
  result = allocateImage(size, size, Rgba8, layers = 6, levels = mipCount(size, size), cube = true)
  for face, image in faces:
    result.uploadImage(image, face)
