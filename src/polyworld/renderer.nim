## Selects the graphics backend behind shared frame and UI operations.

when defined(useDirectX) or defined(useVulkan):
  import backends/native/renderer
elif defined(useMetal4):
  import backends/metal/renderer
else:
  import backends/opengl/renderer

export renderer

when not (defined(useDirectX) or defined(useVulkan)):
  import silky, vmath, windy
  proc beginGameUi*(sk: Silky, window: Window, size: IVec2) =
    sk.beginUi(window, size)
