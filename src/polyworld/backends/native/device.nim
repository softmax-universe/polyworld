when not defined(windows):
  {.error: "Polyworld DirectX 12 and Vulkan currently require Windows.".}

when defined(useDirectX):
  import ../directx/gpu
else:
  import ../vulkan/gpu
export gpu
