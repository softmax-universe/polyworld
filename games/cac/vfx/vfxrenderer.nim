## Material sprites and forged weapons with a selected rendering backend.

when defined(useDirectX) or defined(useVulkan) or defined(useMetal4):
  import backends/passes/vfxrenderer as backendVfxRenderer
else:
  import backends/opengl/vfxrenderer as backendVfxRenderer

export backendVfxRenderer
