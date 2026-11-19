import
  std/os,
  polyworld/assets,
  scene/heroes, tools/stage_card_art

const GameDir = currentSourcePath().parentDir

proc stageFile(source, destination: string) =
  ## Copies one asset and creates its destination directory.
  createDir(destination.parentDir)
  copyFile(source, destination)

proc stageFiles(source, destination, pattern: string) =
  ## Copies the matching assets while preserving their filenames.
  var found = false
  for path in walkFiles(source / pattern):
    stageFile(path, destination / path.extractFilename)
    found = true
  if not found:
    raise newException(AssetError, "No browser assets match " & source / pattern)

proc main() =
  ## Stages CaC's browser art, policies and loading page assets.
  if paramCount() != 2:
    raise newException(AssetError, "Usage: pack_assets <data> <output>")
  let
    data = absolutePath(paramStr(1))
    output = absolutePath(paramStr(2))
    stage = output / "stage"
    players = output / "players"
    public = output / "public"
    loading = public / "loading"
    chargen = "characters/chargen"
  for directory in [stage, players, public]:
    if dirExists(directory):
      removeDir(directory)
    createDir(directory)

  # Loading page assets are available before the Wasm preload finishes.
  stageFiles(GameDir / "web/loading", loading, "*.svg")
  stageFile(data / "cac/loading/moonlit-table.webp",
    loading / "moonlit-table.webp")
  for name in ["Grenze-SemiBold.ttf", "OFL.txt"]:
    stageFile(data / "cac/cards/fonts" / name, loading / name)
  stageFiles(data / "cac/ui/hud", loading, "class-*.svg")
  stageFile(GameDir / "web/loading/cnc-wordmark.svg",
    output / "loading-logo.svg")

  # The game loads the same hero parts, cropped card art and menu assets.
  stageFile(data / "cac/loading/source/moonlit-table.png",
    stage / "cac/loading/source/moonlit-table.png")
  for path in heroAssetFiles(data / chargen):
    stageFile(data / chargen / path, stage / chargen / path)
  for name in ["Rubik-Regular.ttf", "Rubik-Bold.ttf"]:
    stageFile(data / "fonts" / name, stage / "fonts" / name)
  for directory in [
    "themes/main", "sounds", "ui", "cac/cards/fonts", "cac/cards/frames",
    "cac/cards/icons", "cac/vfx/textures", "cac/ui/hud",
    "cac/battlefield/textures"
  ]:
    copyDir(data / directory, stage / directory)
  for name in ["tavern-dance.ogg", "tavern-dance.json"]:
    stageFile(data / "music/cac" / name, stage / "music/cac" / name)
  stageFiles(data / "icons", stage / "icons", "*.png")
  stageFiles(GameDir / "assets/menu", stage / "cac/ui/menu", "button-*.png")
  discard stageCardArt(data / "cac/cards/art", stage / "cac/cards/art")
  stageFiles(GameDir / "players", players, "*.bas")

main()
