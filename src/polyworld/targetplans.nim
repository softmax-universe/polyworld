## Plans render-target storage and phase changes without native GPU objects.

type
  TargetPlanError* = object of CatchableError
  TargetExtent* = object
    width*, height*, samples*: int
  TargetPlan* = object
    extent*: TargetExtent
    color*, depth*, stencil*: bool
    colorMipLevels*: int
    multisampleColor*, multisampleDepth*: bool
  DepthSharePlan* = object
    releaseDepth*: bool
    stencil*, resolved*: bool

proc targetExtent*(width, height, samples: int): TargetExtent =
  ## Describes attachment dimensions and the allocated sample count.
  TargetExtent(width: width, height: height, samples: samples)

proc targetExtent*[T](target: T): TargetExtent =
  ## Reads the common extent fields from a backend-owned target.
  targetExtent(target.width, target.height, target.samples)

proc planRenderTarget*(
  width, height, samples: int,
  color = true,
  depth = true,
  stencil = false,
  mipmapped = false
): TargetPlan =
  ## Validates storage and plans resolved, multisample, and mip attachments.
  if width <= 0 or height <= 0 or samples <= 0:
    raise newException(TargetPlanError, "Invalid render target dimensions")
  if width > int.high div height or width * height > int.high div samples:
    raise newException(TargetPlanError, "Render target extent exceeds address space")
  result = TargetPlan(
    extent: targetExtent(width, height, samples),
    color: color,
    depth: depth,
    stencil: stencil and depth,
    colorMipLevels: 1,
    multisampleColor: color and samples > 1,
    multisampleDepth: depth and samples > 1
  )
  if color and mipmapped:
    var size = max(width, height)
    while size > 1:
      size = size shr 1
      inc result.colorMipLevels

proc needsTargetResize*(current, requested: TargetExtent): bool =
  ## Recreates storage only when dimensions or allocated samples change.
  current != requested

proc renderSampleCount*(samples: int, resolved: bool): int =
  ## Selects resolved attachments after UI composition begins.
  if resolved: 1 else: samples

proc resolvedAfterClear*(resolved, hasDepth, clearDepth: bool): bool =
  ## Restarts multisample rendering only when prior depth is not preserved.
  resolved and hasDepth and not clearDepth

proc planDepthShare*(
  target, source: TargetExtent,
  targetBorrowsDepth, sourceStencil, sourceResolved: bool
): DepthSharePlan =
  ## Validates borrowed depth and carries its phase and stencil properties.
  if target != source:
    raise newException(TargetPlanError, "Shared depth target dimensions differ")
  DepthSharePlan(
    releaseDepth: not targetBorrowsDepth,
    stencil: sourceStencil,
    resolved: sourceResolved
  )
