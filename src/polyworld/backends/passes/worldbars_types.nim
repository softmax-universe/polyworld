import pixie, common

type
  WorldBarTexture* = GpuImage
  WorldBarGpu = object
    program: ShaderProgram
    vertexBuffer: VertexBuffer
    whiteTexture: GpuImage
