when defined(polyworldGpuValidation): import dx12/vtable
when not defined(windows):
  {.error: "Polyworld's DirectX 12 backend requires Windows.".}

import
  dx12, dx12/context, pixie, vmath,
  windy, ../native/[allocations, drawtypes, formats, uniforms]

export drawtypes, formats, uniforms

const
  MaxTextures* = 16
  DescriptorCount = 2048

type
  GpuContext* = ref object
    when defined(polyworldGpuValidation): infoQueue: pointer
    native: D3D12Context
    resolveList: ID3D12GraphicsCommandList1
    command*: ID3D12GraphicsCommandList
    root: ID3D12RootSignature
    textures, samplers: ID3D12DescriptorHeap
    descriptorSize, samplerSize: uint32
    cursor: int
    transient: seq[ID3D12Resource]
    uniformPages: seq[UniformPage]
    uniformPage, uniformOffset: int

  GpuTexture* = ref object
    ctx: GpuContext
    resource: ID3D12Resource
    desc: D3D12_RESOURCE_DESC
    heap: ID3D12DescriptorHeap
    state: uint32
    width*, height*, mipLevels*, baseMip: int
    format*: TextureFormat
    layers*: int
    arrayTexture*, cube*: bool

  GpuBuffer* = ref object
    ctx: GpuContext
    resource: ID3D12Resource
    size: int

  GpuSampler* = ref object
    desc: D3D12_SAMPLER_DESC

  GpuProgram* = ref object
    ctx: GpuContext
    pipeline: ID3D12PipelineState
    stride: int
    topology: uint32

  GpuTarget* = object
    texture*, depth*, resolveColor*, resolveDepth*: GpuTexture
    width*, height*: int
    format*: TextureFormat

  UniformPage = object
    resource: ID3D12Resource
    mapped: pointer

  GpuEncoder* = object
    ctx: GpuContext
    target: GpuTarget
    program: GpuProgram
    textures: array[2 * MaxTextures, GpuTexture]
    samplers: array[2 * MaxTextures, GpuSampler]
    vertex, fragment: GpuConstants

proc finishFrame*(ctx: GpuContext)
proc beginFrame*(ctx: GpuContext)

when defined(polyworldGpuValidation):
  proc enableValidation() =
    ## Enables the installed native DirectX debug layer before device creation.
    proc getDebug(iid: ptr DXGuid, output: ptr pointer): int32
      {.stdcall, dynlib: "d3d12.dll", importc: "D3D12GetDebugInterface".}
    const DebugId = newGuid(0x344488b7'u32, 0x6846, 0x474b,
      0xb9, 0x89, 0xf0, 0x27, 0x44, 0x82, 0x45, 0xe0)
    var debug: pointer
    if getDebug(DebugId.addr, debug.addr) < 0:
      raise newException(GpuError, "The DirectX debug layer is unavailable")
    defer: debug.release()
    type Enable = proc(self: pointer) {.stdcall.}
    callVtbl0(debug, 3, Enable)

proc checkValidation(ctx: GpuContext) =
  ## Reads native debug messages and rejects frames containing API errors.
  when defined(polyworldGpuValidation):
    type
      Message = object
        category, severity, id: uint32
        description: cstring
        length: csize_t
      Count = proc(self: pointer): uint64 {.stdcall.}
      Get = proc(self: pointer, index: uint64, message: ptr Message,
        size: ptr csize_t): int32 {.stdcall.}
      Clear = proc(self: pointer) {.stdcall.}
    var errors: string
    let count = callVtbl0(ctx.infoQueue, 8, Count)
    for i in 0'u64 ..< count:
      var size: csize_t
      discard callVtbl(ctx.infoQueue, 5, Get, i, nil, size.addr)
      var bytes = newSeq[uint8](size)
      let message = cast[ptr Message](bytes[0].addr)
      if callVtbl(ctx.infoQueue, 5, Get, i, message, size.addr) >= 0 and
        message.severity <= 2:
          stderr.writeLine($message.description)
          if message.severity <= 1:
            errors.add($message.description & "\n")
    callVtbl0(ctx.infoQueue, 4, Clear)
    if errors.len > 0:
      raise newException(GpuError, "DirectX validation failed:\n" & errors)

proc nativeFormat(format: TextureFormat): uint32 =
  ## Maps shared storage formats to their unmodified DirectX equivalents.
  case format
  of Rgba8: DXGI_FORMAT_R8G8B8A8_UNORM
  of Rgba16f: DXGI_FORMAT_R16G16B16A16_FLOAT
  of Bgra8: DXGI_FORMAT_B8G8R8A8_UNORM
  of Rg32f: DXGI_FORMAT_R32G32_FLOAT
  of Rgba32f: DXGI_FORMAT_R32G32B32A32_FLOAT
  of Depth32f: DXGI_FORMAT_D32_FLOAT
  of DepthStencil: DXGI_FORMAT_D32_FLOAT_S8X24_UINT
  of R8: DXGI_FORMAT_R8_UNORM
  of Rg8: DXGI_FORMAT_R8G8_UNORM
  of R32f: DXGI_FORMAT_R32_FLOAT

proc freeGpu*[T](value: var T) =
  ## Releases a native resource once and clears its owning reference.
  if value == nil:
    return
  var resume = false
  when T is GpuTexture or T is GpuBuffer or T is GpuProgram:
    resume = value.ctx.command != nil
    value.ctx.finishFrame()
    let context = value.ctx
  when T is GpuTexture:
    if value.heap != nil:
      value.heap.release()
      value.heap = nil
    if value.resource != nil:
      value.resource.release()
    value.resource = nil
  elif T is GpuBuffer:
    if value.resource != nil:
      value.resource.release()
      value.resource = nil
  elif T is GpuProgram:
    if value.pipeline != nil:
      value.pipeline.release()
      value.pipeline = nil
  when T is GpuTexture or T is GpuBuffer or T is GpuProgram:
    if resume:
      context.beginFrame()
  value = nil

proc heap(ctx: GpuContext, kind, count: uint32,
  visible = false): ID3D12DescriptorHeap =
  ## Allocates a descriptor heap with explicit shader visibility.
  var desc = D3D12_DESCRIPTOR_HEAP_DESC(typ: kind,
    NumDescriptors: count,
    Flags: (if visible: D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE else: 0))
  result = ctx.native.device.createDescriptorHeap(desc.addr)

proc newGpuContext*(window: windy.Window): GpuContext =
  result = GpuContext()
  when defined(polyworldGpuValidation): enableValidation()
  result.native.initDevice(window.getHwnd(), window.size.x, window.size.y)
  when defined(polyworldGpuValidation):
    const QueueId = newGuid(0x0742a90b'u32, 0xc387, 0x483f,
      0xb9, 0x46, 0x30, 0xa7, 0xe4, 0xe6, 0x14, 0x58)
    result.infoQueue = queryInterface[pointer](result.native.device, QueueId.addr)
  const List1 = newGuid(0x553103fb'u32, 0x1fe7, 0x4557, 0xbb, 0x38, 0x94, 0x6d, 0x7d, 0x0e, 0x7c, 0xa7)
  result.resolveList = queryInterface[ID3D12GraphicsCommandList1](result.native.commandList, List1.addr)
  result.textures = result.heap(D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV,
    DescriptorCount, true)
  result.samplers = result.heap(D3D12_DESCRIPTOR_HEAP_TYPE_SAMPLER,
    DescriptorCount, true)
  result.descriptorSize = result.native.device.getDescriptorHandleIncrementSize(
    D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV)
  result.samplerSize = result.native.device.getDescriptorHandleIncrementSize(
    D3D12_DESCRIPTOR_HEAP_TYPE_SAMPLER)
  var
    textureRange = D3D12_DESCRIPTOR_RANGE(
      RangeType: D3D12_DESCRIPTOR_RANGE_TYPE_SRV, NumDescriptors: MaxTextures)
    samplerRange = D3D12_DESCRIPTOR_RANGE(
      RangeType: D3D12_DESCRIPTOR_RANGE_TYPE_SAMPLER, NumDescriptors: MaxTextures)
    vertexTextureRange = textureRange
    vertexSamplerRange = samplerRange
    parameters: array[6, D3D12_ROOT_PARAMETER]
  for i in 0 .. 1:
    parameters[i] = D3D12_ROOT_PARAMETER(
      ParameterType: D3D12_ROOT_PARAMETER_TYPE_CBV,
      data: D3D12_ROOT_PARAMETER_UNION(Descriptor:
        D3D12_ROOT_DESCRIPTOR(ShaderRegister: i.uint32, RegisterSpace: 1)),
      ShaderVisibility: (if i == 0: D3D12_SHADER_VISIBILITY_VERTEX
        else: D3D12_SHADER_VISIBILITY_PIXEL))
  vertexTextureRange.RegisterSpace = 2
  vertexSamplerRange.RegisterSpace = 2
  for i, range in [textureRange.addr, samplerRange.addr, vertexTextureRange.addr, vertexSamplerRange.addr]:
    parameters[i + 2] = D3D12_ROOT_PARAMETER(
      ParameterType: D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE,
      data: D3D12_ROOT_PARAMETER_UNION(DescriptorTable:
        D3D12_ROOT_DESCRIPTOR_TABLE(NumDescriptorRanges: 1,
          pDescriptorRanges: range)),
      ShaderVisibility: (if i < 2: D3D12_SHADER_VISIBILITY_PIXEL else: D3D12_SHADER_VISIBILITY_VERTEX))
  var desc = D3D12_ROOT_SIGNATURE_DESC(NumParameters: 6,
    pParameters: parameters[0].addr,
    Flags: D3D12_ROOT_SIGNATURE_FLAG_ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT)
  let blob = serializeRootSignature(desc.addr)
  defer: blob.release()
  result.root = result.native.device.createRootSignature(0,
    blob.getBufferPointer(), blob.getBufferSize())

proc beginFrame*(ctx: GpuContext) =
  ## Starts one command list after the preceding frame completed.
  if ctx == nil or ctx.native.device == nil:
    raise newException(GpuError, "DirectX context has been destroyed")
  if ctx.command != nil:
    raise newException(GpuError, "A DirectX frame is already active")
  ctx.native.commandAllocator.reset()
  ctx.native.commandList.reset(ctx.native.commandAllocator, nil)
  ctx.command = ctx.native.commandList
  ctx.cursor = 0
  ctx.uniformPage = 0
  ctx.uniformOffset = 0

proc finishFrame*(ctx: GpuContext) =
  ## Submits the list and retains transient uploads until fence completion.
  if ctx == nil or ctx.command == nil:
    return
  ctx.command.close()
  var command = cast[ID3D12CommandList](ctx.command)
  ctx.native.commandQueue.executeCommandLists(1, command.addr)
  ctx.command = nil
  ctx.native.waitForGpu()
  ctx.native.device.getDeviceRemovedReason()
  for resource in ctx.transient:
    resource.release()
  ctx.transient.setLen(0)
  ctx.checkValidation()

proc destroy*(ctx: GpuContext) =
  ## Finishes submitted work before releasing its native context.
  if ctx == nil or ctx.native.device == nil:
    return
  ctx.finishFrame()
  for page in ctx.uniformPages.mitems:
    page.resource.unmap(0, nil)
    page.resource.release()
  ctx.uniformPages.setLen(0)
  when defined(polyworldGpuValidation): ctx.infoQueue.release()
  ctx.resolveList.release()
  ctx.root.release()
  ctx.textures.release()
  ctx.samplers.release()
  ctx.native.cleanup()

proc buffer(ctx: GpuContext, size: int, kind: uint32): ID3D12Resource =
  ## Allocates host-visible upload or readback storage.
  var
    heap = D3D12_HEAP_PROPERTIES(typ: kind,
      CreationNodeMask: 1, VisibleNodeMask: 1)
    desc = D3D12_RESOURCE_DESC(Dimension: D3D12_RESOURCE_DIMENSION_BUFFER,
      Width: max(256, size).uint64, Height: 1, DepthOrArraySize: 1,
      MipLevels: 1, SampleDesc: DXGI_SAMPLE_DESC(Count: 1),
      Layout: D3D12_TEXTURE_LAYOUT_ROW_MAJOR)
  result = ctx.native.device.createCommittedResource(heap.addr, 0, desc.addr,
    (if kind == D3D12_HEAP_TYPE_READBACK: D3D12_RESOURCE_STATE_COPY_DEST
      else: D3D12_RESOURCE_STATE_GENERIC_READ), nil)

proc uploadUniform(ctx: GpuContext, data: GpuConstants): uint64 =
  ## Copies one immutable draw snapshot into retained aligned upload storage.
  let
    bytes = data.words.len * sizeof(uint32)
    reserved = alignedBytes(max(1, bytes), 256)
  if reserved > UniformPageBytes:
    raise newException(GpuError, "DirectX uniform block exceeds 64 KiB")
  if ctx.uniformOffset + reserved > UniformPageBytes:
    inc ctx.uniformPage
    ctx.uniformOffset = 0
  if ctx.uniformPage >= MaxUniformPages:
    raise newException(GpuError, "DirectX uniform arena capacity exceeded")
  if ctx.uniformPage == ctx.uniformPages.len:
    var page = UniformPage(resource:
      ctx.buffer(UniformPageBytes, D3D12_HEAP_TYPE_UPLOAD))
    try:
      page.resource.map(0, nil, page.mapped.addr)
    except Exception:
      page.resource.release()
      raise
    ctx.uniformPages.add(page)
  let
    page = ctx.uniformPages[ctx.uniformPage]
    destination = cast[pointer](cast[uint](page.mapped) + ctx.uniformOffset.uint)
  zeroMem(destination, reserved)
  if bytes > 0:
    copyMem(destination, data.words[0].unsafeAddr, bytes)
  result = page.resource.getGPUVirtualAddress() + ctx.uniformOffset.uint64
  ctx.uniformOffset += reserved

proc uploadBuffer*[T](ctx: GpuContext, values: openArray[T]): GpuBuffer =
  ## Copies reusable vertex values into an immutable upload allocation.
  if values.len == 0:
    return nil
  result = GpuBuffer(ctx: ctx, size: values.len * sizeof(T),
    resource: ctx.buffer(values.len * sizeof(T), D3D12_HEAP_TYPE_UPLOAD))
  var mapped: pointer
  result.resource.map(0, nil, mapped.addr)
  copyMem(mapped, values[0].unsafeAddr, values.len * sizeof(T))
  result.resource.unmap(0, nil)

proc transition(texture: GpuTexture, state: uint32) =
  if texture.state == state: return
  var barrier = D3D12_RESOURCE_BARRIER(typ: D3D12_RESOURCE_BARRIER_TYPE_TRANSITION,
    data: D3D12_RESOURCE_BARRIER_union(Transition: D3D12_RESOURCE_TRANSITION_BARRIER(
      pResource: texture.resource, Subresource: D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
      StateBefore: texture.state, StateAfter: state)))
  texture.ctx.command.resourceBarrier(1, barrier.addr)
  texture.state = state

proc uploadLevel*(texture: GpuTexture, layer, level, width, height, bytesPerPixel: int, data: pointer) =
  let ctx = texture.ctx
  let format = texture.format
  if layer notin 0 ..< texture.layers or level notin 0 ..< texture.mipLevels or
      width != max(1, texture.width shr level) or height != max(1, texture.height shr level):
    raise newException(GpuError, "Invalid texture subresource")
  let subresource = layer * texture.mipLevels + level
  var desc = texture.desc
  if bytesPerPixel != format.pixelBytes:
    raise newException(GpuError, "Incorrect DirectX texture row format")
  let ownFrame = ctx.command == nil
  if ownFrame:
    ctx.beginFrame()
  var
    footprint: D3D12_PLACED_SUBRESOURCE_FOOTPRINT
    rows: uint32
    rowSize, total: uint64
  ctx.native.device.getCopyableFootprints(desc.addr, subresource.uint32, 1, 0,
    footprint.addr, rows.addr, rowSize.addr, total.addr)
  let upload = ctx.buffer(total.int, D3D12_HEAP_TYPE_UPLOAD)
  ctx.transient.add(upload)
  var mapped: pointer
  upload.map(0, nil, mapped.addr)
  zeroMem(mapped, total.int)
  for y in 0 ..< height:
    copyMem(cast[pointer](cast[uint](mapped) +
      footprint.Offset.uint + y.uint * footprint.Footprint.RowPitch.uint),
      cast[pointer](cast[uint](data) + (y * width * bytesPerPixel).uint),
      width * bytesPerPixel)
  upload.unmap(0, nil)
  texture.transition(D3D12_RESOURCE_STATE_COPY_DEST)
  var
    destination = D3D12_TEXTURE_COPY_LOCATION(pResource: texture.resource,
      typ: D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX,
      data: D3D12_TEXTURE_COPY_LOCATION_UNION(SubresourceIndex: subresource.uint32))
    source = D3D12_TEXTURE_COPY_LOCATION(pResource: upload,
      typ: D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT,
      data: D3D12_TEXTURE_COPY_LOCATION_UNION(PlacedFootprint: footprint))
  ctx.command.copyTextureRegion(destination.addr, 0, 0, 0, source.addr, nil)
  texture.transition(D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE or D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE)
  if ownFrame:
    ctx.finishFrame()

proc newTexture*(ctx: GpuContext, width, height: int,
  format: TextureFormat, data: pointer = nil, bytesPerPixel = 4,
  mipLevels = 1, layers = 1, arrayTexture = false, cube = false, samples = 1): GpuTexture =
  ## Allocates bounded native texture storage and uploads its first level.
  if width < 1 or height < 1 or width > 16384 or height > 16384 or
    width.int64 * height.int64 * format.pixelBytes > 512 * 1024 * 1024:
      raise newException(GpuError, "DirectX texture dimensions exceed limits")
  result = GpuTexture(ctx: ctx, width: width, height: height, layers: layers, arrayTexture: arrayTexture, cube: cube,
    mipLevels: mipLevels, format: format)
  var
    heap = D3D12_HEAP_PROPERTIES(typ: D3D12_HEAP_TYPE_DEFAULT,
      CreationNodeMask: 1, VisibleNodeMask: 1)
    desc = D3D12_RESOURCE_DESC(Dimension: D3D12_RESOURCE_DIMENSION_TEXTURE2D,
      Width: width.uint64, Height: height.uint32, DepthOrArraySize: layers.uint16,
      MipLevels: mipLevels.uint16, Format: (case format
        of DepthStencil: DXGI_FORMAT_R32G8X24_TYPELESS
        of Depth32f: DXGI_FORMAT_R32_TYPELESS
        else: format.nativeFormat),
      SampleDesc: DXGI_SAMPLE_DESC(Count: samples.uint32),
      Flags: (if format in {Depth32f, DepthStencil}: D3D12_RESOURCE_FLAG_ALLOW_DEPTH_STENCIL
        else: D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET))
  result.desc = desc
  result.resource = ctx.native.device.createCommittedResource(heap.addr,
    0, desc.addr, D3D12_RESOURCE_STATE_COMMON, nil)
  let heapKind = if format in {Depth32f, DepthStencil}: D3D12_DESCRIPTOR_HEAP_TYPE_DSV
    else: D3D12_DESCRIPTOR_HEAP_TYPE_RTV
  result.heap = ctx.heap(heapKind, 1)
  let handle = result.heap.getCPUDescriptorHandleForHeapStart()
  if format in {Depth32f, DepthStencil}:
    var dsv = D3D12_DEPTH_STENCIL_VIEW_DESC(Format: format.nativeFormat, ViewDimension: (if samples == 1: D3D12_DSV_DIMENSION_TEXTURE2D else: D3D12_DSV_DIMENSION_TEXTURE2DMS))
    ctx.native.device.createDepthStencilView(result.resource, dsv.addr, handle)
  else:
    ctx.native.device.createRenderTargetView(result.resource, nil, handle)
  if data != nil:
    result.uploadLevel(0, 0, width, height, bytesPerPixel, data)

proc owns*(ctx: GpuContext, target: GpuTarget): bool =
  ctx != nil and (target.texture != nil or target.depth != nil) and
    (target.texture == nil or target.texture.ctx == ctx) and
    (target.depth == nil or target.depth.ctx == ctx)

proc beginPass*(ctx: GpuContext, target: GpuTarget,
  clearColor = false, clearDepth = false, color = Color(), clearStencil = false): GpuEncoder =
  ## Binds attachments and defines explicit load and clear behavior.
  if not ctx.owns(target) or ctx.command == nil:
    raise newException(GpuError, "A DirectX frame and target are required")
  result = GpuEncoder(ctx: ctx, target: target)
  var
    rtv: D3D12_CPU_DESCRIPTOR_HANDLE
    dsv: D3D12_CPU_DESCRIPTOR_HANDLE
  if target.texture != nil:
    target.texture.transition(D3D12_RESOURCE_STATE_RENDER_TARGET)
    rtv = target.texture.heap.getCPUDescriptorHandleForHeapStart()
  if target.depth != nil:
    target.depth.transition(D3D12_RESOURCE_STATE_DEPTH_WRITE)
    dsv = target.depth.heap.getCPUDescriptorHandleForHeapStart()
  ctx.command.omSetRenderTargets(uint32(target.texture != nil), rtv.addr, 0,
    (if target.depth == nil: nil else: dsv.addr))
  var
    viewport = D3D12_VIEWPORT(Width: target.width.float32,
      Height: target.height.float32, MaxDepth: 1)
    scissor = D3D12_RECT(right: target.width.int32, bottom: target.height.int32)
  ctx.command.rsSetViewports(1, viewport.addr)
  ctx.command.rsSetScissorRects(1, scissor.addr)
  if clearColor and target.texture != nil:
    var clear = [color.r, color.g,
      color.b, color.a]
    ctx.command.clearRenderTargetView(rtv, clear[0].addr, 0, nil)
  if (clearDepth or clearStencil) and target.depth != nil:
    let flags = uint32(clearDepth) or (uint32(clearStencil and target.depth.format == DepthStencil) shl 1)
    ctx.command.clearDepthStencilView(dsv, flags, 1, 0, 0, nil)

proc endPass*(encoder: GpuEncoder) =
  ## Ends the logical pass before a subsequent target transition.
  let t = encoder.target
  if t.resolveColor != nil:
    t.texture.transition(D3D12_RESOURCE_STATE_RESOLVE_SOURCE)
    t.resolveColor.transition(D3D12_RESOURCE_STATE_RESOLVE_DEST)
    encoder.ctx.command.resolveSubresource(t.resolveColor.resource, 0, t.texture.resource, 0, t.format.nativeFormat)
  if t.resolveDepth != nil:
    t.depth.transition(D3D12_RESOURCE_STATE_RESOLVE_SOURCE)
    t.resolveDepth.transition(D3D12_RESOURCE_STATE_RESOLVE_DEST)
    encoder.ctx.resolveList.resolveSubresourceRegion(t.resolveDepth.resource, 0, 0, 0,
      t.depth.resource, 0, nil, (if t.depth.format == DepthStencil: DXGI_FORMAT_R32_FLOAT_X8X24_TYPELESS else: DXGI_FORMAT_R32_FLOAT), D3D12_RESOLVE_MODE_MIN)
    if t.depth.format == DepthStencil:
      encoder.ctx.resolveList.resolveSubresourceRegion(t.resolveDepth.resource, 1, 0, 0,
        t.depth.resource, 1, nil, DXGI_FORMAT_X32_TYPELESS_G8X24_UINT, D3D12_RESOLVE_MODE_MAX)

proc createSampler*(ctx: GpuContext, state: SamplerState): GpuSampler =
  const address = [D3D12_TEXTURE_ADDRESS_MODE_CLAMP, D3D12_TEXTURE_ADDRESS_MODE_WRAP,
    D3D12_TEXTURE_ADDRESS_MODE_MIRROR]
  let filter = (state.minLinear.uint32 shl D3D12_MIN_FILTER_SHIFT) or
    (state.magLinear.uint32 shl D3D12_MAG_FILTER_SHIFT) or state.mipLinear.uint32 or
    (state.comparison.uint32 shl D3D12_FILTER_REDUCTION_TYPE_SHIFT)
  GpuSampler(desc: D3D12_SAMPLER_DESC(Filter: filter, AddressU: address[state.wrapS.ord],
    AddressV: address[state.wrapT.ord], AddressW: address[state.wrapR.ord],
    MaxAnisotropy: 1, ComparisonFunc: D3D12_COMPARISON_FUNC_LESS_EQUAL,
    MaxLOD: (if state.mipmaps: 1000'f else: 0'f)))

proc newPipeline*(ctx: GpuContext, code: ProgramCode, layout: VertexLayout,
    state: DrawState, color, depth: TextureFormat, hasColor, hasDepth: bool, samples: int): GpuProgram =
  var attributes: seq[D3D12_INPUT_ELEMENT_DESC]
  const formats = [DXGI_FORMAT_R32_FLOAT, DXGI_FORMAT_R32G32_FLOAT,
    DXGI_FORMAT_R32G32B32_FLOAT, DXGI_FORMAT_R32G32B32A32_FLOAT,
    DXGI_FORMAT_R32_UINT, DXGI_FORMAT_R32G32_UINT, DXGI_FORMAT_R32G32B32_UINT,
    DXGI_FORMAT_R32G32B32A32_UINT, DXGI_FORMAT_R8G8B8A8_UNORM]
  for input in code.inputs:
    for attribute in layout.attributes:
      if attribute.name == input.name:
        attributes.add D3D12_INPUT_ELEMENT_DESC(SemanticName: input.semantic.cstring,
          SemanticIndex: input.location.uint32, Format: formats[attribute.format.ord],
          AlignedByteOffset: attribute.offset.uint32)
  const compares = [D3D12_COMPARISON_FUNC_LESS_EQUAL, D3D12_COMPARISON_FUNC_LESS,
    D3D12_COMPARISON_FUNC_ALWAYS, D3D12_COMPARISON_FUNC_EQUAL, D3D12_COMPARISON_FUNC_GREATER]
  let vertex = code.vertex
  let fragment = code.fragment
  let stencil = D3D12_DEPTH_STENCILOP_DESC(
    StencilFailOp: D3D12_STENCIL_OP_KEEP,
    StencilDepthFailOp: D3D12_STENCIL_OP_KEEP,
    StencilPassOp: (if state.stencilWrite: D3D12_STENCIL_OP_REPLACE else: D3D12_STENCIL_OP_KEEP),
    StencilFunc: compares[state.stencilCompare.ord])
  var desc = D3D12_GRAPHICS_PIPELINE_STATE_DESC(
    pRootSignature: ctx.root,
    VS: D3D12_SHADER_BYTECODE(pShaderBytecode: cast[pointer](vertex.cstring),
      BytecodeLength: vertex.len.csize_t),
    PS: D3D12_SHADER_BYTECODE(pShaderBytecode: (if fragment.len == 0: nil else: cast[pointer](fragment.cstring)),
      BytecodeLength: fragment.len.csize_t),
    SampleMask: D3D12_DEFAULT_SAMPLE_MASK,
    RasterizerState: D3D12_RASTERIZER_DESC(
      FillMode: (if state.wireframe: D3D12_FILL_MODE_WIREFRAME else: D3D12_FILL_MODE_SOLID),
      FrontCounterClockwise: 1, CullMode: [D3D12_CULL_MODE_NONE, D3D12_CULL_MODE_BACK, D3D12_CULL_MODE_FRONT][state.cull.ord],
      MultisampleEnable: int32(samples > 1), DepthClipEnable: 1),
    DepthStencilState: D3D12_DEPTH_STENCIL_DESC(
      DepthEnable: int32(hasDepth and state.depthTest),
      StencilEnable: int32(hasDepth and depth == DepthStencil and state.stencilTest),
      DepthWriteMask: (if state.depthWrite:
        D3D12_DEPTH_WRITE_MASK_ALL else: D3D12_DEPTH_WRITE_MASK_ZERO),
      DepthFunc: compares[state.depthCompare.ord],
      StencilReadMask: 255, StencilWriteMask: 255,
      FrontFace: stencil, BackFace: stencil),
    PrimitiveTopologyType: [D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE, D3D12_PRIMITIVE_TOPOLOGY_TYPE_LINE, D3D12_PRIMITIVE_TOPOLOGY_TYPE_POINT, D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE][state.primitive.ord],
    NumRenderTargets: uint32(hasColor), SampleDesc: DXGI_SAMPLE_DESC(Count: samples.uint32),
    DSVFormat: (if hasDepth: depth.nativeFormat else: DXGI_FORMAT_UNKNOWN))
  if hasColor: desc.RTVFormats[0] = color.nativeFormat
  desc.BlendState.RenderTarget[0] = D3D12_RENDER_TARGET_BLEND_DESC(
    BlendEnable: int32(state.blend != Opaque), SrcBlend: D3D12_BLEND_ONE,
    DestBlend: D3D12_BLEND_INV_SRC_ALPHA,
    BlendOp: D3D12_BLEND_OP_ADD,
    SrcBlendAlpha: D3D12_BLEND_ONE, DestBlendAlpha: D3D12_BLEND_INV_SRC_ALPHA,
    BlendOpAlpha: D3D12_BLEND_OP_ADD,
    RenderTargetWriteMask: 15)
  desc.BlendState.RenderTarget[0].SrcBlend = (if state.blend == PremultipliedAlpha: D3D12_BLEND_ONE elif state.blend == Multiply: D3D12_BLEND_DEST_COLOR else: D3D12_BLEND_SRC_ALPHA)
  desc.BlendState.RenderTarget[0].DestBlend = (if state.blend == Additive: D3D12_BLEND_ONE elif state.blend == Multiply: D3D12_BLEND_ZERO else: D3D12_BLEND_INV_SRC_ALPHA)
  desc.BlendState.RenderTarget[0].SrcBlendAlpha = (if state.blend in {AlphaBlendPreserveAlpha, Additive, Multiply}: D3D12_BLEND_ZERO elif state.blend == StraightAlpha: D3D12_BLEND_SRC_ALPHA else: D3D12_BLEND_ONE)
  desc.BlendState.RenderTarget[0].DestBlendAlpha = (if state.blend in {AlphaBlendPreserveAlpha, Additive, Multiply}: D3D12_BLEND_ONE else: D3D12_BLEND_INV_SRC_ALPHA)
  if attributes.len > 0:
    desc.InputLayout = D3D12_INPUT_LAYOUT_DESC(
      pInputElementDescs: attributes[0].addr, NumElements: attributes.len.uint32)
  result = GpuProgram(ctx: ctx, stride: layout.stride, topology: [4'u32, 2, 1, 5][state.primitive.ord])
  try:
    result.pipeline = ctx.native.device.createGraphicsPipelineState(desc.addr)
  except Exception:
    ctx.checkValidation()
    raise

proc setProgram*(encoder: var GpuEncoder, program: GpuProgram) =
  ## Selects one immutable native pipeline for subsequent draws.
  encoder.program = program
  encoder.ctx.command.setPipelineState(program.pipeline)
  encoder.ctx.command.setGraphicsRootSignature(encoder.ctx.root)
  encoder.ctx.command.iaSetPrimitiveTopology(program.topology)

proc setTexture*(encoder: var GpuEncoder, texture: GpuTexture, index: uint) =
  ## Records the sampled texture for the next draw's descriptor table.
  encoder.textures[index] = texture

proc setSampler*(encoder: var GpuEncoder, sampler: GpuSampler, index: uint) =
  ## Records the sampler for the next draw's descriptor table.
  encoder.samplers[index] = sampler

proc setVertices*(encoder: GpuEncoder, buffer: GpuBuffer, offset, index: int) =
  ## Binds the pipeline's tightly packed reusable vertex stream.
  let stride = encoder.program.stride
  var view = D3D12_VERTEX_BUFFER_VIEW(
    BufferLocation: buffer.resource.getGPUVirtualAddress() + offset.uint64,
    SizeInBytes: (buffer.size - offset).uint32,
    StrideInBytes: stride.uint32)
  encoder.ctx.command.iaSetVertexBuffers(0, 1, view.addr)

proc bindConstants*(ctx: GpuContext, encoder: var GpuEncoder,
  vertex, fragment: GpuConstants) =
  ## Borrows uniform blocks until the draw copies their bytes.
  encoder.vertex = vertex
  encoder.fragment = fragment

proc drawNative*(encoder: GpuEncoder, first, count, instances: int, indices: GpuBuffer, index32: bool, state: DrawState) =
  ## Binds bounded descriptors and immutable uniforms before a native draw.
  let ctx = encoder.ctx
  if ctx.cursor + 2 * MaxTextures > DescriptorCount:
    raise newException(GpuError, "DirectX frame descriptor capacity exceeded")
  var heaps = [ctx.textures, ctx.samplers]
  ctx.command.setDescriptorHeaps(2, heaps[0].addr)
  for i, data in [encoder.vertex, encoder.fragment]:
    ctx.command.setGraphicsRootConstantBufferView(i.uint32,
      ctx.uploadUniform(data))
  for i in 0 ..< 2 * MaxTextures:
    let texture = encoder.textures[i]
    if texture == nil:
      continue
    texture.transition(D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE)
    var desc = D3D12_SHADER_RESOURCE_VIEW_DESC(
      Format: texture.format.nativeFormat,
      ViewDimension: D3D12_SRV_DIMENSION_TEXTURE2D,
      Shader4ComponentMapping: D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING,
      data: D3D12_SHADER_RESOURCE_VIEW_DESC_UNION(Texture2D:
        D3D12_TEX2D_SRV(MostDetailedMip: texture.baseMip.uint32,
          MipLevels: texture.mipLevels.uint32)))
    case texture.format
    of DepthStencil: desc.Format = DXGI_FORMAT_R32_FLOAT_X8X24_TYPELESS
    of Depth32f: desc.Format = DXGI_FORMAT_R32_FLOAT
    else: discard
    if texture.cube:
      desc.ViewDimension = D3D12_SRV_DIMENSION_TEXTURECUBE
      desc.data.TextureCube = D3D12_TEXCUBE_SRV(MipLevels: texture.mipLevels.uint32)
    elif texture.arrayTexture:
      desc.ViewDimension = D3D12_SRV_DIMENSION_TEXTURE2DARRAY
      desc.data.Texture2DArray = D3D12_TEX2D_ARRAY_SRV(MipLevels: texture.mipLevels.uint32, ArraySize: texture.layers.uint32)
    let handle = offsetHandle(ctx.textures.getCPUDescriptorHandleForHeapStart(),
      ctx.descriptorSize, ctx.cursor + i)
    ctx.native.device.createShaderResourceView(texture.resource, desc.addr, handle)
    if encoder.samplers[i] != nil:
      var sampler = encoder.samplers[i].desc
      ctx.native.device.createSampler(sampler.addr,
        offsetHandle(ctx.samplers.getCPUDescriptorHandleForHeapStart(),
          ctx.samplerSize, ctx.cursor + i))
  var
    textures = ctx.textures.getGPUDescriptorHandleForHeapStart()
    samplers = ctx.samplers.getGPUDescriptorHandleForHeapStart()
  textures.ptrValue += ctx.cursor.uint64 * ctx.descriptorSize.uint64
  samplers.ptrValue += ctx.cursor.uint64 * ctx.samplerSize.uint64
  ctx.command.setGraphicsRootDescriptorTable(2, textures)
  ctx.command.setGraphicsRootDescriptorTable(3, samplers)
  textures.ptrValue += MaxTextures.uint64 * ctx.descriptorSize.uint64
  samplers.ptrValue += MaxTextures.uint64 * ctx.samplerSize.uint64
  ctx.command.setGraphicsRootDescriptorTable(4, textures)
  ctx.command.setGraphicsRootDescriptorTable(5, samplers)
  ctx.cursor += 2 * MaxTextures
  ctx.command.omSetStencilRef(state.stencilReference.uint32)
  if indices == nil:
    ctx.command.drawInstanced(count.uint32, instances.uint32, first.uint32, 0)
  else:
    var view = D3D12_INDEX_BUFFER_VIEW(BufferLocation: indices.resource.getGPUVirtualAddress(),
      SizeInBytes: indices.size.uint32, Format: (if index32: DXGI_FORMAT_R32_UINT else: DXGI_FORMAT_R16_UINT))
    ctx.command.iaSetIndexBuffer(view.addr)
    ctx.command.drawIndexedInstanced(count.uint32, instances.uint32, first.uint32, 0, 0)

proc readImage*(ctx: GpuContext, target: GpuTarget): Image =
  ## Reads completed premultiplied RGBA8 rows without a presentation surface.
  if not ctx.owns(target):
    raise newException(GpuError, "Invalid DirectX readback target")
  ctx.finishFrame()
  if target.format != Rgba8:
    raise newException(GpuError, "Image readback requires RGBA8")
  var
    desc = D3D12_RESOURCE_DESC(Dimension: D3D12_RESOURCE_DIMENSION_TEXTURE2D,
      Width: target.width.uint64, Height: target.height.uint32,
      DepthOrArraySize: 1, MipLevels: 1, Format: DXGI_FORMAT_R8G8B8A8_UNORM,
      SampleDesc: DXGI_SAMPLE_DESC(Count: 1))
    footprint: D3D12_PLACED_SUBRESOURCE_FOOTPRINT
    rows: uint32
    rowSize, total: uint64
  ctx.native.device.getCopyableFootprints(desc.addr, 0, 1, 0,
    footprint.addr, rows.addr, rowSize.addr, total.addr)
  let readback = ctx.buffer(total.int, D3D12_HEAP_TYPE_READBACK)
  defer: readback.release()
  ctx.beginFrame()
  target.texture.transition(D3D12_RESOURCE_STATE_COPY_SOURCE)
  var
    source = D3D12_TEXTURE_COPY_LOCATION(pResource: target.texture.resource,
      typ: D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX)
    destination = D3D12_TEXTURE_COPY_LOCATION(pResource: readback,
      typ: D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT,
      data: D3D12_TEXTURE_COPY_LOCATION_UNION(PlacedFootprint: footprint))
  ctx.command.copyTextureRegion(destination.addr, 0, 0, 0, source.addr, nil)
  ctx.finishFrame()
  var mapped: pointer
  readback.map(0, nil, mapped.addr)
  defer: readback.unmap(0, nil)
  result = newImage(target.width, target.height)
  for y in 0 ..< target.height:
    copyMem(result.data[y * target.width].addr,
      cast[pointer](cast[uint](mapped) + footprint.Offset.uint +
        y.uint * footprint.Footprint.RowPitch.uint), target.width * 4)

proc copyPixels*(source, destination: GpuTexture) =
  source.transition(D3D12_RESOURCE_STATE_COPY_SOURCE)
  destination.transition(D3D12_RESOURCE_STATE_COPY_DEST)
  source.ctx.command.copyResource(destination.resource, source.resource)

proc present*(ctx: GpuContext, frame: GpuTexture, window: windy.Window) =
  if ctx.native.viewport.Width.int != frame.width or ctx.native.viewport.Height.int != frame.height:
    ctx.finishFrame()
    ctx.native.resize(frame.width, frame.height)
    ctx.beginFrame()
  let buffer = GpuTexture(ctx: ctx, resource: ctx.native.renderTargets[ctx.native.currentFrame],
    state: D3D12_RESOURCE_STATE_PRESENT, mipLevels: 1)
  frame.copyPixels(buffer)
  buffer.transition(D3D12_RESOURCE_STATE_PRESENT)
  ctx.finishFrame()
  ctx.native.swapChain.present(if window.vsync: 1 else: 0, 0)
  ctx.native.moveToNextFrame()

proc applyViewport*(encoder: GpuEncoder, size: IVec2) =
  var viewport = D3D12_VIEWPORT(Width: size.x.float32, Height: size.y.float32, MaxDepth: 1)
  encoder.ctx.command.rsSetViewports(1, viewport.addr)

proc copyMip*(source, dest: GpuTexture, level: int) =
  source.transition(D3D12_RESOURCE_STATE_COPY_SOURCE)
  dest.transition(D3D12_RESOURCE_STATE_COPY_DEST)
  var a = D3D12_TEXTURE_COPY_LOCATION(pResource: source.resource, typ: D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX)
  var b = D3D12_TEXTURE_COPY_LOCATION(pResource: dest.resource, typ: D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX,
    data: D3D12_TEXTURE_COPY_LOCATION_UNION(SubresourceIndex: level.uint32))
  source.ctx.command.copyTextureRegion(b.addr, 0, 0, 0, a.addr, nil)

proc needsSubmission*(ctx: GpuContext): bool =
  ctx.cursor + 2 * MaxTextures > DescriptorCount

proc sampleCount*(ctx: GpuContext, requested: int, color, depth: TextureFormat, hasColor = true, hasDepth = true): int =
  if requested <= 1: return 1
  var formats: seq[uint32]
  if hasColor: formats.add(color.nativeFormat)
  if hasDepth: formats.add(depth.nativeFormat)
  for format in formats:
    var support = D3D12_FEATURE_DATA_FORMAT_SUPPORT(Format: format)
    ctx.native.device.checkFeatureSupport(D3D12_FEATURE_FORMAT_SUPPORT, support.addr, sizeof(support).uint32)
    if (support.Support1 and D3D12_FORMAT_SUPPORT1_MULTISAMPLE_RESOLVE) == 0: return 1
  for samples in [16, 8, 4, 2]:
    if samples > requested: continue
    var supported = true
    for format in formats:
      var info = D3D12_FEATURE_DATA_MULTISAMPLE_QUALITY_LEVELS(Format: format, SampleCount: samples.uint32)
      ctx.native.device.checkFeatureSupport(D3D12_FEATURE_MULTISAMPLE_QUALITY_LEVELS, info.addr, sizeof(info).uint32)
      supported = supported and info.NumQualityLevels > 0
    if supported: return samples
  1
