## Metal implementation of the scene pass command interface.
import shady, windy, common
export common

type
  ShaderProgram* = MetalProgram
  VertexBuffer* = MetalBuffer
  GpuImage* = MetalTexture
  GpuError* = PolyworldMetalError

template gpuRenderer*: untyped = metalRenderer
template Rgba16f*: untyped = MTLPixelFormatRGBA16Float
template Rgba8*: untyped = MTLPixelFormatRGBA8Unorm
template nativeStage*(fn, stage: untyped): string = toShader(fn, metalMSL, stage)
proc initNative*(window: Window) = initMetal(window)
proc frameActive*(): bool =
  ## Distinguishes an active scene frame from upload-only command buffers.
  metalRenderer.frameActive

proc setPassSampling*(image: GpuImage, linear = true, repeat = false,
    comparison = false) =
  ## Matches non-anisotropic scene-pass filtering to the other backends.
  if comparison:
    image.setComparisonSampling(linear = linear, anisotropy = 1)
  else:
    image.setTextureSampling(linear = linear, repeat = repeat, anisotropy = 1)
