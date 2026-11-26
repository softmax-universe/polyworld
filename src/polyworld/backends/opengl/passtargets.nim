## Framebuffer ownership and composition for shared OpenGL scene passes.

import
  chroma, pixie, vmath, windy,
  passtypes, passresources, ../../targetplans
from passprograms import withClearWriteMasks

export passtypes

proc saveTarget(): TargetState =
  ## Records framebuffer bindings and viewport before an isolated operation.
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, result.read.addr)
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, result.draw.addr)
  glGetIntegerv(GL_VIEWPORT, result.viewport[0].addr)
  result.target = gpuRenderer.target

proc restoreTarget(state: TargetState) =
  ## Restores the caller's distinct read and draw targets and viewport.
  glBindFramebuffer(GL_READ_FRAMEBUFFER, state.read.GLuint)
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, state.draw.GLuint)
  glViewport(state.viewport[0], state.viewport[1], state.viewport[2],
    state.viewport[3])
  gpuRenderer.target = state.target
  gpuRenderer.viewport = ivec2(state.viewport[2], state.viewport[3])

proc drawFramebuffer(target: RenderTarget): GLuint =
  ## Selects multisample storage until a target is explicitly resolved for UI.
  if target == nil:
    return 0
  if target.samples > 1 and not target.resolved:
    target.multisampleFramebuffer
  else:
    target.framebuffer

proc colorFormat(storage: GLenum): TextureFormat =
  ## Describes the logical channels of a borrowed renderable color attachment.
  case storage
  of GL_RGBA16F: Rgba16f
  of GL_RGBA32F: Rgba32f
  of GL_RG32F: Rg32f
  of GL_R32F: R32f
  of GL_R8: R8
  of GL_RG8: Rg8
  else: Rgba8

proc syncFrameTarget*(framebuffer: GLuint, size: IVec2,
    stencil = true, main = false) =
  ## Adopts a framebuffer owned by the application without taking its lifetime.
  let drawable = gpuRenderer.defaultDrawable
  if framebuffer == 0 and stencil and drawable != nil and
      drawable.width == size.x and drawable.height == size.y:
    gpuRenderer.target = drawable
    gpuRenderer.frameTarget = drawable
    gpuRenderer.viewport = size
    gpuRenderer.active = true
    return
  let previous = saveTarget()
  glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
  defer:
    glBindFramebuffer(GL_READ_FRAMEBUFFER, previous.read.GLuint)
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, previous.draw.GLuint)
  var samples, stencilBits, depthBits, attachmentKind, depthKind: GLint
  glGetIntegerv(GL_SAMPLES, samples.addr)
  let
    depthAttachment = if framebuffer == 0: GL_DEPTH else: GL_DEPTH_ATTACHMENT
    stencilAttachment =
      if framebuffer == 0: GL_STENCIL else: GL_STENCIL_ATTACHMENT
  glGetFramebufferAttachmentParameteriv(GL_FRAMEBUFFER, depthAttachment,
    GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE, attachmentKind.addr)
  if attachmentKind != GL_NONE.GLint:
    glGetFramebufferAttachmentParameteriv(GL_FRAMEBUFFER, depthAttachment,
      GL_FRAMEBUFFER_ATTACHMENT_DEPTH_SIZE, depthBits.addr)
    glGetFramebufferAttachmentParameteriv(GL_FRAMEBUFFER, depthAttachment,
      GL_FRAMEBUFFER_ATTACHMENT_COMPONENT_TYPE, depthKind.addr)
  glGetFramebufferAttachmentParameteriv(GL_FRAMEBUFFER, stencilAttachment,
    GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE, attachmentKind.addr)
  if attachmentKind != GL_NONE.GLint:
    glGetFramebufferAttachmentParameteriv(GL_FRAMEBUFFER, stencilAttachment,
      GL_FRAMEBUFFER_ATTACHMENT_STENCIL_SIZE, stencilBits.addr)
  let target = RenderTarget(
    framebuffer: framebuffer, width: size.x, height: size.y,
    samples: max(1, samples.int), resolved: samples <= 1,
    multisampleFramebuffer: framebuffer,
    stencil: stencil and stencilBits > 0,
    borrowsColor: true, borrowsDepth: true
  )
  target.color = textureFromNative(0, size.x, size.y)
  if target.color == nil:
    target.color = GpuImage(target: GL_TEXTURE_2D, width: size.x,
      height: size.y, pixelFormat: Rgba8)
  if depthBits > 0:
    target.depth = GpuImage(target: GL_TEXTURE_2D, width: size.x,
      height: size.y,
      pixelFormat: if target.stencil: DepthStencil else: Depth32f,
      nativeFormat:
        if target.stencil and depthKind == cGL_FLOAT.GLint:
          GL_DEPTH32F_STENCIL8
        elif target.stencil: GL_DEPTH24_STENCIL8
        elif depthBits == 16: GL_DEPTH_COMPONENT16
        elif depthBits == 24: GL_DEPTH_COMPONENT24
        elif depthKind != cGL_FLOAT.GLint: GL_DEPTH_COMPONENT32
        else: GL_DEPTH_COMPONENT32F)
  if framebuffer != 0:
    var kind, handle: GLint
    glGetFramebufferAttachmentParameteriv(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
      GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE, kind.addr)
    if kind == GL_TEXTURE.GLint:
      glGetFramebufferAttachmentParameteriv(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
        GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME, handle.addr)
      target.color.handle = handle.GLuint
      when not defined(emscripten):
        var previousTexture, storage: GLint
        glGetIntegerv(GL_TEXTURE_BINDING_2D, previousTexture.addr)
        glBindTexture(GL_TEXTURE_2D, handle.GLuint)
        glGetTexLevelParameteriv(GL_TEXTURE_2D, 0,
          GL_TEXTURE_INTERNAL_FORMAT, storage.addr)
        glBindTexture(GL_TEXTURE_2D, previousTexture.GLuint)
        target.color.nativeFormat = storage.GLenum
        target.color.pixelFormat = colorFormat(storage.GLenum)
    elif kind == GL_RENDERBUFFER.GLint:
      var previousBuffer, storage: GLint
      glGetFramebufferAttachmentParameteriv(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
        GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME, handle.addr)
      glGetIntegerv(GL_RENDERBUFFER_BINDING, previousBuffer.addr)
      glBindRenderbuffer(GL_RENDERBUFFER, handle.GLuint)
      glGetRenderbufferParameteriv(GL_RENDERBUFFER,
        GL_RENDERBUFFER_INTERNAL_FORMAT, storage.addr)
      glBindRenderbuffer(GL_RENDERBUFFER, previousBuffer.GLuint)
      target.color.nativeFormat = storage.GLenum
      target.color.pixelFormat = colorFormat(storage.GLenum)
    elif kind == GL_NONE.GLint:
      target.color = nil
    if target.depth != nil:
      glGetFramebufferAttachmentParameteriv(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT,
        GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE, kind.addr)
      if kind == GL_TEXTURE.GLint:
        glGetFramebufferAttachmentParameteriv(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT,
          GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME, handle.addr)
        target.depth.handle = handle.GLuint
        when not defined(emscripten):
          var previousTexture, storage: GLint
          glGetIntegerv(GL_TEXTURE_BINDING_2D, previousTexture.addr)
          glBindTexture(GL_TEXTURE_2D, handle.GLuint)
          glGetTexLevelParameteriv(GL_TEXTURE_2D, 0,
            GL_TEXTURE_INTERNAL_FORMAT, storage.addr)
          glBindTexture(GL_TEXTURE_2D, previousTexture.GLuint)
          target.depth.nativeFormat = storage.GLenum
      elif kind == GL_RENDERBUFFER.GLint:
        var previousBuffer, storage: GLint
        glGetFramebufferAttachmentParameteriv(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT,
          GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME, handle.addr)
        glGetIntegerv(GL_RENDERBUFFER_BINDING, previousBuffer.addr)
        glBindRenderbuffer(GL_RENDERBUFFER, handle.GLuint)
        glGetRenderbufferParameteriv(GL_RENDERBUFFER,
          GL_RENDERBUFFER_INTERNAL_FORMAT, storage.addr)
        glBindRenderbuffer(GL_RENDERBUFFER, previousBuffer.GLuint)
        target.depth.nativeFormat = storage.GLenum
  gpuRenderer.target = target
  gpuRenderer.viewport = size
  gpuRenderer.active = true
  if main or gpuRenderer.frameTarget == nil or framebuffer == 0:
    gpuRenderer.frameTarget = target
  if framebuffer == 0 and stencil:
    gpuRenderer.defaultDrawable = target

proc targetFromNative*(framebuffer: GLuint, size = IVec2()): RenderTarget =
  ## Describes a borrowed legacy framebuffer without changing active pass state.
  let
    previousTarget = gpuRenderer.target
    previousFrame = gpuRenderer.frameTarget
    previousViewport = gpuRenderer.viewport
    previousActive = gpuRenderer.active
  var selectedSize = size
  if selectedSize.x <= 0 or selectedSize.y <= 0:
    var viewport: array[4, GLint]
    glGetIntegerv(GL_VIEWPORT, viewport[0].addr)
    selectedSize = ivec2(viewport[2], viewport[3])
  syncFrameTarget(framebuffer, selectedSize)
  result = gpuRenderer.target
  gpuRenderer.target = previousTarget
  gpuRenderer.frameTarget = previousFrame
  gpuRenderer.viewport = previousViewport
  gpuRenderer.active = previousActive

converter borrowedTarget*(framebuffer: GLuint): RenderTarget =
  ## Adapts public framebuffer handles to the shared pass target contract.
  targetFromNative(framebuffer)

proc initNative*(window: Window) =
  ## Connects the shared pass state to the already selected OpenGL context.
  gpuRenderer.defaultDrawable = nil
  gpuRenderer.window = window
  var framebuffer: GLint
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, framebuffer.addr)
  syncFrameTarget(framebuffer.GLuint, window.size, main = true)

proc frameActive*(): bool =
  ## Reports whether a current application framebuffer is available.
  gpuRenderer.active

proc ensureFrame*(width, height: int) =
  ## Refreshes the application target when a shared pass is entered directly.
  var framebuffer: GLint
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, framebuffer.addr)
  if gpuRenderer.target == nil or
      drawFramebuffer(gpuRenderer.target) != framebuffer.GLuint or
      needsTargetResize(gpuRenderer.target.targetExtent(),
        targetExtent(width, height, gpuRenderer.target.samples)):
    syncFrameTarget(framebuffer.GLuint, ivec2(width.int32, height.int32))

proc ensureFrame*() =
  ## Infers target dimensions from the current viewport when needed.
  var viewport: array[4, GLint]
  glGetIntegerv(GL_VIEWPORT, viewport[0].addr)
  ensureFrame(max(1, viewport[2].int), max(1, viewport[3].int))

proc destroy*(target: RenderTarget) =
  ## Releases only attachments and framebuffer objects owned by this target.
  if target == nil or not target.ownsFramebuffer:
    return
  if not target.borrowsColor:
    target.color.destroy()
    if target.multisampleColor != 0:
      glDeleteRenderbuffers(1, target.multisampleColor.addr)
  if not target.borrowsDepth:
    target.depth.destroy()
    if target.multisampleDepth != 0:
      glDeleteRenderbuffers(1, target.multisampleDepth.addr)
  if target.multisampleFramebuffer != 0:
    glDeleteFramebuffers(1, target.multisampleFramebuffer.addr)
  if target.framebuffer != 0:
    glDeleteFramebuffers(1, target.framebuffer.addr)
  target.framebuffer = 0
  target.multisampleFramebuffer = 0
  target.multisampleColor = 0
  target.multisampleDepth = 0
  target.ownsFramebuffer = false

proc checkTarget() =
  ## Rejects attachments that the current driver cannot render together.
  let status = glCheckFramebufferStatus(GL_FRAMEBUFFER)
  if status != GL_FRAMEBUFFER_COMPLETE:
    raise newException(GpuError, "Incomplete OpenGL pass target: " & $status.uint32)

proc newRenderTarget*(width, height: int, color = true, depth = true,
    samples = 1, colorFormat = Rgba8, stencil = false,
    mipmapped = false): RenderTarget =
  ## Allocates texture-backed resolves and optional multisample renderbuffers.
  if not (color or depth):
    raise newException(GpuError, "Invalid OpenGL pass target dimensions")
  try:
    discard planRenderTarget(width, height, samples, color, depth, stencil,
      mipmapped)
  except TargetPlanError as error:
    raise newException(GpuError, error.msg)
  let previous = saveTarget()
  var previousRenderbuffer: GLint
  glGetIntegerv(GL_RENDERBUFFER_BINDING, previousRenderbuffer.addr)
  defer:
    restoreTarget(previous)
    glBindRenderbuffer(GL_RENDERBUFFER, previousRenderbuffer.GLuint)
  var maxSamples: GLint
  glGetIntegerv(GL_MAX_SAMPLES, maxSamples.addr)
  let
    selectedSamples = max(1, min(samples, maxSamples.int))
    selectedFormat =
      when defined(emscripten):
        if colorFormat == Rgba16f: Rgba8 else: colorFormat
      else:
        colorFormat
    plan = planRenderTarget(width, height, selectedSamples, color, depth,
      stencil, mipmapped)
  result = RenderTarget(width: width, height: height,
    samples: plan.extent.samples, stencil: plan.stencil,
    ownsFramebuffer: true)
  try:
    glGenFramebuffers(1, result.framebuffer.addr)
    glBindFramebuffer(GL_FRAMEBUFFER, result.framebuffer)
    if color:
      result.color = allocateImage(width, height, selectedFormat,
        levels = plan.colorMipLevels)
      glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
        GL_TEXTURE_2D, result.color.handle, 0)
    else:
      var none = GL_NONE.GLenum
      glDrawBuffers(1, none.addr)
      glReadBuffer(GL_NONE)
    if depth:
      result.depth = allocateImage(width, height,
        if stencil: DepthStencil else: Depth32f, linear = false)
      glFramebufferTexture2D(GL_FRAMEBUFFER,
        if stencil: GL_DEPTH_STENCIL_ATTACHMENT else: GL_DEPTH_ATTACHMENT,
        GL_TEXTURE_2D, result.depth.handle, 0)
    checkTarget()
    if plan.multisampleColor or plan.multisampleDepth:
      glGenFramebuffers(1, result.multisampleFramebuffer.addr)
      glBindFramebuffer(GL_FRAMEBUFFER, result.multisampleFramebuffer)
      if color:
        glGenRenderbuffers(1, result.multisampleColor.addr)
        glBindRenderbuffer(GL_RENDERBUFFER, result.multisampleColor)
        glRenderbufferStorageMultisample(GL_RENDERBUFFER,
          selectedSamples.GLsizei, glFormat(selectedFormat).internal.GLenum,
          width.GLsizei, height.GLsizei)
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
          GL_RENDERBUFFER, result.multisampleColor)
      else:
        var none = GL_NONE.GLenum
        glDrawBuffers(1, none.addr)
        glReadBuffer(GL_NONE)
      if depth:
        glGenRenderbuffers(1, result.multisampleDepth.addr)
        glBindRenderbuffer(GL_RENDERBUFFER, result.multisampleDepth)
        glRenderbufferStorageMultisample(GL_RENDERBUFFER,
          selectedSamples.GLsizei,
          if stencil: GL_DEPTH24_STENCIL8 else: GL_DEPTH_COMPONENT32F,
          width.GLsizei, height.GLsizei)
        glFramebufferRenderbuffer(GL_FRAMEBUFFER,
          if stencil: GL_DEPTH_STENCIL_ATTACHMENT else: GL_DEPTH_ATTACHMENT,
          GL_RENDERBUFFER, result.multisampleDepth)
      checkTarget()
  except:
    result.destroy()
    raise

proc renderSamples*(target: RenderTarget): int =
  ## Returns the sample count of the target's current composition phase.
  if target == nil: 1 else: renderSampleCount(target.samples, target.resolved)

proc resolveTarget*(target: RenderTarget) =
  ## Resolves owned multisample attachments without changing drawing state.
  if target == nil or target.samples <= 1 or target.resolved or
      not target.ownsFramebuffer:
    return
  let previous = saveTarget()
  let scissored = glIsEnabled(GL_SCISSOR_TEST) == GL_TRUE
  defer:
    restoreTarget(previous)
    if scissored: glEnable(GL_SCISSOR_TEST)
  glDisable(GL_SCISSOR_TEST)
  glBindFramebuffer(GL_READ_FRAMEBUFFER, target.multisampleFramebuffer)
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, target.framebuffer)
  var mask: GLbitfield
  if target.color != nil: mask = mask or GL_COLOR_BUFFER_BIT
  if target.depth != nil: mask = mask or GL_DEPTH_BUFFER_BIT
  if target.stencil: mask = mask or GL_STENCIL_BUFFER_BIT
  glBlitFramebuffer(0, 0, target.width.GLint, target.height.GLint,
    0, 0, target.width.GLint, target.height.GLint, mask, GL_NEAREST.GLenum)

proc setTarget*(target: RenderTarget = nil) =
  ## Selects a shared target while keeping its viewport and ownership explicit.
  let selected = if target == nil: gpuRenderer.frameTarget else: target
  if selected == nil:
    raise newException(GpuError, "No OpenGL scene target is active")
  gpuRenderer.target = selected
  gpuRenderer.viewport = ivec2(selected.width.int32, selected.height.int32)
  glBindFramebuffer(GL_FRAMEBUFFER, drawFramebuffer(selected))
  glViewport(0, 0, selected.width.GLsizei, selected.height.GLsizei)

proc setRenderViewport*(size: IVec2) =
  ## Sets the active target's draw viewport.
  gpuRenderer.viewport = size
  glViewport(0, 0, size.x.GLsizei, size.y.GLsizei)

proc pushTarget*(target: RenderTarget) =
  ## Preserves external framebuffer bindings around an offscreen scene pass.
  ensureFrame()
  gpuRenderer.stack.add saveTarget()
  setTarget(target)

proc popTarget*() =
  ## Resolves the completed pass and restores the previous target and viewport.
  if gpuRenderer.stack.len == 0:
    raise newException(GpuError, "The OpenGL pass target stack is empty")
  resolveTarget(gpuRenderer.target)
  restoreTarget(gpuRenderer.stack.pop())

proc resolveForUi*(): RenderTarget =
  ## Continues UI drawing on single-sample attachments after resolving the scene.
  result = gpuRenderer.target
  if result != nil and result.ownsFramebuffer:
    resolveTarget(result)
    result.resolved = true
    setTarget(result)

proc matchDepthStorage(source, destination: RenderTarget) =
  ## Matches borrowed depth precision before a GL depth blit requires it.
  if source.depth == nil or destination.depth == nil:
    return
  let storage = source.depth.nativeFormat
  if storage.uint32 == 0 or storage == destination.depth.nativeFormat:
    return
  if not destination.ownsFramebuffer or destination.borrowsDepth:
    raise newException(GpuError, "Cannot replace borrowed depth copy storage")
  var previousTexture, previousUnpackBuffer: GLint
  glGetIntegerv(GL_TEXTURE_BINDING_2D, previousTexture.addr)
  glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, previousUnpackBuffer.addr)
  defer:
    glBindTexture(GL_TEXTURE_2D, previousTexture.GLuint)
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, previousUnpackBuffer.GLuint)
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0)
  glBindTexture(GL_TEXTURE_2D, destination.depth.handle)
  let
    packed = storage in [GL_DEPTH24_STENCIL8, GL_DEPTH32F_STENCIL8]
    external = if packed: GL_DEPTH_STENCIL else: GL_DEPTH_COMPONENT
    kind =
      if storage == GL_DEPTH24_STENCIL8: GL_UNSIGNED_INT_24_8
      elif storage == GL_DEPTH32F_STENCIL8: GL_FLOAT_32_UNSIGNED_INT_24_8_REV
      elif storage == GL_DEPTH_COMPONENT32F: cGL_FLOAT
      else: GL_UNSIGNED_INT
  glTexImage2D(GL_TEXTURE_2D, 0, storage.GLint,
    destination.width.GLsizei, destination.height.GLsizei, 0,
    external, kind, nil)
  destination.depth.nativeFormat = storage
  glBindFramebuffer(GL_FRAMEBUFFER, destination.framebuffer)
  checkTarget()

proc copyTarget*(source, destination: RenderTarget, color = true,
    depth = true) =
  ## Copies or resolves matching attachments while retaining external GL state.
  if source == nil or destination == nil or source.width != destination.width or
      source.height != destination.height or destination.renderSamples() > 1:
    raise newException(GpuError, "Incompatible OpenGL target copy")
  let previous = saveTarget()
  let scissored = glIsEnabled(GL_SCISSOR_TEST) == GL_TRUE
  defer:
    restoreTarget(previous)
    if scissored: glEnable(GL_SCISSOR_TEST)
  glDisable(GL_SCISSOR_TEST)
  if depth:
    matchDepthStorage(source, destination)
  glBindFramebuffer(GL_READ_FRAMEBUFFER, drawFramebuffer(source))
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, destination.framebuffer)
  var mask: GLbitfield
  if color and source.color != nil and destination.color != nil:
    mask = mask or GL_COLOR_BUFFER_BIT
  if depth and source.depth != nil and destination.depth != nil:
    mask = mask or GL_DEPTH_BUFFER_BIT
    if source.stencil and destination.stencil:
      mask = mask or GL_STENCIL_BUFFER_BIT
  if mask.uint32 != 0:
    glBlitFramebuffer(0, 0, source.width.GLint, source.height.GLint,
      0, 0, destination.width.GLint, destination.height.GLint, mask,
      GL_NEAREST.GLenum)

proc snapshotTarget*(color = true, depth = true): RenderTarget =
  ## Copies the current application framebuffer into shader-readable textures.
  ensureFrame()
  let target = gpuRenderer.target
  result = newRenderTarget(target.width, target.height,
    color and target.color != nil, depth and target.depth != nil,
    colorFormat = if target.color == nil: Rgba8 else: target.color.pixelFormat,
    stencil = target.stencil)
  copyTarget(target, result, color, depth)

proc shareDepth*(target, source: RenderTarget) =
  ## Borrows compatible depth storage without taking its lifetime.
  if target == source:
    return
  if target == nil or source == nil:
    raise newException(GpuError, "Shared OpenGL depth target mismatch")
  var plan: DepthSharePlan
  try:
    plan = planDepthShare(target.targetExtent(), source.targetExtent(),
      target.borrowsDepth, source.stencil, source.resolved)
  except TargetPlanError as error:
    raise newException(GpuError, error.msg)
  let previous = saveTarget()
  defer: restoreTarget(previous)
  if plan.releaseDepth:
    target.depth.destroy()
    if target.multisampleDepth != 0:
      glDeleteRenderbuffers(1, target.multisampleDepth.addr)
  target.depth = source.depth
  target.multisampleDepth = source.multisampleDepth
  target.stencil = plan.stencil
  target.borrowsDepth = true
  target.resolved = plan.resolved
  let attachment =
    if source.stencil: GL_DEPTH_STENCIL_ATTACHMENT else: GL_DEPTH_ATTACHMENT
  glBindFramebuffer(GL_FRAMEBUFFER, target.framebuffer)
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT,
    GL_TEXTURE_2D, 0, 0)
  glFramebufferTexture2D(GL_FRAMEBUFFER, attachment, GL_TEXTURE_2D,
    if source.depth == nil: 0.GLuint else: source.depth.handle, 0)
  checkTarget()
  if target.samples > 1:
    glBindFramebuffer(GL_FRAMEBUFFER, target.multisampleFramebuffer)
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT,
      GL_RENDERBUFFER, 0)
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, attachment, GL_RENDERBUFFER,
      source.multisampleDepth)
    checkTarget()

proc clearDepthStencil(depth, stencil: bool) =
  ## Supply clear values in the command, leaving the context's defaults intact.
  if depth and stencil:
    glClearBufferfi(GL_DEPTH_STENCIL, 0, 1, 0)
  elif depth:
    var value: GLfloat = 1
    glClearBufferfv(GL_DEPTH, 0, value.addr)
  elif stencil:
    var value: GLint = 0
    glClearBufferiv(GL_STENCIL, 0, value.addr)

proc clear*(value: Color, depth = true, stencil = false) =
  ## Clears attachments with writable masks while preserving caller draw state.
  ensureFrame()
  let target = gpuRenderer.target
  if target.ownsFramebuffer:
    let resolved = resolvedAfterClear(target.resolved,
      target.depth != nil, depth)
    if resolved != target.resolved:
      target.resolved = resolved
      glBindFramebuffer(GL_DRAW_FRAMEBUFFER, drawFramebuffer(target))
  var colorMask: array[4, GLboolean]
  glGetBooleanv(GL_COLOR_WRITEMASK, colorMask[0].addr)
  let scissored = glIsEnabled(GL_SCISSOR_TEST) == GL_TRUE
  defer:
    glColorMask(colorMask[0], colorMask[1], colorMask[2], colorMask[3])
    if scissored: glEnable(GL_SCISSOR_TEST)
  if scissored: glDisable(GL_SCISSOR_TEST)
  glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE)
  if target.ownsFramebuffer or target.framebuffer == 0:
    if target.color != nil:
      var rgba = [value.r, value.g, value.b, value.a]
      glClearBufferfv(GL_COLOR, 0, rgba[0].addr)
  else:
    # A borrowed FBO can have additional enabled color attachments.
    var oldColor: array[4, GLfloat]
    glGetFloatv(GL_COLOR_CLEAR_VALUE, oldColor[0].addr)
    glClearColor(value.r, value.g, value.b, value.a)
    glClear(GL_COLOR_BUFFER_BIT)
    glClearColor(oldColor[0], oldColor[1], oldColor[2], oldColor[3])
  withClearWriteMasks(depth, stencil):
    clearDepthStencil(depth, stencil)

proc clearDepth*() =
  ## Clears the current depth attachment independently of scene color.
  let scissored = glIsEnabled(GL_SCISSOR_TEST) == GL_TRUE
  if scissored: glDisable(GL_SCISSOR_TEST)
  withClearWriteMasks(true, false):
    clearDepthStencil(true, false)
  if scissored: glEnable(GL_SCISSOR_TEST)

proc setStencil*(write: bool, reference: int, compare = Always) =
  ## Applies character stencil intent to subsequent shared pass draws.
  gpuRenderer.stencilOverride = DrawState(stencilTest: true,
    stencilWrite: write, stencilReference: reference, stencilCompare: compare)
  gpuRenderer.hasStencilOverride = true

proc clearStencilState*() =
  ## Removes an application stencil override from subsequent draws.
  gpuRenderer.hasStencilOverride = false

proc captureTargetImage*(target: RenderTarget = nil): Image =
  ## Reads resolved target pixels in top-left image row order.
  ensureFrame()
  let selected = if target == nil: gpuRenderer.target else: target
  let previous = saveTarget()
  var readable = selected
  defer:
    if readable != selected:
      readable.destroy()
  if not selected.ownsFramebuffer and selected.renderSamples() > 1:
    readable = newRenderTarget(selected.width, selected.height, depth = false,
      colorFormat = if selected.color == nil: Rgba8 else: selected.color.pixelFormat)
    copyTarget(selected, readable, depth = false)
  var pack, rowLength, skipRows, skipPixels, packBuffer: GLint
  glGetIntegerv(GL_PACK_ALIGNMENT, pack.addr)
  glGetIntegerv(GL_PACK_ROW_LENGTH, rowLength.addr)
  glGetIntegerv(GL_PACK_SKIP_ROWS, skipRows.addr)
  glGetIntegerv(GL_PACK_SKIP_PIXELS, skipPixels.addr)
  glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, packBuffer.addr)
  defer:
    restoreTarget(previous)
    glPixelStorei(GL_PACK_ALIGNMENT, pack)
    glPixelStorei(GL_PACK_ROW_LENGTH, rowLength)
    glPixelStorei(GL_PACK_SKIP_ROWS, skipRows)
    glPixelStorei(GL_PACK_SKIP_PIXELS, skipPixels)
    glBindBuffer(GL_PIXEL_PACK_BUFFER, packBuffer.GLuint)
  resolveTarget(readable)
  glBindFramebuffer(GL_READ_FRAMEBUFFER,
    if readable.ownsFramebuffer: readable.framebuffer
    else: drawFramebuffer(readable))
  glPixelStorei(GL_PACK_ALIGNMENT, 1)
  glPixelStorei(GL_PACK_ROW_LENGTH, 0)
  glPixelStorei(GL_PACK_SKIP_ROWS, 0)
  glPixelStorei(GL_PACK_SKIP_PIXELS, 0)
  glBindBuffer(GL_PIXEL_PACK_BUFFER, 0)
  result = newImage(selected.width, selected.height)
  glReadPixels(0, 0, selected.width.GLsizei, selected.height.GLsizei,
    GL_RGBA, GL_UNSIGNED_BYTE, result.data[0].addr)
  for y in 0 ..< selected.height div 2:
    for x in 0 ..< selected.width:
      swap(result.data[y * selected.width + x],
        result.data[(selected.height - y - 1) * selected.width + x])

proc waitForGpu*() =
  ## Waits for explicit capture and test boundaries only.
  glFinish()

proc flushEncoder*() =
  ## Keeps the shared pass API uniform without forcing an OpenGL submission.
  discard
