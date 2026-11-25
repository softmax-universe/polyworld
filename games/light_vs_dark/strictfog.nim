## Final current-sight clipping using the selected graphics backend.

when defined(useDirectX):
  import polyworld/backends/directx/renderer as backendStrictFog
elif defined(useVulkan):
  import polyworld/backends/vulkan/renderer as backendStrictFog
elif defined(useMetal4):
  import backends/metal/strictfog as backendStrictFog
else:
  import backends/opengl/strictfog as backendStrictFog

export backendStrictFog
