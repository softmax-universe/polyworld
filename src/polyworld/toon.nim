## Toon rendering selected for the application graphics backend.

import tooncommon

when defined(useDirectX):
  {.error: "The DirectX toon backend is not implemented.".}
elif defined(useVulkan):
  {.error: "The Vulkan toon backend is not implemented.".}
elif defined(useMetal4):
  import backends/metal/toon as backendToon
else:
  import backends/opengl/toon as backendToon

export tooncommon, backendToon
