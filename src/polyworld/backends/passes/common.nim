when defined(useMetal4):
  import ../metal/passapi
  export passapi
elif defined(useDirectX) or defined(useVulkan):
  import ../native/common
  export common

  proc setPassSampling*(image: GpuImage, linear = true, repeat = false,
      comparison = false) =
    ## Sets scene-pass filtering; native shader bindings select comparison.
    image.setTextureSampling(linear = linear, repeat = repeat)

else:
  import ../opengl/passapi
  export passapi

when defined(useMetal4) or defined(useDirectX) or defined(useVulkan):
  proc newIndexBuffer*[T](values: openArray[T]): VertexBuffer =
    ## Allocates index storage on backends without OpenGL binding roles.
    newBuffer(values)

  template preserveDrawState*(body: untyped) =
    ## Executes a pass whose explicit backend state is already local.
    body

const PassTopLeftOrigin* =
  defined(useMetal4) or defined(useDirectX) or defined(useVulkan)
