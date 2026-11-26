## Converts authored material sampling to API-independent descriptions.

import gltf, renderdescriptions

proc textureAddress(wrap: TextureWrap): TextureAddress =
  ## Preserves each authored texture axis independently.
  case wrap
  of ClampToEdgeWrap: ClampEdge
  of RepeatWrap: Repeat
  of MirroredRepeatWrap: MirrorRepeat

proc samplingState*(sampler: TextureSampler): SamplerState =
  ## Describes glTF filtering and wrapping without constructing GPU objects.
  SamplerState(
    minLinear: sampler.minFilter in {LinearMinFilter,
      LinearMipmapNearestMinFilter, LinearMipmapLinearMinFilter},
    magLinear: sampler.magFilter != NearestMagFilter,
    mipLinear: sampler.minFilter in {NearestMipmapLinearMinFilter,
      LinearMipmapLinearMinFilter},
    mipmaps: sampler.minFilter notin {NearestMinFilter, LinearMinFilter},
    wrapS: textureAddress(sampler.wrapS),
    wrapT: textureAddress(sampler.wrapT),
    wrapR: ClampEdge,
    maxAnisotropy: 1
  )
