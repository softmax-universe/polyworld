## Shared card caching, batching, and drawing over the active scene target.

import std/tables
import chroma, pixie, shady, silky, vmath
import polyworld/backends/passes/common
from polyworld/renderer import atlasTexture, drawUiLayer
import ../../../core/core, ../../../ui/[cardfaces, silkyfaces]
import ../shaders/cards
export silkyfaces.FaceState, silkyfaces.addFaceAssets

type
  CardTexture = GpuImage

  CardRenderer* = object
    program: ShaderProgram
    vertexBuffer: VertexBuffer
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
  FaceTextureTop =
    when PassTopLeftOrigin: 0.5'f
    else: CardFaceHeight.float32 - 0.5'f
  FaceTextureBottom =
    when PassTopLeftOrigin: CardFaceHeight.float32 - 0.5'f
    else: 0.5'f

var
  faceTextures: Table[FaceState, FaceTexture]
  faceTargets: seq[RenderTarget]
  frame = 0
  hudFaces: seq[HudFace]
  hudProgram: ShaderProgram
  hudVertexBuffer: VertexBuffer

proc initCardRenderer*(): CardRenderer =
  ## Creates the shared card-surface pipeline.
  result.program = newProgram(
    nativeStage(cardVertex, shaderVertex),
    nativeStage(cardFragment, shaderFragment),
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
      drawUiLayer(sk, vertices, vec2(CardFaceWidth.float32, CardFaceHeight.float32), 1)
    generateMipmaps(texture)

include ../../cardgeometry

proc draw*(renderer: var CardRenderer, sk: Silky, viewProjection: Mat4) =
  ## Draws premultiplied card faces and atlas sprites against scene depth.
  if renderer.vertices.len == 0:
    return
  preserveDrawState:
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
  preserveDrawState:
    if hudProgram.isNil:
      hudProgram = newProgram(
        nativeStage(hudVertex, shaderVertex),
        nativeStage(hudFragment, shaderFragment),
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
        top = when PassTopLeftOrigin: 0.0'f else: 1.0'f
        bottom = 1.0'f - top
        vertices = [a.x, a.y, 0.0'f, top, a.x, b.y, 0, bottom,
          b.x, b.y, 1, bottom, a.x, a.y, 0, top, b.x, b.y, 1, bottom,
          b.x, a.y, 1, top]
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
