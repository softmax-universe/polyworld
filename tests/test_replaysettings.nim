import
  std/[monotimes, os, strutils],
  windy,
  polyworld/[menus, replaysettings]

proc testReplayPreferences() =
  ## Exercises shared recording preferences without touching any game's config.
  let
    app = "Polyworld replay preferences test " & $getCurrentProcessId() &
      "-" & $getMonoTime().ticks
    directory = getConfigHome(app)
    otherSettings = """{"name":"Keep me","musicVolume":0}"""
  doAssert not dirExists(directory)
  defer:
    if dirExists(directory):
      removeDir(directory)

  echo "Testing replay recording defaults on and missing settings remain absent"
  doAssert readReplayPreferences(app).saveReplay
  doAssert not dirExists(directory)
  doAssert decodeReplayPreferences("").saveReplay
  doAssert decodeReplayPreferences("{}").saveReplay
  doAssert decodeReplayPreferences("""{"futureSetting":17}""").saveReplay

  echo "Testing replay choices persist separately from other device settings"
  setConfig(app, "settings.json", otherSettings)
  for enabled in [false, true, false]:
    ReplayPreferences(saveReplay: enabled).saveReplayPreferences(app)
    doAssert readReplayPreferences(app).saveReplay == enabled
    doAssert getConfig(app, "settings.json") == otherSettings

  echo "Testing invalid replay preferences report an error without replacement"
  for malformed in ["{", """{"saveReplay":"yes"}"""]:
    setConfig(app, "replays.json", malformed)
    var rejected = false
    try:
      discard readReplayPreferences(app)
    except MenusError as error:
      rejected = error.msg.startsWith("Cannot read replay settings:")
    doAssert rejected
    doAssert getConfig(app, "replays.json") == malformed
    doAssert getConfig(app, "settings.json") == otherSettings

testReplayPreferences()
echo "Shared replay preference checks passed."
