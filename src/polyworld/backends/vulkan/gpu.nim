import
  vk14, vk14/context, pixie, vmath,
  windy, ../native/[framecounts, allocations, drawtypes, formats, uniforms]

export drawtypes, formats, uniforms

const
  MaxTextures* = 16
  MaxDraws = 2048

type
  DrawDescriptors = object
    sets: array[3, VkDescriptorSet]
    images: array[2 * MaxTextures, tuple[id: uint64, sampler: int64]]
    constants: array[2, VkDescriptorBufferInfo]
  FrameStorage = object
    serial: uint64
    uploadPages, uniformPages, transient: seq[GpuBuffer]
    uploads, uniforms: UploadPlan
    drawSets: seq[DrawDescriptors]
    descriptorPools: seq[VkDescriptorPool]
  GpuContext* = ref object
    frames: array[2, FrameStorage]
    slot: int
    submitted*, completed*: uint64
    nextImageId: uint64
    surfaces: seq[GpuTexture]
    presentReady: seq[VkSemaphore]
    presentation: VulkanContext
    instance: VkInstance
    physical: VkPhysicalDevice
    device: VkDevice
    queue: VkQueue
    pool: VkCommandPool
    buffer: VkCommandBuffer
    command*: pointer
    inPass: bool
    activeTarget: GpuTarget
    textureLayout, uniformLayout: VkDescriptorSetLayout
    layout: VkPipelineLayout
    memory: VkPhysicalDeviceMemoryProperties
    uniformAlignment, uniformRange: int
    drawCursor: int

  GpuBuffer* = ref object
    ctx: GpuContext
    buffer: VkBuffer
    memory: VkDeviceMemory
    mapped: pointer
    size*, capacity*: int
    offset: int
    indexBytes: seq[byte]

  GpuTexture* = ref object
    id: uint64
    ctx: GpuContext
    image: VkImage
    memory: VkDeviceMemory
    view, attachment: VkImageView
    layouts: seq[VkImageLayout]
    width*, height*, mipLevels*: int
    format*: TextureFormat
    layers*: int
    arrayTexture*, cube*: bool
    surface: bool

  GpuSampler* = ref object
    ctx: GpuContext
    sampler: VkSampler

  GpuProgram* = ref object
    ctx: GpuContext
    pipeline: VkPipeline

  GpuTarget* = object
    texture*, depth*, resolveColor*, resolveDepth*: GpuTexture
    width*, height*: int
    format*: TextureFormat

  GpuEncoder* = object
    ctx: GpuContext
    target: GpuTarget
    program: GpuProgram
    textures: array[2 * MaxTextures, GpuTexture]
    samplers: array[2 * MaxTextures, GpuSampler]
    vertex, fragment: GpuConstants

proc closePass(ctx: GpuContext) =
  if ctx.inPass:
    vkCmdEndRendering(ctx.buffer)
    ctx.inPass = false
    ctx.activeTarget = GpuTarget()

proc finishFrame*(ctx: GpuContext)
proc beginFrame*(ctx: GpuContext)

proc checked(value: VkResult, operation: string) =
  ## Preserves the native Vulkan result in a library-specific error.
  if value != VK_SUCCESS:
    raise newException(GpuError, operation & ": VkResult " & $value)

proc nativeFormat(format: TextureFormat): VkFormat =
  ## Maps shared texture storage to unmodified Vulkan formats.
  case format
  of Rgba8: VK_FORMAT_R8G8B8A8_UNORM
  of Rgba16f: VK_FORMAT_R16G16B16A16_SFLOAT
  of Bgra8: VK_FORMAT_B8G8R8A8_UNORM
  of Rg32f: VK_FORMAT_R32G32_SFLOAT
  of Rgba32f: VK_FORMAT_R32G32B32A32_SFLOAT
  of Depth32f: VK_FORMAT_D32_SFLOAT
  of DepthStencil: VK_FORMAT_D24_UNORM_S8_UINT
  of R8: VK_FORMAT_R8_UNORM
  of Rg8: VK_FORMAT_R8G8_UNORM
  of R32f: VK_FORMAT_R32_SFLOAT

proc freeGpu*[T](value: var T) =
  ## Releases a completed native allocation and clears its owning reference.
  if value == nil:
    return
  let device = value.ctx.device
  when T is GpuTexture:
    if int64(value.view) != 0:
      vkDestroyImageView(device, value.view, nil)
      vkDestroyImageView(device, value.attachment, nil)
      value.view = VkImageView(0)
    if int64(value.image) != 0:
      vkDestroyImage(device, value.image, nil)
      value.image = VkImage(0)
    if int64(value.memory) != 0:
      vkFreeMemory(device, value.memory, nil)
      value.memory = VkDeviceMemory(0)
  elif T is GpuBuffer:
    if value.mapped != nil:
      vkUnmapMemory(device, value.memory)
    if int64(value.buffer) != 0:
      vkDestroyBuffer(device, value.buffer, nil)
    if int64(value.memory) != 0:
      vkFreeMemory(device, value.memory, nil)
  elif T is GpuProgram:
    vkDestroyPipeline(device, value.pipeline, nil)
  elif T is GpuSampler:
    vkDestroySampler(device, value.sampler, nil)
  value = nil

proc newGpuContext*(window: windy.Window): GpuContext =
  result = GpuContext()
  result.presentation.initDevice(window.getHWND(), window.size.x, window.size.y,
    window.vsync, samplerAnisotropy = true)
  result.instance = result.presentation.instance
  result.physical = result.presentation.physicalDevice
  result.device = result.presentation.device
  result.queue = result.presentation.graphicsQueue
  var properties: VkPhysicalDeviceProperties
  vkGetPhysicalDeviceProperties(result.physical, properties.addr)
  result.uniformAlignment = max(1, properties.limits.minUniformBufferOffsetAlignment.int)
  result.uniformRange = properties.limits.maxUniformBufferRange.int
  vkGetPhysicalDeviceMemoryProperties(result.physical, result.memory.addr)
  var textureBindings: array[MaxTextures * 2, VkDescriptorSetLayoutBinding]
  for i in 0 ..< MaxTextures:
    textureBindings[i] = VkDescriptorSetLayoutBinding(binding: i.uint32,
      descriptorType: VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,
      descriptorCount: 1, stageFlags: VkShaderStageFlags(VK_SHADER_STAGE_FRAGMENT_BIT or VK_SHADER_STAGE_VERTEX_BIT))
    textureBindings[MaxTextures + i] = textureBindings[i]
    textureBindings[MaxTextures + i].binding = (32 + i).uint32
    textureBindings[MaxTextures + i].descriptorType = VK_DESCRIPTOR_TYPE_SAMPLER
  var layout = VkDescriptorSetLayoutCreateInfo(
    sType: VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
    bindingCount: MaxTextures * 2, pBindings: textureBindings[0].addr)
  vkCreateDescriptorSetLayout(result.device, layout.addr, nil,
    result.textureLayout.addr).checked("Create texture layout")
  var uniformBindings: array[2, VkDescriptorSetLayoutBinding]
  for i in 0 ..< 2:
    uniformBindings[i] = VkDescriptorSetLayoutBinding(binding: i.uint32,
      descriptorType: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, descriptorCount: 1,
      stageFlags: VkShaderStageFlags(if i == 0: VK_SHADER_STAGE_VERTEX_BIT
        else: VK_SHADER_STAGE_FRAGMENT_BIT))
  layout.bindingCount = 2
  layout.pBindings = uniformBindings[0].addr
  vkCreateDescriptorSetLayout(result.device, layout.addr, nil,
    result.uniformLayout.addr).checked("Create uniform layout")
  var
    layouts = [result.textureLayout, result.uniformLayout, result.textureLayout]
    pipeline = VkPipelineLayoutCreateInfo(
      sType: VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
      setLayoutCount: 3, pSetLayouts: layouts[0].addr)
  vkCreatePipelineLayout(result.device, pipeline.addr, nil,
    result.layout.addr).checked("Create pipeline layout")

proc descriptorPool(ctx: GpuContext): VkDescriptorPool =
  var
    sizes = [VkDescriptorPoolSize(`type`:
      VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE, descriptorCount: MaxDraws * MaxTextures * 2),
      VkDescriptorPoolSize(`type`: VK_DESCRIPTOR_TYPE_SAMPLER, descriptorCount: MaxDraws * MaxTextures * 2),
      VkDescriptorPoolSize(`type`: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        descriptorCount: MaxDraws * 2)]
    descriptors = VkDescriptorPoolCreateInfo(
      sType: VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
      maxSets: MaxDraws * 3, poolSizeCount: 3, pPoolSizes: sizes[0].addr)
  vkCreateDescriptorPool(ctx.device, descriptors.addr, nil, result.addr).checked("Create descriptor pool")

proc awaitSlot(ctx: GpuContext, slot: int) =
  let serial = ctx.frames[slot].serial
  if serial > ctx.completed:
    let fence = ctx.presentation.inFlightFences[slot]
    let status = vkGetFenceStatus(ctx.device, fence)
    if status == VK_NOT_READY:
      timedWait: vkWaitForFences(ctx.device, 1, fence.unsafeAddr, VK_TRUE, uint64.high).checked("Wait for frame storage")
    else: status.checked("Read frame fence")
    ctx.completed = serial

proc beginFrame*(ctx: GpuContext) =
  ## Resets reusable command and descriptor storage after GPU completion.
  if ctx == nil or int64(ctx.device) == 0:
    raise newException(GpuError, "Vulkan context has been destroyed")
  if ctx.command != nil:
    raise newException(GpuError, "A Vulkan frame is already active")
  ctx.awaitSlot(ctx.slot)
  for buffer in ctx.frames[ctx.slot].transient.mitems: buffer.freeGpu()
  ctx.frames[ctx.slot].transient.setLen(0)
  ctx.buffer = ctx.presentation.commandBuffers[ctx.slot]
  vkResetCommandBuffer(ctx.buffer, VkCommandBufferResetFlags(0)).checked("Reset command buffer")
  ctx.frames[ctx.slot].uniforms.resetUploadPlan()
  ctx.drawCursor = 0
  ctx.frames[ctx.slot].uploads.resetUploadPlan()
  var info = VkCommandBufferBeginInfo(
    sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    flags: VkCommandBufferUsageFlags(VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT))
  vkBeginCommandBuffer(ctx.buffer, info.addr).checked("Begin command buffer")
  ctx.command = cast[pointer](ctx.buffer)

proc submitFrame*(ctx: GpuContext, acquired = VkSemaphore(0), ready = VkSemaphore(0)) =
  if ctx == nil or ctx.command == nil:
    return
  ctx.closePass()
  vkEndCommandBuffer(ctx.buffer).checked("End command buffer")
  var submit = VkSubmitInfo(sType: VK_STRUCTURE_TYPE_SUBMIT_INFO,
    commandBufferCount: 1, pCommandBuffers: ctx.buffer.addr)
  var waitStage = VkPipelineStageFlags(VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT)
  if int64(acquired) != 0:
    submit.waitSemaphoreCount = 1
    submit.pWaitSemaphores = acquired.unsafeAddr
    submit.pWaitDstStageMask = waitStage.addr
    submit.signalSemaphoreCount = 1
    submit.pSignalSemaphores = ready.unsafeAddr
  let fence = ctx.presentation.inFlightFences[ctx.slot]
  vkResetFences(ctx.device, 1, fence.unsafeAddr).checked("Reset frame fence")
  counted: inc submits
  vkQueueSubmit(ctx.queue, 1, submit.addr, fence).checked("Submit frame")
  ctx.command = nil
  inc ctx.submitted
  ctx.frames[ctx.slot].serial = ctx.submitted
  ctx.slot = (ctx.slot + 1) mod ctx.frames.len

proc finishFrame*(ctx: GpuContext) =
  if ctx == nil: return
  ctx.submitFrame()
  ctx.awaitSlot((ctx.slot + ctx.frames.len - 1) mod ctx.frames.len)

proc releaseSurface(ctx: GpuContext) =
  for surface in ctx.surfaces:
    if surface != nil: vkDestroyImageView(ctx.device, surface.attachment, nil)
  for semaphore in ctx.presentReady: vkDestroySemaphore(ctx.device, semaphore, nil)
  ctx.surfaces.setLen(0)
  ctx.presentReady.setLen(0)

proc destroy*(ctx: GpuContext) =
  ## Completes work before releasing the native queue and device resources.
  if ctx == nil:
    return
  ctx.finishFrame()
  if int64(ctx.device) != 0:
    vkDeviceWaitIdle(ctx.device).checked("Drain presentation")
    ctx.releaseSurface()
    for frame in ctx.frames.mitems:
      for page in frame.uploadPages.mitems: page.freeGpu()
      for page in frame.uniformPages.mitems: page.freeGpu()
      for buffer in frame.transient.mitems: buffer.freeGpu()
      for pool in frame.descriptorPools: vkDestroyDescriptorPool(ctx.device, pool, nil)
      frame = FrameStorage()
    vkDestroyPipelineLayout(ctx.device, ctx.layout, nil)
    vkDestroyDescriptorSetLayout(ctx.device, ctx.textureLayout, nil)
    vkDestroyDescriptorSetLayout(ctx.device, ctx.uniformLayout, nil)
    ctx.presentation.cleanup()
    ctx.device = VkDevice(0)

proc memoryType(ctx: GpuContext, bits, flags: uint32): uint32 =
  ## Finds a memory type meeting every required native property.
  for i in 0'u32 ..< ctx.memory.memoryTypeCount:
    if (bits and (1'u32 shl i)) != 0 and
      (ctx.memory.memoryTypes[i].propertyFlags.uint32 and flags) == flags:
        return i
  raise newException(GpuError, "No suitable Vulkan memory type")

proc newBuffer(ctx: GpuContext, size: int, usage: uint32, deviceLocal = false, preferMappedLocal = false): GpuBuffer =
  counted: inc bufferCreates
  ## Allocate device-local geometry or a coherently mapped transfer range.
  result = GpuBuffer(ctx: ctx, size: max(16, size), capacity: max(16, size))
  var
    info = VkBufferCreateInfo(sType: VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
      size: result.size.uint64, usage: VkBufferUsageFlags(usage))
    requirements: VkMemoryRequirements
  vkCreateBuffer(ctx.device, info.addr, nil, result.buffer.addr).checked(
    "Create buffer")
  vkGetBufferMemoryRequirements(ctx.device, result.buffer, requirements.addr)
  var memory = VkMemoryAllocateInfo(sType: VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
    allocationSize: requirements.size, memoryTypeIndex: ctx.memoryType(
      requirements.memoryTypeBits, (if deviceLocal: VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT
      else: VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT or VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)))
  if preferMappedLocal:
    let fallback = memory.memoryTypeIndex
    let flags = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT or VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT or VK_MEMORY_PROPERTY_HOST_COHERENT_BIT
    for i in 0'u32 ..< ctx.memory.memoryTypeCount:
      if (requirements.memoryTypeBits and (1'u32 shl i)) != 0 and
          (ctx.memory.memoryTypes[i].propertyFlags.uint32 and flags) == flags:
        memory.memoryTypeIndex = i
        break
    if vkAllocateMemory(ctx.device, memory.addr, nil, result.memory.addr) != VK_SUCCESS:
      memory.memoryTypeIndex = fallback
      vkAllocateMemory(ctx.device, memory.addr, nil, result.memory.addr).checked("Allocate mapped uniform memory")
  else:
    vkAllocateMemory(ctx.device, memory.addr, nil, result.memory.addr).checked("Allocate buffer memory")
  vkBindBufferMemory(ctx.device, result.buffer, result.memory, 0).checked(
    "Bind buffer memory")
  if not deviceLocal:
    vkMapMemory(ctx.device, result.memory, 0, result.size.uint64, VkMemoryMapFlags(0),
      result.mapped.addr).checked("Map buffer")

proc uploadUniform(ctx: GpuContext, data: GpuConstants): VkDescriptorBufferInfo =
  ## Copies each draw's uniform bytes into a retained device-aligned slice.
  let bytes = max(16, data.words.len * sizeof(uint32))
  if bytes > min(UniformPageBytes, ctx.uniformRange):
    raise newException(GpuError, "Vulkan uniform block exceeds device limits")
  let
    frame = addr ctx.frames[ctx.slot]
    reservation = frame.uniforms.reserveUpload(
      bytes, ctx.uniformAlignment, UniformPageBytes
    )
  if reservation.allocate:
    frame.uniformPages.add(ctx.newBuffer(reservation.capacity,
      VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, preferMappedLocal = true))
  let
    page = frame.uniformPages[reservation.page]
    destination = cast[pointer](cast[uint](page.mapped) + reservation.offset.uint)
  if data.words.len > 0:
    copyMem(destination, data.words[0].unsafeAddr, data.words.len * 4)
  result = VkDescriptorBufferInfo(buffer: page.buffer,
    offset: reservation.offset.uint64, range: bytes.uint64)
  frame.uniforms.commitUpload(reservation)

proc drawDescriptors(ctx: GpuContext): ptr DrawDescriptors =
  ## Reuse descriptor sets only after the owning frame slot retires.
  let poolIndex = ctx.drawCursor div MaxDraws
  if poolIndex == ctx.frames[ctx.slot].descriptorPools.len:
    ctx.frames[ctx.slot].descriptorPools.add ctx.descriptorPool()
  if ctx.drawCursor == ctx.frames[ctx.slot].drawSets.len:
    var
      layouts = [ctx.textureLayout, ctx.uniformLayout, ctx.textureLayout]
      sets: array[3, VkDescriptorSet]
      allocate = VkDescriptorSetAllocateInfo(
        sType: VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        descriptorPool: ctx.frames[ctx.slot].descriptorPools[poolIndex], descriptorSetCount: 3,
        pSetLayouts: layouts[0].addr)
    vkAllocateDescriptorSets(ctx.device, allocate.addr, sets[0].addr).checked(
      "Allocate draw descriptors")
    ctx.frames[ctx.slot].drawSets.add DrawDescriptors(sets: sets)
  result = addr ctx.frames[ctx.slot].drawSets[ctx.drawCursor]
  inc ctx.drawCursor

proc uploadSlice(ctx: GpuContext, bytes, alignment: int): tuple[buffer: VkBuffer, mapped: pointer, offset: int] =
  ## Reserves CPU upload storage while keeping native allocation backend-local.
  let
    frame = addr ctx.frames[ctx.slot]
    reservation = frame.uploads.reserveUpload(
      bytes, alignment, 4 * 1024 * 1024, 65536
    )
  if bytes == 0:
    return
  if reservation.allocate:
    frame.uploadPages.add ctx.newBuffer(reservation.capacity,
      VK_BUFFER_USAGE_TRANSFER_SRC_BIT or VK_BUFFER_USAGE_VERTEX_BUFFER_BIT)
  let page = frame.uploadPages[reservation.page]
  frame.uploads.commitUpload(reservation)
  (page.buffer,
    cast[pointer](cast[uint](page.mapped) + reservation.offset.uint),
    reservation.offset)

proc streamVertices*[T](ctx: GpuContext, view: var GpuBuffer, values: openArray[T]) =
  let bytes = values.len * sizeof(T)
  let slice = ctx.uploadSlice(bytes, 16)
  copyMem(slice.mapped, values[0].unsafeAddr, bytes)
  if view == nil: view = GpuBuffer(ctx: ctx)
  view.buffer = slice.buffer
  view.offset = slice.offset
  view.size = bytes

proc writeBuffer*[T](buffer: GpuBuffer, values: openArray[T]) =
  let ctx = buffer.ctx
  let bytes = values.len * sizeof(T)
  let previousSize = buffer.size
  buffer.size = bytes
  if bytes == 0: return
  when T is SomeInteger:
    buffer.indexBytes.setLen(bytes)
    copyMem(buffer.indexBytes[0].addr, values[0].unsafeAddr, bytes)
  let ownFrame = ctx.command == nil
  if ownFrame: ctx.beginFrame()
  ctx.closePass()
  let upload = ctx.uploadSlice(bytes, 4)
  copyMem(upload.mapped, values[0].unsafeAddr, bytes)
  const reads = VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT or VK_ACCESS_INDEX_READ_BIT
  template barrier(srcStage, dstStage, srcAccess, dstAccess: uint32) =
    var dep = VkBufferMemoryBarrier(sType: VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
      srcAccessMask: VkAccessFlags(srcAccess), dstAccessMask: VkAccessFlags(dstAccess),
      srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED, dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
      buffer: buffer.buffer, size: VK_WHOLE_SIZE)
    vkCmdPipelineBarrier(ctx.buffer, VkPipelineStageFlags(srcStage), VkPipelineStageFlags(dstStage),
      VkDependencyFlags(0), 0, nil, 1, dep.addr, 0, nil)
  if previousSize > 0:
    barrier(VK_PIPELINE_STAGE_VERTEX_INPUT_BIT or VK_PIPELINE_STAGE_TRANSFER_BIT,
      VK_PIPELINE_STAGE_TRANSFER_BIT, reads or VK_ACCESS_TRANSFER_WRITE_BIT, VK_ACCESS_TRANSFER_WRITE_BIT)
  var region = VkBufferCopy(srcOffset: upload.offset.uint64, size: bytes.uint64)
  vkCmdCopyBuffer(ctx.buffer, upload.buffer, buffer.buffer, 1, region.addr)
  barrier(VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_VERTEX_INPUT_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, reads)
  if ownFrame: ctx.finishFrame()

proc uploadBuffer*[T](ctx: GpuContext, values: openArray[T], capacity = 0): GpuBuffer =
  if values.len == 0: return nil
  result = ctx.newBuffer(max(capacity, values.len * sizeof(T)), VK_BUFFER_USAGE_VERTEX_BUFFER_BIT or
    VK_BUFFER_USAGE_INDEX_BUFFER_BIT or VK_BUFFER_USAGE_TRANSFER_DST_BIT, deviceLocal = true)
  result.size = 0
  result.writeBuffer(values)

proc scope(layout: VkImageLayout): tuple[stage, access: uint32] =
  case layout
  of VK_IMAGE_LAYOUT_UNDEFINED: (VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, 0'u32)
  of VK_IMAGE_LAYOUT_PRESENT_SRC_KHR: (VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0'u32)
  of VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL:
    (VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, VK_ACCESS_COLOR_ATTACHMENT_READ_BIT or VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT)
  of VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL:
    # Depth/stencil resolves run at the color attachment output stage.
    (VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT or VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT or VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
      VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT or VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT or VK_ACCESS_COLOR_ATTACHMENT_READ_BIT or VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT)
  of VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL:
    (VK_PIPELINE_STAGE_VERTEX_SHADER_BIT or VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, VK_ACCESS_SHADER_READ_BIT)
  of VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL: (VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_READ_BIT)
  of VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL: (VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT)
  else: (VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, VK_ACCESS_MEMORY_READ_BIT or VK_ACCESS_MEMORY_WRITE_BIT)

proc transition(texture: GpuTexture, layout: VkImageLayout,
  first = 0, count = 0) =
  ## Orders all prior accesses and tracks layout independently for each mip.
  let levels = if count == 0: texture.mipLevels else: count
  for level in first ..< first + levels:
    let old = texture.layouts[level]
    if old == layout and layout == VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL: continue
    texture.ctx.closePass()
    let src = if texture.surface and layout == VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL:
      (stage: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, access: 0'u32)
    else: scope(old)
    let dst = scope(layout)
    # Equal attachment layouts still need write-after-write ordering.
    var barrier = VkImageMemoryBarrier(
      sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
      oldLayout: old, newLayout: layout,
      srcAccessMask: VkAccessFlags(src.access), dstAccessMask: VkAccessFlags(dst.access),
      srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
      dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
      image: texture.image,
      subresourceRange: VkImageSubresourceRange(
        aspectMask: VkImageAspectFlags(if texture.format == DepthStencil: VK_IMAGE_ASPECT_DEPTH_BIT or VK_IMAGE_ASPECT_STENCIL_BIT
          elif texture.format in {Depth32f, DepthStencil}: VK_IMAGE_ASPECT_DEPTH_BIT
          else: VK_IMAGE_ASPECT_COLOR_BIT),
        baseMipLevel: level.uint32, levelCount: 1, layerCount: texture.layers.uint32))
    counted: inc barriers
    vkCmdPipelineBarrier(texture.ctx.buffer, VkPipelineStageFlags(src.stage),
      VkPipelineStageFlags(dst.stage), VkDependencyFlags(0), 0, nil, 0, nil, 1, barrier.addr)
    texture.layouts[level] = layout

proc uploadLevel*(texture: GpuTexture, layer, level, width, height, bytesPerPixel: int, data: pointer) =
  let ctx = texture.ctx
  let format = texture.format
  if layer notin 0 ..< texture.layers or level notin 0 ..< texture.mipLevels or
      width != max(1, texture.width shr level) or height != max(1, texture.height shr level):
    raise newException(GpuError, "Invalid texture subresource")
  if bytesPerPixel != format.pixelBytes:
    raise newException(GpuError, "Incorrect Vulkan texture row format")
  let ownFrame = ctx.command == nil
  if ownFrame:
    ctx.beginFrame()
  let upload = ctx.uploadSlice(width * height * bytesPerPixel, max(4, bytesPerPixel))
  copyMem(upload.mapped, data, width * height * bytesPerPixel)
  texture.transition(VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL)
  var region = VkBufferImageCopy(bufferOffset: upload.offset.uint64, imageSubresource: VkImageSubresourceLayers(
    aspectMask: VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT), mipLevel: level.uint32, baseArrayLayer: layer.uint32, layerCount: 1), imageExtent: VkExtent3D(width: width.uint32, height: height.uint32, depth: 1))
  vkCmdCopyBufferToImage(ctx.buffer, upload.buffer, texture.image,
    VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, region.addr)
  texture.transition(VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL)
  if ownFrame:
    ctx.finishFrame()

proc imageUsage(format: TextureFormat): VkImageUsageFlags =
  let attachment =
    if format in {Depth32f, DepthStencil}: VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT
    else: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT
  VkImageUsageFlags(attachment or VK_IMAGE_USAGE_SAMPLED_BIT or
    VK_IMAGE_USAGE_TRANSFER_SRC_BIT or VK_IMAGE_USAGE_TRANSFER_DST_BIT)

proc newTexture*(ctx: GpuContext, width, height: int,
  format: TextureFormat, data: pointer = nil, bytesPerPixel = 4,
  mipLevels = 1, layers = 1, arrayTexture = false, cube = false, samples = 1): GpuTexture =
  ## Allocates bounded optimal texture storage and uploads the first level.
  if width < 1 or height < 1 or width > 16384 or height > 16384 or
    width.int64 * height.int64 * format.pixelBytes > 512 * 1024 * 1024:
      raise newException(GpuError, "Vulkan texture dimensions exceed limits")
  counted: inc textureCreates
  inc ctx.nextImageId
  result = GpuTexture(ctx: ctx, id: ctx.nextImageId, width: width, height: height, layers: layers, arrayTexture: arrayTexture, cube: cube, format: format,
    mipLevels: mipLevels, layouts: newSeq[VkImageLayout](mipLevels))
  var
    info = VkImageCreateInfo(sType: VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
      imageType: VK_IMAGE_TYPE_2D, format: format.nativeFormat,
      extent: VkExtent3D(width: width.uint32, height: height.uint32, depth: 1),
      mipLevels: mipLevels.uint32, arrayLayers: layers.uint32,
      flags: VkImageCreateFlags(if cube: VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT else: 0),
      samples: VkSampleCountFlagBits(samples), tiling: VK_IMAGE_TILING_OPTIMAL,
      usage: format.imageUsage)
    requirements: VkMemoryRequirements
  vkCreateImage(ctx.device, info.addr, nil, result.image.addr).checked("Create image")
  vkGetImageMemoryRequirements(ctx.device, result.image, requirements.addr)
  var memory = VkMemoryAllocateInfo(sType: VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
    allocationSize: requirements.size, memoryTypeIndex: ctx.memoryType(
      requirements.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT))
  vkAllocateMemory(ctx.device, memory.addr, nil, result.memory.addr).checked(
    "Allocate image memory")
  vkBindImageMemory(ctx.device, result.image, result.memory, 0).checked(
    "Bind image memory")
  var view = VkImageViewCreateInfo(sType: VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
    image: result.image, viewType: (if cube: VK_IMAGE_VIEW_TYPE_CUBE elif arrayTexture: VK_IMAGE_VIEW_TYPE_2D_ARRAY else: VK_IMAGE_VIEW_TYPE_2D), format: format.nativeFormat,
    subresourceRange: VkImageSubresourceRange(
      aspectMask: VkImageAspectFlags(if format in {Depth32f, DepthStencil}: VK_IMAGE_ASPECT_DEPTH_BIT
        else: VK_IMAGE_ASPECT_COLOR_BIT),
      levelCount: mipLevels.uint32, layerCount: layers.uint32))
  vkCreateImageView(ctx.device, view.addr, nil, result.view.addr).checked(
    "Create image view")
  view.viewType = VK_IMAGE_VIEW_TYPE_2D
  view.subresourceRange.layerCount = 1
  view.subresourceRange.levelCount = 1
  if format == DepthStencil:
    view.subresourceRange.aspectMask = VkImageAspectFlags(VK_IMAGE_ASPECT_DEPTH_BIT or VK_IMAGE_ASPECT_STENCIL_BIT)
  vkCreateImageView(ctx.device, view.addr, nil, result.attachment.addr).checked("Create attachment view")
  if data != nil:
    result.uploadLevel(0, 0, width, height, bytesPerPixel, data)

proc owns*(ctx: GpuContext, target: GpuTarget): bool =
  ctx != nil and (target.texture != nil or target.depth != nil) and
    (target.texture == nil or target.texture.ctx == ctx) and
    (target.depth == nil or target.depth.ctx == ctx)

proc beginPass*(ctx: GpuContext, target: GpuTarget,
  clearColor = false, clearDepth = false, color = Color(), clearStencil = false): GpuEncoder =
  ## Begins dynamic rendering with explicit attachment layouts and load actions.
  if not ctx.owns(target) or ctx.command == nil:
    raise newException(GpuError, "A Vulkan frame and target are required")
  if ctx.inPass and ctx.activeTarget == target and not (clearColor or clearDepth or clearStencil):
    return GpuEncoder(ctx: ctx, target: target)
  ctx.closePass()
  counted: inc passCount
  if target.texture != nil:
    target.texture.transition(VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL)
  if target.depth != nil:
    target.depth.transition(VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL)
  var
    colorAttachment = VkRenderingAttachmentInfo(
      sType: VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
      imageView: (if target.texture != nil: target.texture.attachment else: VkImageView(0)),
      imageLayout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
      loadOp: (if clearColor: VK_ATTACHMENT_LOAD_OP_CLEAR
        else: VK_ATTACHMENT_LOAD_OP_LOAD), storeOp: VK_ATTACHMENT_STORE_OP_STORE,
      clearValue: VkClearValue(color: VkClearColorValue(float32:
        [color.r, color.g, color.b, color.a])))
    depthAttachment = VkRenderingAttachmentInfo(
      sType: VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
      imageLayout: VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
      loadOp: (if clearDepth: VK_ATTACHMENT_LOAD_OP_CLEAR
        else: VK_ATTACHMENT_LOAD_OP_LOAD), storeOp: VK_ATTACHMENT_STORE_OP_STORE,
      clearValue: VkClearValue(depthStencil: VkClearDepthStencilValue(depth: 1)))
    render = VkRenderingInfo(sType: VK_STRUCTURE_TYPE_RENDERING_INFO,
      renderArea: VkRect2D(extent: VkExtent2D(width: target.width.uint32,
        height: target.height.uint32)), layerCount: 1,
      colorAttachmentCount: uint32(target.texture != nil), pColorAttachments: colorAttachment.addr)
  if target.resolveColor != nil:
    target.resolveColor.transition(VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL)
    colorAttachment.resolveMode = VK_RESOLVE_MODE_AVERAGE_BIT
    colorAttachment.resolveImageView = target.resolveColor.attachment
    colorAttachment.resolveImageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
  if target.resolveDepth != nil:
    target.resolveDepth.transition(VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL)
    depthAttachment.resolveMode = VK_RESOLVE_MODE_SAMPLE_ZERO_BIT
    depthAttachment.resolveImageView = target.resolveDepth.attachment
    depthAttachment.resolveImageLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
  var stencilAttachment = depthAttachment
  if target.depth != nil:
    depthAttachment.imageView = target.depth.attachment
    if target.depth.format == DepthStencil:
      stencilAttachment.imageView = target.depth.attachment
      stencilAttachment.loadOp = if clearStencil: VK_ATTACHMENT_LOAD_OP_CLEAR else: VK_ATTACHMENT_LOAD_OP_LOAD
      render.pStencilAttachment = stencilAttachment.addr
    render.pDepthAttachment = depthAttachment.addr
  vkCmdBeginRendering(ctx.buffer, render.addr)
  ctx.inPass = true
  ctx.activeTarget = target
  var
    viewport = VkViewport(width: target.width.float32,
      height: target.height.float32, maxDepth: 1)
    scissor = render.renderArea
  vkCmdSetViewport(ctx.buffer, 0, 1, viewport.addr)
  vkCmdSetScissor(ctx.buffer, 0, 1, scissor.addr)
  GpuEncoder(ctx: ctx, target: target)

proc endPass*(encoder: GpuEncoder) =
  ## Each subsequent use transitions the attachment to its required layout.
  discard

proc createSampler*(ctx: GpuContext, state: SamplerState): GpuSampler =
  ## Translates shared sampling intent within the device's enabled limits.
  const address = [VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE, VK_SAMPLER_ADDRESS_MODE_REPEAT,
    VK_SAMPLER_ADDRESS_MODE_MIRRORED_REPEAT]
  let anisotropy = state.samplerAnisotropy(
    ctx.presentation.maxSamplerAnisotropy.int)
  var info = VkSamplerCreateInfo(sType: VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
    magFilter: (if state.magLinear: VK_FILTER_LINEAR else: VK_FILTER_NEAREST),
    minFilter: (if state.minLinear: VK_FILTER_LINEAR else: VK_FILTER_NEAREST),
    mipmapMode: (if state.mipLinear: VK_SAMPLER_MIPMAP_MODE_LINEAR else: VK_SAMPLER_MIPMAP_MODE_NEAREST),
    compareEnable: uint32(state.comparison), compareOp: VK_COMPARE_OP_LESS_OR_EQUAL,
    anisotropyEnable: uint32(anisotropy > 1), maxAnisotropy: anisotropy.float32,
    addressModeU: address[state.wrapS.ord], addressModeV: address[state.wrapT.ord],
    addressModeW: address[state.wrapR.ord], maxLod: (if state.mipmaps: 1000'f else: 0'f))
  result = GpuSampler(ctx: ctx)
  vkCreateSampler(ctx.device, info.addr, nil, result.sampler.addr).checked(
    "Create sampler")

proc shader(ctx: GpuContext, binary: string): VkShaderModule =
  ## Creates a native module from an aligned SPIR-V word buffer.
  var words = newSeq[uint32](binary.len div 4)
  copyMem(words[0].addr, binary[0].unsafeAddr, binary.len)
  var info = VkShaderModuleCreateInfo(sType: VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
    codeSize: binary.len.csize_t, pCode: words[0].addr)
  vkCreateShaderModule(ctx.device, info.addr, nil, result.addr).checked(
    "Create shader module")

proc wireTriangles(state: DrawState): bool =
  state.wireframe and state.primitive in {Triangles, TriangleStrip}

proc wireIndices(ctx: GpuContext, source: GpuBuffer, first, count: int,
    index32: bool, primitive: Primitive): GpuBuffer =
  # vk14 creates a device with solid fill. Draw mesh outlines as line lists.
  let triangles = if primitive == Triangles: count div 3 else: max(0, count - 2)
  if triangles == 0: return nil
  proc index(i: int): uint32 =
    let offset = first + i
    if source == nil: return offset.uint32
    if index32: return cast[ptr UncheckedArray[uint32]](source.indexBytes[0].unsafeAddr)[offset]
    cast[ptr UncheckedArray[uint16]](source.indexBytes[0].unsafeAddr)[offset].uint32
  var edges = newSeqOfCap[uint32](triangles * 6)
  for triangle in 0 ..< triangles:
    let start = if primitive == Triangles: triangle * 3 else: triangle
    let a = index(start)
    let b = index(start + 1)
    let c = index(start + 2)
    edges.add [a, b, b, c, c, a]
  result = ctx.newBuffer(edges.len * sizeof(uint32), VK_BUFFER_USAGE_INDEX_BUFFER_BIT)
  copyMem(result.mapped, edges[0].addr, edges.len * sizeof(uint32))
  ctx.frames[ctx.slot].transient.add result

proc newPipeline*(ctx: GpuContext, code: ProgramCode, layout: VertexLayout,
    state: DrawState, format, depth: TextureFormat, hasColor, hasDepth: bool, samples: int): GpuProgram =
  let vertexBinary = code.vertex
  let fragmentBinary = code.fragment
  let
    vertex = ctx.shader(vertexBinary)
    fragment = if fragmentBinary.len > 0: ctx.shader(fragmentBinary) else: VkShaderModule(0)
  defer:
    vkDestroyShaderModule(ctx.device, vertex, nil)
    vkDestroyShaderModule(ctx.device, fragment, nil)
  var stages = [VkPipelineShaderStageCreateInfo(
    sType: VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
    stage: VK_SHADER_STAGE_VERTEX_BIT, module: vertex, pName: "main"),
    VkPipelineShaderStageCreateInfo(
      sType: VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
      stage: VK_SHADER_STAGE_FRAGMENT_BIT, module: fragment, pName: "main")]
  var
    attributes: seq[VkVertexInputAttributeDescription]
    binding: VkVertexInputBindingDescription
    input = VkPipelineVertexInputStateCreateInfo(
      sType: VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO)
  const formats = [VK_FORMAT_R32_SFLOAT, VK_FORMAT_R32G32_SFLOAT,
    VK_FORMAT_R32G32B32_SFLOAT, VK_FORMAT_R32G32B32A32_SFLOAT,
    VK_FORMAT_R32_UINT, VK_FORMAT_R32G32_UINT, VK_FORMAT_R32G32B32_UINT,
    VK_FORMAT_R32G32B32A32_UINT, VK_FORMAT_R8G8B8A8_UNORM]
  for field in code.inputs:
    for attribute in layout.attributes:
      if field.name == attribute.name:
        attributes.add VkVertexInputAttributeDescription(location: field.location.uint32,
          offset: attribute.offset.uint32, format: formats[attribute.format.ord])
  if attributes.len > 0:
    binding.stride = layout.stride.uint32
    input.vertexBindingDescriptionCount = 1
    input.pVertexBindingDescriptions = binding.addr
    input.vertexAttributeDescriptionCount = attributes.len.uint32
    input.pVertexAttributeDescriptions = attributes[0].addr
  var
    assembly = VkPipelineInputAssemblyStateCreateInfo(
      sType: VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
      topology: if state.wireTriangles: VK_PRIMITIVE_TOPOLOGY_LINE_LIST
        else: [VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, VK_PRIMITIVE_TOPOLOGY_LINE_LIST, VK_PRIMITIVE_TOPOLOGY_POINT_LIST, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP][state.primitive.ord])
    viewport = VkPipelineViewportStateCreateInfo(
      sType: VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
      viewportCount: 1, scissorCount: 1)
    raster = VkPipelineRasterizationStateCreateInfo(
      sType: VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
      polygonMode: VK_POLYGON_MODE_FILL, cullMode: VkCullModeFlags([VK_CULL_MODE_NONE, VK_CULL_MODE_BACK_BIT, VK_CULL_MODE_FRONT_BIT][state.cull.ord]),
      frontFace: VK_FRONT_FACE_COUNTER_CLOCKWISE, lineWidth: 1)
    multisample = VkPipelineMultisampleStateCreateInfo(
      sType: VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
      rasterizationSamples: VkSampleCountFlagBits(samples))
    depthState = VkPipelineDepthStencilStateCreateInfo(
      sType: VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
      depthTestEnable: uint32(hasDepth and state.depthTest),
      depthWriteEnable: uint32(hasDepth and state.depthWrite),
      depthCompareOp: [VK_COMPARE_OP_LESS_OR_EQUAL, VK_COMPARE_OP_LESS, VK_COMPARE_OP_ALWAYS, VK_COMPARE_OP_EQUAL, VK_COMPARE_OP_GREATER][state.depthCompare.ord])
    attachment = VkPipelineColorBlendAttachmentState(
      blendEnable: uint32(state.blend != Opaque),
      srcColorBlendFactor: VK_BLEND_FACTOR_ONE,
      dstColorBlendFactor: VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
      colorBlendOp: VK_BLEND_OP_ADD,
      srcAlphaBlendFactor: VK_BLEND_FACTOR_ONE,
      dstAlphaBlendFactor: VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
      alphaBlendOp: VK_BLEND_OP_ADD,
      colorWriteMask: VkColorComponentFlags(15))
    blending = VkPipelineColorBlendStateCreateInfo(
      sType: VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
      attachmentCount: uint32(hasColor), pAttachments: attachment.addr)
    states = [VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR]
    dynamic = VkPipelineDynamicStateCreateInfo(
      sType: VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
      dynamicStateCount: 2, pDynamicStates: states[0].addr)
    color = format.nativeFormat
    rendering = VkPipelineRenderingCreateInfo(
      sType: VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
      colorAttachmentCount: uint32(hasColor), pColorAttachmentFormats: color.addr,
      stencilAttachmentFormat: (if hasDepth and depth == DepthStencil: depth.nativeFormat else: VK_FORMAT_UNDEFINED),
      depthAttachmentFormat: (if hasDepth: depth.nativeFormat else: VK_FORMAT_UNDEFINED))
    info = VkGraphicsPipelineCreateInfo(
      sType: VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
      pNext: rendering.addr, stageCount: (if fragmentBinary.len > 0: 2'u32 else: 1'u32), pStages: stages[0].addr,
      pVertexInputState: input.addr, pInputAssemblyState: assembly.addr,
      pViewportState: viewport.addr, pRasterizationState: raster.addr,
      pMultisampleState: multisample.addr, pDepthStencilState: depthState.addr,
      pColorBlendState: blending.addr, pDynamicState: dynamic.addr,
      layout: ctx.layout)
  attachment.srcColorBlendFactor = (if state.blend == PremultipliedAlpha: VK_BLEND_FACTOR_ONE elif state.blend == Multiply: VK_BLEND_FACTOR_DST_COLOR else: VK_BLEND_FACTOR_SRC_ALPHA)
  attachment.dstColorBlendFactor = (if state.blend == Additive: VK_BLEND_FACTOR_ONE elif state.blend == Multiply: VK_BLEND_FACTOR_ZERO else: VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA)
  attachment.srcAlphaBlendFactor = (if state.blend in {AlphaBlendPreserveAlpha, Additive, Multiply}: VK_BLEND_FACTOR_ZERO elif state.blend == StraightAlpha: VK_BLEND_FACTOR_SRC_ALPHA else: VK_BLEND_FACTOR_ONE)
  attachment.dstAlphaBlendFactor = (if state.blend in {AlphaBlendPreserveAlpha, Additive, Multiply}: VK_BLEND_FACTOR_ONE else: VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA)
  if state.stencilTest and hasDepth and depth == DepthStencil:
    depthState.stencilTestEnable = VK_TRUE
    depthState.front = VkStencilOpState(failOp: VK_STENCIL_OP_KEEP, depthFailOp: VK_STENCIL_OP_KEEP,
      passOp: (if state.stencilWrite: VK_STENCIL_OP_REPLACE else: VK_STENCIL_OP_KEEP),
      compareOp: [VK_COMPARE_OP_LESS_OR_EQUAL, VK_COMPARE_OP_LESS, VK_COMPARE_OP_ALWAYS, VK_COMPARE_OP_EQUAL, VK_COMPARE_OP_GREATER][state.stencilCompare.ord],
      compareMask: 255, writeMask: 255, reference: state.stencilReference.uint32)
    depthState.back = depthState.front
  result = GpuProgram(ctx: ctx)
  vkCreateGraphicsPipelines(ctx.device, VkPipelineCache(0), 1, info.addr, nil,
    result.pipeline.addr).checked("Create graphics pipeline")

proc setProgram*(encoder: var GpuEncoder, program: GpuProgram) =
  ## Selects an immutable native graphics pipeline for subsequent draws.
  encoder.program = program
  vkCmdBindPipeline(encoder.ctx.buffer, VK_PIPELINE_BIND_POINT_GRAPHICS,
    program.pipeline)

proc setTexture*(encoder: var GpuEncoder, texture: GpuTexture, index: uint) =
  ## Records a completed source texture for the next draw's descriptor set.
  encoder.textures[index] = texture

proc setSampler*(encoder: var GpuEncoder, sampler: GpuSampler, index: uint) =
  ## Records a sampler for the next draw's descriptor set.
  encoder.samplers[index] = sampler

proc setVertices*(encoder: GpuEncoder, buffer: GpuBuffer, offset, index: int) =
  ## Binds the immutable tightly packed vertex stream at binding zero.
  var
    native = buffer.buffer
    start = (buffer.offset + offset).uint64
  vkCmdBindVertexBuffers(encoder.ctx.buffer, 0, 1, native.addr, start.addr)

proc bindConstants*(ctx: GpuContext, encoder: var GpuEncoder,
  vertex, fragment: GpuConstants) =
  ## Borrows uniform blocks until the draw copies their bytes.
  encoder.vertex = vertex
  encoder.fragment = fragment

proc drawNative*(encoder: GpuEncoder, first, count, instances: int, indices: GpuBuffer, index32: bool, state: DrawState, ranges: openArray[IndexRange]) =
  ## Binds per-draw textures, samplers, and uniform storage.
  let
    ctx = encoder.ctx
    descriptors = ctx.drawDescriptors()
  template sets: untyped = descriptors.sets
  var
    imageInfo: array[2 * MaxTextures, VkDescriptorImageInfo]
    bufferInfo: array[2, VkDescriptorBufferInfo]
    writes: array[4 * MaxTextures + 2, VkWriteDescriptorSet]
    writeCount: int
  for i, texture in encoder.textures:
    if texture == nil:
      continue
    if texture == encoder.target.texture:
      raise newException(GpuError, "A Vulkan pass cannot sample its output")
    let binding = (id: texture.id, sampler: int64(encoder.samplers[i].sampler))
    if binding == descriptors.images[i]: continue
    descriptors.images[i] = binding
    imageInfo[i] = VkDescriptorImageInfo(sampler: encoder.samplers[i].sampler,
      imageView: texture.view, imageLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL)
    writes[writeCount] = VkWriteDescriptorSet(
      sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
      dstSet: sets[(if i < MaxTextures: 0 else: 2)], dstBinding: (i mod MaxTextures).uint32, descriptorCount: 1,
      descriptorType: VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,
      pImageInfo: imageInfo[i].addr)
    writes[writeCount + 1] = writes[writeCount]
    writes[writeCount + 1].descriptorType = VK_DESCRIPTOR_TYPE_SAMPLER
    writes[writeCount + 1].dstBinding += 32
    writeCount += 2
  for i, data in [encoder.vertex, encoder.fragment]:
    bufferInfo[i] = ctx.uploadUniform(data)
    let previous = descriptors.constants[i]
    if int64(previous.buffer) == int64(bufferInfo[i].buffer) and previous.offset == bufferInfo[i].offset and previous.range == bufferInfo[i].range: continue
    descriptors.constants[i] = bufferInfo[i]
    writes[writeCount] = VkWriteDescriptorSet(
      sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
      dstSet: sets[1], dstBinding: i.uint32, descriptorCount: 1,
      descriptorType: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
      pBufferInfo: bufferInfo[i].addr)
    inc writeCount
  if writeCount > 0: vkUpdateDescriptorSets(ctx.device, writeCount.uint32, writes[0].addr, 0, nil)
  vkCmdBindDescriptorSets(ctx.buffer, VK_PIPELINE_BIND_POINT_GRAPHICS,
    ctx.layout, 0, 3, sets[0].unsafeAddr, 0, nil)
  if state.wireTriangles:
    let edges = ctx.wireIndices(indices, first, count, index32, state.primitive)
    if edges != nil:
      vkCmdBindIndexBuffer(ctx.buffer, edges.buffer, 0, VK_INDEX_TYPE_UINT32)
      vkCmdDrawIndexed(ctx.buffer, (edges.size div sizeof(uint32)).uint32, instances.uint32, 0, 0, 0)
  elif indices == nil:
    vkCmdDraw(ctx.buffer, count.uint32, instances.uint32, first.uint32, 0)
  else:
    vkCmdBindIndexBuffer(ctx.buffer, indices.buffer, 0, if index32: VK_INDEX_TYPE_UINT32 else: VK_INDEX_TYPE_UINT16)
    if ranges.len == 0:
      vkCmdDrawIndexed(ctx.buffer, count.uint32, instances.uint32, first.uint32, 0, 0)
    else:
      for span in ranges:
        vkCmdDrawIndexed(ctx.buffer, span.count.uint32, instances.uint32, span.first.uint32, 0, 0)

proc generateMipmaps*(ctx: GpuContext, texture: GpuTexture) =
  ## Builds each lower mip on the GPU using explicit subresource transitions.
  var properties: VkFormatProperties
  vkGetPhysicalDeviceFormatProperties(ctx.physical, texture.format.nativeFormat,
    properties.addr)
  if (properties.optimalTilingFeatures.uint32 and
    VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT) == 0:
      raise newException(GpuError, "Vulkan format cannot generate linear mipmaps")
  let ownFrame = ctx.command == nil
  if ownFrame:
    ctx.beginFrame()
  for level in 1 ..< texture.mipLevels:
    texture.transition(VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, level - 1, 1)
    texture.transition(VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, level, 1)
    var blit = VkImageBlit(srcSubresource: VkImageSubresourceLayers(
      aspectMask: VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT), mipLevel: (level - 1).uint32,
      layerCount: 1), dstSubresource: VkImageSubresourceLayers(
        aspectMask: VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT), mipLevel: level.uint32, layerCount: 1))
    blit.srcOffsets[1] = VkOffset3D(x: max(1, texture.width shr (level - 1)).int32,
      y: max(1, texture.height shr (level - 1)).int32, z: 1)
    blit.dstOffsets[1] = VkOffset3D(x: max(1, texture.width shr level).int32,
      y: max(1, texture.height shr level).int32, z: 1)
    vkCmdBlitImage(ctx.buffer, texture.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
      texture.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, blit.addr, VK_FILTER_LINEAR)
  texture.transition(VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL)
  if ownFrame:
    ctx.finishFrame()

proc readImage*(ctx: GpuContext, target: GpuTarget): Image =
  ## Reads completed premultiplied RGBA8 bytes in top-left row order.
  if not ctx.owns(target):
    raise newException(GpuError, "Invalid Vulkan readback target")
  ctx.finishFrame()
  if target.format != Rgba8:
    raise newException(GpuError, "Image readback requires RGBA8")
  var readback = ctx.newBuffer(target.width * target.height * 4,
    VK_BUFFER_USAGE_TRANSFER_DST_BIT)
  defer: readback.freeGpu()
  ctx.beginFrame()
  target.texture.transition(VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL)
  var region = VkBufferImageCopy(imageSubresource: VkImageSubresourceLayers(
    aspectMask: VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT), layerCount: 1),
    imageExtent: VkExtent3D(width: target.width.uint32,
      height: target.height.uint32, depth: 1))
  vkCmdCopyImageToBuffer(ctx.buffer, target.texture.image,
    VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, readback.buffer, 1, region.addr)
  ctx.finishFrame()
  result = newImage(target.width, target.height)
  copyMem(result.data[0].addr, readback.mapped, target.width * target.height * 4)

proc applyViewport*(encoder: GpuEncoder, size: IVec2) =
  var viewport = VkViewport(width: size.x.float32, height: size.y.float32, maxDepth: 1)
  vkCmdSetViewport(encoder.ctx.buffer, 0, 1, viewport.addr)

proc prepareSample*(texture: GpuTexture) =
  texture.transition(VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL)

proc copyPixels*(source, destination: GpuTexture) =
  source.transition(VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL)
  destination.transition(VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL)
  let aspect = if source.format in {Depth32f, DepthStencil}: VK_IMAGE_ASPECT_DEPTH_BIT else: VK_IMAGE_ASPECT_COLOR_BIT
  var layers = VkImageSubresourceLayers(aspectMask: VkImageAspectFlags(aspect), layerCount: 1)
  var region = VkImageCopy(srcSubresource: layers, dstSubresource: layers,
    extent: VkExtent3D(width: source.width.uint32, height: source.height.uint32, depth: 1))
  vkCmdCopyImage(source.ctx.buffer, source.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
    destination.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, region.addr)
  if source.format == DepthStencil:
    region.srcSubresource.aspectMask = VkImageAspectFlags(VK_IMAGE_ASPECT_STENCIL_BIT)
    region.dstSubresource = region.srcSubresource
    vkCmdCopyImage(source.ctx.buffer, source.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
      destination.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, region.addr)

proc acquireSurface*(ctx: GpuContext, window: windy.Window, index: var uint32): GpuTexture =
  let size = window.size
  if size.x <= 0 or size.y <= 0: return
  template resizeSurface() =
    ctx.finishFrame()
    vkDeviceWaitIdle(ctx.device).checked("Drain swap chain")
    ctx.releaseSurface()
    ctx.presentation.recreateSwapChain(size.x, size.y)
    ctx.beginFrame()
  if ctx.presentation.swapChainExtent.width.int != size.x or
      ctx.presentation.swapChainExtent.height.int != size.y or ctx.presentation.vsync != window.vsync:
    ctx.presentation.vsync = window.vsync
    resizeSurface()
  var acquired = ctx.presentation.imageAvailableSemaphores[ctx.slot]
  var status = vkAcquireNextImageKHR(ctx.device, ctx.presentation.swapChain, uint64.high, acquired, VkFence(0), index.addr)
  if status == VK_ERROR_OUT_OF_DATE_KHR:
    resizeSurface()
    acquired = ctx.presentation.imageAvailableSemaphores[ctx.slot]
    status = vkAcquireNextImageKHR(ctx.device, ctx.presentation.swapChain, uint64.high, acquired, VkFence(0), index.addr)
  if status != VK_SUBOPTIMAL_KHR: status.checked("Acquire back buffer")
  if ctx.surfaces.len == 0:
    ctx.surfaces.setLen(ctx.presentation.swapChainImages.len)
    ctx.presentReady.setLen(ctx.surfaces.len)
  if ctx.surfaces[index] != nil: return ctx.surfaces[index]
  let fmt = ctx.presentation.swapChainImageFormat
  if fmt != VK_FORMAT_B8G8R8A8_UNORM:
    raise newException(GpuError, "Unsupported swap chain format: " & $fmt)
  result = GpuTexture(ctx: ctx, surface: true, format: Bgra8, image: ctx.presentation.swapChainImages[index],
    width: size.x, height: size.y, layers: 1, mipLevels: 1, layouts: @[VK_IMAGE_LAYOUT_UNDEFINED])
  var desc = VkImageViewCreateInfo(sType: VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
    image: result.image, viewType: VK_IMAGE_VIEW_TYPE_2D, format: fmt,
    subresourceRange: VkImageSubresourceRange(aspectMask: VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT), levelCount: 1, layerCount: 1))
  vkCreateImageView(ctx.device, desc.addr, nil, result.attachment.addr).checked("Create surface attachment")

  ctx.surfaces[index] = result
  var semaphore = VkSemaphoreCreateInfo(sType: VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO)
  vkCreateSemaphore(ctx.device, semaphore.addr, nil, ctx.presentReady[index].addr).checked("Create present semaphore")

proc presentSurface*(ctx: GpuContext, texture: GpuTexture, index: uint32) =
  texture.transition(VK_IMAGE_LAYOUT_PRESENT_SRC_KHR)
  ctx.submitFrame(ctx.presentation.imageAvailableSemaphores[ctx.slot], ctx.presentReady[index])
  var info = VkPresentInfoKHR(sType: VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
    waitSemaphoreCount: 1, pWaitSemaphores: ctx.presentReady[index].addr,
    swapchainCount: 1, pSwapchains: ctx.presentation.swapChain.addr, pImageIndices: index.unsafeAddr)
  let status = vkQueuePresentKHR(ctx.presentation.presentQueue, info.addr)
  if status notin [VK_SUBOPTIMAL_KHR, VK_ERROR_OUT_OF_DATE_KHR]: status.checked("Present frame")

proc sampleCount*(ctx: GpuContext, requested: int, color, depth: TextureFormat, hasColor = true, hasDepth = true): int =
  if requested <= 1: return 1
  var counts = uint32.high
  for (enabled, format) in [(hasColor, color), (hasDepth, depth)]:
    if enabled:
      var properties: VkImageFormatProperties
      let status = vkGetPhysicalDeviceImageFormatProperties(ctx.physical, format.nativeFormat,
        VK_IMAGE_TYPE_2D, VK_IMAGE_TILING_OPTIMAL, format.imageUsage, VkImageCreateFlags(0), properties.addr)
      if status == VK_ERROR_FORMAT_NOT_SUPPORTED: return 1
      status.checked("Query supported sample counts")
      counts = counts and properties.sampleCounts.uint32
  for count in [16, 8, 4, 2]:
    if count <= requested and (counts and count.uint32) != 0: return count
  1
