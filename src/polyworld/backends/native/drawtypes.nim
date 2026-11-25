type
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
  ShaderInput* = object
    name*, semantic*: string
    location*: int
  ProgramCode* = object
    vertex*, fragment*: string
    inputs*: seq[ShaderInput]
