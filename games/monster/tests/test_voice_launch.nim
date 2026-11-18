import
  std/[os, strutils, tempfiles],
  ../../../experiments/voice/launches

const
  Identifier = "org.polyworld.monster.launchtest"
  Plist = currentSourcePath().parentDir.parentDir / "macos.plist"

when defined(macosx):
  restoreApplicationDirectory(Identifier)
  let child = getEnv("MONSTER_LAUNCH_TEST_DIRECTORY").len > 0
  if child:
    let directory = getEnv("MONSTER_LAUNCH_TEST_DIRECTORY")
    doAssert getCurrentDir() == getEnv("MONSTER_LAUNCH_TEST_CWD")
    doAssert getEnv("MONSTER_LAUNCH_TEST_VALUE") == "A value with spaces"
    doAssert commandLineParams().join("\n") ==
      getEnv("MONSTER_LAUNCH_TEST_ARGUMENTS")
    doAssert not launchApplication(identifier = Identifier)
    if getEnv("MONSTER_LAUNCH_TEST_FAIL") == "1":
      quit(7)
    writeFile(directory / "child.txt", "ok")
    finishApplication(Identifier)
  else:
    echo "Testing Monster app identity without a window or microphone"
    let directory = createTempDir("monster-launch-", "")
    try:
      let
        plist = directory / "Info.plist"
        app = directory / "Monster launch test.app"
      writeFile(plist, readFile(Plist).replace(
        "org.polyworld.monster", Identifier))
      putEnv("MONSTER_LAUNCH_TEST_DIRECTORY", directory)
      putEnv("MONSTER_LAUNCH_TEST_CWD", getCurrentDir())
      putEnv("MONSTER_LAUNCH_TEST_VALUE", "A value with spaces")
      putEnv("MONSTER_LAUNCH_TEST_ARGUMENTS", commandLineParams().join("\n"))
      doAssert launchApplication(
        name = "Monster launch test",
        identifier = Identifier,
        appPath = app,
        infoPlist = plist,
        binary = "monster",
        includeFonts = false
      )
      doAssert readFile(directory / "child.txt") == "ok"
      removeFile(directory / "child.txt")
      putEnv("MONSTER_LAUNCH_TEST_FAIL", "1")
      var failed = false
      try:
        discard launchApplication(
          name = "Monster launch test",
          identifier = Identifier,
          appPath = app,
          infoPlist = plist,
          binary = "monster",
          includeFonts = false
        )
      except IOError as error:
        failed = "exited unexpectedly" in error.msg
      doAssert failed
      doAssert not fileExists(directory / "child.txt")
    finally:
      for key in ["MONSTER_LAUNCH_TEST_DIRECTORY", "MONSTER_LAUNCH_TEST_CWD",
        "MONSTER_LAUNCH_TEST_VALUE", "MONSTER_LAUNCH_TEST_ARGUMENTS",
        "MONSTER_LAUNCH_TEST_FAIL"]:
          delEnv(key)
      removeDir(directory)
    echo "Monster app identity, arguments, environment and exit checks passed"
else:
  echo "Skipping macOS app identity on this platform"
