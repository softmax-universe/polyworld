## Releases model buffers through the selected graphics backend.

import gltf

when defined(useMetal4):
  import backends/metal/meshes

proc clearModelGpu*(primitive: Primitive) =
  ## Invalidates one primitive after CPU geometry or material replacement.
  if primitive == nil:
    return
  when defined(useMetal4):
    modelMeshCache.release(primitive)
    modelMeshCache.release(primitive.material)
  else:
    primitive.clearFromGpu()

proc clearModelGpu*(node: Node) =
  ## Releases GPU resources associated with every primitive under a node.
  if node == nil:
    return
  for child in node.walkNodes:
    if child.mesh != nil:
      for primitive in child.mesh.primitives:
        primitive.clearModelGpu()
