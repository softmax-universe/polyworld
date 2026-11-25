## Keeps native rendering calls inside their selected implementations.

import std/[os, re, strutils]

const Root = currentSourcePath().parentDir.parentDir

let
  nativeSymbols = re"\b(?:opengl|GL(?:uint|int|enum|sizei|float|double|boolean|bitfield)|GL_[A-Z0-9_]+|gl[A-Z][a-z][a-zA-Z0-9]*)\b"
  metalSymbols = re"\b(?:MTL[A-Z][a-zA-Z0-9]*|CAMetalLayer|metal4)\b"

proc checkBackends(directory: string) =
  ## Checks engine and game production sources, excluding driver fixtures.
  for kind, path in walkDir(directory):
    if kind == pcDir:
      if path.lastPathPart notin ["tests", "tools", "build",
          "tmp", "nimcache", "emscripten"]:
        checkBackends(path)
    elif kind == pcFile and path.endsWith(".nim"):
      var number = 0
      for original in readFile(path).splitLines():
        inc number
        let line = original.split('#')[0].strip()
        if "backends/opengl/" in line:
          continue
        if "/backends/opengl/" notin path:
          doAssert not line.contains(nativeSymbols),
            "Native OpenGL operation outside its backend: " & path &
            ":" & $number & ": " & line
        if "/backends/metal/" notin path:
          doAssert not line.contains(metalSymbols),
            "Native Metal operation outside its backend: " & path &
            ":" & $number & ": " & line

checkBackends(Root / "src" / "polyworld")
checkBackends(Root / "games")
echo "Game and engine graphics use backend boundaries"
