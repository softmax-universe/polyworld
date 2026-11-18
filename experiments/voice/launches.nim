import std/[os, osproc, tempfiles]

when defined(macosx):
  const ExperimentDir = currentSourcePath().parentDir

  {.compile: ExperimentDir / "launches.m".}
  {.passL: "-framework AppKit".}

  proc voiceLaunchedApplication(identifier: cstring): bool {.importc.}
    ## Identifies the app instance started through LaunchServices.
  proc voiceLaunchApplication(path, completion: cstring): cint {.importc.}
    ## Launches a separate app identity and waits for it to finish.
  proc voiceObserveTermination() {.importc.}
    ## Recognizes an orderly native Quit action as a successful exit.

proc restoreApplicationDirectory*(identifier = "org.polyworld.voicelab") =
  ## Restores the terminal directory before resolving relative CLI paths.
  when defined(macosx):
    if voiceLaunchedApplication(identifier.cstring):
      let directory = getEnv("POLYWORLD_VOICE_DIRECTORY")
      if directory.len > 0:
        setCurrentDir(directory)

proc launchApplication*(
  name = "Voice Lab",
  identifier = "org.polyworld.voicelab",
  appPath = "",
  infoPlist = "",
  binary = "voice",
  includeFonts = true
): bool =
  ## Launches a native app identity while preserving arguments and environment.
  when defined(macosx):
    if voiceLaunchedApplication(identifier.cstring):
      restoreApplicationDirectory(identifier)
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
        elif appPath.len > 0: appPath
        else: ExperimentDir / "build/Voice Lab.app"
    if not bundled:
      let
        target = appDir / "Contents/MacOS" / binary
        temporary = target & "." & $getCurrentProcessId()
        assets = appDir / "Contents/Resources/assets"
      createDir(target.parentDir)
      createDir(assets)
      copyFileWithPermissions(executable, temporary)
      moveFile(temporary, target)
      copyFile(
        if infoPlist.len > 0: infoPlist else: ExperimentDir / "macos.plist",
        appDir / "Contents/Info.plist"
      )
      if includeFonts:
        for filename in ["IBMPlexSans-Regular.ttf", "OFL-IBMPlexSans.txt"]:
          copyFile(ExperimentDir / "assets" / filename, assets / filename)
      let signing = execCmdEx(
        "/usr/bin/codesign --force --sign - " & quoteShell(appDir))
      if signing.exitCode != 0:
        raise newException(IOError,
          "Could not sign " & name & ": " & signing.output)
    let (completionFile, completionPath) = createTempFile("voice-exit-", ".txt")
    completionFile.close()
    defer: removeFile(completionPath)
    echo "Opening " & name & " with its own macOS microphone permissions."
    if voiceLaunchApplication(appDir.cstring, completionPath.cstring) != 0:
      raise newException(IOError, "macOS could not launch " & name & ".")
    if readFile(completionPath) != "ok":
      raise newException(IOError,
        name & " exited unexpectedly. Check the macOS crash report.")
    return true
  else:
    return false

proc finishApplication*(identifier = "org.polyworld.voicelab") =
  ## Reports a clean app exit to the terminal launcher without hiding crashes.
  when defined(macosx):
    let path = getEnv("POLYWORLD_VOICE_COMPLETION")
    if voiceLaunchedApplication(identifier.cstring) and path.len > 0:
      writeFile(path, "ok")
