## Retains the Metal entry point for the shared effects regression.

when not defined(useMetal4):
  {.error: "Run this GPU fixture with -d:useMetal4.".}
include test_effects_render
