## Verifies shared pass targets preserve legacy framebuffer and pixel state.

import
  chroma, pixie, vmath, windy,
  polyworld/backends/opengl/passapi

proc checkErrors() =
  ## Fails at the first unsupported or incompatible OpenGL operation.
  let error = glGetError()
  doAssert error == GL_NO_ERROR, "OpenGL error " & $error.uint32

proc verifySamples(samples: int) =
  ## Reads single-sample and multisample color and depth snapshots.
  let
    source = newRenderTarget(24, 24, samples = samples, stencil = true)
    copy = newRenderTarget(24, 24, stencil = true)
  defer:
    source.destroy()
    copy.destroy()
  pushTarget(source)
  clear(color(0.25, 0.5, 0.75, 1), stencil = true)
  popTarget()
  copyTarget(source, copy)
  let pixels = captureTargetImage(copy)
  let actual = pixels[12, 12]
  doAssert abs(actual.r.int - 64) <= 1
  doAssert abs(actual.g.int - 128) <= 1
  doAssert abs(actual.b.int - 191) <= 1
  if samples > 1:
    let borrowed = targetFromNative(source.multisampleFramebuffer, ivec2(24))
    doAssert captureTargetImage(borrowed)[12, 12] == actual
  glBindFramebuffer(GL_READ_FRAMEBUFFER, copy.framebuffer)
  var depth: float32
  glReadPixels(12, 12, 1, 1, GL_DEPTH_COMPONENT, cGL_FLOAT, depth.addr)
  doAssert depth == 1.0'f
  checkErrors()

proc verifyBorrowedDepth() =
  ## Preserves the exact depth format required by legacy framebuffer blits.
  let
    source = newRenderTarget(24, 24)
    destination = newRenderTarget(24, 24)
  defer:
    source.destroy()
    destination.destroy()
  glBindTexture(GL_TEXTURE_2D, source.depth.handle)
  glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT24.GLint, 24, 24, 0,
    GL_DEPTH_COMPONENT, GL_UNSIGNED_INT, nil)
  var actualFormat: GLint
  glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_INTERNAL_FORMAT,
    actualFormat.addr)
  pushTarget(source)
  clear(color(1, 0, 0, 1))
  glClearDepth(0.375)
  glDepthMask(GL_TRUE)
  glClear(GL_DEPTH_BUFFER_BIT)
  glClearDepth(1)
  let borrowed = targetFromNative(source.framebuffer, ivec2(24))
  doAssert borrowed.depth.nativeFormat == actualFormat.GLenum
  copyTarget(borrowed, destination)
  doAssert destination.depth.nativeFormat == actualFormat.GLenum
  glBindFramebuffer(GL_READ_FRAMEBUFFER, destination.framebuffer)
  var depth: float32
  glReadPixels(12, 12, 1, 1, GL_DEPTH_COMPONENT, cGL_FLOAT, depth.addr)
  doAssert abs(depth - 0.375'f) < 0.00001'f
  popTarget()
  checkErrors()

proc verifyCompositionPhase() =
  ## Keeps UI on resolved storage and restarts multisampling on a depth clear.
  let target = newRenderTarget(24, 24, samples = 4)
  defer: target.destroy()
  pushTarget(target)
  clear(color(1, 0, 0, 1))
  doAssert target.renderSamples() == 4
  discard resolveForUi()
  doAssert target.renderSamples() == 1
  clear(color(0, 1, 0, 1), depth = false)
  doAssert target.renderSamples() == 1
  doAssert captureTargetImage(target)[12, 12] == rgbx(0, 255, 0, 255)
  clear(color(0, 0, 1, 1))
  doAssert target.renderSamples() == 4
  doAssert captureTargetImage(target)[12, 12] == rgbx(0, 0, 255, 255)
  popTarget()
  checkErrors()

proc verifyDepthSharing() =
  ## Replaces stencil storage with borrowed depth without retaining attachments.
  let
    source = newRenderTarget(24, 24, samples = 4)
    target = newRenderTarget(24, 24, samples = 4, stencil = true)
  defer:
    target.destroy()
    source.destroy()
  target.shareDepth(source)
  doAssert target.depth == source.depth
  doAssert target.borrowsDepth and not target.stencil
  pushTarget(target)
  clear(color(1, 1, 0, 1))
  var stencilKind: GLint
  glGetFramebufferAttachmentParameteriv(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT,
    GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE, stencilKind.addr)
  doAssert stencilKind == GL_NONE.GLint
  doAssert captureTargetImage(target)[12, 12] == rgbx(255, 255, 0, 255)
  popTarget()
  checkErrors()

proc verifyReadbackState() =
  ## Restores pack buffers, row settings, viewport, and separate framebuffers.
  let
    source = newRenderTarget(24, 24, depth = false)
    other = newRenderTarget(24, 24, depth = false)
    buffer = newBuffer([0'u32, 0])
  defer:
    source.destroy()
    other.destroy()
    buffer.destroy()
  pushTarget(source)
  clear(color(0, 1, 0, 1), depth = false)
  popTarget()
  glBindFramebuffer(GL_READ_FRAMEBUFFER, source.framebuffer)
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, other.framebuffer)
  glViewport(2, 3, 5, 7)
  glBindBuffer(GL_PIXEL_PACK_BUFFER, buffer.handle)
  glPixelStorei(GL_PACK_ALIGNMENT, 8)
  glPixelStorei(GL_PACK_ROW_LENGTH, 11)
  glPixelStorei(GL_PACK_SKIP_ROWS, 3)
  glPixelStorei(GL_PACK_SKIP_PIXELS, 2)
  let pixels = captureTargetImage(source)
  doAssert pixels[12, 12] == rgbx(0, 255, 0, 255)
  for (field, expected) in [
    (GL_READ_FRAMEBUFFER_BINDING, source.framebuffer.GLint),
    (GL_DRAW_FRAMEBUFFER_BINDING, other.framebuffer.GLint),
    (GL_PIXEL_PACK_BUFFER_BINDING, buffer.handle.GLint),
    (GL_PACK_ALIGNMENT, 8.GLint), (GL_PACK_ROW_LENGTH, 11.GLint),
    (GL_PACK_SKIP_ROWS, 3.GLint), (GL_PACK_SKIP_PIXELS, 2.GLint)
  ]:
    var actual: GLint
    glGetIntegerv(field, actual.addr)
    doAssert actual == expected
  var viewport: array[4, GLint]
  glGetIntegerv(GL_VIEWPORT, viewport[0].addr)
  doAssert viewport == [2.GLint, 3, 5, 7]
  glBindBuffer(GL_PIXEL_PACK_BUFFER, 0)
  glPixelStorei(GL_PACK_ALIGNMENT, 4)
  glPixelStorei(GL_PACK_ROW_LENGTH, 0)
  glPixelStorei(GL_PACK_SKIP_ROWS, 0)
  glPixelStorei(GL_PACK_SKIP_PIXELS, 0)
  checkErrors()

proc main() =
  ## Runs the GPU fixture entirely in an invisible, non-activating window.
  let window = newWindow("Shared pass targets", ivec2(24), visible = false)
  defer: window.close()
  window.makeContextCurrent()
  loadExtensions()
  initNative(window)
  verifySamples(1)
  verifySamples(4)
  verifyBorrowedDepth()
  verifyCompositionPhase()
  verifyDepthSharing()
  verifyReadbackState()
  echo "Shared OpenGL target resolve, depth copies, and readback state passed"

main()
