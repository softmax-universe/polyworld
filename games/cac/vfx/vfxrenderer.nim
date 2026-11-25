## Material sprites and forged weapons with a selected rendering backend.

when defined(useDirectX):
  import backends/directx/vfxrenderer as backendVfxRenderer
elif defined(useVulkan):
  import backends/vulkan/vfxrenderer as backendVfxRenderer
elif defined(useMetal4):
  import backends/metal/vfxrenderer as backendVfxRenderer
else:
  import backends/opengl/vfxrenderer as backendVfxRenderer

export backendVfxRenderer
