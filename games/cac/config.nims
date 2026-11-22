import std/os
import "../../src/polyworld/emscripten.nims"

setupEmscripten(
  thisDir(),
  "cac",
  output = getEnv("CAC_WEB_DIR"),
  shell = thisDir() / "web" / "shell.html",
  preJsFiles = @[thisDir() / "web" / "inputs.js"],
  preloadMounts = @[(path: "players", mount: "/players")],
  loadingLogo = "loading-logo.svg",
  logoWidth = 560,
  logoHeight = 350,
  minimumWebglVersion = 2,
  linkOptions = "-s STACK_SIZE=8388608 -s INITIAL_MEMORY=134217728"
)

when defined(emscripten) and not defined(headless):
  switch("passL", "-s EXPORTED_FUNCTIONS=" &
    "_main,_malloc,_free,_windy_websocket_open_callback," &
    "_windy_websocket_message_callback,_windy_websocket_error_callback," &
    "_windy_websocket_close_callback")
