## Selects the CaC post renderer at compile time.

when defined(useDirectX):
  import backends/directx/post
elif defined(useVulkan):
  import backends/vulkan/post
elif defined(useMetal4):
  import backends/metal/post
else:
  import backends/opengl/post

export post
