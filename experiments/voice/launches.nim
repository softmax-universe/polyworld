import std/[os, osproc, tempfiles]

when defined(macosx):
  const ExperimentDir = currentSourcePath().parentDir

  {.compile: ExperimentDir / "launches.m".}
  {.passL: "-framework AppKit".}

  proc voiceLaunchedApplication(): bool {.importc.}
    ## Identifies the app instance started through LaunchServices.
  proc voiceLaunchApplication(path, completion: cstring): cint {.importc.}
    ## Launches a separate app identity and waits for it to finish.
  proc voiceObserveTermination() {.importc.}
    ## Recognizes an orderly native Quit action as a successful exit.

proc launchApplication*(): bool =
  ## Gives macOS microphone requests the experiment's own app identity.
  when defined(macosx):
    if voiceLaunchedApplication():
      voiceObserveTermination()
      return false
    let
      executable = getAppFilename()
      contents = executable.parentDir.parentDir
      bundled = executable.parentDir.lastPathPart == "MacOS" and
        contents.lastPathPart == "Contents" and
        fileExists(contents / "Info.plist")
      appDir =
        if bundled: contents.parentDir
        else: ExperimentDir / "build/Voice Lab.app"
    if not bundled:
      let
        target = appDir / "Contents/MacOS/voice"
        temporary = target & "." & $getCurrentProcessId()
        assets = appDir / "Contents/Resources/assets"
      createDir(target.parentDir)
      createDir(assets)
      copyFileWithPermissions(executable, temporary)
      moveFile(temporary, target)
      copyFile(ExperimentDir / "macos.plist", appDir / "Contents/Info.plist")
      for name in ["IBMPlexSans-Regular.ttf", "OFL-IBMPlexSans.txt"]:
        copyFile(ExperimentDir / "assets" / name, assets / name)
      let signing = execCmdEx(
        "/usr/bin/codesign --force --sign - " & quoteShell(appDir))
      if signing.exitCode != 0:
        raise newException(IOError,
          "Could not sign Voice Lab: " & signing.output)
    let (completionFile, completionPath) = createTempFile("voice-exit-", ".txt")
    completionFile.close()
    defer: removeFile(completionPath)
    echo "Opening Voice Lab with its own macOS microphone permissions."
    if voiceLaunchApplication(appDir.cstring, completionPath.cstring) != 0:
      raise newException(IOError, "macOS could not launch Voice Lab.")
    if readFile(completionPath) != "ok":
      raise newException(IOError,
        "Voice Lab exited unexpectedly. Check the macOS crash report.")
    return true
  else:
    return false

proc finishApplication*() =
  ## Reports a clean app exit to the terminal launcher without hiding crashes.
  when defined(macosx):
    let path = getEnv("POLYWORLD_VOICE_COMPLETION")
    if voiceLaunchedApplication() and path.len > 0:
      writeFile(path, "ok")
