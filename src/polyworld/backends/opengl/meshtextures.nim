## Material texture operations for the shared model preparation and passes.

import gltf, pixie, passapi
import ../../texturesampling

proc uploadTexture*(image: Image, sampling: TextureSampler,
    fallback: GpuImage): GpuImage =
  ## Uploads straight material texels while preserving glTF sampler settings.
  if image == nil:
    return fallback
  let state = sampling.samplingState()
  result = newTexture(image, mipmaps = state.mipmaps)
  result.setTextureSampling(state)

proc newCubeTexture*(faces: array[6, Image]): GpuImage =
  ## Uploads a validated cubemap and generates its complete mip chain.
  if faces[0] == nil:
    raise newException(GpuError, "Cubemap images cannot be nil.")
  let size = faces[0].width
  if size <= 0:
    raise newException(GpuError, "Cubemap images cannot be empty.")
  for face in faces:
    if face == nil or face.width != size or face.height != size:
      raise newException(GpuError,
        "Cubemap faces must be equally sized square images.")
  result = allocateImage(size, size, Rgba8, layers = 6,
    levels = mipCount(size, size), cube = true)
  try:
    for index, image in faces:
      result.uploadLevel(index, 0, size, size, image.data[0].addr)
    result.generateMipmaps()
  except:
    result.destroy()
    raise
