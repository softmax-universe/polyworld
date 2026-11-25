type TextureFormat* = enum
  Rgba8, Rgba16f, Bgra8, Rg32f, Rgba32f, Depth32f, DepthStencil, R8, Rg8, R32f

proc pixelBytes*(format: TextureFormat): int =
  ## Returns the native storage size of one uncompressed texel.
  case format
  of Rgba8, Bgra8, Depth32f, DepthStencil, R32f: 4
  of R8: 1
  of Rg8: 2
  of Rgba16f, Rg32f: 8
  of Rgba32f: 16

type GpuError* = object of CatchableError
