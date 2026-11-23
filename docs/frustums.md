# Checking object bounds before drawing

Call `worldBounds.inFrustum(projection * view)` with the same matrices used
for the current draw pass. A tree or building can skip that pass when the
query returns `false`. A box touching or crossing the screen edge stays
eligible to draw, even if its center is offscreen.

```nim
import gltf, vmath
import polyworld/frustums

proc eligibleToDraw(localBounds: AABounds, model, view, projection: Mat4): bool =
  let worldBounds = localBounds.transformed(model)
  worldBounds.inFrustum(projection * view)
```

If the bounds are already in world space, pass them directly. Use bounds that
enclose the current pose, including any animation. Update the view matrix as
the camera moves. For a shadow pass, use the light's view-projection matrix.

The query works with perspective and orthographic projections. It rejects an
empty box or a box whose eight corners all lie beyond the same clip plane.
A `true` result is conservative because the object may still be occluded or
cover no pixels.
