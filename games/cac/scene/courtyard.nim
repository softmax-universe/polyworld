## Shared courtyard geometry and the selected renderer.

import courtyardgeometry
export courtyardgeometry

when not defined(headless):
  when defined(useDirectX):
    import backends/directx/courtyard
  elif defined(useVulkan):
    import backends/vulkan/courtyard
  elif defined(useMetal4):
    import backends/metal/courtyard
  else:
    import backends/opengl/courtyard
  export courtyard
