## Material sampling and environment cubemap uploads.
import pixie, gltf, common

proc uploadTexture*(image: Image, sampler: TextureSampler,
    fallback: GpuImage): GpuImage =
  ## Preserves glTF's straight texture bytes and authored sampling behavior.
  if image == nil:
    return fallback
  proc address(wrap: TextureWrap): TextureAddress =
    case wrap
    of ClampToEdgeWrap: ClampEdge
    of RepeatWrap: Repeat
    of MirroredRepeatWrap: MirrorRepeat
  let mipmaps = sampler.minFilter notin {NearestMinFilter, LinearMinFilter}
  result = newTexture(image, mipmaps = mipmaps)
  result.sampling = SamplerState(wrapS: address(sampler.wrapS), wrapT: address(sampler.wrapT),
    magLinear: sampler.magFilter != NearestMagFilter, mipmaps: mipmaps,
    minLinear: sampler.minFilter in {LinearMinFilter, LinearMipmapNearestMinFilter, LinearMipmapLinearMinFilter},
    mipLinear: sampler.minFilter in {NearestMipmapLinearMinFilter, LinearMipmapLinearMinFilter})

proc newCubeTexture*(faces: array[6, Image]): GpuImage =
  let size = faces[0].width
  result = allocateImage(size, size, Rgba8, layers = 6, levels = mipCount(size, size), cube = true)
  for face, image in faces:
    result.uploadImage(image, face)
