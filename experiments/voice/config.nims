import std/[os, strutils]

switch("opt", "speed")

when defined(emscripten):
  let
    experiment = thisDir()
    output = experiment / "emscripten"
    dependencies = getEnv("POLYWORLD_DEPS", experiment / "../../..")
    captureCheckout = dependencies / "slappy-wasm-microphone/src"
  if getEnv("SLAPPY_PATH").len == 0 and
    fileExists(captureCheckout / "slappy/browsermicrophones.nim"):
      switch("path", captureCheckout)
  mkDir(output)
  switch("nimcache", output / "tmp")
  switch("out", output / "voice.html")
  switch("threads", "off")
  switch("os", "linux")
  switch("cpu", "wasm32")
  switch("cc", "clang")
  when defined(windows):
    switch("clang.exe", "emcc.bat")
    switch("clang.linkerexe", "emcc.bat")
  else:
    switch("clang.exe", "emcc")
    switch("clang.linkerexe", "emcc")
  switch("mm", "orc")
  switch("exceptions", "goto")
  switch("define", "noSignalHandler")
  switch("define", "noAutoGLerrorCheck")
  switch("define", "flatty64")
  switch("passL", "-O3 -sASYNCIFY -sFETCH -sEXIT_RUNTIME=0 " &
    "-sUSE_WEBGL2=1 -sMAX_WEBGL_VERSION=2 -sMIN_WEBGL_VERSION=1 " &
    "-sFULL_ES3=1 -sGL_ENABLE_GET_PROC_ADDRESS=1 " &
    "-sALLOW_MEMORY_GROWTH -lopenal")
  switch("passL", "--preload-file " &
    quoteShell(experiment / "assets" & "@/voice-assets"))
  switch("passL", "--shell-file " & quoteShell(experiment / "web.html"))
  switch("passL", "-sEXPORTED_FUNCTIONS=_main,_malloc,_free," &
    "_voiceBrowserAction,_voiceBrowserText,_voiceBrowserState")
  switch("passL", "-sEXPORTED_RUNTIME_METHODS=ccall,UTF8ToString")
  if paramStr(1) in ["run", "r"]:
    setCommand("c")
    echo "Serve this build with nim r experiments/voice/serve.nim"
else:
  switch("define", "ssl")
