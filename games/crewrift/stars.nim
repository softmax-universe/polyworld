## Replay-timed stars rendered by the selected graphics backend.

when defined(useDirectX) or defined(useVulkan) or defined(useMetal4):
  import backends/passes/stars as backendStars
else:
  import backends/opengl/stars as backendStars

export backendStars
