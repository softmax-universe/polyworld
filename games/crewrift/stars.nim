## Replay-timed stars rendered by the selected graphics backend.

when defined(useDirectX):
  import polyworld/backends/directx/renderer as backendStars
elif defined(useVulkan):
  import polyworld/backends/vulkan/renderer as backendStars
elif defined(useMetal4):
  import backends/metal/stars as backendStars
else:
  import backends/opengl/stars as backendStars

export backendStars
