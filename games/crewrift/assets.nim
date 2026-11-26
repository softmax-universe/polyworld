import
  std/os,
  polyworld/[assets, chargen, common]

const
  CrewLibrary* = DataRoot & "/characters/chargen"
  CrewClips* = ["Idle_Loop", "Walk_Loop", "Interact"]

proc browserAssets*(): seq[Asset] =
  ## Packs the ship, astronaut parts, animation clips, and shared HUD art.
  for path in [DefaultFontPath, BoldFontPath, MonoFontPath]:
    result.add fileAsset(path)
  for path in [MainThemeDir, UiDir, IconDir]:
    result.add Asset(kind: ImageDirectory, source: path.assetName)
  for path in ["LICENSE", "crewrift/license.md",
      "characters/chargen/license.md", "fonts/OFL-Rubik.txt",
      "fonts/OFL-OverpassMono.txt",
      "animations/quaternius/universal_standard/README.txt"]:
    result.add fileAsset(path)
  # Preserve authored matrices and atlas transforms used by loadShipSkin.
  result.add fileAsset("crewrift/crewRift-map1-textured.glb")
  result.add terrainAssets(
    NoTrees,
    GeneratedTerrain,
    NoRocks,
    TerrainAssets(grass: false, water: false, size: 256)
  )
  let
    manifest = readManifest(CrewLibrary)
    inventory = manifest.presetManifest(manifest.namedPreset("Astronaut"))
  for path in ["manifest.json", manifest.skinPalette, manifest.hairPalette,
      manifest.pupilPalette, manifest.hatPalette]:
    result.add fileAsset(CrewLibrary / path)
  for category in manifest.categories:
    for path in walkFiles(CrewLibrary / category.directory / "*.json"):
      result.add fileAsset(path)
  result.add modelAsset(CrewLibrary / manifest.rig)
  for category in inventory.categories:
    for item in category.items:
      for path in item.files:
        result.add modelAsset(CrewLibrary / path, textureSize = 512)
      for path in [item.texture, item.pupilMask]:
        if path.len > 0:
          result.add imageAsset(CrewLibrary / path, 512)
  for clip in manifest.clips:
    if clip.name in CrewClips:
      result.add modelAsset(CrewLibrary / clip.file)
