## Screen-space ambient occlusion using the selected rendering backend.

when defined(useDirectX):
  import backends/directx/renderer as backendScreenOcclusions
elif defined(useVulkan):
  import backends/vulkan/renderer as backendScreenOcclusions
elif defined(useMetal4):
  import backends/metal/screenocclusions as backendScreenOcclusions
else:
  import backends/opengl/screenocclusions as backendScreenOcclusions

export backendScreenOcclusions
