import
  std/os,
  ../assets

block abilityIcons:
  let directory = getTempDir() /
    ("polyworld-cta-icon-test-" & $getCurrentProcessId())
  createDir(directory)
  defer: removeDir(directory)
  for (name, fallback) in [
    ("cta_icicle", "ice_spear"), ("cta_glacier", "ice_wall"),
    ("cta_lightning", "lightning_storm"), ("cta_blizzard", "frost_sigil")
  ]:
    let
      intended = directory / (name & ".png")
      shared = directory / (fallback & ".png")
    writeFile(shared, "shared")
    doAssert abilityIconPath(name, directory) == shared
    writeFile(intended, "intended")
    doAssert abilityIconPath(name, directory) == intended
  doAssert abilityIconPath("sword_attack", directory) ==
    directory / "sword_attack.png"

echo "CTA ability icon selection passed"
