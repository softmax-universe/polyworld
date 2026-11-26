## Shared Emscripten compile recipe for Polyworld games.

import
  std/[hashes, os, strformat, strutils]

proc setupEmscripten*(
  gameDir: string,
  game = "",
  output = "",
  shell = "",
  preJsFiles: seq[string] = @[],
  preloadMounts: seq[tuple[path, mount: string]] = @[],
  loadingLogo = "loading-logo.png",
  logoWidth = 320,
  logoHeight = 240,
  minimumWebglVersion = 2,
  linkOptions = ""
) =
  ## Configures the wasm backend and writes the bundle next to the game.
  ## Packers write art to stage/, browser files to public/, and additional
  ## preload roots below their cache directory.
  when defined(emscripten):
    let
      repoDir = gameDir / ".." / ".."
      dataDir = getEnv("POLYWORLD_ART", repoDir / ".." / "polyworld_art")
      outputDir =
        if output.len > 0: absolutePath(output)
        elif getEnv("POLYWORLD_WEB_DIR").len > 0:
          absolutePath(getEnv("POLYWORLD_WEB_DIR"))
        else: gameDir / "emscripten"
      shellTemplate =
        if defined(replayViewer):
          repoDir / "src" / "polyworld" / "replay.html"
        elif shell.len > 0:
          shell
        else:
          repoDir / "src" / "polyworld" / "emscripten.html"
      shellFile = outputDir / "shell.html"
    var preJs = ""
    when not defined(replayViewer):
      preJs = "--pre-js " & quoteShell(
        repoDir / "src" / "polyworld" / "webinputs.js")
      for path in preJsFiles:
        preJs.add " --pre-js " & quoteShell(path)
    var preload = "--preload-file " & quoteShell(dataDir & "@/polyworld_art")
    var logo = ""
    if not dirExists(outputDir):
      mkDir(outputDir)
    if game.len > 0:
      let
        variant = if defined(webPng): "png" else: "ktx2"
        cache = repoDir / "tmp" / "webassets" / (game & "-" & variant)
        packer = cache / "pack_assets".addFileExt(ExeExt)
        options = if defined(webPng): " -d:webPng" else: ""
      if not dirExists(cache):
        mkDir(cache)
      exec quoteShell(getCurrentCompilerExe()) & " c --hints:off" & options &
        " --nimcache:" & quoteShell(cache / "nimcache") &
        " -o:" & quoteShell(packer) & " " &
        quoteShell(gameDir / "pack_assets.nim")
      exec quoteShell(packer) & " " & quoteShell(dataDir) &
        " " & quoteShell(cache)
      if dirExists(cache / "public"):
        cpDir(cache / "public", outputDir)
      if loadingLogo.len > 0:
        let
          logoFile = outputDir / loadingLogo
          logoData = readFile(cache / loadingLogo)
        if not fileExists(logoFile) or readFile(logoFile) != logoData:
          writeFile(logoFile, logoData)
        logo = "<img id=\"loading-logo\" alt=\"Game logo\" " &
          "width=\"" & $logoWidth & "\" height=\"" & $logoHeight &
          "\" src=\"" & loadingLogo & "?v=" &
          $hash(logoData) & "\" " &
          "fetchpriority=\"high\">"
      preload = "--preload-file " & quoteShell(cache / "stage" & "@/polyworld_art")
      for asset in preloadMounts:
        preload.add " --preload-file " & quoteShell(
          cache / asset.path & "@" & asset.mount)
    if game in ["gota", "lvd"]:
      let bots =
        if game == "gota":
          @["base", "rusher", "puller", "jev", "khors", "lane_sustain",
            "red-kite", "black-kite", "cogas"]
        else:
          @["base"]
      for bot in bots:
        preload.add " --preload-file " & quoteShell(
          gameDir / "players" / (bot & ".bas") &
          "@/policies/" & game & "/" & bot & ".bas")
      switch("passL", "-s EXPORTED_FUNCTIONS=" &
        "_main,_malloc,_free,_windy_websocket_open_callback," &
        "_windy_websocket_message_callback,_windy_websocket_error_callback," &
        "_windy_websocket_close_callback")
    let shellData = readFile(shellTemplate).replace("<!-- GAME_LOGO -->", logo)
    if not fileExists(shellFile) or readFile(shellFile) != shellData:
      writeFile(shellFile, shellData)
    switch("nimcache", outputDir / "tmp")
    switch("threads", "off")
    --os:linux
    --cpu:wasm32
    --cc:clang
    let emcc =
      when defined(windows):
        if findExe("emcc.exe").len > 0: "emcc.exe" else: "emcc.bat"
      else:
        "emcc"
    for option in ["clang.exe", "clang.linkerexe", "clang.cpp.exe", "clang.cpp.linkerexe"]:
      switch(option, emcc)
    --gc:arc
    --exceptions:goto
    --define:noSignalHandler
    --debugger:native
    --define:noAutoGLerrorCheck
    --define:flatty64
    when not defined(debug):
      --define:release
      # Release -O3 only reaches the compile step. emcc also needs it at link
      # time, or Binaryen leaves the wasm and Asyncify unoptimized.
      switch("passL", "-O3")
    switch(
      "passL",
      (&"""
      -o {quoteShell(outputDir / (projectName() & ".html"))}
      {preload}
      {preJs}
      --shell-file {quoteShell(shellFile)}
      -s ASYNCIFY
      -s FETCH
      -s EXIT_RUNTIME=1
      -s USE_WEBGL2=1
      -s MAX_WEBGL_VERSION=2
      -s MIN_WEBGL_VERSION={minimumWebglVersion}
      -s FULL_ES3=1
      -s GL_ENABLE_GET_PROC_ADDRESS=1
      -s ALLOW_MEMORY_GROWTH
      --profiling
      {linkOptions}
      """).replace("\n", " ")
    )
    if paramStr(1) == "run" or paramStr(1) == "r":
      setCommand("c")
      echo "To run the Emscripten build, use:"
      echo "emrun " & outputDir / (projectName() & ".html")
