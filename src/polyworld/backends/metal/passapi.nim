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
proc frameActive*(): bool = not metalRenderer.commandBuffer.isNil
