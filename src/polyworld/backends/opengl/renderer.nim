## Owns OpenGL frame targets, presentation, UI state, and pixel readback.

import
  chroma, opengl, pixie, silky, vmath, windy,
  ../../screenshots,
  passapi, ../passes/meshes as passMeshes,
  silky/drawers/shader as uiShaders, shady
from silky/drawers/ogl import DrawerVertex

const
  RendererBackend* = when defined(emscripten): "webgl" else: "opengl"
  BackendBenchSamples* {.intdefine.} = 1

static:
  doAssert BackendBenchSamples in [1, 2, 4, 8],
    "backendBenchSamples must be 1, 2, 4, or 8"

when defined(backendThroughput) and
    (not defined(backendBench) or defined(emscripten)):
  {.error: "backendThroughput requires a native backendBench build".}

type
  TextureHandle* = GLuint
  FramebufferHandle* = GLuint
  FrameTarget* = object
    framebuffer*, texture*, depth*: GLuint
    size*: IVec2
    samples*: int
    resolveFramebuffer, multisampleColor: GLuint
  ScreenshotTarget* = FrameTarget
  TargetState = object
    read, draw: GLint
    viewport: array[4, GLint]

var
  uiProgram: passapi.ShaderProgram
  targetStack: seq[TargetState]
  multisampleTargets: seq[FrameTarget]
  screenshotFrame: FrameTarget

when defined(backendThroughput):
  const BenchmarkQueueCapacity = 3

  from ../../measurements import BenchmarkGpuStats
  export BenchmarkGpuStats

  var
    benchmarkFences: array[BenchmarkQueueCapacity, GLsync]
    benchmarkFenceHead, benchmarkFenceCount: int
    benchmarkGpuStats = BenchmarkGpuStats(capacity: BenchmarkQueueCapacity)

  proc drainBenchmarkGpuFrames*(): BenchmarkGpuStats
    ## Completes every submitted frame before returning aggregate counts.

proc initRenderer*(window: Window, samples = 1) =
  ## Initializes OpenGL entry points for the active window.
  window.makeContextCurrent()
  loadExtensions()
  passapi.initNative(window)

proc shutdownRenderer*() =
  ## Releases shared model resources before the active context is closed.
  passapi.endGameFrameDraws()
  passMeshes.clearModelResources()
  passapi.destroy(uiProgram)
  uiProgram = nil
  when defined(backendThroughput):
    discard drainBenchmarkGpuFrames()

proc newGameUi*(window: Window, atlasPath: string): Silky =
  ## Creates the UI drawer for the active graphics context.
  newSilky(window, atlasPath)

proc presentRenderer*(window: Window) =
  ## Presents the completed OpenGL back buffer.
  passapi.endGameFrameDraws()
  passapi.gpuRenderer.active = false
  when not defined(backendBench):
    window.swapBuffers()

proc atlasTexture*(sk: Silky): TextureHandle =
  ## Borrows the current atlas texture for world-space text.
  sk.atlasTextureId()

proc drawUiLayer*(sk: Silky, vertices: openArray[DrawerVertex], size: Vec2,
    scale: float32) =
  ## Renders shared Silky geometry into the application's current target.
  if vertices.len == 0:
    return
  if uiProgram == nil:
    uiProgram = newProgram(
      nativeStage(uiShaders.silkyVert, shaderVertex),
      nativeStage(uiShaders.silkyFrag, shaderFragment),
      VertexLayout(stride: sizeof(DrawerVertex), attributes: @[
        VertexAttribute(name: "pos", format: Float2,
          offset: offsetOf(DrawerVertex, pos)),
        VertexAttribute(name: "uv", format: Float2,
          offset: offsetOf(DrawerVertex, uv)),
        VertexAttribute(name: "color", format: Unorm8x4,
          offset: offsetOf(DrawerVertex, color)),
        VertexAttribute(name: "clipPos", format: Float2,
          offset: offsetOf(DrawerVertex, clipPos)),
        VertexAttribute(name: "clipSize", format: Float2,
          offset: offsetOf(DrawerVertex, clipSize)),
        VertexAttribute(name: "maskUv", format: Float2,
          offset: offsetOf(DrawerVertex, maskUv))]))
  uiProgram.setUniform("viewportSize", size / scale)
  uiProgram.setUniform("atlasSize", sk.atlasImageSize().vec2)
  uiProgram.bindTexture("atlasSampler", sk.atlasTexture())
  drawStream(uiProgram, vertices, vertices.len,
    DrawState(blend: PremultipliedAlpha))

proc setRenderViewport*(size: IVec2) =
  ## Sets the viewport to the complete rendering surface.
  glViewport(0, 0, size.x.GLsizei, size.y.GLsizei)
  var framebuffer: GLint
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, framebuffer.addr)
  passapi.syncFrameTarget(framebuffer.GLuint, size)

proc setMultisampling*(enabled: bool) =
  ## Enables desktop multisampling when requested.
  when not defined(emscripten):
    if enabled:
      glEnable(GL_MULTISAMPLE)
    else:
      glDisable(GL_MULTISAMPLE)

proc bindFrameTarget*(target: FramebufferHandle = 0) =
  ## Selects the target for subsequent scene drawing.
  glBindFramebuffer(GL_FRAMEBUFFER, target)
  var viewport: array[4, GLint]
  glGetIntegerv(GL_VIEWPORT, viewport[0].addr)
  passapi.syncFrameTarget(target, ivec2(viewport[2], viewport[3]))

proc clearFrame*(value: Color, depth = true, stencil = false) =
  ## Clears the requested attachments with writable depth and stencil.
  passapi.invalidateDrawState()
  glClearColor(value.r, value.g, value.b, value.a)
  var mask = GL_COLOR_BUFFER_BIT
  if depth:
    glDepthMask(GL_TRUE)
    mask = mask or GL_DEPTH_BUFFER_BIT
  if stencil:
    glStencilMask(0xff)
    glClearStencil(0)
    mask = mask or GL_STENCIL_BUFFER_BIT
  glClear(mask)

proc prepareUi*(sk: Silky) =
  ## Restores the drawing state needed by a UI pass.
  passapi.endSceneDraws()
  passapi.clearStencilState()
  glDisable(GL_DEPTH_TEST)
  glDisable(GL_STENCIL_TEST)
  glDisable(GL_CULL_FACE)
  glDisable(GL_SCISSOR_TEST)
  glDisable(GL_BLEND)
  setMultisampling(false)
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, sk.atlasTextureId())

proc finishUi*(sk: Silky) =
  ## Submits queued UI geometry into the active frame target.
  passapi.endSceneDraws()
  sk.endUi()

proc beginGameUi*(sk: Silky, window: Window, size: IVec2) =
  ## Return the context before Silky begins an application UI pass.
  passapi.endSceneDraws()
  sk.beginUi(window, size)

proc beginStencil*(reference: int) =
  ## Marks fragments from the following character draws.
  passapi.setStencil(true, reference)
  if passapi.gameOwnsDrawState(): return
  passapi.invalidateDrawState()
  glEnable(GL_STENCIL_TEST)
  glStencilMask(0xff)
  glStencilFunc(GL_ALWAYS, reference.GLint, 0xff)
  glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE)

proc endStencil*() =
  ## Ends character stencil marking.
  passapi.clearStencilState()
  if passapi.gameOwnsDrawState(): return
  passapi.invalidateDrawState()
  glStencilMask(0)
  glDisable(GL_STENCIL_TEST)

proc destroyFrameTarget*(target: var FrameTarget) =
  ## Releases the color, depth, and framebuffer resources.
  if screenshotFrame.framebuffer == target.framebuffer:
    screenshotFrame = FrameTarget()
  for i in 0 ..< multisampleTargets.len:
    if multisampleTargets[i].framebuffer == target.framebuffer:
      multisampleTargets.delete(i)
      break
  if target.multisampleColor != 0:
    glDeleteRenderbuffers(1, target.multisampleColor.addr)
  if target.resolveFramebuffer != 0:
    glDeleteFramebuffers(1, target.resolveFramebuffer.addr)
  if target.depth != 0:
    glDeleteRenderbuffers(1, target.depth.addr)
  if target.texture != 0:
    glDeleteTextures(1, target.texture.addr)
  if target.framebuffer != 0:
    glDeleteFramebuffers(1, target.framebuffer.addr)
  target = FrameTarget()

proc validateRenderbufferSamples(target: var FrameTarget, expected: int) =
  ## Rejects renderbuffer storage with a different sample count than requested.
  var actual: GLint
  glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_SAMPLES,
    actual.addr)
  if max(1, actual.int) != expected:
    target.destroyFrameTarget()
    raise newException(
      ScreenshotError,
      "OpenGL renderbuffer samples " & $actual & " differ from " & $expected
    )

proc newFrameTarget*(width, height: int, samples = 1): FrameTarget =
  ## Allocates a complete offscreen color and depth-stencil target.
  if width <= 0 or height <= 0:
    raise newException(ScreenshotError, "Render target dimensions are empty")
  if samples notin [1, 2, 4, 8]:
    raise newException(ScreenshotError, "Unsupported render target samples")
  var previousRead, previousDraw: GLint
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, previousRead.addr)
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, previousDraw.addr)
  defer:
    glBindFramebuffer(GL_READ_FRAMEBUFFER, previousRead.GLuint)
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, previousDraw.GLuint)
  glGenFramebuffers(1, result.framebuffer.addr)
  glBindFramebuffer(GL_FRAMEBUFFER, result.framebuffer)
  glGenTextures(1, result.texture.addr)
  glBindTexture(GL_TEXTURE_2D, result.texture)
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.GLint, width.GLsizei,
    height.GLsizei, 0, GL_RGBA, GL_UNSIGNED_BYTE, nil)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR.GLint)
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
    GL_TEXTURE_2D, result.texture, 0)
  if samples > 1:
    if glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE:
      result.destroyFrameTarget()
      raise newException(ScreenshotError, "Unable to allocate resolve target")
    result.resolveFramebuffer = result.framebuffer
    glGenFramebuffers(1, result.framebuffer.addr)
    glBindFramebuffer(GL_FRAMEBUFFER, result.framebuffer)
    glGenRenderbuffers(1, result.multisampleColor.addr)
    glBindRenderbuffer(GL_RENDERBUFFER, result.multisampleColor)
    glRenderbufferStorageMultisample(
      GL_RENDERBUFFER,
      samples.GLsizei,
      GL_RGBA8,
      width.GLsizei,
      height.GLsizei
    )
    result.validateRenderbufferSamples(samples)
    glFramebufferRenderbuffer(
      GL_FRAMEBUFFER,
      GL_COLOR_ATTACHMENT0,
      GL_RENDERBUFFER,
      result.multisampleColor
    )
  glGenRenderbuffers(1, result.depth.addr)
  glBindRenderbuffer(GL_RENDERBUFFER, result.depth)
  if samples > 1:
    glRenderbufferStorageMultisample(
      GL_RENDERBUFFER,
      samples.GLsizei,
      GL_DEPTH24_STENCIL8,
      width.GLsizei,
      height.GLsizei
    )
  else:
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8,
      width.GLsizei, height.GLsizei)
  result.validateRenderbufferSamples(samples)
  glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT,
    GL_RENDERBUFFER, result.depth)
  if glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE:
    result.destroyFrameTarget()
    raise newException(ScreenshotError, "Unable to allocate render target")
  result.size = ivec2(width.int32, height.int32)
  result.samples = samples
  if samples > 1:
    multisampleTargets.add(result)

proc resolveFrameTarget(target: FrameTarget): GLuint =
  ## Resolves multisample color while preserving read and draw bindings.
  if target.samples <= 1:
    return target.framebuffer
  var previousRead, previousDraw: GLint
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, previousRead.addr)
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, previousDraw.addr)
  let scissored = glIsEnabled(GL_SCISSOR_TEST) == GL_TRUE
  if scissored:
    glDisable(GL_SCISSOR_TEST)
  glBindFramebuffer(GL_READ_FRAMEBUFFER, target.framebuffer)
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, target.resolveFramebuffer)
  glBlitFramebuffer(
    0,
    0,
    target.size.x,
    target.size.y,
    0,
    0,
    target.size.x,
    target.size.y,
    GL_COLOR_BUFFER_BIT,
    GL_NEAREST.GLenum
  )
  glBindFramebuffer(GL_READ_FRAMEBUFFER, previousRead.GLuint)
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, previousDraw.GLuint)
  if scissored:
    glEnable(GL_SCISSOR_TEST)
  target.resolveFramebuffer

proc readFramebuffer(drawing: GLuint): GLuint =
  ## Selects resolved color storage when reading a multisample target.
  for target in multisampleTargets:
    if target.framebuffer == drawing:
      return resolveFrameTarget(target)
  drawing

proc pushFrameTarget*(target: FrameTarget) =
  ## Saves the current framebuffer and viewport before an offscreen pass.
  var previous: TargetState
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, previous.read.addr)
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, previous.draw.addr)
  glGetIntegerv(GL_VIEWPORT, previous.viewport[0].addr)
  targetStack.add(previous)
  bindFrameTarget(target.framebuffer)
  setRenderViewport(target.size)

proc popFrameTarget*() =
  ## Restores the framebuffer and viewport after an offscreen pass.
  doAssert targetStack.len > 0, "No offscreen target to restore"
  let previous = targetStack.pop()
  glBindFramebuffer(GL_READ_FRAMEBUFFER, previous.read.GLuint)
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, previous.draw.GLuint)
  glViewport(previous.viewport[0], previous.viewport[1],
    previous.viewport[2], previous.viewport[3])
  passapi.syncFrameTarget(previous.draw.GLuint,
    ivec2(previous.viewport[2], previous.viewport[3]))

proc releaseScreenshotTarget*(target: var ScreenshotTarget) =
  ## Releases the hidden-window capture target.
  target.destroyFrameTarget()

proc beginScreenshotFrame*(target: var ScreenshotTarget, window: Window,
    enabled = captureActive()): FramebufferHandle =
  ## Binds an offscreen surface when a hidden window is being captured.
  passapi.beginGameFrameDraws()
  let offscreen = enabled or
    (defined(backendBench) and not defined(emscripten))
  if not offscreen:
    screenshotFrame = FrameTarget()
    glBindFramebuffer(GL_FRAMEBUFFER, 0)
    glViewport(0, 0, window.size.x.GLsizei, window.size.y.GLsizei)
    passapi.syncFrameTarget(0, window.size)
    return 0
  const Samples = when defined(backendBench): BackendBenchSamples else: 1
  if target.framebuffer == 0 or target.size != window.size or
    target.samples != Samples:
      target.destroyFrameTarget()
      target = newFrameTarget(window.size.x, window.size.y, Samples)
  screenshotFrame = target
  bindFrameTarget(target.framebuffer)
  setRenderViewport(target.size)
  target.framebuffer

proc readFrameImage*(width, height: int): Image =
  ## Reads the current drawing surface into a top-left-oriented image.
  result = newImage(width, height)
  var previousRead, drawing, readBuffer, packAlignment: GLint
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, previousRead.addr)
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, drawing.addr)
  glBindFramebuffer(GL_READ_FRAMEBUFFER, readFramebuffer(drawing.GLuint))
  glGetIntegerv(GL_READ_BUFFER, readBuffer.addr)
  glGetIntegerv(GL_PACK_ALIGNMENT, packAlignment.addr)
  defer:
    glPixelStorei(GL_PACK_ALIGNMENT, packAlignment)
    glReadBuffer(readBuffer.GLenum)
    glBindFramebuffer(GL_READ_FRAMEBUFFER, previousRead.GLuint)
  glReadBuffer(if drawing == 0: GL_BACK else: GL_COLOR_ATTACHMENT0)
  glPixelStorei(GL_PACK_ALIGNMENT, 1)
  glReadPixels(0, 0, width.GLsizei, height.GLsizei,
    GL_RGBA, GL_UNSIGNED_BYTE, result.data[0].addr)
  result.flipVertical()

proc finishGpu*() =
  ## Waits for submitted rendering before recording benchmark timings.
  glFinish()

proc readFramePixel*(): array[4, uint8] =
  ## Reads one output pixel, synchronizing rendering even in WebGL browsers.
  var previousRead, drawing, readBuffer, packBuffer: GLint
  var packing: array[4, GLint]
  const PackSettings = [GL_PACK_ALIGNMENT, GL_PACK_ROW_LENGTH,
    GL_PACK_SKIP_ROWS, GL_PACK_SKIP_PIXELS]
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, previousRead.addr)
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, drawing.addr)
  glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, packBuffer.addr)
  glBindFramebuffer(GL_READ_FRAMEBUFFER, readFramebuffer(drawing.GLuint))
  glGetIntegerv(GL_READ_BUFFER, readBuffer.addr)
  for i, setting in PackSettings:
    glGetIntegerv(setting, packing[i].addr)
  defer:
    for i, setting in PackSettings:
      glPixelStorei(setting, packing[i])
    glBindBuffer(GL_PIXEL_PACK_BUFFER, packBuffer.GLuint)
    glReadBuffer(readBuffer.GLenum)
    glBindFramebuffer(GL_READ_FRAMEBUFFER, previousRead.GLuint)
  glBindBuffer(GL_PIXEL_PACK_BUFFER, 0)
  glReadBuffer(if drawing == 0: GL_BACK else: GL_COLOR_ATTACHMENT0)
  for i, setting in PackSettings:
    glPixelStorei(setting, if i == 0: 1 else: 0)
  glReadPixels(0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, result[0].addr)

when defined(backendThroughput):
  proc retireBenchmarkFrame() =
    ## Releases the oldest completed logical frame marker.
    glDeleteSync(benchmarkFences[benchmarkFenceHead])
    benchmarkFences[benchmarkFenceHead] = cast[GLsync](nil)
    benchmarkFenceHead = (benchmarkFenceHead + 1) mod BenchmarkQueueCapacity
    dec benchmarkFenceCount
    inc benchmarkGpuStats.completedFrames

  proc pollBenchmarkFrames(waitForOldest = false) =
    ## Retires completed markers, optionally waiting for the oldest frame.
    var waiting = waitForOldest
    while benchmarkFenceCount > 0:
      let status = glClientWaitSync(
        benchmarkFences[benchmarkFenceHead],
        0.GLbitfield,
        (if waiting: 1_000_000_000'u64 else: 0'u64).GLuint64
      )
      case status
      of GL_ALREADY_SIGNALED, GL_CONDITION_SATISFIED:
        retireBenchmarkFrame()
        waiting = false
      of GL_TIMEOUT_EXPIRED:
        if not waiting:
          break
      else:
        raise newException(ScreenshotError, "OpenGL frame fence wait failed")

  proc beginBenchmarkGpuFrame*() =
    ## Applies bounded backpressure before encoding the next frame.
    pollBenchmarkFrames()
    if benchmarkFenceCount == BenchmarkQueueCapacity:
      pollBenchmarkFrames(waitForOldest = true)

  proc submitBenchmarkGpuFrame*() =
    ## Resolves output and submits one offscreen frame completion marker.
    if benchmarkFenceCount >= BenchmarkQueueCapacity:
      raise newException(ScreenshotError, "OpenGL frame queue is full")
    if screenshotFrame.framebuffer == 0:
      raise newException(ScreenshotError, "No offscreen benchmark target")
    discard resolveFrameTarget(screenshotFrame)
    let fence = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0.GLbitfield)
    if cast[pointer](fence) == nil:
      raise newException(ScreenshotError, "Unable to create OpenGL frame fence")
    let index = (benchmarkFenceHead + benchmarkFenceCount) mod
      BenchmarkQueueCapacity
    benchmarkFences[index] = fence
    inc benchmarkFenceCount
    inc benchmarkGpuStats.submittedFrames
    benchmarkGpuStats.maxOutstanding = max(
      benchmarkGpuStats.maxOutstanding,
      benchmarkFenceCount
    )
    glFlush()

  proc drainBenchmarkGpuFrames*(): BenchmarkGpuStats =
    ## Completes every submitted frame before returning aggregate counts.
    glFinish()
    while benchmarkFenceCount > 0:
      retireBenchmarkFrame()
    benchmarkGpuStats

  proc resetBenchmarkGpuStats*() =
    ## Starts a measurement window after all earlier frames have drained.
    if benchmarkFenceCount != 0:
      raise newException(ScreenshotError, "Drain OpenGL before resetting stats")
    benchmarkGpuStats = BenchmarkGpuStats(capacity: BenchmarkQueueCapacity)

  proc readBenchmarkGpuStats*(): BenchmarkGpuStats =
    ## Returns frame submission and retirement counts without blocking.
    pollBenchmarkFrames()
    benchmarkGpuStats
