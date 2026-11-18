import
  std/[monotimes, os],
  windy,
  polyworld/menus

proc testGraphicsPreferences() =
  ## Checks graphics defaults and saved choices in isolated configuration.
  let
    app = "Polyworld graphics preferences test " & $getCurrentProcessId() &
      "-" & $getMonoTime().ticks
    directory = getConfigHome(app)
  doAssert not dirExists(directory)
  defer:
    if dirExists(directory):
      removeDir(directory)

  echo "Testing ambient occlusion defaults on for fresh settings"
  doAssert readPreferences(app).ambientOcclusion

  echo "Testing older settings gain AO without replacing existing choices"
  setConfig(app, "settings.json",
    """{"musicVolume":0,"interpolation":false,"fps":120}""")
  let previous = readPreferences(app)
  doAssert previous.ambientOcclusion
  doAssert previous.musicVolume == 0
  doAssert not previous.interpolation
  doAssert previous.fps == 120

  echo "Testing AO on and off persist across reloads"
  for enabled in [false, true, false]:
    var preferences = previous
    preferences.ambientOcclusion = enabled
    preferences.savePreferences(app)
    let loaded = readPreferences(app)
    doAssert loaded.ambientOcclusion == enabled
    doAssert loaded.musicVolume == 0
    doAssert not loaded.interpolation
    doAssert loaded.fps == 120

testGraphicsPreferences()
