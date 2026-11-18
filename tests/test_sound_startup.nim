import
  std/[monotimes, os, strutils],
  jsony, windy,
  polyworld/[menus, sounds]

when not defined(audioTest):
  {.error: "Run this preference check with -d:audioTest.".}

proc checkVolumes(preferences: Preferences, master = 37) =
  ## Checks that the master preserves independently saved channel levels.
  doAssert preferences.mainVolume == master
  doAssert preferences.musicVolume == 23
  doAssert preferences.fxVolume == 61
  doAssert preferences.uiVolume == 79

proc testSoundStartup() =
  ## Exercises startup, migration, and transitions with isolated saved settings.
  let
    app = "Polyworld sound startup test " & $getCurrentProcessId() &
      "-" & $getMonoTime().ticks
    directory = getConfigHome(app)
  doAssert not dirExists(directory)
  defer:
    configureSoundLaunch(false, false)
    configureSounds(false, 100, 100, 100, 100)
    if dirExists(directory):
      removeDir(directory)

  echo "Testing a fresh launch uses audible default sliders"
  configureSoundLaunch(false, false)
  let defaults = readPreferences(app)
  doAssert defaults.mainVolume == 100 and defaults.musicVolume == 100
  doAssert defaults.fxVolume == 100 and defaults.uiVolume == 100
  defaults.applyPreferences(Window(nil), configureDisplay = false)
  doAssert not soundsMuted()

  echo "Testing a game's Music default preserves explicitly saved levels"
  let quietMusic = readPreferences(app, defaultMusicVolume = 25)
  doAssert quietMusic.musicVolume == 25
  doAssert quietMusic.mainVolume == 100 and quietMusic.fxVolume == 100
  doAssert quietMusic.uiVolume == 100
  doAssert readPreferences(app).musicVolume == 100
  for bytes in ["{}", """{"name":"musicVolume","mainVolume":37}""",
      """{"soundMuted":true,"mainVolume":37}"""]:
    setConfig(app, "settings.json", bytes)
    let current = readPreferences(app, defaultMusicVolume = 25)
    doAssert current.musicVolume == 25
    doAssert current.fxVolume == 100 and current.uiVolume == 100
    if bytes.contains("soundMuted"):
      doAssert current.mainVolume == 0
    current.savePreferences(app)
    doAssert readPreferences(app).musicVolume == 25,
      "Saving a new profile must preserve its chosen game default"
  for level in [0, 25, 73, 100]:
    setConfig(app, "settings.json", "{\"musicVolume\":" & $level &
      ",\"mainVolume\":37,\"fxVolume\":61,\"uiVolume\":79}")
    let current = readPreferences(app, defaultMusicVolume = 25)
    doAssert current.musicVolume == level
    doAssert current.mainVolume == 37
    doAssert current.fxVolume == 61 and current.uiVolume == 79
    current.savePreferences(app)
    doAssert readPreferences(app, defaultMusicVolume = 25).musicVolume == level
  setConfig(app, "settings.json", "{\"musicVolume\":")
  var malformedRejected = false
  try:
    discard readPreferences(app, defaultMusicVolume = 25)
  except MenusError:
    malformedRejected = true
  doAssert malformedRejected,
    "Malformed settings must retain the existing error/fallback contract"
  removeFile(directory / "settings.json")
  doAssert readPreferences(app, defaultMusicVolume = -5).musicVolume == 0
  doAssert readPreferences(app, defaultMusicVolume = 105).musicVolume == 100
  configureSoundLaunch(true)
  var mutedFresh = readPreferences(app, defaultMusicVolume = 25)
  doAssert mutedFresh.mainVolume == 0 and mutedFresh.musicVolume == 25
  mutedFresh.name = "Fresh muted player"
  mutedFresh.savePreferences(app)
  configureSoundLaunch(false, false)
  let restoredFresh = readPreferences(app, defaultMusicVolume = 25)
  doAssert restoredFresh.mainVolume == 100 and restoredFresh.musicVolume == 25

  echo "Testing every saved slider survives launches and menu transitions"
  var saved = Preferences(
    name: "Saved player",
    mainVolume: 37,
    musicVolume: 23,
    fxVolume: 61,
    uiVolume: 79
  )
  saved.savePreferences(app)
  for transition in 0 ..< 3:
    configureSoundLaunch(false, false)
    let current = readPreferences(app)
    current.checkVolumes()
    doAssert current.name == saved.name
    current.applyPreferences(Window(nil), configureDisplay = false)
    doAssert not soundsMuted()

  echo "Testing Master zero persists without changing the other sliders"
  saved.mainVolume = 0
  saved.applyPreferences(Window(nil), configureDisplay = false)
  doAssert soundsMuted()
  saved.savePreferences(app)
  configureSoundLaunch(false, false)
  let quiet = readPreferences(app)
  quiet.checkVolumes(0)
  quiet.applyPreferences(Window(nil), configureDisplay = false)
  doAssert soundsMuted()
  saved.mainVolume = 37
  saved.applyPreferences(Window(nil), configureDisplay = false)
  doAssert not soundsMuted()
  saved.savePreferences(app)
  readPreferences(app).checkVolumes()

  echo "Testing legacy mute migrates once to Master zero"
  setConfig(app, "settings.json", """{"soundMuted":true,"mainVolume":37,
    "musicVolume":23,"fxVolume":61,"uiVolume":79}""")
  var migrated = readPreferences(app)
  migrated.checkVolumes(0)
  migrated.applyPreferences(Window(nil), configureDisplay = false)
  doAssert soundsMuted()
  migrated.savePreferences(app)
  doAssert not getConfig(app, "settings.json").contains("soundMuted")
  configureSoundLaunch(false, false)
  readPreferences(app).checkVolumes(0)
  migrated.mainVolume = 37
  migrated.savePreferences(app)
  configureSoundLaunch(false, false)
  readPreferences(app).checkVolumes()
  setConfig(app, "settings.json", """{"soundMuted":false,"mainVolume":37,
    "musicVolume":23,"fxVolume":61,"uiVolume":79}""")
  readPreferences(app).checkVolumes()
  saved.savePreferences(app)

  echo "Testing explicit launch mute stays visible without replacing saved Master"
  configureSoundLaunch(true)
  var launched = readPreferences(app)
  launched.checkVolumes(0)
  launched.applyPreferences(Window(nil), configureDisplay = false)
  doAssert soundsMuted()
  launched.name = "Name edited while launched quietly"
  launched.savePreferences(app)
  getConfig(app, "settings.json").fromJson(Preferences).checkVolumes()
  for transition in 0 ..< 3:
    let current = readPreferences(app)
    current.checkVolumes(0)
    current.applyPreferences(Window(nil), configureDisplay = false)
    doAssert soundsMuted()
  launched.mainVolume = 52
  launched.applyPreferences(Window(nil), configureDisplay = false)
  launched.savePreferences(app)
  readPreferences(app).checkVolumes(52)
  doAssert not soundsMuted()
  configureSoundLaunch(false, false)
  readPreferences(app).checkVolumes(52)

  echo "Testing explicit unmute respects saved levels or lifts saved Master zero"
  saved.savePreferences(app)
  configureSoundLaunch(false)
  readPreferences(app).checkVolumes()
  configureSoundLaunch(false, false)
  saved.mainVolume = 0
  saved.savePreferences(app)
  configureSoundLaunch(false)
  launched = readPreferences(app)
  launched.checkVolumes(100)
  launched.applyPreferences(Window(nil), configureDisplay = false)
  doAssert not soundsMuted()
  launched.name = "Name edited during explicit unmute"
  launched.savePreferences(app)
  getConfig(app, "settings.json").fromJson(Preferences).checkVolumes(0)
  readPreferences(app).checkVolumes(100)
  configureSoundLaunch(false, false)
  readPreferences(app).checkVolumes(0)
  configureSoundLaunch(false)
  launched = readPreferences(app)
  launched.mainVolume = 43
  launched.savePreferences(app)
  readPreferences(app).checkVolumes(43)
  configureSoundLaunch(false, false)
  readPreferences(app).checkVolumes(43)

  echo "Testing missing settings keep launch overrides temporary"
  removeFile(directory / "settings.json")
  configureSoundLaunch(true)
  launched = readPreferences(app)
  doAssert launched.mainVolume == 0
  launched.name = "New player"
  launched.savePreferences(app)
  configureSoundLaunch(false, false)
  doAssert readPreferences(app).mainVolume == 100
  echo "PASS saved sliders, Master mute, legacy migration and launch overrides"

testSoundStartup()
