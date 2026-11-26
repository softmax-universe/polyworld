## Releases model buffers through the selected graphics backend.

import gltf
import backends/passes/meshes

proc clearModelGpu*(primitive: Primitive) =
  ## Invalidates one primitive after CPU geometry or material replacement.
  if primitive == nil:
    return
  modelMeshCache.release(primitive)
  modelMeshCache.release(primitive.material)
  when not (defined(useMetal4) or defined(useDirectX) or defined(useVulkan)):
    # The glTF PBR renderer owns separate resources from the shared toon pass.
    primitive.clearFromGpu()

proc clearModelGpu*(node: Node) =
  ## Releases GPU resources associated with every primitive under a node.
  if node == nil:
    return
  for child in node.walkNodes:
    if child.mesh != nil:
      for primitive in child.mesh.primitives:
        primitive.clearModelGpu()
