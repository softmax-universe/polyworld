## Selection and occlusion outlines using the selected rendering backend.

when defined(useDirectX):
  import backends/directx/renderer as backendSelectionOutlines
elif defined(useVulkan):
  import backends/vulkan/renderer as backendSelectionOutlines
elif defined(useMetal4):
  import backends/metal/selectionoutlines as backendSelectionOutlines
else:
  import backends/opengl/selectionoutlines as backendSelectionOutlines

export backendSelectionOutlines
