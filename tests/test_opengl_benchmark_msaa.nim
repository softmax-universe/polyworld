## Verifies benchmark sample storage, resolve readback, and queued completion.

import
  opengl, pixie, vmath, windy,
  polyworld/backends/opengl/renderer

when not defined(backendBench) or not defined(backendThroughput):
  {.error: "Build with backendBench and backendThroughput".}

static:
  doAssert BackendBenchSamples == 4, "Build with backendBenchSamples=4"

proc verifySamples(target: FrameTarget, expected: int) =
  ## Checks driver-selected framebuffer and attachment sample counts.
  bindFrameTarget(target.framebuffer)
  var samples, attachment, format: GLint
  glGetIntegerv(GL_SAMPLES, samples.addr)
  doAssert max(1, samples.int) == expected
  for point in [GL_COLOR_ATTACHMENT0, GL_DEPTH_ATTACHMENT]:
    glGetFramebufferAttachmentParameteriv(
      GL_FRAMEBUFFER,
      point,
      GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE,
      attachment.addr
    )
    if expected == 1 and point == GL_COLOR_ATTACHMENT0:
      doAssert attachment.GLenum == GL_TEXTURE
      continue
    doAssert attachment.GLenum == GL_RENDERBUFFER
    glGetFramebufferAttachmentParameteriv(
      GL_FRAMEBUFFER,
      point,
      GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME,
      attachment.addr
    )
    glBindRenderbuffer(GL_RENDERBUFFER, attachment.GLuint)
    glGetRenderbufferParameteriv(
      GL_RENDERBUFFER,
      GL_RENDERBUFFER_SAMPLES,
      samples.addr
    )
    glGetRenderbufferParameteriv(
      GL_RENDERBUFFER,
      GL_RENDERBUFFER_INTERNAL_FORMAT,
      format.addr
    )
    doAssert max(1, samples.int) == expected
    doAssert format.GLenum ==
      (if point == GL_COLOR_ATTACHMENT0: GL_RGBA8 else: GL_DEPTH24_STENCIL8)
  doAssert glGetError() == GL_NO_ERROR

proc verifyDepthCopy(source: FrameTarget) =
  ## Resolves depth into the exact single-sample texture format used by AO.
  var framebuffer, texture: GLuint
  glGenFramebuffers(1, framebuffer.addr)
  glGenTextures(1, texture.addr)
  defer:
    bindFrameTarget(source.framebuffer)
    glDeleteFramebuffers(1, framebuffer.addr)
    glDeleteTextures(1, texture.addr)
  glBindTexture(GL_TEXTURE_2D, texture)
  glTexImage2D(
    GL_TEXTURE_2D,
    0,
    GL_DEPTH24_STENCIL8.GLint,
    source.size.x,
    source.size.y,
    0,
    GL_DEPTH_STENCIL,
    GL_UNSIGNED_INT_24_8,
    nil
  )
  glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
  glFramebufferTexture2D(
    GL_FRAMEBUFFER,
    GL_DEPTH_STENCIL_ATTACHMENT,
    GL_TEXTURE_2D,
    texture,
    0
  )
  glDrawBuffer(GL_NONE)
  glReadBuffer(GL_NONE)
  doAssert glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE
  glBindFramebuffer(GL_READ_FRAMEBUFFER, source.framebuffer)
  glBlitFramebuffer(
    0,
    0,
    source.size.x,
    source.size.y,
    0,
    0,
    source.size.x,
    source.size.y,
    GL_DEPTH_BUFFER_BIT,
    GL_NEAREST.GLenum
  )
  doAssert glGetError() == GL_NO_ERROR, "AO depth resolve must be supported"
  glBindFramebuffer(GL_READ_FRAMEBUFFER, framebuffer)
  var depth: float32
  glReadPixels(0, 0, 1, 1, GL_DEPTH_COMPONENT, cGL_FLOAT, depth.addr)
  doAssert abs(depth - 0.25'f) < 0.000001'f,
    "AO depth copy must contain the multisampled scene's depth"
  doAssert glGetError() == GL_NO_ERROR

proc verifyImage(image: Image) =
  ## Checks full-frame readback despite a scissor covering only the right half.
  for y in 0 ..< image.height:
    for x in 0 ..< image.width:
      doAssert image[x, y] ==
        (if x < image.width div 2: rgbx(255, 0, 0, 255)
        else: rgbx(0, 0, 255, 255))

proc main() =
  ## Exercises the public offscreen and throughput APIs without game assets.
  let window = newWindow("OpenGL benchmark MSAA", ivec2(32, 24),
    visible = false, vsync = false)
  initRenderer(window)
  var
    single = newFrameTarget(32, 24)
    target: ScreenshotTarget
  defer:
    shutdownRenderer()
    releaseScreenshotTarget(target)
    destroyFrameTarget(single)
    window.close()

  single.verifySamples(1)
  glClearDepth(0.25)
  clearFrame(color(1, 0, 0, 1))
  single.verifyDepthCopy()
  discard beginScreenshotFrame(target, window)
  target.verifySamples(4)
  clearFrame(color(1, 0, 0, 1))
  target.verifyDepthCopy()

  glEnable(GL_SCISSOR_TEST)
  glScissor(16, 0, 16, 24)
  clearFrame(color(0, 0, 1, 1), depth = false)
  glBindFramebuffer(GL_READ_FRAMEBUFFER, single.framebuffer)
  doAssert readFramePixel() == [255'u8, 0, 0, 255]
  readFrameImage(32, 24).verifyImage()
  var read, draw: GLint
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, read.addr)
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, draw.addr)
  doAssert read.GLuint == single.framebuffer
  doAssert draw.GLuint == target.framebuffer
  doAssert glIsEnabled(GL_SCISSOR_TEST)
  glDisable(GL_SCISSOR_TEST)
  doAssert glGetError() == GL_NO_ERROR

  discard drainBenchmarkGpuFrames()
  resetBenchmarkGpuStats()
  for frame in 0 ..< 7:
    beginBenchmarkGpuFrame()
    discard beginScreenshotFrame(target, window)
    clearFrame(color((frame mod 2).float32, 1, 0, 1))
    submitBenchmarkGpuFrame()
  let stats = drainBenchmarkGpuFrames()
  doAssert stats.submittedFrames == 7 and stats.completedFrames == 7
  doAssert stats.capacity == 3 and stats.maxOutstanding in 1 .. 3
  doAssert readFramePixel() == [0'u8, 255, 0, 255]
  doAssert glGetError() == GL_NO_ERROR
  resetBenchmarkGpuStats()
  doAssert readBenchmarkGpuStats().submittedFrames == 0
  echo "PASS OpenGL 1x/4x storage, color/depth resolve, and queued completion"

main()
