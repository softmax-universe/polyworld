## Adapts shared game frames and Silky UI to the native renderer.

import std/tables
import chroma, pixie, silky, vmath, windy, shady
import silky/drawers/shader as uiShaders
when defined(useDirectX): import silky/drawers/dx12 as uiDrawer
else: import silky/drawers/vk14 as uiDrawer
import common, meshes, ../../screenshots

type
  TextureHandle* = GpuImage
  FramebufferHandle* = RenderTarget
  FrameTarget* = RenderTarget
  ScreenshotTarget* = object
    framebuffer*: FramebufferHandle
    size*: IVec2

var
  atlasViews: Table[pointer, tuple[image: Image, entries: int, texture: GpuImage]]
  uiProgram: ShaderProgram

proc initRenderer*(window: Window, samples = 1) =
  initNative(window)
  setFrameSamples(samples)

proc shutdownRenderer*() =
  clearModelResources()
  shutdownNative()
  atlasViews.clear()
  uiProgram = nil

proc newGameUi*(window: Window, atlasPath: string): Silky =
  newSilky(window, atlasPath, uiDrawer.Drawer())

proc beginGameUi*(sk: Silky, window: Window, size: IVec2) =
  sk.beginUiShared(window, size)

proc presentRenderer*(window: Window) = endFrame(not captureActive())

proc atlasTexture*(sk: Silky): TextureHandle =
  let view = atlasViews.getOrDefault(cast[pointer](sk))
  if view.image != sk.image or view.entries != sk.atlas.entries.len or view.texture == nil:
    view.texture.destroy()
    atlasViews[cast[pointer](sk)] = (sk.image, sk.atlas.entries.len, newTexture(sk.image))
  atlasViews[cast[pointer](sk)].texture

proc drawUiLayer*(sk: Silky, vertices: openArray[DrawerVertex], size: Vec2, scale: float32) =
  if vertices.len == 0: return
  if uiProgram == nil:
    uiProgram = newProgram(nativeStage(uiShaders.silkyVert, shaderVertex), nativeStage(uiShaders.silkyFrag, shaderFragment),
      VertexLayout(stride: sizeof(DrawerVertex), attributes: @[
        VertexAttribute(name: "pos", format: Float2, offset: offsetOf(DrawerVertex, pos)),
        VertexAttribute(name: "uv", format: Float2, offset: offsetOf(DrawerVertex, uv)),
        VertexAttribute(name: "color", format: Unorm8x4, offset: offsetOf(DrawerVertex, color)),
        VertexAttribute(name: "clipPos", format: Float2, offset: offsetOf(DrawerVertex, clipPos)),
        VertexAttribute(name: "clipSize", format: Float2, offset: offsetOf(DrawerVertex, clipSize)),
        VertexAttribute(name: "maskUv", format: Float2, offset: offsetOf(DrawerVertex, maskUv))]))
  uiProgram.setUniform("viewportSize", size / scale)
  uiProgram.setUniform("atlasSize", sk.atlasImageSize().vec2)
  uiProgram.bindTexture("atlasSampler", sk.atlasTexture())
  drawStream(uiProgram, vertices, vertices.len, DrawState(blend: PremultipliedAlpha))

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
  for layer in sk.drawer.layers:
    sk.drawUiLayer(layer, sk.framebufferSize.vec2, sk.uiScale)
  sk.endUiShared()

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
  ## Uses the same offscreen frame for visible and hidden windows.
  ensureFrame()
  target.framebuffer = gpuRenderer.frameTarget
  target.size = window.size
  setTarget(target.framebuffer)
  target.framebuffer

proc readFrameImage*(width, height: int): Image =
  ## Completes pending rendering and reads the current target's pixels.
  ensureFrame()
  result = captureTargetImage()
  if result.width != width or result.height != height:
    raise newException(ScreenshotError,
      "Capture dimensions do not match the active rendering target")

proc finishGpu*() =
  ## Completes submitted rendering while preserving the active target.
  waitForGpu()
