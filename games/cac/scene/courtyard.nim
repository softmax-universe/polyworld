## Shared courtyard geometry and the selected renderer.

import courtyardgeometry
export courtyardgeometry

when not defined(headless):
  import backends/passes/courtyard
  export courtyard
