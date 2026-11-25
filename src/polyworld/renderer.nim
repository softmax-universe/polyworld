## Selects the graphics backend behind shared frame and UI operations.

when defined(useDirectX):
  import backends/directx/renderer
elif defined(useVulkan):
  import backends/vulkan/renderer
elif defined(useMetal4):
  import backends/metal/renderer
else:
  import backends/opengl/renderer

export renderer
