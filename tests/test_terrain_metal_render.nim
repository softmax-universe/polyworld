## Runs the shared terrain rendering contract through Metal.

when not defined(useMetal4):
  {.error: "Run this rendering regression with -d:useMetal4.".}

include test_shared_terrain_render
