when defined(polyworldGpuValidation): import dx12/vtable
when not defined(windows):
  {.error: "Polyworld's DirectX 12 backend requires Windows.".}

import
  std/tables, dx12, dx12/context, pixie, vmath,
  windy, ../native/[framecounts, allocations, drawtypes, formats, uniforms]

export drawtypes, formats, uniforms

const
  MaxTextures* = 16
  DescriptorCount = 2048

type
  DescriptorKey = array[2 * MaxTextures, tuple[texture: uint64, sampler: pointer]]
  DescriptorPage = ref object
    textures, samplers: ID3D12DescriptorHeap
    offsets: Table[DescriptorKey, int]
    recording: uint64
  FrameStorage = object
    allocator: ID3D12CommandAllocator
    constantsList: ID3D12GraphicsCommandList
    fence: uint64
    uploadPages, uniformPages: seq[UniformPage]
    descriptorPages: seq[DescriptorPage]
  GpuContext* = ref object
    frames: array[2, FrameStorage]
    slot: int
    submitted*, completed*: uint64
    nextImageId: uint64
    when defined(polyworldGpuValidation): infoQueue: pointer
    native: D3D12Context
    resolveList: ID3D12GraphicsCommandList1
    command*: ID3D12GraphicsCommandList
    root: ID3D12RootSignature
    descriptorPage: int
    descriptorSize, samplerSize: uint32
    activeTarget: GpuTarget
    activePage: DescriptorPage
    activeProgram: GpuProgram
    recording: uint64
    uploadPage, uploadOffset: int
    uniformPage, uniformOffset: int

  GpuTexture* = ref object
    id: uint64
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
    size*, capacity*: int
    offset: int
    state: uint32
    lastCommand: uint64

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
    resource, local: ID3D12Resource
    mapped: pointer
    capacity: int

  GpuEncoder* = object
    ctx: GpuContext
    target: GpuTarget
    program: GpuProgram
    textures: array[2 * MaxTextures, GpuTexture]
    samplers: array[2 * MaxTextures, GpuSampler]
    vertex, fragment: GpuConstants

proc closePass(ctx: GpuContext)
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
  result.frames[0].allocator = result.native.commandAllocator
  result.frames[1].allocator = result.native.device.createCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT)
  for frame in result.frames.mitems:
    frame.constantsList = result.native.device.createCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT, frame.allocator, nil)
    frame.constantsList.close()
  when defined(polyworldGpuValidation):
    const QueueId = newGuid(0x0742a90b'u32, 0xc387, 0x483f,
      0xb9, 0x46, 0x30, 0xa7, 0xe4, 0xe6, 0x14, 0x58)
    result.infoQueue = queryInterface[pointer](result.native.device, QueueId.addr)
  const List1 = newGuid(0x553103fb'u32, 0x1fe7, 0x4557, 0xbb, 0x38, 0x94, 0x6d, 0x7d, 0x0e, 0x7c, 0xa7)
  result.resolveList = queryInterface[ID3D12GraphicsCommandList1](result.native.commandList, List1.addr)
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

proc awaitFence(ctx: GpuContext, value: uint64) =
  ctx.completed = ctx.native.fence.getCompletedValue()
  if ctx.completed < value:
    ctx.native.fence.setEventOnCompletion(value, cast[pointer](ctx.native.fenceEvent))
    timedWait: discard WaitForSingleObject(ctx.native.fenceEvent, WAIT_INFINITE)
    ctx.completed = ctx.native.fence.getCompletedValue()

proc beginFrame*(ctx: GpuContext) =
  ## Wait for this allocator only when both frame slots are in flight.
  if ctx == nil or ctx.native.device == nil:
    raise newException(GpuError, "DirectX context has been destroyed")
  if ctx.command != nil:
    raise newException(GpuError, "A DirectX frame is already active")
  ctx.awaitFence(ctx.frames[ctx.slot].fence)
  let allocator = ctx.frames[ctx.slot].allocator
  allocator.reset()
  ctx.native.commandList.reset(allocator, nil)
  ctx.command = ctx.native.commandList
  ctx.activePage = nil
  ctx.activeProgram = nil
  ctx.command.setGraphicsRootSignature(ctx.root)
  inc ctx.recording
  ctx.uploadPage = 0
  ctx.uploadOffset = 0
  ctx.descriptorPage = 0
  ctx.uniformPage = 0
  ctx.uniformOffset = 0

proc submitFrame*(ctx: GpuContext) =
  ## Queue one completed list and retire its storage behind a fence.
  if ctx == nil or ctx.command == nil:
    return
  ctx.closePass()
  counted: inc submits
  ctx.command.close()
  let frame = addr ctx.frames[ctx.slot]
  var lists = [cast[ID3D12CommandList](ctx.command), cast[ID3D12CommandList](ctx.command)]
  var listCount = 1'u32
  if ctx.uniformOffset > 0:
    # All constants are now final. Copy the occupied pages before executing
    # the draw list, in the same ExecuteCommandLists call and fence epoch.
    let uploads = frame.constantsList
    uploads.reset(frame.allocator, nil)
    for i in 0 .. ctx.uniformPage:
      let page = addr frame.uniformPages[i]
      let bytes = if i == ctx.uniformPage: ctx.uniformOffset else: UniformPageBytes
      # New buffers start in COPY_DEST. Reused buffers decay to COMMON
      # between submissions and promote for the copy.
      uploads.copyBufferRegion(page.local, 0, page.resource, 0, bytes.uint64)
      var barrier = D3D12_RESOURCE_BARRIER(typ: D3D12_RESOURCE_BARRIER_TYPE_TRANSITION,
        data: D3D12_RESOURCE_BARRIER_union(Transition: D3D12_RESOURCE_TRANSITION_BARRIER(
          pResource: page.local, Subresource: D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
          StateBefore: D3D12_RESOURCE_STATE_COPY_DEST, StateAfter: D3D12_RESOURCE_STATE_VERTEX_AND_CONSTANT_BUFFER)))
      uploads.resourceBarrier(1, barrier.addr)
    uploads.close()
    lists[0] = cast[ID3D12CommandList](uploads)
    listCount = 2
  ctx.native.commandQueue.executeCommandLists(listCount, lists[0].addr)
  ctx.command = nil
  ctx.submitted = ctx.native.fenceValue
  inc ctx.native.fenceValue
  ctx.native.commandQueue.signal(ctx.native.fence, ctx.submitted)
  ctx.frames[ctx.slot].fence = ctx.submitted
  ctx.slot = (ctx.slot + 1) mod ctx.frames.len
  ctx.native.device.getDeviceRemovedReason()
  ctx.checkValidation()

proc finishFrame*(ctx: GpuContext) =
  if ctx == nil: return
  ctx.submitFrame()
  ctx.awaitFence(ctx.submitted)

proc destroy*(ctx: GpuContext) =
  ## Finishes submitted work before releasing its native context.
  if ctx == nil or ctx.native.device == nil:
    return
  ctx.finishFrame()
  for frame in ctx.frames.mitems:
    for page in frame.uploadPages:
      page.resource.unmap(0, nil)
      page.resource.release()
    frame.constantsList.release()
    for page in frame.uniformPages:
      page.local.release()
      page.resource.unmap(0, nil)
      page.resource.release()
    for page in frame.descriptorPages:
      page.textures.release()
      page.samplers.release()
  ctx.frames[1].allocator.release()
  when defined(polyworldGpuValidation): ctx.infoQueue.release()
  ctx.resolveList.release()
  ctx.root.release()
  ctx.native.cleanup()

proc buffer(ctx: GpuContext, size: int, kind: uint32): ID3D12Resource =
  counted: inc bufferCreates
  ## Selects the initial state for default, upload, and readback heaps.
  var
    heap = D3D12_HEAP_PROPERTIES(typ: kind,
      CreationNodeMask: 1, VisibleNodeMask: 1)
    desc = D3D12_RESOURCE_DESC(Dimension: D3D12_RESOURCE_DIMENSION_BUFFER,
      Width: max(256, size).uint64, Height: 1, DepthOrArraySize: 1,
      MipLevels: 1, SampleDesc: DXGI_SAMPLE_DESC(Count: 1),
      Layout: D3D12_TEXTURE_LAYOUT_ROW_MAJOR)
  result = ctx.native.device.createCommittedResource(heap.addr, 0, desc.addr,
    (if kind != D3D12_HEAP_TYPE_UPLOAD: D3D12_RESOURCE_STATE_COPY_DEST
      else: D3D12_RESOURCE_STATE_GENERIC_READ), nil)

proc uploadUniform(ctx: GpuContext, data: GpuConstants): uint64 =
  ## Copies one immutable draw snapshot into retained aligned upload storage.
  let
    bytes = data.words.len * sizeof(uint32)
    reserved = alignedBytes(max(1, bytes), 256)
  if reserved > 64 * 1024:
    raise newException(GpuError, "DirectX uniform block exceeds 64 KiB")
  if ctx.uniformOffset + reserved > UniformPageBytes:
    inc ctx.uniformPage
    ctx.uniformOffset = 0
  if ctx.uniformPage == ctx.frames[ctx.slot].uniformPages.len:
    var page = UniformPage(resource: ctx.buffer(UniformPageBytes, D3D12_HEAP_TYPE_UPLOAD))
    try:
      page.resource.map(0, nil, page.mapped.addr)
      page.local = ctx.buffer(UniformPageBytes, D3D12_HEAP_TYPE_DEFAULT)
    except Exception:
      page.resource.release()
      raise
    ctx.frames[ctx.slot].uniformPages.add(page)
  let
    page = ctx.frames[ctx.slot].uniformPages[ctx.uniformPage]
    destination = cast[pointer](cast[uint](page.mapped) + ctx.uniformOffset.uint)
  if bytes > 0:
    copyMem(destination, data.words[0].unsafeAddr, bytes)
  result = page.local.getGPUVirtualAddress() + ctx.uniformOffset.uint64
  ctx.uniformOffset += reserved

proc uploadSlice(ctx: GpuContext, bytes, alignment: int): tuple[resource: ID3D12Resource, mapped: pointer, offset: int] =
  var offset = alignedBytes(ctx.uploadOffset, alignment)
  while ctx.uploadPage < ctx.frames[ctx.slot].uploadPages.len and offset + bytes > ctx.frames[ctx.slot].uploadPages[ctx.uploadPage].capacity:
    inc ctx.uploadPage
    offset = 0
  if ctx.uploadPage == ctx.frames[ctx.slot].uploadPages.len:
    let capacity = max(4 * 1024 * 1024, alignedBytes(bytes, 65536))
    var page = UniformPage(resource: ctx.buffer(capacity, D3D12_HEAP_TYPE_UPLOAD), capacity: capacity)
    page.resource.map(0, nil, page.mapped.addr)
    ctx.frames[ctx.slot].uploadPages.add page
  let page = ctx.frames[ctx.slot].uploadPages[ctx.uploadPage]
  ctx.uploadOffset = offset + bytes
  (page.resource, cast[pointer](cast[uint](page.mapped) + offset.uint), offset)

proc streamVertices*[T](ctx: GpuContext, view: var GpuBuffer, values: openArray[T]) =
  let bytes = values.len * sizeof(T)
  let slice = ctx.uploadSlice(bytes, 16)
  copyMem(slice.mapped, values[0].unsafeAddr, bytes)
  if view == nil: view = GpuBuffer(ctx: ctx)
  view.resource = slice.resource
  view.offset = slice.offset
  view.size = bytes

proc writeBuffer*[T](buffer: GpuBuffer, values: openArray[T]) =
  let ctx = buffer.ctx
  let bytes = values.len * sizeof(T)
  buffer.size = bytes
  if bytes == 0: return
  let ownFrame = ctx.command == nil
  if ownFrame: ctx.beginFrame()
  let upload = ctx.uploadSlice(bytes, 16)
  copyMem(upload.mapped, values[0].unsafeAddr, bytes)
  # Buffers decay to COMMON at the end of each submitted command list.
  let before = if buffer.lastCommand == ctx.recording: buffer.state else: D3D12_RESOURCE_STATE_COMMON
  template transition(a, b: uint32) =
    var barrier = D3D12_RESOURCE_BARRIER(typ: D3D12_RESOURCE_BARRIER_TYPE_TRANSITION,
      data: D3D12_RESOURCE_BARRIER_union(Transition: D3D12_RESOURCE_TRANSITION_BARRIER(
        pResource: buffer.resource, Subresource: D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
        StateBefore: a, StateAfter: b)))
    ctx.command.resourceBarrier(1, barrier.addr)
  if before != D3D12_RESOURCE_STATE_COPY_DEST: transition(before, D3D12_RESOURCE_STATE_COPY_DEST)
  ctx.command.copyBufferRegion(buffer.resource, 0, upload.resource, upload.offset.uint64, bytes.uint64)
  buffer.state = D3D12_RESOURCE_STATE_VERTEX_AND_CONSTANT_BUFFER or D3D12_RESOURCE_STATE_INDEX_BUFFER
  buffer.lastCommand = ctx.recording
  transition(D3D12_RESOURCE_STATE_COPY_DEST, buffer.state)
  if ownFrame: ctx.finishFrame()

proc uploadBuffer*[T](ctx: GpuContext, values: openArray[T], capacity = 0): GpuBuffer =
  if values.len == 0: return nil
  let bytes = max(capacity, values.len * sizeof(T))
  let ownFrame = ctx.command == nil
  if ownFrame: ctx.beginFrame()
  result = GpuBuffer(ctx: ctx, capacity: bytes, lastCommand: ctx.recording,
    state: D3D12_RESOURCE_STATE_COPY_DEST, resource: ctx.buffer(bytes, D3D12_HEAP_TYPE_DEFAULT))
  result.writeBuffer(values)
  if ownFrame: ctx.finishFrame()

proc transition(texture: GpuTexture, state: uint32) =
  if texture.state == state: return
  var barrier = D3D12_RESOURCE_BARRIER(typ: D3D12_RESOURCE_BARRIER_TYPE_TRANSITION,
    data: D3D12_RESOURCE_BARRIER_union(Transition: D3D12_RESOURCE_TRANSITION_BARRIER(
      pResource: texture.resource, Subresource: D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
      StateBefore: texture.state, StateAfter: state)))
  counted: inc barriers
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
  ctx.closePass()
  let upload = ctx.uploadSlice(total.int, 512)
  let mapped = upload.mapped
  for y in 0 ..< height:
    copyMem(cast[pointer](cast[uint](mapped) +
      footprint.Offset.uint + y.uint * footprint.Footprint.RowPitch.uint),
      cast[pointer](cast[uint](data) + (y * width * bytesPerPixel).uint),
      width * bytesPerPixel)
  footprint.Offset += upload.offset.uint64
  texture.transition(D3D12_RESOURCE_STATE_COPY_DEST)
  var
    destination = D3D12_TEXTURE_COPY_LOCATION(pResource: texture.resource,
      typ: D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX,
      data: D3D12_TEXTURE_COPY_LOCATION_UNION(SubresourceIndex: subresource.uint32))
    source = D3D12_TEXTURE_COPY_LOCATION(pResource: upload.resource,
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
  counted: inc textureCreates
  inc ctx.nextImageId
  result = GpuTexture(ctx: ctx, id: ctx.nextImageId, width: width, height: height, layers: layers, arrayTexture: arrayTexture, cube: cube,
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
  if ctx.activeTarget == target and not (clearColor or clearDepth or clearStencil): return
  ctx.closePass()
  ctx.activeTarget = target
  counted: inc passCount
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

proc closePass(ctx: GpuContext) =
  let t = ctx.activeTarget
  ctx.activeTarget = GpuTarget()
  if t.resolveColor != nil:
    t.texture.transition(D3D12_RESOURCE_STATE_RESOLVE_SOURCE)
    t.resolveColor.transition(D3D12_RESOURCE_STATE_RESOLVE_DEST)
    ctx.command.resolveSubresource(t.resolveColor.resource, 0, t.texture.resource, 0, t.format.nativeFormat)
  if t.resolveDepth != nil:
    t.depth.transition(D3D12_RESOURCE_STATE_RESOLVE_SOURCE)
    t.resolveDepth.transition(D3D12_RESOURCE_STATE_RESOLVE_DEST)
    ctx.resolveList.resolveSubresourceRegion(t.resolveDepth.resource, 0, 0, 0,
      t.depth.resource, 0, nil, (if t.depth.format == DepthStencil: DXGI_FORMAT_R32_FLOAT_X8X24_TYPELESS else: DXGI_FORMAT_R32_FLOAT), D3D12_RESOLVE_MODE_MIN)
    if t.depth.format == DepthStencil:
      ctx.resolveList.resolveSubresourceRegion(t.resolveDepth.resource, 1, 0, 0,
        t.depth.resource, 1, nil, DXGI_FORMAT_X32_TYPELESS_G8X24_UINT, D3D12_RESOLVE_MODE_MAX)

proc endPass*(encoder: GpuEncoder) =
  discard # Resolve once when the target is consumed or replaced.

proc createSampler*(ctx: GpuContext, state: SamplerState): GpuSampler =
  ## Translates shared sampling intent to a Direct3D descriptor.
  const address = [D3D12_TEXTURE_ADDRESS_MODE_CLAMP, D3D12_TEXTURE_ADDRESS_MODE_WRAP,
    D3D12_TEXTURE_ADDRESS_MODE_MIRROR]
  let anisotropy = state.samplerAnisotropy()
  var filter = (state.minLinear.uint32 shl D3D12_MIN_FILTER_SHIFT) or
    (state.magLinear.uint32 shl D3D12_MAG_FILTER_SHIFT) or state.mipLinear.uint32 or
    (state.comparison.uint32 shl D3D12_FILTER_REDUCTION_TYPE_SHIFT)
  if anisotropy > 1:
    filter = if state.comparison: D3D12_FILTER_COMPARISON_ANISOTROPIC
      else: D3D12_FILTER_ANISOTROPIC
  GpuSampler(desc: D3D12_SAMPLER_DESC(Filter: filter, AddressU: address[state.wrapS.ord],
    AddressV: address[state.wrapT.ord], AddressW: address[state.wrapR.ord],
    MaxAnisotropy: anisotropy.uint32,
    ComparisonFunc: D3D12_COMPARISON_FUNC_LESS_EQUAL,
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
  if program == encoder.ctx.activeProgram: return
  encoder.ctx.activeProgram = program
  encoder.ctx.command.setPipelineState(program.pipeline)
  encoder.ctx.command.iaSetPrimitiveTopology(program.topology)

proc setTexture*(encoder: var GpuEncoder, texture: GpuTexture, index: uint) =
  ## Records the sampled texture for the next draw's descriptor table.
  encoder.textures[index] = texture

proc setSampler*(encoder: var GpuEncoder, sampler: GpuSampler, index: uint) =
  ## Records the sampler for the next draw's descriptor table.
  encoder.samplers[index] = sampler

proc markRead(buffer: GpuBuffer, state: uint32) =
  # A buffer promotes from COMMON on its first read of a new command list.
  if buffer.lastCommand != buffer.ctx.recording:
    buffer.lastCommand = buffer.ctx.recording
    buffer.state = state
  else:
    buffer.state = buffer.state or state

proc setVertices*(encoder: GpuEncoder, buffer: GpuBuffer, offset, index: int) =
  buffer.markRead(D3D12_RESOURCE_STATE_VERTEX_AND_CONSTANT_BUFFER)
  ## Binds the pipeline's tightly packed reusable vertex stream.
  let stride = encoder.program.stride
  var view = D3D12_VERTEX_BUFFER_VIEW(
    BufferLocation: buffer.resource.getGPUVirtualAddress() + (buffer.offset + offset).uint64,
    SizeInBytes: (buffer.size - offset).uint32,
    StrideInBytes: stride.uint32)
  encoder.ctx.command.iaSetVertexBuffers(0, 1, view.addr)

proc bindConstants*(ctx: GpuContext, encoder: var GpuEncoder,
  vertex, fragment: GpuConstants) =
  ## Borrows uniform blocks until the draw copies their bytes.
  encoder.vertex = vertex
  encoder.fragment = fragment

proc drawNative*(encoder: GpuEncoder, first, count, instances: int, indices: GpuBuffer, index32: bool, state: DrawState, ranges: openArray[IndexRange]) =
  ## Binds bounded descriptors and immutable uniforms before a native draw.
  let ctx = encoder.ctx
  var key: DescriptorKey
  for i in 0 ..< key.len:
    let texture = encoder.textures[i]
    if texture != nil:
      texture.transition(D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE or D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE)
      key[i] = (texture.id, cast[pointer](encoder.samplers[i]))
  while ctx.descriptorPage < ctx.frames[ctx.slot].descriptorPages.len:
    let page = ctx.frames[ctx.slot].descriptorPages[ctx.descriptorPage]
    if page.offsets.len < DescriptorCount div key.len or key in page.offsets: break
    if page.recording != ctx.recording:
      page.offsets.clear() # This slot's fence retired the previous contents.
      break
    inc ctx.descriptorPage
  if ctx.descriptorPage == ctx.frames[ctx.slot].descriptorPages.len:
    ctx.frames[ctx.slot].descriptorPages.add DescriptorPage(
      textures: ctx.heap(D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV, DescriptorCount, true),
      samplers: ctx.heap(D3D12_DESCRIPTOR_HEAP_TYPE_SAMPLER, DescriptorCount, true))
  let page = ctx.frames[ctx.slot].descriptorPages[ctx.descriptorPage]
  page.recording = ctx.recording
  if page != ctx.activePage:
    var heaps = [page.textures, page.samplers]
    ctx.command.setDescriptorHeaps(2, heaps[0].addr)
    ctx.activePage = page
  for i, data in [encoder.vertex, encoder.fragment]:
    ctx.command.setGraphicsRootConstantBufferView(i.uint32,
      ctx.uploadUniform(data))
  var offset = page.offsets.getOrDefault(key, -1)
  if offset < 0:
    offset = page.offsets.len * key.len
    page.offsets[key] = offset
    for i in 0 ..< 2 * MaxTextures:
      let texture = encoder.textures[i]
      if texture == nil:
        continue
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
      let handle = offsetHandle(page.textures.getCPUDescriptorHandleForHeapStart(),
        ctx.descriptorSize, offset + i)
      ctx.native.device.createShaderResourceView(texture.resource, desc.addr, handle)
      if encoder.samplers[i] != nil:
        var sampler = encoder.samplers[i].desc
        ctx.native.device.createSampler(sampler.addr,
          offsetHandle(page.samplers.getCPUDescriptorHandleForHeapStart(),
            ctx.samplerSize, offset + i))
  var
    textures = page.textures.getGPUDescriptorHandleForHeapStart()
    samplers = page.samplers.getGPUDescriptorHandleForHeapStart()
  textures.ptrValue += offset.uint64 * ctx.descriptorSize.uint64
  samplers.ptrValue += offset.uint64 * ctx.samplerSize.uint64
  ctx.command.setGraphicsRootDescriptorTable(2, textures)
  ctx.command.setGraphicsRootDescriptorTable(3, samplers)
  textures.ptrValue += MaxTextures.uint64 * ctx.descriptorSize.uint64
  samplers.ptrValue += MaxTextures.uint64 * ctx.samplerSize.uint64
  ctx.command.setGraphicsRootDescriptorTable(4, textures)
  ctx.command.setGraphicsRootDescriptorTable(5, samplers)
  ctx.command.omSetStencilRef(state.stencilReference.uint32)
  if indices == nil:
    ctx.command.drawInstanced(count.uint32, instances.uint32, first.uint32, 0)
  else:
    indices.markRead(D3D12_RESOURCE_STATE_INDEX_BUFFER)
    var view = D3D12_INDEX_BUFFER_VIEW(BufferLocation: indices.resource.getGPUVirtualAddress(),
      SizeInBytes: indices.size.uint32, Format: (if index32: DXGI_FORMAT_R32_UINT else: DXGI_FORMAT_R16_UINT))
    ctx.command.iaSetIndexBuffer(view.addr)
    if ranges.len == 0:
      ctx.command.drawIndexedInstanced(count.uint32, instances.uint32, first.uint32, 0, 0)
    else:
      for span in ranges:
        ctx.command.drawIndexedInstanced(span.count.uint32, instances.uint32, span.first.uint32, 0, 0)

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
  source.ctx.closePass()
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
  ctx.submitFrame()
  ctx.native.swapChain.present(if window.vsync: 1 else: 0, 0)
  ctx.native.currentFrame = ctx.native.swapChain.getCurrentBackBufferIndex().int

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
