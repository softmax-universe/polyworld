import polyworld/targetplans

for samples in [1, 2, 4, 8]:
  for color in [false, true]:
    for depth in [false, true]:
      for stencil in [false, true]:
        let plan = planRenderTarget(17, 9, samples, color, depth,
          stencil, mipmapped = true)
        doAssert plan.extent == targetExtent(17, 9, samples)
        doAssert plan.color == color and plan.depth == depth
        doAssert plan.stencil == (stencil and depth)
        doAssert plan.multisampleColor == (color and samples > 1)
        doAssert plan.multisampleDepth == (depth and samples > 1)
        doAssert plan.colorMipLevels == (if color: 5 else: 1)

doAssert planRenderTarget(1, 1, 1, mipmapped = true).colorMipLevels == 1
doAssert planRenderTarget(8, 32, 1, mipmapped = true).colorMipLevels == 6
doAssert planRenderTarget(8, 32, 1).colorMipLevels == 1

for extent in [targetExtent(0, 10, 1), targetExtent(10, -1, 1),
    targetExtent(10, 10, 0), targetExtent(int.high, 2, 1),
    targetExtent(int.high div 2, 1, 4)]:
  var rejected = false
  try:
    discard planRenderTarget(extent.width, extent.height, extent.samples)
  except TargetPlanError:
    rejected = true
  doAssert rejected, "Invalid target extent was accepted"

let extent = targetExtent(64, 32, 4)
doAssert not needsTargetResize(extent, targetExtent(64, 32, 4))
for changed in [targetExtent(32, 32, 4), targetExtent(64, 64, 4),
    targetExtent(64, 32, 1)]:
  doAssert needsTargetResize(extent, changed)
  var rejected = false
  try:
    discard planDepthShare(extent, changed, false, true, false)
  except TargetPlanError:
    rejected = true
  doAssert rejected, "Incompatible depth storage was accepted"

for borrowed in [false, true]:
  for stencil in [false, true]:
    for resolved in [false, true]:
      let shared = planDepthShare(extent, extent, borrowed, stencil, resolved)
      doAssert shared.releaseDepth == not borrowed
      doAssert shared.stencil == stencil and shared.resolved == resolved
      doAssert renderSampleCount(4, shared.resolved) ==
        (if resolved: 1 else: 4)

doAssert renderSampleCount(1, false) == 1
doAssert renderSampleCount(1, true) == 1
doAssert not resolvedAfterClear(false, true, false)
doAssert resolvedAfterClear(true, true, false)
doAssert not resolvedAfterClear(true, true, true)
doAssert not resolvedAfterClear(true, false, false)

echo "Render target allocation, resize, depth sharing and phase plans passed"
