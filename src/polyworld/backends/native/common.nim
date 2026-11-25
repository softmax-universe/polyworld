## Shared scene commands for the D3D12 and Vulkan implementations.
import std/[json, strutils, tables], pixie, vmath, windy, shady
import device, stages
export device, stages

type
  VertexBuffer* = ref object
    handle: GpuBuffer
  GpuImage* = ref object
    handle*: GpuTexture
    sampling*: SamplerState
  RenderTarget* = ref object
    width*, height*, samples*: int
    color*, depth*: GpuImage
    multisampleColor, multisampleDepth: GpuImage
    stencil*, borrowsDepth, resolved: bool
  PipelineKey = tuple[state: DrawState, layout: VertexLayout, color, depth: TextureFormat, hasColor, hasDepth: bool, samples: int]
  ShaderProgram* = ref object
    label: string
    code: ProgramCode
    layout: VertexLayout
    vertex, fragment: GpuConstants
    textures: Table[string, GpuImage]
    shadowInputs: seq[string]
    pipelines: Table[PipelineKey, GpuProgram]
  RendererState* = ref object
    ctx*: GpuContext
    window: Window
    frameSamples: int
    frameTarget*, target*: RenderTarget
    viewport: IVec2
    stack: seq[tuple[target: RenderTarget, viewport: IVec2]]
    stencil: DrawState
    samplers: Table[SamplerState, GpuSampler]
    retiredBuffers: seq[GpuBuffer]
    retiredTextures: seq[GpuTexture]
    retiredPipelines: seq[GpuProgram]
    blit: ShaderProgram
    quad: VertexBuffer
    programs: seq[ShaderProgram]
    buffers: seq[VertexBuffer]
    images: seq[GpuImage]

var gpuRenderer*: RendererState

proc initNative*(window: Window) =
  if gpuRenderer == nil:
    gpuRenderer = RendererState(window: window, frameSamples: 1, ctx: newGpuContext(window))

proc collect() =
  for item in gpuRenderer.retiredBuffers.mitems: item.freeGpu()
  for item in gpuRenderer.retiredTextures.mitems: item.freeGpu()
  for item in gpuRenderer.retiredPipelines.mitems: item.freeGpu()
  gpuRenderer.retiredBuffers.setLen(0)
  gpuRenderer.retiredTextures.setLen(0)
  gpuRenderer.retiredPipelines.setLen(0)

proc destroy*(b: VertexBuffer) =
  if b == nil or b notin gpuRenderer.buffers: return
  if b.handle != nil: gpuRenderer.retiredBuffers.add b.handle
  b.handle = nil
  gpuRenderer.buffers.del(gpuRenderer.buffers.find(b))

proc destroy*(t: GpuImage) =
  if t == nil or t.handle == nil: return
  gpuRenderer.retiredTextures.add t.handle
  t.handle = nil
  gpuRenderer.images.del(gpuRenderer.images.find(t))

proc destroy*(p: ShaderProgram) =
  if p == nil or p notin gpuRenderer.programs: return
  for pipeline in p.pipelines.values: gpuRenderer.retiredPipelines.add pipeline
  p.pipelines.clear()
  gpuRenderer.programs.del(gpuRenderer.programs.find(p))

proc destroy*(target: RenderTarget) =
  if target == nil: return
  target.color.destroy()
  target.multisampleColor.destroy()
  if not target.borrowsDepth:
    target.depth.destroy()
    target.multisampleDepth.destroy()

proc newBuffer*[T](values: openArray[T]): VertexBuffer =
  result = VertexBuffer(handle: gpuRenderer.ctx.uploadBuffer(values))
  gpuRenderer.buffers.add result

proc updateBuffer*[T](b: VertexBuffer, values: openArray[T]) =
  if b.handle != nil: gpuRenderer.retiredBuffers.add b.handle
  b.handle = gpuRenderer.ctx.uploadBuffer(values)

proc width*(image: GpuImage): int = image.handle.width
proc height*(image: GpuImage): int = image.handle.height
proc pixelFormat*(image: GpuImage): TextureFormat = image.handle.format
proc setTextureSampling*(image: GpuImage, linear: bool, repeat = false) =
  let wrap = if repeat: Repeat else: ClampEdge
  image.sampling = SamplerState(minLinear: linear, magLinear: linear, mipLinear: linear,
    mipmaps: image.handle.mipLevels > 1, wrapS: wrap, wrapT: wrap, wrapR: wrap)

proc allocateImage*(width, height: int, format: TextureFormat, linear = true,
    repeat = false, layers = 1, levels = 1, arrayTexture = false, cube = false, samples = 1): GpuImage =
  result = GpuImage(handle: gpuRenderer.ctx.newTexture(width, height, format,
    mipLevels = levels, layers = layers, arrayTexture = arrayTexture, cube = cube, samples = samples))
  result.setTextureSampling(linear, repeat)
  gpuRenderer.images.add result

proc mipCount*(width, height: int): int =
  var size = max(width, height)
  while size > 0:
    inc result
    size = size shr 1

proc uploadImage*(texture: GpuImage, image: Image, layer = 0) =
  var level = image
  for i in 0 ..< texture.handle.mipLevels:
    texture.handle.uploadLevel(layer, i, level.width, level.height, 4, level.data[0].addr)
    if i + 1 < texture.handle.mipLevels:
      level = level.resize(max(1, level.width div 2), max(1, level.height div 2))

proc newTexture*(image: Image, linear = true, repeat = false, mipmaps = false): GpuImage =
  result = allocateImage(image.width, image.height, Rgba8, linear, repeat,
    levels = (if mipmaps: mipCount(image.width, image.height) else: 1))
  result.uploadImage(image)

proc updateTexture*(texture: GpuImage, image: Image) = texture.uploadImage(image)

proc newRenderTarget*(width, height: int, color = true, depth = true, samples = 1,
    colorFormat = Rgba8, stencil = false, mipmapped = false): RenderTarget =
  result = RenderTarget(width: width, height: height, samples: gpuRenderer.ctx.sampleCount(samples, colorFormat, (if stencil: DepthStencil else: Depth32f), color, depth), stencil: stencil)
  if color:
    result.color = allocateImage(width, height, colorFormat,
      levels = (if mipmapped: mipCount(width, height) else: 1))
  if depth:
    result.depth = allocateImage(width, height, if stencil: DepthStencil else: Depth32f, linear = false)

  if result.samples > 1:
    if color: result.multisampleColor = allocateImage(width, height, colorFormat, samples = result.samples)
    if depth: result.multisampleDepth = allocateImage(width, height, result.depth.pixelFormat, samples = result.samples)

proc renderSamples*(target: RenderTarget): int =
  if target.resolved: 1 else: target.samples

proc resolveForUi*(): RenderTarget =
  result = gpuRenderer.target
  result.resolved = true

proc setFrameSamples*(samples: int) =
  gpuRenderer.frameSamples = gpuRenderer.ctx.sampleCount(samples, Rgba8, DepthStencil)


proc shareDepth*(target, source: RenderTarget) =
  if target == source: return
  if target.width != source.width or target.height != source.height or target.samples != source.samples:
    raise newException(GpuError, "Shared depth dimensions differ")
  if not target.borrowsDepth:
    target.depth.destroy()
    target.multisampleDepth.destroy()
  target.multisampleDepth = source.multisampleDepth
  target.depth = source.depth
  target.resolved = source.resolved
  target.stencil = source.stencil
  target.borrowsDepth = true

proc driverTarget(target: RenderTarget, read = false): GpuTarget =
  result = GpuTarget(width: target.width, height: target.height)
  if target.color != nil:
    result.texture = target.color.handle
    result.format = target.color.pixelFormat
  if target.depth != nil: result.depth = target.depth.handle
  if not read and target.renderSamples() > 1:
    if result.texture != nil:
      result.resolveColor = result.texture
      result.texture = target.multisampleColor.handle
    if result.depth != nil:
      result.resolveDepth = result.depth
      result.depth = target.multisampleDepth.handle

proc frameActive*(): bool = gpuRenderer.ctx.command != nil

proc ensureFrame*(width, height: int) =
  if frameActive(): return
  let r = gpuRenderer
  if r.frameTarget == nil or r.frameTarget.width != width or r.frameTarget.height != height or r.frameTarget.samples != r.frameSamples:
    r.frameTarget.destroy()
    r.frameTarget = newRenderTarget(width, height, samples = r.frameSamples, stencil = true)
  collect()
  r.ctx.beginFrame()
  r.target = r.frameTarget
  r.viewport = ivec2(width.int32, height.int32)

proc ensureFrame*() =
  ensureFrame(gpuRenderer.window.size.x, gpuRenderer.window.size.y)

proc setTarget*(target: RenderTarget = nil) =
  ensureFrame()
  gpuRenderer.target = if target == nil: gpuRenderer.frameTarget else: target
  gpuRenderer.viewport = ivec2(gpuRenderer.target.width.int32, gpuRenderer.target.height.int32)

proc setRenderViewport*(size: IVec2) = gpuRenderer.viewport = size

proc pushTarget*(target: RenderTarget) =
  ensureFrame()
  gpuRenderer.stack.add (gpuRenderer.target, gpuRenderer.viewport)
  setTarget(target)

proc popTarget*() =
  (gpuRenderer.target, gpuRenderer.viewport) = gpuRenderer.stack.pop()

proc clear*(color: Color, depth = true, stencil = false) =
  ensureFrame()
  if depth or gpuRenderer.target.depth == nil: gpuRenderer.target.resolved = false
  gpuRenderer.ctx.beginPass(gpuRenderer.target.driverTarget(), true, depth, color, stencil).endPass()

proc clearDepth*() =
  ensureFrame()
  gpuRenderer.ctx.beginPass(gpuRenderer.target.driverTarget(), clearDepth = true).endPass()

proc beginFrame*(width, height: int, color: Color) =
  ensureFrame(width, height)
  setTarget()
  clear(color, stencil = true)

proc copyTarget*(source, destination: RenderTarget, color = true, depth = true) =
  for attachment in [(color, source.color, destination.color), (depth, source.depth, destination.depth)]:
    let (enabled, a, b) = attachment
    if enabled and a != nil and b != nil and a != b:
      if a.width != b.width or a.height != b.height or a.pixelFormat != b.pixelFormat:
        raise newException(GpuError, "Incompatible attachment copy")
      copyPixels(a.handle, b.handle)

proc snapshotTarget*(color = true, depth = true): RenderTarget =
  let target = gpuRenderer.target
  result = newRenderTarget(target.width, target.height, color and target.color != nil,
    depth and target.depth != nil, colorFormat = (if target.color != nil: target.color.pixelFormat else: Rgba8),
    stencil = target.stencil)
  copyTarget(target, result, color, depth)

proc setStencil*(write: bool, reference: int, compare = Always) =
  gpuRenderer.stencil = DrawState(stencilTest: true, stencilWrite: write, stencilCompare: compare, stencilReference: reference)

proc clearStencilState*() = gpuRenderer.stencil = DrawState()

proc decodeStage(packed: string): tuple[source, binary: string] =
  if packed.len == 0: return
  let boundary = packed.find('\0')
  if boundary < 0: raise newException(GpuError, "Use nativeStage for native shader overrides")
  (packed[0 ..< boundary], packed[boundary+1 .. ^1])

proc newProgram*(vertexSource, fragmentSource: string, layout = VertexLayout()): ShaderProgram =
  let v = decodeStage(vertexSource)
  let f = decodeStage(fragmentSource)
  let vertex = v.source.split('\n', 1)
  let fragment = f.source.split('\n', 1)
  let vs = parseJson(vertex[1])
  let ps = if f.source.len > 0: parseJson(fragment[1]) else: newJObject()
  result = ShaderProgram(label: vertex[0] & " / " & fragment[0], layout: layout, code: ProgramCode(vertex: v.binary, fragment: f.binary),
    vertex: uniformLayout(vs).constants, fragment: uniformLayout(ps).constants)
  for input in vs{"inputs"}.getElems():
    result.code.inputs.add ShaderInput(name: input["name"].getStr(),
      semantic: "TEXCOORD", location: input["location"].getInt())
  for stage in [vs, ps]:
    for sampler in stage{"textures"}.getElems():
      if sampler["type"].getStr().endsWith("Shadow"):
        result.shadowInputs.add sampler["name"].getStr()
  gpuRenderer.programs.add result

proc setVertexLayout*(p: ShaderProgram, layout: VertexLayout) = p.layout = layout

proc setUniform*[T](p: ShaderProgram, name: string, value: T) =
  template write(buffer: untyped) =
    when T is Mat4 or T is Mat3 or T is Vec2 or T is Vec3 or T is Vec4:
      buffer.put(name, value)
    elif T is array or T is seq:
      for i, item in value: buffer.put(name, item, i)
    else:
      buffer.put(name, value)
  write(p.vertex)
  write(p.fragment)

proc bindTexture*(p: ShaderProgram, name: string, image: GpuImage) = p.textures[name] = image

proc waitForGpu*()

proc draw*(p: ShaderProgram, vertices: VertexBuffer, count: int, state = DrawState(),
    indices: VertexBuffer = nil, first = 0, index32 = true, instanceCount = 1, layout = VertexLayout()) =
  if count <= 0: return
  ensureFrame()
  let r = gpuRenderer
  if r.ctx.needsSubmission(): waitForGpu()
  let target = r.target
  var actual = state
  if r.stencil.stencilTest:
    actual.stencilTest = true
    actual.stencilWrite = r.stencil.stencilWrite
    actual.stencilCompare = r.stencil.stencilCompare
    actual.stencilReference = r.stencil.stencilReference
  let key: PipelineKey = (actual, (if layout.stride > 0: layout else: p.layout),
    (if target.color != nil: target.color.pixelFormat else: Rgba8),
    (if target.depth != nil: target.depth.pixelFormat else: Depth32f),
    target.color != nil, target.depth != nil, target.renderSamples())
  if key notin p.pipelines:
    try:
      p.pipelines[key] = r.ctx.newPipeline(p.code, key.layout, actual, key.color, key.depth, key.hasColor, key.hasDepth, key.samples)
    except Exception as error:
      raise newException(GpuError, p.label & ": " & error.msg)
  when defined(useVulkan):
    for uniforms in [p.vertex, p.fragment]:
      for name in uniforms.layout.textures:
        let image = p.textures.getOrDefault(name)
        if image != nil: image.handle.prepareSample()
  var encoder = r.ctx.beginPass(target.driverTarget())
  encoder.applyViewport(r.viewport)
  encoder.setProgram(p.pipelines[key])
  for stage, uniforms in [p.vertex, p.fragment]:
    for i, name in uniforms.layout.textures:
      let image = p.textures.getOrDefault(name)
      if image == nil: continue
      var sampling = image.sampling
      sampling.comparison = name in p.shadowInputs
      if sampling notin r.samplers:
        r.samplers[sampling] = r.ctx.createSampler(sampling)
      encoder.setTexture(image.handle, (i + (if stage == 0: MaxTextures else: 0)).uint)
      encoder.setSampler(r.samplers[sampling], (i + (if stage == 0: MaxTextures else: 0)).uint)
  if vertices != nil: encoder.setVertices(vertices.handle, 0, 0)
  r.ctx.bindConstants(encoder, p.vertex, p.fragment)
  encoder.drawNative(first, count, instanceCount, if indices != nil: indices.handle else: nil, index32, actual)
  encoder.endPass()

proc waitForGpu*() =
  if frameActive():
    gpuRenderer.ctx.finishFrame()
    collect()
    gpuRenderer.ctx.beginFrame()

proc captureTargetImage*(target: RenderTarget = nil): Image =
  ensureFrame()
  let source = if target == nil: gpuRenderer.target else: target
  result = gpuRenderer.ctx.readImage(source.driverTarget(read = true))
  collect()
  gpuRenderer.ctx.beginFrame()

proc shutdownNative*() =
  if gpuRenderer == nil: return
  let r = gpuRenderer
  r.ctx.finishFrame()
  while r.images.len > 0: r.images[^1].destroy()
  while r.buffers.len > 0: r.buffers[^1].destroy()
  while r.programs.len > 0: r.programs[^1].destroy()
  collect()
  for sampler in r.samplers.mvalues: sampler.freeGpu()
  r.ctx.destroy()
  gpuRenderer = nil

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


proc blit(source: GpuImage) =
  let r = gpuRenderer
  if r.blit == nil:
    r.blit = newProgram(nativeStage(presentVertex, shaderVertex), nativeStage(presentFragment, shaderFragment),
      VertexLayout(stride: 16, attributes: @[VertexAttribute(name: "position", format: Float2),
        VertexAttribute(name: "texcoord", format: Float2, offset: 8)]))
    r.quad = newBuffer([-1'f32, -1, 0, 1, 3, -1, 2, 1, -1, 3, 0, -1])
  r.blit.bindTexture("presentTexture", source)
  draw(r.blit, r.quad, 3)

proc generateMipmaps*(image: GpuImage) =
  if image.handle.mipLevels <= 1: return
  when defined(useVulkan): gpuRenderer.ctx.generateMipmaps(image.handle)
  else:
    var previous = image
    for level in 1 ..< image.handle.mipLevels:
      let target = newRenderTarget(max(1, image.width shr level), max(1, image.height shr level), depth = false)
      pushTarget(target)
      blit(previous)
      popTarget()
      copyMip(target.color.handle, image.handle, level)
      if previous != image: previous.destroy()
      previous = target.color
    previous.destroy()

proc endFrame*(present = true) =
  if not frameActive(): return
  let r = gpuRenderer
  if present:
    when defined(useDirectX):
      r.ctx.present(r.frameTarget.color.handle, r.window)
    else:
      var index: uint32
      let surface = r.ctx.acquireSurface(r.window, index)
      if surface != nil:
        r.target = RenderTarget(width: surface.width, height: surface.height, samples: 1,
          color: GpuImage(handle: surface))
        r.viewport = ivec2(surface.width.int32, surface.height.int32)
        blit(r.frameTarget.color)
        r.ctx.presentSurface(surface, index)
  r.ctx.finishFrame()
  collect()
  r.target = r.frameTarget
