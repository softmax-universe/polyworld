## Procedural effects with shared geometry and a selected GPU backend.

import fxmeshdata

when defined(useDirectX) or defined(useVulkan) or defined(useMetal4):
  import backends/passes/fxmeshes as backendFxMeshes
else:
  import backends/opengl/fxmeshes as backendFxMeshes

export fxmeshdata, backendFxMeshes
