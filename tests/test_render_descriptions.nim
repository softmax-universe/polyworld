import
  std/tables,
  polyworld/[renderdescriptions, pixelformats],
  polyworld/backends/native/[drawtypes, formats]

let
  layout = renderdescriptions.VertexLayout(stride: 12, attributes: @[
    renderdescriptions.VertexAttribute(name: "position", format: Float2),
    renderdescriptions.VertexAttribute(name: "color", format: Unorm8x4,
      offset: 8)
  ])
  state = renderdescriptions.DrawState(depthTest: true, depthWrite: true,
    depthCompare: LessEqual, cull: CullBack, blend: PremultipliedAlpha,
    primitive: Triangles, stencilTest: true, stencilReference: 3,
    stencilCompare: Equal)
  nativeLayout: drawtypes.VertexLayout = layout
  nativeState: drawtypes.DrawState = state
  nativeFormat: formats.TextureFormat = pixelformats.Rgba16f

doAssert nativeLayout == layout
doAssert nativeState == state
doAssert nativeFormat.pixelBytes() == 8
for (format, bytes) in [
  (R8, 1), (Rg8, 2), (Rgba8, 4), (Bgra8, 4), (R32f, 4),
  (Rg32f, 8), (Rgba16f, 8), (Rgba32f, 16)
]:
  doAssert format.pixelBytes() == bytes

let
  defaultState = SamplerState()
  ordinary = linearSampler()
  anisotropic = linearSampler(maxAnisotropy = 8)
  repeated = linearSampler(repeat = true)

doAssert defaultState.samplerAnisotropy() == 1
doAssert ordinary.samplerAnisotropy() == 1
doAssert anisotropic.samplerAnisotropy() == 8
doAssert anisotropic.samplerAnisotropy(4) == 4
doAssert anisotropic.samplerAnisotropy(1) == 1
doAssert linearSampler(maxAnisotropy = 99).samplerAnisotropy() == 16
doAssert linearSampler(maxAnisotropy = 0).samplerAnisotropy() == 1
doAssert linearSampler(maxAnisotropy = -1).samplerAnisotropy() == 1
doAssert repeated.wrapS == Repeat and repeated.wrapT == Repeat and
  repeated.wrapR == Repeat

for mode in 0 ..< 4:
  var filtered = anisotropic
  case mode
  of 0: filtered.minLinear = false
  of 1: filtered.magLinear = false
  of 2: filtered.mipLinear = false
  else: filtered.mipmaps = false
  doAssert filtered.samplerAnisotropy() == 1

var
  descriptions: Table[SamplerState, int]
  comparison = anisotropic
  wrapped = anisotropic
comparison.comparison = true
wrapped.wrapS = MirrorRepeat
wrapped.wrapT = Repeat
wrapped.wrapR = ClampEdge
for index, description in [ordinary, anisotropic, comparison, wrapped]:
  descriptions[description] = index
doAssert descriptions.len == 4
doAssert descriptions[comparison] == 2
doAssert descriptions[wrapped] == 3

echo "Shared draw descriptions, pixel formats, and sampler policies passed"
