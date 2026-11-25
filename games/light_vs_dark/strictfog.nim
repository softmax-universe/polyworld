## Final current-sight clipping using the selected graphics backend.

when defined(useDirectX) or defined(useVulkan) or defined(useMetal4):
  import backends/passes/strictfog as backendStrictFog
else:
  import backends/opengl/strictfog as backendStrictFog

export backendStrictFog
