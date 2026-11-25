## Selection and occlusion outlines using the selected rendering backend.

when defined(useDirectX) or defined(useVulkan) or defined(useMetal4):
  import backends/passes/selectionoutlines as backendSelectionOutlines
else:
  import backends/opengl/selectionoutlines as backendSelectionOutlines

export backendSelectionOutlines
