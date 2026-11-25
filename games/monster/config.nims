import "../../src/polyworld/emscripten.nims"

setupEmscripten(
  thisDir(),
  "monster",
  loadingLogo = "",
  preloadMounts = @[(path: "hud", mount: "/monster-hud")],
  minimumWebglVersion = 2,
  linkOptions = "-lopenal -s STACK_SIZE=8388608 -s INITIAL_MEMORY=134217728"
)

when not defined(emscripten):
  switch("define", "ssl")
