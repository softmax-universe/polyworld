import pixie, common

type
  ShapeTexture* = GpuImage
  ShapeGpu = object
    program: ShaderProgram
    vertexBuffer: VertexBuffer
    whiteTexture: GpuImage
