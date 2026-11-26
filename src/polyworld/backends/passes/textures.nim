when defined(useMetal4):
  import ../metal/textures
elif defined(useDirectX) or defined(useVulkan):
  import ../native/textures
else:
  import ../opengl/passtextures as textures
export textures
