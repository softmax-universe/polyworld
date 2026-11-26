## API-independent draw, layout, shader, and texture sampling descriptions.

type
  IndexRange* = tuple[first, count: int]
  VertexFormat* = enum
    Float1, Float2, Float3, Float4, UInt1, UInt2, UInt3, UInt4, Unorm8x4
  VertexAttribute* = object
    name*: string
    format*: VertexFormat
    offset*: int
  VertexLayout* = object
    stride*: int
    attributes*: seq[VertexAttribute]
  DepthCompare* = enum
    LessEqual, Less, Always, Equal, Greater
  CullMode* = enum
    CullNone, CullBack, CullFront
  BlendMode* = enum
    Opaque, AlphaBlend, PremultipliedAlpha, Additive, Multiply,
    StraightAlpha, AlphaBlendPreserveAlpha
  Primitive* = enum
    Triangles, Lines, Points, TriangleStrip
  DrawState* = object
    depthTest*, depthWrite*: bool
    depthCompare*: DepthCompare
    cull*: CullMode
    blend*: BlendMode
    primitive*: Primitive
    wireframe*: bool
    stencilTest*, stencilWrite*: bool
    stencilReference*: int
    stencilCompare*: DepthCompare
  TextureAddress* = enum
    ClampEdge, Repeat, MirrorRepeat
  SamplerState* = object
    minLinear*, magLinear*, mipLinear*, mipmaps*, comparison*: bool
    wrapS*, wrapT*, wrapR*: TextureAddress
    maxAnisotropy*: int
  ShaderInput* = object
    name*, semantic*: string
    location*: int
  ProgramCode* = object
    vertex*, fragment*: string
    inputs*: seq[ShaderInput]

proc linearSampler*(linear = true, repeat = false, mipmaps = true,
    comparison = false, maxAnisotropy = 1): SamplerState =
  ## Describes the common uniform-filter sampler without native handles.
  let wrap = if repeat: Repeat else: ClampEdge
  SamplerState(minLinear: linear, magLinear: linear, mipLinear: linear,
    mipmaps: mipmaps, comparison: comparison, wrapS: wrap, wrapT: wrap,
    wrapR: wrap, maxAnisotropy: maxAnisotropy)

proc samplerAnisotropy*(state: SamplerState, limit = 16): int =
  ## Limits anisotropic filtering to supported, fully linear mip sampling.
  if not (state.minLinear and state.magLinear and state.mipLinear and
      state.mipmaps):
    return 1
  max(1, min(state.maxAnisotropy, limit))
