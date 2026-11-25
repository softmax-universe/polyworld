## Metal card faces share Silky's atlas and the application's command buffer.

import std/tables
import chroma, pixie, shady, silky, silky/drawers/metal4, vmath
import pkg/metal4 as metal
import polyworld/backends/metal/common
from polyworld/renderer import atlasTexture
import ../../../core/core, ../../../ui/[cardfaces, silkyfaces]
import ../../cardshaders
export silkyfaces.FaceState, silkyfaces.addFaceAssets

type
  CardTexture = MetalTexture

  CardRenderer* = object
    program: MetalProgram
    vertexBuffer: MetalBuffer
    vertices: seq[float32]
    batches: seq[Batch]

  Batch = object
    texture: CardTexture
    size: Vec2
    first, count: int

  FaceTexture = object
    texture: CardTexture
    lastFrame: int

  HudFace = object
    texture: CardTexture
    origin, size: Vec2
    tint: ColorRGBX

const
  CardBackKey* = "card/back"
  FloatsPerVertex = 9
  FaceTextureBudget = 64
  FaceTextureTop = 0.5'f
  FaceTextureBottom = CardFaceHeight.float32 - 0.5'f

var
  faceTextures: Table[FaceState, FaceTexture]
  faceTargets: seq[RenderTarget]
  frame = 0
  hudFaces: seq[HudFace]
  hudProgram: MetalProgram
  hudVertexBuffer: MetalBuffer

proc initCardRenderer*(): CardRenderer =
  ## Creates the shared card-surface pipeline.
  result.program = newProgram(
    toMSL(cardVertex, shaderVertex),
    toMSL(cardFragment, shaderFragment),
    VertexLayout(stride: FloatsPerVertex * sizeof(float32), attributes: @[
      VertexAttribute(name: "position", format: Float3, offset: 0),
      VertexAttribute(name: "uv", format: Float2, offset: 3 * sizeof(float32)),
      VertexAttribute(name: "tint", format: Float4, offset: 5 * sizeof(float32))
    ])
  )

proc newFaceTexture(): CardTexture =
  ## Allocates a reusable offscreen face target matching the UI drawer format.
  let target = newRenderTarget(CardFaceWidth, CardFaceHeight, depth = false,
    mipmapped = true)
  faceTargets.add target
  target.color

proc renderFace(sk: Silky, state: FaceState, texture: CardTexture) =
  ## Renders one face while preserving the HUD geometry queued by the caller.
  var target: RenderTarget
  for candidate in faceTargets:
    if candidate.color == texture:
      target = candidate
      break
  doAssert not target.isNil
  sk.isolatedDrawing(rect(0, 0, CardFaceWidth.float32,
      CardFaceHeight.float32)):
    sk.paintFace(state, vec2(0, 0))
    pushTarget(target)
    defer:
      popTarget()
    clear(color(0, 0, 0, 0), depth = false)
    let vertices = sk.drawer.layers[0]
    if vertices.len > 0:
      flushEncoder()
      sk.drawer.setExternalFrame(metalRenderer.commandBuffer, target.color.handle)
      sk.drawer.endFrame(sk.image,
        vec2(CardFaceWidth.float32, CardFaceHeight.float32),
        vertices[0].unsafeAddr, vertices.len)
    generateMipmaps(texture)

include ../../cardgeometry

proc draw*(renderer: var CardRenderer, sk: Silky, viewProjection: Mat4) =
  ## Draws premultiplied card faces and atlas sprites against scene depth.
  if renderer.vertices.len == 0:
    return
  if renderer.vertexBuffer.isNil:
    renderer.vertexBuffer = newBuffer(renderer.vertices)
  else:
    updateBuffer(renderer.vertexBuffer, renderer.vertices)
  renderer.program.setUniform("cardViewProjection", viewProjection)
  for batch in renderer.batches:
    renderer.program.setUniform("cardAtlasSize", batch.size)
    renderer.program.bindTexture("cardAtlasSampler", batch.texture)
    draw(renderer.program, renderer.vertexBuffer, batch.count,
      DrawState(depthTest: true, depthWrite: true, depthCompare: Less,
        blend: PremultipliedAlpha),
      first = batch.first)

proc drawHudFaces*(sk: Silky) =
  ## Composites queued cached faces over the UI in framebuffer pixel space.
  if hudFaces.len == 0:
    return
  if hudProgram.isNil:
    hudProgram = newProgram(
      toMSL(hudVertex, shaderVertex),
      toMSL(hudFragment, shaderFragment),
      VertexLayout(stride: 4 * sizeof(float32), attributes: @[
        VertexAttribute(name: "position", format: Float2, offset: 0),
        VertexAttribute(name: "uv", format: Float2,
          offset: 2 * sizeof(float32))
      ])
    )
  hudProgram.setUniform("hudViewportSize",
    vec2(sk.framebufferSize.x.float32, sk.framebufferSize.y.float32))
  for face in hudFaces:
    let
      a = face.origin * sk.uiScale
      b = (face.origin + face.size) * sk.uiScale
      vertices = [a.x, a.y, 0.0'f, 0, a.x, b.y, 0, 1, b.x, b.y, 1, 1,
        a.x, a.y, 0, 0, b.x, b.y, 1, 1, b.x, a.y, 1, 0]
    if hudVertexBuffer.isNil:
      hudVertexBuffer = newBuffer(vertices)
    else:
      updateBuffer(hudVertexBuffer, vertices)
    hudProgram.setUniform("hudTint", vec4(face.tint.r.float32 / 255,
      face.tint.g.float32 / 255, face.tint.b.float32 / 255,
      face.tint.a.float32 / 255))
    hudProgram.bindTexture("hudSampler", face.texture)
    draw(hudProgram, hudVertexBuffer, 6, DrawState(blend: PremultipliedAlpha))
  hudFaces.setLen(0)
