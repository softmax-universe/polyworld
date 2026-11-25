## Shared courtyard geometry and the selected renderer.

import courtyardgeometry
export courtyardgeometry

when not defined(headless):
  when defined(useDirectX) or defined(useVulkan) or defined(useMetal4):
    import backends/passes/courtyard
  else:
    import backends/opengl/courtyard
  export courtyard
