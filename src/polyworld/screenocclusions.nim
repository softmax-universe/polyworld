## Screen-space ambient occlusion using the selected rendering backend.

when defined(useDirectX) or defined(useVulkan) or defined(useMetal4):
  import backends/passes/screenocclusions as backendScreenOcclusions
else:
  import backends/opengl/screenocclusions as backendScreenOcclusions

export backendScreenOcclusions
