## Runs the shared water pixel contract on Metal.

when not defined(useMetal4):
  {.error: "Compile this rendering test with -d:useMetal4.".}

include fixtures/waterbody
