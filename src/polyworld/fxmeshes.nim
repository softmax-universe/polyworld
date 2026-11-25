## Procedural effects with shared geometry and a selected GPU backend.

import fxmeshdata

when defined(useDirectX):
  import backends/directx/fxmeshes as backendFxMeshes
elif defined(useVulkan):
  import backends/vulkan/fxmeshes as backendFxMeshes
elif defined(useMetal4):
  import backends/metal/fxmeshes as backendFxMeshes
else:
  import backends/opengl/fxmeshes as backendFxMeshes

export fxmeshdata, backendFxMeshes
