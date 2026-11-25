## Metal silhouette masks and depth-aware outline compositing.

import
  pixie, shady, vmath,
  common, ../shaders/selectionoutlines

export selectionoutlines

type
  SelectionOutline* = object
    target: RenderTarget
    program: MetalProgram
    vertices: MetalBuffer
    size: IVec2
    visibility: OutlineVisibility

proc initSelectionOutline*(
    visibility = AlwaysOutline
): SelectionOutline =
  ## Compiles the selected outline shader and its full-screen triangle.
  result.visibility = visibility
  let fragment =
    if visibility == OccludedOutline:
      toShader(occlusionFragment, metalMSL, shaderFragment)
    else:
      toShader(selectionFragment, metalMSL, shaderFragment)
  result.program = newProgram(
    toShader(selectionVertex, metalMSL, shaderVertex), fragment,
    VertexLayout(stride: sizeof(Vec2), attributes: @[
      VertexAttribute(name: "vertexPosition", format: Float2, offset: 0)
    ])
  )
  result.vertices = newBuffer([vec2(-1, -1), vec2(3, -1), vec2(-1, 3)])

proc ensureSize(outline: var SelectionOutline, size: IVec2) =
  ## Resizes the single-sample silhouette color and depth attachments.
  let safeSize = ivec2(max(size.x, 1), max(size.y, 1))
  if outline.size == safeSize:
    return
  destroy(outline.target)
  outline.size = safeSize
  outline.target = newRenderTarget(safeSize.x, safeSize.y)
  outline.target.color.setTextureSampling(linear = false)
  outline.target.depth.setTextureSampling(linear = false)

proc beginMask*(outline: var SelectionOutline, size: IVec2) =
  ## Clears and binds the selected-object silhouette target.
  outline.ensureSize(size)
  pushTarget(outline.target)
  clear(color(0, 0, 0, 0))

proc drawOutline*(
    outline: SelectionOutline,
    color = SelectionOutlineColor
) =
  ## Composites edges into the preceding target without changing its depth.
  popTarget()
  outline.program.bindTexture("selectionTexture", outline.target.color)
  if outline.visibility == OccludedOutline:
    outline.program.bindTexture("selectionDepth", outline.target.depth)
  outline.program.setUniform("selectionResolution",
    vec2(outline.size.x.float32, outline.size.y.float32))
  outline.program.setUniform("selectionColor", color)
  outline.program.setUniform("selectionYTransform", vec2(-1, 1))
  draw(outline.program, outline.vertices, 3, DrawState(
    depthTest: outline.visibility == OccludedOutline,
    depthCompare: Greater,
    depthWrite: false,
    blend: AlphaBlend
  ))

proc closeSelectionOutline*(outline: var SelectionOutline) =
  ## Releases the outline pipeline, triangle, and target attachments.
  destroy(outline.target)
  destroy(outline.vertices)
  destroy(outline.program)
  outline = SelectionOutline()
