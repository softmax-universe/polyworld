## Retains the Metal entry point for the shared CaC post regression.

when not defined(useMetal4):
  {.error: "Run this GPU fixture with -d:useMetal4.".}
include test_post_render
