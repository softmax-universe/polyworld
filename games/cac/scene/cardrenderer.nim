## Card surfaces rendered through the selected graphics backend.

when defined(useDirectX):
  import backends/directx/cardrenderer
elif defined(useVulkan):
  import backends/vulkan/cardrenderer
elif defined(useMetal4):
  import backends/metal/cardrenderer
else:
  import backends/opengl/cardrenderer
export cardrenderer
