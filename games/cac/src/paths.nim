import
  std/os,
  polyworld/common

when not defined(emscripten):
  # This file is in games/cac/src: the repository is three folders up.
  const SourceRepo = currentSourcePath().parentDir.parentDir.parentDir.parentDir

proc artworkRoot*(): string =
  ## Locate CaC artwork in the shared Polyworld data folder.
  when defined(emscripten):
    DataRoot / "cac"
  else:
    let repo = absolutePath(getEnv("POLYWORLD_REPO", SourceRepo))
    absolutePath(DataRoot, repo) / "cac"

proc menuArtworkRoot*(): string =
  ## Finds the menu art bundled with CaC on desktop and in the browser pack.
  when defined(emscripten):
    DataRoot / "cac/ui/menu"
  else:
    const SourceMenu =
      currentSourcePath().parentDir.parentDir / "assets/menu"
    let bundled = getAppDir() / "assets/menu"
    if fileExists(bundled / "button-primary.png"): bundled else: SourceMenu
