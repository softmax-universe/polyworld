## Native check of browser asset declarations for the woodcutting variant.
import
  std/os,
  polyworld/[assets, chargen, common],
  ../assets

let manifest = readManifest(ChargenLibrary)
var found = false
for category in manifest.categories:
  if category.key == "Right hand":
    for item in category.items:
      if item.name == "Berserker axe":
        doAssert item.attachmentBone == "RightHand"
        for file in item.files:
          var declared = false
          for asset in generatedCharacterAssets():
            if asset.kind == ModelAsset and
                asset.source == assetName(DataRoot / "characters/chargen" / file):
              declared = true
          doAssert declared, "missing browser model asset: " & file
          doAssert fileExists(ChargenLibrary / file)
        found = true
doAssert found
echo "wood axe browser assets declared"
