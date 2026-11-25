import pixie, common

type
  ShapeTexture* = MetalTexture
  ShapeGpu = object
    program: MetalProgram
    vertexBuffer: MetalBuffer
    whiteTexture: MetalTexture
