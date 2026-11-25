import "../../src/polyworld/emscripten.nims"

setupEmscripten(
  thisDir(),
  "heartleaf",
  preloadMounts = @[(path: "players", mount: "/players")],
  minimumWebglVersion = 2
)
