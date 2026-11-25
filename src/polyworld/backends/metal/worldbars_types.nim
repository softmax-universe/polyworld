import pixie, common

type
  WorldBarTexture* = MetalTexture
  WorldBarGpu = object
    program: MetalProgram
    vertexBuffer: MetalBuffer
    whiteTexture: MetalTexture
