import
  std/[strutils, tables],
  metal4, pixie, shady, vmath, windy,
  uniforms

when defined(metalProfile):
  import profiles
  export profiles

import windy/platforms/apple/objc as nativeObjc

export metal4

const GeometryBufferIndex = 2'u

type
  PolyworldMetalError* = object of CatchableError
  VertexFormat* = enum
    Float1, Float2, Float3, Float4, UInt1, UInt2, UInt3, UInt4
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
  MetalBuffer* = ref object
    handle*: MTLBuffer
    size*: int
  MetalTexture* = ref object
    handle*: MTLTexture
    width*, height*: int
    pixelFormat*: MTLPixelFormat
    sampler*: MTLSamplerState
    comparisonSampler: MTLSamplerState
    ownsHandle*: bool
    lastUse: uint64
  RenderTarget* = ref object
    width*, height*, samples*: int
    color*, depth*: MetalTexture
    multisampleColor, multisampleDepth: MetalTexture
    stencil*: bool
    borrowsColor, borrowsDepth: bool
    resolved: bool
  TextureBinding = object
    name: string
    index, samplerIndex: int
    comparison: bool
  PipelineEntry = object
    layout: VertexLayout
    blend: BlendMode
    colorFormat, depthFormat: MTLPixelFormat
    samples: int
    stencil: bool
    handle: MTLRenderPipelineState
  MetalProgram* = ref object
    vertexSource*, fragmentSource*: string
    layout*: VertexLayout
    vertexFunction, fragmentFunction: MTLFunction
    vertexUniforms, fragmentUniforms: UniformBuffer
    vertexTextures, fragmentTextures: seq[TextureBinding]
    textures: Table[system.string, MetalTexture]
    pipelines: seq[PipelineEntry]
  MetalRenderer* = ref object
    ctx*: MetalContext
    commandBuffer*: MTLCommandBuffer
    target*, frameTarget*: RenderTarget
    encoder: MTLRenderCommandEncoder
    targets: seq[RenderTarget]
    viewports: seq[IVec2]
    framePool: ID
    buffers: seq[MetalBuffer]
    textures: seq[MetalTexture]
    programs: seq[MetalProgram]
    depthStates: Table[system.string, MTLDepthStencilState]
    stencilOverride: DrawState
    hasStencilOverride: bool
    presentProgram: MetalProgram
    presentVertices: MetalBuffer
    viewport: IVec2
    frameSamples: int
    commandSerial: uint64
  MTLStencilDescriptor = distinct NSObject

objc:
  proc supportsTextureSampleCount(self: MTLDevice, x: uint): bool
  proc init(self: MTLStencilDescriptor): MTLStencilDescriptor
  proc setStencilCompareFunction(self: MTLStencilDescriptor, x: uint)
  proc setStencilFailureOperation(self: MTLStencilDescriptor, x: uint)
  proc setDepthFailureOperation(self: MTLStencilDescriptor, x: uint)
  proc setDepthStencilPassOperation(self: MTLStencilDescriptor, x: uint)
  proc setReadMask(self: MTLStencilDescriptor, x: uint32)
  proc setWriteMask(self: MTLStencilDescriptor, x: uint32)
  proc setFrontFaceStencil(self: MTLDepthStencilDescriptor,
    x: MTLStencilDescriptor)
  proc setBackFaceStencil(self: MTLDepthStencilDescriptor,
    x: MTLStencilDescriptor)
  proc setStencilReferenceValue(self: MTLRenderCommandEncoder, x: uint32)
  proc setStencilAttachmentPixelFormat(self: MTLRenderPipelineDescriptor,
    x: MTLPixelFormat)
  proc stencilAttachment(self: MTLRenderPassDescriptor):
    MTLRenderPassDepthAttachmentDescriptor
  proc setClearStencil(self: MTLRenderPassDepthAttachmentDescriptor, x: uint32)
  proc setTextureType*(self: MTLTextureDescriptor, x: uint)
  proc setSampleCount*(self: MTLTextureDescriptor, x: uint)
  proc setRasterSampleCount(self: MTLRenderPipelineDescriptor, x: uint)
  proc setResolveTexture(self: MTLRenderPassAttachmentDescriptor, x: MTLTexture)
  proc setDepthResolveFilter(self: MTLRenderPassDepthAttachmentDescriptor,
    x: uint)
  proc setStencilResolveFilter(self: MTLRenderPassDepthAttachmentDescriptor,
    x: uint)
  proc setCompareFunction(self: MTLSamplerDescriptor, x: MTLCompareFunction)
  proc setMaxAnisotropy(self: MTLSamplerDescriptor, x: uint)
  proc setFragmentBuffer(self: MTLRenderCommandEncoder, x: MTLBuffer,
    offset: uint, atIndex: uint)
  proc setVertexTexture(self: MTLRenderCommandEncoder, x: MTLTexture,
    atIndex: uint)
  proc setVertexSamplerState(self: MTLRenderCommandEncoder, x: MTLSamplerState,
    atIndex: uint)
  proc setTriangleFillMode(self: MTLRenderCommandEncoder, x: uint)
  proc drawPrimitives(self: MTLRenderCommandEncoder, x: MTLPrimitiveType,
    vertexStart: uint, vertexCount: uint, instanceCount: uint)
  proc drawIndexedPrimitives(self: MTLRenderCommandEncoder,
    x: MTLPrimitiveType, indexCount: uint, indexType: uint,
    indexBuffer: MTLBuffer, indexBufferOffset: uint, instanceCount: uint)
  proc copyFromTexture(self: MTLBlitCommandEncoder, x: MTLTexture,
    sourceSlice: uint, sourceLevel: uint, sourceOrigin: MTLOrigin,
    sourceSize: MTLSize, toTexture: MTLTexture, destinationSlice: uint,
    destinationLevel: uint, destinationOrigin: MTLOrigin)

when defined(metalProfile):
  objc:
    proc GPUStartTime(self: MTLCommandBuffer): float64
    proc GPUEndTime(self: MTLCommandBuffer): float64

var metalRenderer*: MetalRenderer

proc presentVertex(
  gl_Position: var Vec4, uv: var Vec2, position: Vec2, texcoord: Vec2
) =
  ## Generates clip coordinates for the presentation quad.
  gl_Position = vec4(position.x, position.y, 0, 1)
  uv = texcoord

var presentTexture: Uniform[Sampler2D]

proc presentFragment(fragColor: var Vec4, uv: Vec2) =
  ## Copies the resolved frame into the drawable.
  fragColor = texture(presentTexture, uv)

template nativePool() =
  ## Drains temporary Cocoa objects created outside an active frame.
  let pool = nativeObjc.NSAutoreleasePool.new()
  defer: pool.release()

proc requireRenderer() =
  ## Rejects operations before the shared device exists.
  if metalRenderer == nil:
    raise newException(PolyworldMetalError, "Metal renderer is not initialized")

proc flushEncoder*() =
  ## Ends the current pass and resolves its multisampled attachments.
  if metalRenderer != nil and not metalRenderer.encoder.isNil:
    when defined(metalProfile):
      profileEndRenderPass()
    metalRenderer.encoder.endEncoding()
    metalRenderer.encoder = 0.MTLRenderCommandEncoder

proc removeBuffer(buffer: MetalBuffer) =
  ## Removes a retired buffer from the shutdown registry.
  if metalRenderer != nil:
    for i in countdown(metalRenderer.buffers.high, 0):
      if metalRenderer.buffers[i] == buffer:
        metalRenderer.buffers.delete(i)

proc destroy*(buffer: MetalBuffer) =
  ## Releases a buffer owned by the engine.
  if buffer != nil:
    buffer.handle.release()
    buffer.handle = 0.MTLBuffer
    buffer.size = 0
    removeBuffer(buffer)

proc destroy*(texture: MetalTexture) =
  ## Releases owned texture and sampler resources.
  if texture != nil:
    if texture.ownsHandle:
      texture.handle.release()
    texture.sampler.release()
    texture.comparisonSampler.release()
    texture.handle = 0.MTLTexture
    texture.sampler = 0.MTLSamplerState
    texture.comparisonSampler = 0.MTLSamplerState
    if metalRenderer != nil:
      for i in countdown(metalRenderer.textures.high, 0):
        if metalRenderer.textures[i] == texture:
          metalRenderer.textures.delete(i)

proc destroy*(program: MetalProgram) =
  ## Releases shader functions and their cached pipelines.
  if program != nil:
    program.vertexFunction.release()
    program.fragmentFunction.release()
    program.vertexFunction = 0.MTLFunction
    program.fragmentFunction = 0.MTLFunction
    for pipeline in program.pipelines:
      pipeline.handle.release()
    program.pipelines.setLen(0)
    if metalRenderer != nil:
      for i in countdown(metalRenderer.programs.high, 0):
        if metalRenderer.programs[i] == program:
          metalRenderer.programs.delete(i)

proc destroy*(target: RenderTarget) =
  ## Releases a target's color, depth and multisample textures.
  if target != nil:
    if not target.borrowsColor:
      destroy(target.color)
    if not target.borrowsDepth:
      destroy(target.depth)
      destroy(target.multisampleDepth)
    destroy(target.multisampleColor)

proc sampler(linear, repeat, comparison: bool): MTLSamplerState =
  ## Creates an explicit sampling state for a texture.
  let descriptor = MTLSamplerDescriptor.alloc().init()
  defer: descriptor.release()
  let filter = if linear: MTLSamplerMinMagFilterLinear
    else: MTLSamplerMinMagFilterNearest
  descriptor.setMinFilter(filter)
  descriptor.setMagFilter(filter)
  descriptor.setMipFilter(MTLSamplerMipFilterLinear)
  descriptor.setMaxAnisotropy(if linear: 8'u else: 1'u)
  let mode = if repeat: MTLSamplerAddressModeRepeat
    else: MTLSamplerAddressModeClampToEdge
  descriptor.setSAddressMode(mode)
  descriptor.setTAddressMode(mode)
  if comparison:
    descriptor.setCompareFunction(MTLCompareFunctionLessEqual)
  result = metalRenderer.ctx.device.newSamplerStateWithDescriptor(descriptor)
  checkNil(result, "Could not create a Metal sampler")

proc setTextureSampling*(texture: MetalTexture, linear: bool,
    repeat = false) =
  ## Replaces the sampling state without changing texture contents.
  texture.sampler.release()
  texture.sampler = sampler(linear, repeat, false)

proc textureFromNative*(
  handle: MTLTexture, width, height: int, pixelFormat: MTLPixelFormat,
  ownsHandle = false, linear = true, repeat = false
): MetalTexture =
  ## Wraps a native texture with the engine's sampling and lifetime metadata.
  requireRenderer()
  checkNil(handle, "Cannot wrap a nil Metal texture")
  result = MetalTexture(
    handle: handle, width: width, height: height, pixelFormat: pixelFormat,
    ownsHandle: ownsHandle, sampler: sampler(linear, repeat, false)
  )
  metalRenderer.textures.add(result)

proc allocateTexture(
  width, height: int, format: MTLPixelFormat, samples = 1, mipmapped = false
): MetalTexture =
  ## Allocates a sampleable render attachment on the shared device.
  nativePool()
  let descriptor = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
    format, width.uint, height.uint, mipmapped
  )
  descriptor.setUsage(MTLTextureUsageRenderTarget or MTLTextureUsageShaderRead)
  if samples > 1:
    descriptor.setTextureType(4)
    descriptor.setSampleCount(samples.uint)
    descriptor.setStorageMode(MTLStorageModePrivate)
  elif format == MTLPixelFormatDepth32Float or
      format == MTLPixelFormatDepth32Float_Stencil8:
    descriptor.setStorageMode(MTLStorageModePrivate)
  result = textureFromNative(
    metalRenderer.ctx.device.newTextureWithDescriptor(descriptor),
    width, height, format, ownsHandle = true
  )

proc newRenderTarget*(
  width, height: int, color = true, depth = true, samples = 1,
  colorFormat: MTLPixelFormat = MTLPixelFormatRGBA8Unorm, stencil = false,
  mipmapped = false
): RenderTarget =
  ## Allocates resolved attachments and optional multisample attachments.
  requireRenderer()
  if width <= 0 or height <= 0 or samples <= 0:
    raise newException(PolyworldMetalError, "Invalid Metal target dimensions")
  result = RenderTarget(width: width, height: height, samples: samples,
    stencil: stencil and depth)
  if color:
    result.color = allocateTexture(width, height, colorFormat,
      mipmapped = mipmapped)
    if samples > 1:
      result.multisampleColor = allocateTexture(
        width, height, colorFormat, samples
      )
  if depth:
    let format = if stencil: MTLPixelFormatDepth32Float_Stencil8
      else: MTLPixelFormatDepth32Float
    result.depth = allocateTexture(width, height, format)
    if samples > 1:
      result.multisampleDepth = allocateTexture(width, height, format, samples)

proc renderSamples*(target: RenderTarget): int =
  ## Returns the sample count of the target's current rendering phase.
  if target.resolved: 1 else: target.samples

proc shareDepth*(target, source: RenderTarget) =
  ## Shares an existing depth attachment with a compatible color pass.
  if target == source:
    return
  if target.width != source.width or target.height != source.height or
    target.samples != source.samples:
      raise newException(PolyworldMetalError, "Shared depth target mismatch")
  if not target.borrowsDepth:
    destroy(target.depth)
    destroy(target.multisampleDepth)
  target.borrowsDepth = true
  target.depth = source.depth
  target.multisampleDepth = source.multisampleDepth
  target.stencil = source.stencil
  target.resolved = source.resolved

proc updateTexture*(texture: MetalTexture, image: Image) =
  ## Uploads RGBA pixels without changing textures used by earlier draws.
  nativePool()
  if image.width != texture.width or image.height != texture.height:
    raise newException(PolyworldMetalError, "Metal texture upload size mismatch")
  if not metalRenderer.commandBuffer.isNil and
    texture.lastUse == metalRenderer.commandSerial:
      let descriptor = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
        texture.pixelFormat, texture.width.uint, texture.height.uint,
        texture.handle.mipmapLevelCount() > 1
      )
      descriptor.setUsage(MTLTextureUsageShaderRead)
      let replacement = metalRenderer.ctx.device.newTextureWithDescriptor(
        descriptor
      )
      checkNil(replacement, "Could not replace an in-use Metal texture")
      if texture.ownsHandle:
        texture.handle.release()
      texture.handle = replacement
      texture.ownsHandle = true
      texture.lastUse = 0
  texture.handle.replaceRegion(
    MTLRegion(origin: MTLOrigin(), size: MTLSize(
      width: image.width.uint, height: image.height.uint, depth: 1
    )), 0, image.data[0].addr, (image.width * 4).uint
  )

proc generateMipmaps*(texture: MetalTexture) =
  ## Generates mip levels after an upload or render-to-texture pass.
  nativePool()
  flushEncoder()
  let ownsCommands = metalRenderer.commandBuffer.isNil
  let commands = if ownsCommands: metalRenderer.ctx.newCommandBuffer()
    else: metalRenderer.commandBuffer
  let encoder = commands.blitCommandEncoder()
  when defined(metalProfile):
    profileBlitPass()
  encoder.generateMipmapsForTexture(texture.handle)
  encoder.endEncoding()
  if ownsCommands:
    commands.commit()
    commands.waitUntilCompleted()
    when defined(metalProfile):
      profileCommandBuffer(commands.GPUStartTime(), commands.GPUEndTime())
    checkNSError(commands.error(), "Could not generate Metal texture mips")

proc newTexture*(image: Image, linear = true, repeat = false,
    mipmaps = false): MetalTexture =
  ## Uploads an image into a shader-readable RGBA texture.
  nativePool()
  requireRenderer()
  let descriptor = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
    MTLPixelFormatRGBA8Unorm, image.width.uint, image.height.uint, mipmaps
  )
  descriptor.setUsage(MTLTextureUsageShaderRead)
  result = textureFromNative(
    metalRenderer.ctx.device.newTextureWithDescriptor(descriptor),
    image.width, image.height, MTLPixelFormatRGBA8Unorm, true, linear, repeat
  )
  result.updateTexture(image)
  if mipmaps:
    result.generateMipmaps()

proc updateBuffer*[T](buffer: MetalBuffer, data: openArray[T]) =
  ## Replaces immutable draw data without modifying resources in flight.
  requireRenderer()
  buffer.handle.release()
  buffer.handle = 0.MTLBuffer
  buffer.size = data.len * sizeof(T)
  if data.len > 0:
    buffer.handle = metalRenderer.ctx.device.newBufferWithBytes(
      unsafeAddr data[0], buffer.size.uint, 0
    )
    checkNil(buffer.handle, "Could not allocate a Metal vertex buffer")
    when defined(metalProfile):
      profileBuffer(buffer.size)

proc newBuffer*[T](data: openArray[T]): MetalBuffer =
  ## Uploads typed vertex or index data into a retained Metal buffer.
  result = MetalBuffer()
  result.updateBuffer(data)
  metalRenderer.buffers.add(result)

proc parseBinding(line, marker: string): int =
  ## Reads an integer attribute from compiler-generated MSL.
  let start = line.find(marker)
  if start < 0:
    return -1
  try:
    result = parseInt(line[start + marker.len ..< line.find(')', start)])
  except ValueError as error:
    raise newException(PolyworldMetalError, error.msg)

proc textureBindings(source: string): seq[TextureBinding] =
  ## Reflects named texture and sampler indices from Shady declarations.
  for line in source.splitLines():
    let index = parseBinding(line, "[[texture(")
    if index >= 0:
      let words = strutils.splitWhitespace(line.strip())
      result.add(TextureBinding(
        name: words[1], index: index, samplerIndex: index,
        comparison: words[0].startsWith("depth")
      ))
  for line in source.splitLines():
    let index = parseBinding(line, "[[sampler(")
    if index >= 0:
      let words = strutils.splitWhitespace(line.strip())
      for binding in result.mitems:
        if words[1] == binding.name & "Sampler":
          binding.samplerIndex = index

proc compileFunction(source, entry: string): MTLFunction =
  ## Compiles one generated Shady stage through the native Metal compiler.
  nativePool()
  if source.len == 0:
    return 0.MTLFunction
  var error: NSError
  let library = metalRenderer.ctx.device.newLibraryWithSource(
    @source, 0.ID, error.addr
  )
  checkNSError(error, "Could not compile " & entry & "\n" & source)
  checkNil(library, "Metal returned an empty shader library")
  defer: library.release()
  result = library.newFunctionWithName(@entry)
  checkNil(result, "Metal shader entry is missing: " & entry)

proc newProgram*(
  vertexSource, fragmentSource: string,
  layout = VertexLayout()
): MetalProgram =
  ## Compiles generated MSL and reflects uniform and texture bindings.
  requireRenderer()
  result = MetalProgram(
    vertexSource: vertexSource, fragmentSource: fragmentSource, layout: layout,
    vertexUniforms: initUniformBuffer(vertexSource),
    fragmentUniforms: initUniformBuffer(fragmentSource),
    vertexTextures: textureBindings(vertexSource),
    fragmentTextures: textureBindings(fragmentSource)
  )
  try:
    result.vertexFunction = compileFunction(vertexSource, "vertexMain")
    result.fragmentFunction = compileFunction(fragmentSource, "fragmentMain")
  except:
    destroy(result)
    raise
  metalRenderer.programs.add(result)

proc setVertexLayout*(program: MetalProgram, layout: VertexLayout) =
  ## Selects the vertex interpretation used by subsequent draws.
  program.layout = layout

proc setUniform*[T](program: MetalProgram, name: string, value: T) =
  ## Packs a named uniform into every stage that declares it.
  discard program.vertexUniforms.setUniform(name, value)
  discard program.fragmentUniforms.setUniform(name, value)

proc bindTexture*(program: MetalProgram, name: string, texture: MetalTexture) =
  ## Associates a named shader input with a texture for subsequent draws.
  program.textures[name] = texture

proc compareFunction(compare: DepthCompare): MTLCompareFunction =
  ## Maps engine comparison choices to native Metal values.
  case compare
  of LessEqual: MTLCompareFunctionLessEqual
  of Less: MTLCompareFunctionLess
  of Always: MTLCompareFunctionAlways
  of Equal: MTLCompareFunctionEqual
  of Greater: MTLCompareFunctionGreater

proc setStencil*(write: bool, reference: int, compare = Always) =
  ## Applies a stencil override to subsequent feature draws.
  metalRenderer.hasStencilOverride = true
  metalRenderer.stencilOverride = DrawState(
    stencilTest: true, stencilWrite: write,
    stencilReference: reference, stencilCompare: compare
  )

proc clearStencilState*() =
  ## Restores each draw's explicit stencil configuration.
  metalRenderer.hasStencilOverride = false

proc makePass(clearColor: bool, color: Color, clearDepth: bool,
    clearStencil = false):
    MTLRenderPassDescriptor =
  ## Builds load/store actions for the current resolved or multisample target.
  let target = metalRenderer.target
  result = MTLRenderPassDescriptor.renderPassDescriptor()
  if target.color != nil:
    let attachment = result.colorAttachments().objectAtIndexedSubscript(0)
    attachment.setTexture(target.color.handle)
    attachment.setStoreAction(MTLStoreActionStore)
    if target.renderSamples() > 1:
      attachment.setTexture(target.multisampleColor.handle)
      attachment.setResolveTexture(target.color.handle)
      attachment.setStoreAction(MTLStoreActionStoreAndMultisampleResolve)
    attachment.setLoadAction(
      if clearColor: MTLLoadActionClear else: MTLLoadActionLoad
    )
    attachment.setClearColor(MTLClearColor(
      red: color.r.float64, green: color.g.float64,
      blue: color.b.float64, alpha: color.a.float64
    ))
  if target.depth != nil:
    let attachment = result.depthAttachment()
    attachment.setTexture(target.depth.handle)
    attachment.setStoreAction(MTLStoreActionStore)
    if target.renderSamples() > 1:
      attachment.setTexture(target.multisampleDepth.handle)
      attachment.setResolveTexture(target.depth.handle)
      attachment.setDepthResolveFilter(0)
      attachment.setStoreAction(MTLStoreActionStoreAndMultisampleResolve)
    attachment.setLoadAction(
      if clearDepth: MTLLoadActionClear else: MTLLoadActionLoad
    )
    attachment.setClearDepth(1.0)
    if target.stencil:
      let stencil = result.stencilAttachment()
      stencil.setTexture(if target.renderSamples() > 1:
        target.multisampleDepth.handle else: target.depth.handle)
      stencil.setStoreAction(MTLStoreActionStore)
      if target.renderSamples() > 1:
        stencil.setResolveTexture(target.depth.handle)
        stencil.setStencilResolveFilter(0)
        stencil.setStoreAction(MTLStoreActionStoreAndMultisampleResolve)
      stencil.setLoadAction(
        if clearStencil: MTLLoadActionClear else: MTLLoadActionLoad
      )
      stencil.setClearStencil(0)

proc ensureEncoder() =
  ## Opens a preserving render pass when a feature first draws.
  if metalRenderer.commandBuffer.isNil or metalRenderer.target == nil:
    raise newException(PolyworldMetalError, "No active Metal frame")
  if metalRenderer.encoder.isNil:
    metalRenderer.encoder =
      metalRenderer.commandBuffer.renderCommandEncoderWithDescriptor(
        makePass(false, color(0, 0, 0, 0), false)
      )
    checkNil(metalRenderer.encoder, "Could not open a Metal render pass")
    when defined(metalProfile):
      profileRenderPass()
    metalRenderer.encoder.setViewport(MTLViewport(
      width: metalRenderer.viewport.x.float64,
      height: metalRenderer.viewport.y.float64, znear: 0, zfar: 1
    ))

proc clear*(color: Color, depth = true, stencil = false) =
  ## Clears color and optionally depth and stencil in the current target.
  flushEncoder()
  if depth or metalRenderer.target.depth == nil:
    metalRenderer.target.resolved = false
  metalRenderer.encoder =
    metalRenderer.commandBuffer.renderCommandEncoderWithDescriptor(
      makePass(true, color, depth, stencil)
    )
  when defined(metalProfile):
    profileRenderPass()
  flushEncoder()

proc clearDepth*() =
  ## Clears the current target's depth while preserving color and stencil.
  flushEncoder()
  metalRenderer.encoder =
    metalRenderer.commandBuffer.renderCommandEncoderWithDescriptor(
      makePass(false, color(0, 0, 0, 0), true)
    )
  when defined(metalProfile):
    profileRenderPass()
  flushEncoder()

proc setTarget*(target: RenderTarget = nil) =
  ## Selects a target without submitting the shared command buffer.
  flushEncoder()
  metalRenderer.target = if target == nil:
    metalRenderer.frameTarget else: target
  metalRenderer.viewport = ivec2(
    metalRenderer.target.width.int32, metalRenderer.target.height.int32
  )

proc ensureFrame*(width, height: int)

proc pushTarget*(target: RenderTarget) =
  ## Saves the active target and opens an offscreen pass on demand.
  if metalRenderer.commandBuffer.isNil:
    let size = metalRenderer.ctx.window.size
    ensureFrame(max(1, size.x.int), max(1, size.y.int))
  metalRenderer.targets.add(metalRenderer.target)
  metalRenderer.viewports.add(metalRenderer.viewport)
  setTarget(target)

proc popTarget*() =
  ## Restores the previous target and preserves its rendered contents.
  if metalRenderer.targets.len == 0:
    raise newException(PolyworldMetalError, "Metal target stack is empty")
  setTarget(metalRenderer.targets.pop())
  metalRenderer.viewport = metalRenderer.viewports.pop()

proc resolveForUi*(): RenderTarget =
  ## Continues on resolved attachments until the next full target clear.
  flushEncoder()
  result = metalRenderer.target
  result.resolved = true

proc copyTexture(source, destination: MetalTexture) =
  ## Copies one resolved attachment with a native blit command.
  if source == nil or destination == nil:
    return
  if source.width != destination.width or source.height != destination.height or
    source.pixelFormat != destination.pixelFormat:
      raise newException(PolyworldMetalError, "Metal texture copy mismatch")
  let encoder = metalRenderer.commandBuffer.blitCommandEncoder()
  when defined(metalProfile):
    profileBlitPass()
  encoder.copyFromTexture(
    source.handle, 0, 0, MTLOrigin(),
    MTLSize(width: source.width.uint, height: source.height.uint, depth: 1),
    destination.handle, 0, 0, MTLOrigin()
  )
  encoder.endEncoding()

proc copyTarget*(source, destination: RenderTarget, color = true,
    depth = true) =
  ## Copies resolved color and depth between matching offscreen targets.
  if destination.renderSamples() > 1:
    raise newException(PolyworldMetalError,
      "Metal target copies require a single-sample destination")
  flushEncoder()
  if color:
    copyTexture(source.color, destination.color)
  if depth:
    copyTexture(source.depth, destination.depth)

proc snapshotTarget*(color = true, depth = true): RenderTarget =
  ## Copies the active target into new single-sample attachments.
  let target = metalRenderer.target
  result = newRenderTarget(
    target.width, target.height, color and target.color != nil,
    depth and target.depth != nil,
    colorFormat = if target.color != nil: target.color.pixelFormat
      else: MTLPixelFormatRGBA8Unorm,
    stencil = target.stencil
  )
  copyTarget(target, result, color, depth)

proc vertexDescriptor(program: MetalProgram, layout: VertexLayout):
    MTLVertexDescriptor =
  ## Matches named Shady inputs to the packed vertex layout.
  result = MTLVertexDescriptor.vertexDescriptor()
  let buffer = result.layouts().objectAtIndexedSubscript(GeometryBufferIndex)
  buffer.setStride(layout.stride.uint)
  buffer.setStepFunction(MTLVertexStepFunctionPerVertex)
  for line in program.vertexSource.splitLines():
    let location = parseBinding(line, "[[attribute(")
    if location < 0:
      continue
    let words = strutils.splitWhitespace(line.strip())
    var found = false
    for attribute in layout.attributes:
      if attribute.name == words[1]:
        found = true
        let descriptor = result.attributes().objectAtIndexedSubscript(
          location.uint
        )
        let format = case attribute.format
          of Float1: MTLVertexFormatFloat
          of Float2: MTLVertexFormatFloat2
          of Float3: MTLVertexFormatFloat3
          of Float4: MTLVertexFormatFloat4
          of UInt1: MTLVertexFormatUInt
          of UInt2: MTLVertexFormatUInt2
          of UInt3: MTLVertexFormatUInt3
          of UInt4: MTLVertexFormatUInt4
        descriptor.setFormat(format)
        descriptor.setOffset(attribute.offset.uint)
        descriptor.setBufferIndex(GeometryBufferIndex)
    if not found:
      raise newException(PolyworldMetalError,
        "Missing Metal vertex attribute: " & words[1])

proc pipeline(program: MetalProgram, state: DrawState,
    layout: VertexLayout): MTLRenderPipelineState =
  ## Reuses pipelines with identical attachments and vertex interpretation.
  let
    target = metalRenderer.target
    colorFormat = if target.color == nil: MTLPixelFormatInvalid
      else: target.color.pixelFormat
    depthFormat = if target.depth == nil: MTLPixelFormatInvalid
      else: target.depth.pixelFormat
  for entry in program.pipelines:
    if entry.layout == layout and entry.blend == state.blend and
      entry.colorFormat == colorFormat and entry.depthFormat == depthFormat and
      entry.samples == target.renderSamples() and entry.stencil == target.stencil:
        return entry.handle
  let descriptor = MTLRenderPipelineDescriptor.alloc().init()
  defer: descriptor.release()
  descriptor.setVertexFunction(program.vertexFunction)
  descriptor.setFragmentFunction(program.fragmentFunction)
  if layout.stride > 0:
    descriptor.setVertexDescriptor(vertexDescriptor(program, layout))
  descriptor.setDepthAttachmentPixelFormat(depthFormat)
  if target.stencil:
    descriptor.setStencilAttachmentPixelFormat(depthFormat)
  descriptor.setRasterSampleCount(target.renderSamples().uint)
  let attachment = descriptor.colorAttachments().objectAtIndexedSubscript(0)
  attachment.setPixelFormat(colorFormat)
  if colorFormat != MTLPixelFormatInvalid and state.blend != Opaque:
    attachment.setBlendingEnabled(true)
    attachment.setRgbBlendOperation(MTLBlendOperationAdd)
    attachment.setAlphaBlendOperation(MTLBlendOperationAdd)
    var
      source = MTLBlendFactorSourceAlpha
      destination = MTLBlendFactorOneMinusSourceAlpha
      alphaSource = MTLBlendFactorOne
      alphaDestination = MTLBlendFactorOneMinusSourceAlpha
    case state.blend
    of PremultipliedAlpha:
      source = MTLBlendFactorOne
    of Additive:
      destination = MTLBlendFactorOne
      alphaSource = MTLBlendFactorZero
      alphaDestination = MTLBlendFactorOne
    of StraightAlpha:
      alphaSource = MTLBlendFactorSourceAlpha
    of AlphaBlendPreserveAlpha:
      alphaSource = MTLBlendFactorZero
      alphaDestination = MTLBlendFactorOne
    of Multiply:
      source = MTLBlendFactorDestinationColor
      destination = MTLBlendFactorZero
      alphaSource = MTLBlendFactorZero
      alphaDestination = MTLBlendFactorOne
    else: discard
    attachment.setSourceRGBBlendFactor(source)
    attachment.setDestinationRGBBlendFactor(destination)
    attachment.setSourceAlphaBlendFactor(alphaSource)
    attachment.setDestinationAlphaBlendFactor(alphaDestination)
  var error: NSError
  result = metalRenderer.ctx.device.newRenderPipelineStateWithDescriptor(
    descriptor, error.addr
  )
  checkNSError(error, "Could not create a Polyworld Metal render pipeline")
  checkNil(result, "Metal returned an empty render pipeline")
  program.pipelines.add(PipelineEntry(
    layout: layout, blend: state.blend, colorFormat: colorFormat,
    depthFormat: depthFormat, samples: target.renderSamples(),
    stencil: target.stencil, handle: result
  ))

proc depthState(state: DrawState): MTLDepthStencilState =
  ## Caches depth and stencil functions independently of render pipelines.
  let key = $state.depthTest & $state.depthWrite & $state.depthCompare &
    $state.stencilTest & $state.stencilWrite & $state.stencilCompare
  if key in metalRenderer.depthStates:
    return metalRenderer.depthStates[key]
  let descriptor = MTLDepthStencilDescriptor.alloc().init()
  defer: descriptor.release()
  descriptor.setDepthCompareFunction(if state.depthTest:
    compareFunction(state.depthCompare) else: MTLCompareFunctionAlways)
  descriptor.setDepthWriteEnabled(state.depthWrite)
  if state.stencilTest or state.stencilWrite:
    let stencil = MTLStencilDescriptor.alloc().init()
    defer: stencil.release()
    stencil.setStencilCompareFunction(compareFunction(state.stencilCompare))
    stencil.setReadMask(255)
    stencil.setWriteMask(if state.stencilWrite: 255'u32 else: 0'u32)
    stencil.setStencilFailureOperation(0)
    stencil.setDepthFailureOperation(0)
    stencil.setDepthStencilPassOperation(if state.stencilWrite: 2'u else: 0'u)
    descriptor.setFrontFaceStencil(stencil)
    descriptor.setBackFaceStencil(stencil)
  result = metalRenderer.ctx.device.newDepthStencilStateWithDescriptor(
    descriptor
  )
  checkNil(result, "Could not create a Metal depth state")
  metalRenderer.depthStates[key] = result

proc bindUniforms(buffer: var UniformBuffer, vertex: bool) =
  ## Copies immutable per-draw constants, including large skinning buffers.
  if buffer.data.len == 0:
    return
  when defined(metalProfile):
    profileUniforms(buffer.data.len)
  let index = if vertex: 0'u else: 1'u
  if buffer.data.len <= 4096:
    if vertex:
      metalRenderer.encoder.setVertexBytes(
        buffer.data[0].addr, buffer.data.len.uint, index
      )
    else:
      metalRenderer.encoder.setFragmentBytes(
        buffer.data[0].addr, buffer.data.len.uint, index
      )
  else:
    let nativeBuffer = metalRenderer.ctx.device.newBufferWithBytes(
      buffer.data[0].addr, buffer.data.len.uint, 0
    )
    checkNil(nativeBuffer, "Could not upload Metal shader constants")
    when defined(metalProfile):
      profileBuffer(buffer.data.len)
    defer: nativeBuffer.release()
    if vertex:
      metalRenderer.encoder.setVertexBuffer(nativeBuffer, 0, index)
    else:
      metalRenderer.encoder.setFragmentBuffer(nativeBuffer, 0, index)

proc bindTextures(program: MetalProgram, bindings: seq[TextureBinding],
    vertex: bool) =
  ## Applies each reflected texture and sampler to its shader stage.
  for binding in bindings:
    let texture = program.textures.getOrDefault(binding.name)
    if texture == nil or texture.handle.isNil:
      raise newException(PolyworldMetalError,
        "Unbound Metal shader texture: " & binding.name)
    texture.lastUse = metalRenderer.commandSerial
    var nativeSampler = texture.sampler
    if binding.comparison:
      if texture.comparisonSampler.isNil:
        texture.comparisonSampler = sampler(true, false, true)
      nativeSampler = texture.comparisonSampler
    if vertex:
      metalRenderer.encoder.setVertexTexture(texture.handle, binding.index.uint)
      metalRenderer.encoder.setVertexSamplerState(
        nativeSampler, binding.samplerIndex.uint
      )
    else:
      metalRenderer.encoder.setFragmentTexture(texture.handle, binding.index.uint)
      metalRenderer.encoder.setFragmentSamplerState(
        nativeSampler, binding.samplerIndex.uint
      )

proc draw*(
  program: MetalProgram, vertices: MetalBuffer, count: int,
  state = DrawState(), indices: MetalBuffer = nil, first = 0,
  index32 = true, instanceCount = 1, layout = VertexLayout()
) =
  ## Encodes one explicit indexed, procedural or instanced draw.
  if count <= 0 or instanceCount <= 0:
    return
  ensureEncoder()
  when defined(metalProfile):
    profileDraw()
  var effectiveState = state
  if metalRenderer.hasStencilOverride:
    effectiveState.stencilTest = metalRenderer.stencilOverride.stencilTest
    effectiveState.stencilWrite = metalRenderer.stencilOverride.stencilWrite
    effectiveState.stencilCompare = metalRenderer.stencilOverride.stencilCompare
    effectiveState.stencilReference =
      metalRenderer.stencilOverride.stencilReference
  let effectiveLayout = if layout.stride > 0: layout else: program.layout
  let encoder = metalRenderer.encoder
  encoder.setRenderPipelineState(pipeline(program, effectiveState,
    effectiveLayout))
  encoder.setDepthStencilState(depthState(effectiveState))
  encoder.setStencilReferenceValue(effectiveState.stencilReference.uint32)
  encoder.setCullMode(case effectiveState.cull
    of CullNone: MTLCullModeNone
    of CullBack: MTLCullModeBack
    of CullFront: MTLCullModeFront)
  encoder.setFrontFacingWinding(MTLWindingCounterClockwise)
  encoder.setTriangleFillMode(if effectiveState.wireframe: 1'u else: 0'u)
  if vertices != nil:
    encoder.setVertexBuffer(vertices.handle, 0, GeometryBufferIndex)
  bindUniforms(program.vertexUniforms, true)
  bindUniforms(program.fragmentUniforms, false)
  bindTextures(program, program.vertexTextures, true)
  bindTextures(program, program.fragmentTextures, false)
  let primitive = case effectiveState.primitive
    of Triangles: MTLPrimitiveTypeTriangle
    of Lines: MTLPrimitiveTypeLine
    of Points: MTLPrimitiveTypePoint
    of TriangleStrip: MTLPrimitiveTypeTriangleStrip
  if indices == nil:
    encoder.drawPrimitives(primitive, first.uint, count.uint, instanceCount.uint)
  else:
    encoder.drawIndexedPrimitives(
      primitive, count.uint, (if index32: 1'u else: 0'u), indices.handle,
      (first * (if index32: 4 else: 2)).uint, instanceCount.uint
    )

proc initMetal*(window: Window) =
  ## Creates the single device, queue and presentation layer for the engine.
  nativePool()
  if metalRenderer != nil:
    return
  metalRenderer = MetalRenderer(frameSamples: 1)
  metalRenderer.ctx.init(window)
  metalRenderer.presentProgram = newProgram(
    toMSL(presentVertex, shaderVertex), toMSL(presentFragment, shaderFragment),
    VertexLayout(stride: 16, attributes: @[
      VertexAttribute(name: "position", format: Float2, offset: 0),
      VertexAttribute(name: "texcoord", format: Float2, offset: 8)
    ])
  )
  metalRenderer.presentVertices = newBuffer([
    -1.0'f, -1, 0, 1, 1, -1, 1, 1, 1, 1, 1, 0,
    -1.0'f, -1, 0, 1, 1, 1, 1, 0, -1, 1, 0, 0
  ])

proc setFrameSamples*(samples: int) =
  ## Chooses the highest supported frame sample count up to the request.
  requireRenderer()
  var supported = 1
  for count in [2, 4, 8, 16]:
    if count <= samples and
      metalRenderer.ctx.device.supportsTextureSampleCount(count.uint):
        supported = count
  metalRenderer.frameSamples = supported

proc ensureFrame*(width, height: int) =
  ## Creates a command buffer and resizes the shared frame when necessary.
  requireRenderer()
  if not metalRenderer.commandBuffer.isNil:
    return
  metalRenderer.framePool = cast[ID](nativeObjc.NSAutoreleasePool.new())
  if metalRenderer.frameTarget == nil or
    metalRenderer.frameTarget.width != width or
    metalRenderer.frameTarget.height != height or
    metalRenderer.frameTarget.samples != metalRenderer.frameSamples:
      destroy(metalRenderer.frameTarget)
      metalRenderer.frameTarget = newRenderTarget(width, height,
        samples = metalRenderer.frameSamples, stencil = true)
  inc metalRenderer.commandSerial
  metalRenderer.commandBuffer = metalRenderer.ctx.newCommandBuffer()
  metalRenderer.commandBuffer.retain()
  metalRenderer.target = metalRenderer.frameTarget
  metalRenderer.viewport = ivec2(width.int32, height.int32)
  metalRenderer.targets.setLen(0)
  metalRenderer.viewports.setLen(0)

proc beginFrame*(width, height: int, clearColor: Color) =
  ## Starts a frame and clears its shared scene attachments.
  ensureFrame(width, height)
  setTarget()
  clear(clearColor, stencil = true)

proc setRenderViewport*(size: IVec2) =
  ## Applies a viewport to the active render pass.
  metalRenderer.viewport = size
  ensureEncoder()
  metalRenderer.encoder.setViewport(MTLViewport(
    width: size.x.float64, height: size.y.float64, znear: 0, zfar: 1
  ))

proc endFrame*(present = true) =
  ## Resolves the frame, presents it, and waits before CPU readback or reuse.
  if metalRenderer == nil or metalRenderer.commandBuffer.isNil:
    return
  flushEncoder()
  if present:
    let drawable = metalRenderer.ctx.currentDrawable()
    if not drawable.isNil:
      let nativeTexture = drawable.texture()
      let drawableTarget = RenderTarget(
        width: nativeTexture.width().int, height: nativeTexture.height().int,
        samples: 1,
        color: textureFromNative(nativeTexture, nativeTexture.width().int,
          nativeTexture.height().int, MTLPixelFormatBGRA8Unorm)
      )
      setTarget(drawableTarget)
      metalRenderer.presentProgram.bindTexture(
        "presentTexture", metalRenderer.frameTarget.color
      )
      draw(metalRenderer.presentProgram, metalRenderer.presentVertices, 6)
      flushEncoder()
      destroy(drawableTarget)
      metalRenderer.commandBuffer.presentDrawable(drawable)
  metalRenderer.commandBuffer.commit()
  metalRenderer.commandBuffer.waitUntilCompleted()
  when defined(metalProfile):
    profileCommandBuffer(metalRenderer.commandBuffer.GPUStartTime(),
      metalRenderer.commandBuffer.GPUEndTime())
  let error = metalRenderer.commandBuffer.error()
  let message = if error.isNil: "" else:
    messageNSError(error, "Polyworld Metal frame failed")
  metalRenderer.commandBuffer.release()
  metalRenderer.commandBuffer = 0.MTLCommandBuffer
  metalRenderer.target = metalRenderer.frameTarget
  metalRenderer.framePool.release()
  metalRenderer.framePool = 0.ID
  if message.len > 0:
    raise newException(PolyworldMetalError, message)

proc waitForGpu*() =
  ## Submits queued work and resumes encoding with the target stack intact.
  if metalRenderer.commandBuffer.isNil:
    return
  let
    previous = metalRenderer.target
    viewport = metalRenderer.viewport
  endFrame(false)
  metalRenderer.framePool = cast[ID](nativeObjc.NSAutoreleasePool.new())
  inc metalRenderer.commandSerial
  metalRenderer.commandBuffer = metalRenderer.ctx.newCommandBuffer()
  metalRenderer.commandBuffer.retain()
  metalRenderer.target = previous
  metalRenderer.viewport = viewport

proc captureTargetImage*(target: RenderTarget = nil): Image =
  ## Reads resolved RGBA pixels while preserving the active target and stack.
  let selected = if target == nil: metalRenderer.target else: target
  if selected == nil or selected.color == nil:
    raise newException(PolyworldMetalError, "No Metal color target to capture")
  if selected.color.pixelFormat != MTLPixelFormatRGBA8Unorm:
    raise newException(PolyworldMetalError, "Capture requires an RGBA8 target")
  waitForGpu()
  result = newImage(selected.width, selected.height)
  selected.color.handle.getBytes(
    result.data[0].addr, (selected.width * 4).uint,
    MTLRegion(origin: MTLOrigin(), size: MTLSize(
      width: selected.width.uint, height: selected.height.uint, depth: 1
    )), 0
  )

proc captureImage*(): Image =
  ## Reads the active resolved target without disrupting offscreen rendering.
  captureTargetImage()

proc readFrameImage*(width, height: int): Image =
  ## Reads the current frame, resizing only when the caller requests it.
  result = captureImage()
  if result.width != width or result.height != height:
    result = result.resize(width, height)

proc shutdownMetal*() =
  ## Releases engine resources before destroying the presentation context.
  if metalRenderer == nil:
    return
  endFrame(false)
  while metalRenderer.programs.len > 0:
    destroy(metalRenderer.programs[^1])
  while metalRenderer.buffers.len > 0:
    destroy(metalRenderer.buffers[^1])
  while metalRenderer.textures.len > 0:
    destroy(metalRenderer.textures[^1])
  for state in metalRenderer.depthStates.values:
    state.release()
  metalRenderer.ctx.destroy()
  metalRenderer = nil
