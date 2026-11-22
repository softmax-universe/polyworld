import std/[os, osproc, strtabs, strutils, tempfiles]

const
  ExperimentDir = currentSourcePath().parentDir.parentDir
  RepositoryDir = ExperimentDir.parentDir.parentDir

proc runCommand(
  arguments: openArray[string], directory: string,
  environment: StringTableRef, timeout: int
): tuple[output: string, exitCode: int] =
  ## Captures process diagnostics without blocking on a full compiler pipe.
  let (file, path) = createTempFile("voice-launch-output-", ".txt")
  file.close()
  defer:
    removeFile(path)
  let command = "exec " & quoteShellCommand(arguments) &
    " > " & quoteShell(path) & " 2>&1"
  let process = startProcess(
    "/bin/sh", workingDir = directory, args = ["-c", command],
    env = environment, options = {poParentStreams}
  )
  defer:
    process.close()
  result.exitCode = process.waitForExit(timeout)
  result.output = readFile(path)

proc dimension(data: string, offset: int): uint32 =
  ## Reads one big-endian dimension from a validated PNG image header.
  for i in offset ..< offset + 4:
    result = (result shl 8) or data[i].ord.uint32

proc checkCompletionFiles(directory: string) =
  ## Requires the launcher to remove its receipt after success or failure.
  for path in walkFiles(directory / "voice-exit-*.txt"):
    doAssert false, "The launcher left its completion file: " & path

proc testLaunches() =
  ## Checks real offline app launch, argument forwarding, and failure reporting.
  let
    buildDir = ExperimentDir / "build"
    executable = buildDir / "test_voice"
    environment = newStringTable(modeCaseSensitive)
  createDir(buildDir)
  for name, value in envPairs():
    environment[name] = value
  for name in [
    "OPENAI_API_KEY", "POLYWORLD_VOICE_APPLICATION",
    "POLYWORLD_VOICE_COMPLETION"
  ]:
    environment.del(name)

  echo "Building the actual Voice Lab entry point."
  let compilation = runCommand(
    [getEnv("NIM", "nim"), "c", "--parallelBuild:1", "--out:" & executable,
      ExperimentDir / "voice.nim"],
    RepositoryDir, environment, 180_000
  )
  doAssert compilation.exitCode == 0, compilation.output

  let
    temporaryDir = createTempDir("voice-launch-test-", "")
    screenshot = temporaryDir / "preview with spaces.png"
  defer:
    removeDir(temporaryDir)
  environment["TMPDIR"] = temporaryDir & DirSep
  echo "Checking clean app exit and forwarded screenshot path."
  let preview = runCommand(
    [executable, "--demo", "--frames=3", "--screenshot=" & screenshot],
    RepositoryDir, environment, 60_000
  )
  doAssert preview.exitCode == 0, preview.output
  doAssert "Opening Voice Lab" in preview.output, preview.output
  doAssert fileExists(screenshot), "The launched app did not save its frame."
  let png = readFile(screenshot)
  doAssert png.len >= 24 and png[0 .. 7] == "\x89PNG\r\n\x1a\n",
    "Screenshot is not a PNG."
  doAssert png[12 .. 15] == "IHDR", "Screenshot has no PNG image header."
  doAssert dimension(png, 16) > 0 and dimension(png, 20) > 0,
    "Screenshot is empty."
  checkCompletionFiles(temporaryDir)
  if getEnv("VOICE_TEST_SCREENSHOT").len > 0:
    let evidence = absolutePath(getEnv("VOICE_TEST_SCREENSHOT"))
    createDir(evidence.parentDir)
    copyFile(screenshot, evidence)
    echo "Launcher preview saved: ", evidence

  let invalidScreenshot = temporaryDir / "existing-directory.png"
  createDir(invalidScreenshot)
  echo "Checking that a child failure reaches the terminal."
  let failure = runCommand(
    [executable, "--demo", "--frames=3",
      "--screenshot=" & invalidScreenshot],
    RepositoryDir, environment, 60_000
  )
  doAssert failure.exitCode != 0, failure.output
  doAssert "exited unexpectedly" in failure.output, failure.output
  doAssert dirExists(invalidScreenshot)
  checkCompletionFiles(temporaryDir)
  echo "macOS launcher checks passed."

when defined(macosx):
  testLaunches()
else:
  echo "Skipping macOS launcher checks on this platform."
