## Toon rendering selected for the application graphics backend.

import tooncommon

when defined(useDirectX) or defined(useVulkan) or defined(useMetal4):
  import backends/passes/toon as backendToon
else:
  import backends/opengl/toon as backendToon

export tooncommon, backendToon
