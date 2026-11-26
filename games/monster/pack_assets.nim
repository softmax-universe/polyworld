import
  std/os,
  polyworld/[assets, chargen],
  ../../tools/assetpacks,
  ../light_vs_dark/assets as lvdassets

proc browserAssets(): seq[Asset] =
  ## Selects the village's terrain, models, portraits, and shared HUD art.
  for path in [DefaultFontPath, BoldFontPath, MonoFontPath]:
    result.add fileAsset(path)
  for path in [MainThemeDir, UiDir, IconDir]:
    result.add Asset(kind: ImageDirectory, source: path.assetName)
  result.add terrainAssets(
    NoTrees, GeneratedTerrain, NoRocks,
    TerrainAssets(grass: false, water: true, size: 512)
  )
  for path in TreegenTextures:
    result.add imageAsset(path, GeneratorTextureSize)
  result.add imageAsset(TreegenFlowerTexture, GeneratorTextureSize)
  result.add imageAsset(RockgenTexture, GeneratorTextureSize)
  for name in ["town_hall", "farm", "blacksmith"]:
    result.add modelAsset(
      "terrain/lvd_buildings/models/" & name & ".glb", textureSize = 512
    )
  for path in [
    "characters/chargen/portraits/lvd/0_0.png",
    "terrain/lvd_buildings/portraits/blacksmith.png",
    "terrain/lvd_buildings/portraits/town_hall.png",
    "LICENSE", "fonts/OFL-Rubik.txt", "fonts/OFL-OverpassMono.txt",
    "terrain/lvd_buildings/license.md",
    "animations/quaternius/universal_standard/README.txt"
  ]:
    result.add fileAsset(path)
  result.add generatedCharacterAssets()
  let manifest = readManifest(ChargenLibrary)
  for name in ["Punch_Jab", "Hit_Chest", "Sprint_Loop", "Sitting_Idle_Loop",
      "Walk_Loop", "Fixing_Kneeling", "Idle_Talking_Loop"]:
    var found = false
    for clip in manifest.clips:
      if clip.name == name:
        result.add modelAsset("characters/chargen" / clip.file)
        found = true
    if not found:
      raise newException(AssetError, "Missing Monster animation: " & name)

proc main() =
  ## Packs browser assets and the repository-owned woodland HUD separately.
  if paramCount() != 2:
    raise newException(AssetError, "Usage: pack_assets <data> <output>")
  discard packAssets(browserAssets(), paramStr(1), paramStr(2))
  let hud = paramStr(2) / "hud"
  createDir(hud)
  for name in ["woodland-frame.png", "moss-portrait.png", "resource-icons.png"]:
    copyFile(currentSourcePath().parentDir / "assets" / "hud" / name,
      hud / name)

main()
