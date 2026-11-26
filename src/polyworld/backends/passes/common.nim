when defined(useMetal4):
  import ../metal/passapi
  export passapi
else:
  import ../native/common
  export common

  proc setPassSampling*(image: GpuImage, linear = true, repeat = false,
      comparison = false) =
    ## Sets scene-pass filtering; native shader bindings select comparison.
    image.setTextureSampling(linear = linear, repeat = repeat)
