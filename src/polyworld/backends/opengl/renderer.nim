## Owns OpenGL frame targets, presentation, UI state, and pixel readback.

import
  chroma, opengl, pixie, silky, vmath, windy,
  ../../screenshots

type
  TextureHandle* = GLuint
  FramebufferHandle* = GLuint
  FrameTarget* = object
    framebuffer*, texture*, depth*: GLuint
    size*: IVec2
  ScreenshotTarget* = FrameTarget
  TargetState = object
    read, draw: GLint
    viewport: array[4, GLint]

var targetStack: seq[TargetState]

proc initRenderer*(window: Window, samples = 1) =
  ## Initializes OpenGL entry points for the active window.
  window.makeContextCurrent()
  loadExtensions()

proc shutdownRenderer*() =
  ## Leaves context-owned resources to their explicit feature owners.
  discard

proc newGameUi*(window: Window, atlasPath: string): Silky =
  ## Creates the UI drawer for the active graphics context.
  newSilky(window, atlasPath)

proc presentRenderer*(window: Window) =
  ## Presents the completed OpenGL back buffer.
  window.swapBuffers()

proc atlasTexture*(sk: Silky): TextureHandle =
  ## Borrows the current atlas texture for world-space text.
  sk.atlasTextureId()

proc setRenderViewport*(size: IVec2) =
  ## Sets the viewport to the complete rendering surface.
  glViewport(0, 0, size.x.GLsizei, size.y.GLsizei)

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

proc clearFrame*(value: Color, depth = true, stencil = false) =
  ## Clears the requested attachments with writable depth and stencil.
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
  sk.endUi()

proc beginStencil*(reference: int) =
  ## Marks fragments from the following character draws.
  glEnable(GL_STENCIL_TEST)
  glStencilMask(0xff)
  glStencilFunc(GL_ALWAYS, reference.GLint, 0xff)
  glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE)

proc endStencil*() =
  ## Ends character stencil marking.
  glStencilMask(0)
  glDisable(GL_STENCIL_TEST)

proc destroyFrameTarget*(target: var FrameTarget) =
  ## Releases the color, depth, and framebuffer resources.
  if target.depth != 0:
    glDeleteRenderbuffers(1, target.depth.addr)
  if target.texture != 0:
    glDeleteTextures(1, target.texture.addr)
  if target.framebuffer != 0:
    glDeleteFramebuffers(1, target.framebuffer.addr)
  target = FrameTarget()

proc newFrameTarget*(width, height: int): FrameTarget =
  ## Allocates a complete offscreen color and depth-stencil target.
  if width <= 0 or height <= 0:
    raise newException(ScreenshotError, "Render target dimensions are empty")
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
  glGenRenderbuffers(1, result.depth.addr)
  glBindRenderbuffer(GL_RENDERBUFFER, result.depth)
  glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8,
    width.GLsizei, height.GLsizei)
  glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT,
    GL_RENDERBUFFER, result.depth)
  if glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE:
    result.destroyFrameTarget()
    raise newException(ScreenshotError, "Unable to allocate render target")
  result.size = ivec2(width.int32, height.int32)

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

proc releaseScreenshotTarget*(target: var ScreenshotTarget) =
  ## Releases the hidden-window capture target.
  target.destroyFrameTarget()

proc beginScreenshotFrame*(target: var ScreenshotTarget, window: Window,
    enabled = captureActive()): FramebufferHandle =
  ## Binds an offscreen surface when a hidden window is being captured.
  if not enabled:
    bindFrameTarget()
    setRenderViewport(window.size)
    return 0
  if target.framebuffer == 0 or target.size != window.size:
    target.destroyFrameTarget()
    target = newFrameTarget(window.size.x, window.size.y)
  bindFrameTarget(target.framebuffer)
  setRenderViewport(target.size)
  target.framebuffer

proc readFrameImage*(width, height: int): Image =
  ## Reads the current drawing surface into a top-left-oriented image.
  result = newImage(width, height)
  var previousRead, drawing, readBuffer, packAlignment: GLint
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, previousRead.addr)
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, drawing.addr)
  glBindFramebuffer(GL_READ_FRAMEBUFFER, drawing.GLuint)
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
