## Metal rendering of CaC material sprites and particles.

import
  std/[math, os],
  pixie, shady, vmath,
  polyworld/backends/metal/common,
  ../../../core/core, ../../[vfxdata, vfxshaders]

export vfxdata

type
  VfxRenderer* = object
    program: MetalProgram
    vertexBuffer, materialBuffer: MetalBuffer
    lightningTexture, oozeTexture, oozeDropletTexture: MetalTexture
    lightningAspect: float32
    vertices, materialVertices: seq[float32]

proc initVfxRenderer*(textureRoot: string): VfxRenderer =
  ## Compiles the shared stages and loads the effect sprites on Metal.
  result.program = newProgram(
    toShader(vfxVertex, metalMSL, shaderVertex),
    toShader(vfxFragment, metalMSL, shaderFragment),
    VertexLayout(
      stride: 12 * sizeof(float32),
      attributes: @[
        VertexAttribute(name: "position", format: Float3, offset: 0),
        VertexAttribute(name: "uv", format: Float2,
          offset: 3 * sizeof(float32)),
        VertexAttribute(name: "ink", format: Float4,
          offset: 5 * sizeof(float32)),
        VertexAttribute(name: "style", format: Float1,
          offset: 9 * sizeof(float32)),
        VertexAttribute(name: "dimensions", format: Float2,
          offset: 10 * sizeof(float32))
      ]
    )
  )
  result.vertexBuffer = newBuffer([0.0'f])
  result.materialBuffer = newBuffer([0.0'f])
  let lightning = readImage(textureRoot / "lightning-strike.png")
  result.lightningAspect = lightning.width.float32 / lightning.height.float32
  result.lightningTexture = newTexture(lightning, mipmaps = true)
  result.oozeTexture = newTexture(
    readImage(textureRoot / "ooze-splat.png"), mipmaps = true
  )
  result.oozeDropletTexture = newTexture(
    readImage(textureRoot / "ooze-droplet.png"), mipmaps = true
  )

include ../../vfxgeometry

proc drawEffects(renderer: var VfxRenderer, viewProjection: Mat4,
    additive, depthTest: bool, stencilReference = -1) =
  ## Draws material surfaces before their light, preserving scene depth.
  if renderer.vertices.len == 0 and renderer.materialVertices.len == 0:
    return
  renderer.program.setUniform("vfxViewProjection", viewProjection)
  renderer.program.bindTexture("vfxLightningSampler", renderer.lightningTexture)
  renderer.program.bindTexture("vfxOozeSampler", renderer.oozeTexture)
  renderer.program.bindTexture(
    "vfxOozeDropletSampler", renderer.oozeDropletTexture
  )
  var state = DrawState(
    depthTest: depthTest,
    depthWrite: false,
    blend: AlphaBlend
  )
  if stencilReference >= 0:
    state.stencilCompare = Equal
    state.stencilTest = true
    state.stencilReference = stencilReference
    state.stencilWrite = false
  if renderer.materialVertices.len > 0:
    renderer.materialBuffer.updateBuffer(renderer.materialVertices)
    draw(renderer.program, renderer.materialBuffer,
      renderer.materialVertices.len div 12, state)
  if renderer.vertices.len > 0:
    renderer.vertexBuffer.updateBuffer(renderer.vertices)
    state.blend = if additive: Additive else: AlphaBlend
    draw(renderer.program, renderer.vertexBuffer,
      renderer.vertices.len div 12, state)

proc draw*(renderer: var VfxRenderer, viewProjection: Mat4,
    additive = true, depthTest = true) =
  ## Renders the queued material and light geometry into the current target.
  renderer.drawEffects(viewProjection, additive, depthTest)

proc drawCharacterFlash*(renderer: var VfxRenderer, stencilRef: int,
    strength: float32) =
  ## Overlays red only on the visible character silhouette in stencil.
  if strength <= 0:
    return
  var
    savedVertices = move(renderer.vertices)
    savedMaterials = move(renderer.materialVertices)
  defer:
    renderer.vertices = move(savedVertices)
    renderer.materialVertices = move(savedMaterials)
  renderer.addQuad(
    [vec3(-1, 1, 0), vec3(-1, -1, 0), vec3(1, -1, 0), vec3(1, 1, 0)],
    [vec2(0), vec2(0), vec2(0), vec2(0)],
    vec4(1, 0.025, 0.045, strength * 0.88'f),
    0
  )
  renderer.drawEffects(mat4(), false, false, stencilRef)

proc dispose*(renderer: var VfxRenderer) =
  ## Releases the effect pipeline, sprite textures, and upload buffers.
  destroy(renderer.program)
  destroy(renderer.vertexBuffer)
  destroy(renderer.materialBuffer)
  destroy(renderer.lightningTexture)
  destroy(renderer.oozeTexture)
  destroy(renderer.oozeDropletTexture)
  renderer = VfxRenderer()
