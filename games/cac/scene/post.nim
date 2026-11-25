## Selects the CaC post renderer at compile time.

when defined(useDirectX) or defined(useVulkan):
  import backends/native/post
elif defined(useMetal4):
  import backends/metal/post
else:
  import backends/opengl/post

export post
