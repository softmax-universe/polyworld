## Adapts shared game frames and Silky UI to the Metal renderer.

import
  std/tables,
  chroma, pixie, silky, vmath, windy, pkg/metal4,
  silky/drawers/metal4 as silkyMetal,
  common, meshes, ../../screenshots

const RendererBackend* = "metal"

type
  TextureHandle* = MetalTexture
  FramebufferHandle* = RenderTarget
  FrameTarget* = RenderTarget
  ScreenshotTarget* = object
    framebuffer*: FramebufferHandle
    size*: IVec2

var
  renderWindow: Window
  atlasViews: Table[uint, MetalTexture]

proc ensureFrame() =
  ## Starts one shared command buffer before the first rendering operation.
  if metalRenderer.commandBuffer.isNil:
    beginFrame(renderWindow.size.x, renderWindow.size.y, color(0, 0, 0, 1))

proc initRenderer*(window: Window, samples = 1) =
  ## Creates the device, presentation surface, and shared frame owner.
  renderWindow = window
  initMetal(window)
  setFrameSamples(samples)

proc shutdownRenderer*() =
  ## Releases cached model and atlas views before destroying the device.
  clearModelResources()
  shutdownMetal()
  atlasViews.clear()
  renderWindow = nil

proc newGameUi*(window: Window, atlasPath: string): Silky =
  ## Shares the renderer's device with an externally submitted UI drawer.
  let
    data = readAtlas(atlasPath)
    drawer = silkyMetal.newDrawer(metalRenderer.ctx.device, data.image,
      window.size, MTLPixelFormatRGBA8Unorm)
  newSilky(window, data.image, data.atlas, drawer)

proc presentRenderer*(window: Window) =
  ## Presents and completes the shared scene and UI command buffer.
  if not metalRenderer.commandBuffer.isNil:
    endFrame(not captureActive() and not defined(backendBench))

proc atlasTexture*(sk: Silky): TextureHandle =
  ## Borrows the current UI atlas for world-space text and labels.
  ensureFrame()
  flushEncoder()
  sk.drawer.prepareAtlas(metalRenderer.commandBuffer)
  let handle = sk.drawer.atlasTexture()
  let key = uint(handle)
  if key notin atlasViews or atlasViews[key].handle.isNil:
    let size = sk.atlasImageSize()
    handle.retain()
    atlasViews[key] = textureFromNative(handle, size.x, size.y,
      MTLPixelFormatRGBA8Unorm, ownsHandle = true)
  atlasViews[key]

proc setRenderViewport*(size: IVec2) =
  ## Sets the viewport for the current and subsequent render encoders.
  ensureFrame()
  common.setRenderViewport(size)

proc setMultisampling*(enabled: bool) =
  ## Ends multisampling before UI and subsequent composition passes.
  if not enabled:
    ensureFrame()
    discard resolveForUi()

proc bindFrameTarget*(target: FramebufferHandle = nil) =
  ## Selects an existing target, or the shared presentation surface.
  ensureFrame()
  setTarget(target)

proc clearFrame*(value: Color, depth = true, stencil = false) =
  ## Clears selected attachments in the shared command buffer.
  ensureFrame()
  common.clear(value, depth, stencil)

proc prepareUi*(sk: Silky) =
  ## Ends character stencil marking before the UI pass.
  ensureFrame()
  clearStencilState()
  discard resolveForUi()

proc finishUi*(sk: Silky) =
  ## Encodes UI over the resolved scene without presenting a separate frame.
  ensureFrame()
  discard resolveForUi()
  sk.drawer.setExternalFrame(metalRenderer.commandBuffer,
    metalRenderer.target.color.handle)
  sk.endUi()

proc beginStencil*(reference: int) =
  ## Marks fragments from the following character draws.
  ensureFrame()
  setStencil(true, reference)

proc endStencil*() =
  ## Ends character stencil marking.
  clearStencilState()

proc newFrameTarget*(width, height: int): FrameTarget =
  ## Allocates color and depth-stencil storage for an offscreen pass.
  newRenderTarget(width, height, stencil = true)

proc destroyFrameTarget*(target: var FrameTarget) =
  ## Releases one offscreen rendering surface.
  destroy(target)
  target = nil

proc pushFrameTarget*(target: FrameTarget) =
  ## Saves the current target and begins an offscreen pass.
  ensureFrame()
  pushTarget(target)

proc popFrameTarget*() =
  ## Returns to the previous rendering target.
  popTarget()

proc releaseScreenshotTarget*(target: var ScreenshotTarget) =
  ## Forgets the borrowed frame target owned by the renderer.
  target = ScreenshotTarget()

proc beginScreenshotFrame*(target: var ScreenshotTarget, window: Window,
    enabled = captureActive()): FramebufferHandle =
  ## Uses the same offscreen frame for visible and hidden Metal windows.
  ensureFrame()
  target.framebuffer = metalRenderer.frameTarget
  target.size = window.size
  setTarget(target.framebuffer)
  target.framebuffer

proc readFrameImage*(width, height: int): Image =
  ## Completes pending rendering and reads the current target's pixels.
  ensureFrame()
  result = captureImage()
  if result.width != width or result.height != height:
    raise newException(ScreenshotError,
      "Capture dimensions do not match the active rendering target")

proc finishGpu*() =
  ## Completes submitted rendering while preserving the active target.
  waitForGpu()

proc readFramePixel*(): array[4, uint8] =
  ## Completes rendering and reads one pixel from the active RGBA8 target.
  ensureFrame()
  let target = metalRenderer.target
  if target.color.pixelFormat != MTLPixelFormatRGBA8Unorm:
    raise newException(PolyworldMetalError, "Pixel readback requires RGBA8")
  waitForGpu()
  target.color.handle.getBytes(
    result[0].addr,
    4,
    MTLRegion(origin: MTLOrigin(), size: MTLSize(width: 1, height: 1, depth: 1)),
    0
  )
