## Keeps shader authoring in Shady, including render regression fixtures.

import std/[os, strutils]

const
  Root = currentSourcePath().parentDir.parentDir
  SourceDirectories = ["src", "games", "experiments", "tests", "tools"]
  GeneratedDirectories = ["build", "tmp", "nimcache", "emscripten"]
  ShaderExtensions = [".glsl", ".vert", ".frag", ".geom", ".tesc",
    ".tese", ".comp"]

proc checkShaderSources(directory: string) =
  ## Rejects handwritten shaders while excluding generated build products.
  for kind, path in walkDir(directory):
    if kind == pcDir:
      if path.lastPathPart notin GeneratedDirectories:
        checkShaderSources(path)
    elif kind == pcFile:
      let extension = path.splitFile.ext
      doAssert extension notin ShaderExtensions,
        "Use a Shady procedure instead of " & path
      if extension in [".nim", ".nims"] and path != currentSourcePath():
        let source = readFile(path)
        for marker in ["#version", "void main(", "void main (",
            "precision highp", "precision mediump"]:
          doAssert marker notin source,
            "Handwritten GLSL in " & path & ": " & marker

for directory in SourceDirectories:
  checkShaderSources(Root / directory)
echo "All shader sources are authored in Shady"
