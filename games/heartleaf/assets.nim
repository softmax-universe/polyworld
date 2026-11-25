import
  std/os,
  polyworld/[assets, chargen, common],
  appearances, scenery

const LogoPath* = DataRoot & "/themes/heartleaf/heartleaf_logo.png"

proc browserAssets*(): seq[Asset] =
  ## Packs the village, its nine gnomes, and the shared terrain and HUD art.
  result = hudAssets(LogoPath)
  for path in ["LICENSE", "characters/chargen/license.md",
      "fonts/OFL-Rubik.txt", "fonts/OFL-OverpassMono.txt",
      "animations/quaternius/universal_standard/README.txt"]:
    result.add fileAsset(path)
  result.add terrainAssets(
    NoTrees,
    GeneratedTerrain,
    NoRocks,
    TerrainAssets(size: 512, grass: false, water: false),
    ["heartleaf-layer-grass-1", "heartleaf-layer-path-2",
      "heartleaf-layer-paving-1"]
  )
  for path in TreegenTextures:
    result.add fileAsset(path)
  result.add fileAsset(RockgenTexture)
  result.add fileAsset(TreegenFlowerTexture)
  result.add fileAsset("terrain/heartleaf/layers/01-grass-and-paths.png")
  for path in [CottagePath, DetailsPath, GardenPartsPath, GardenLayoutPath]:
    result.add fileAsset(path)
  for name in VillageModels:
    result.add fileAsset(VillageRoot & name & ".glb")
  let manifest = readManifest(GnomeLibrary)
  for path in ["manifest.json", manifest.rig, manifest.skinPalette,
      manifest.hairPalette, manifest.pupilPalette, manifest.hatPalette]:
    result.add fileAsset(GnomeLibrary / path)
  for category in manifest.categories:
    for path in walkFiles(GnomeLibrary / category.directory / "*.json"):
      result.add fileAsset(path)
  for name in GnomePresets:
    let inventory = manifest.presetManifest(manifest.namedPreset(name))
    for category in inventory.categories:
      for item in category.items:
        for path in item.files:
          result.add fileAsset(GnomeLibrary / path)
        for path in [item.texture, item.pupilMask]:
          if path.len > 0:
            result.add fileAsset(GnomeLibrary / path)
  for clip in manifest.clips:
    if clip.name in GnomeClips:
      result.add fileAsset(GnomeLibrary / clip.file)
