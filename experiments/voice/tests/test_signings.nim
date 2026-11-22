import
  std/[os, osproc, strtabs, strutils, tempfiles],
  jsony

const SignScript = currentSourcePath().parentDir.parentDir / "sign.sh"

proc fakeCommand() =
  ## Substitutes signing commands without accessing the keychain or an app.
  if paramCount() == 0:
    return
  case paramStr(1)
  of "--fake-security":
    echo getEnv("SIGNING_TEST_IDENTITIES")
    quit(parseInt(getEnv("SIGNING_TEST_SECURITY_EXIT", "0")))
  of "--fake-codesign":
    var arguments: seq[string]
    for i in 2 .. paramCount():
      arguments.add(paramStr(i))
    writeFile(getEnv("SIGNING_TEST_ARGUMENTS"), arguments.toJson())
    quit(parseInt(getEnv("SIGNING_TEST_CODESIGN_EXIT", "0")))
  else:
    raise newException(ValueError, "Unknown signing test command.")

proc testSignings() =
  ## Exercises the shared signing script against isolated Nim substitutes.
  let
    first = repeat('A', 40)
    second = repeat('B', 40)
    root = createTempDir("voice-signing-test-", "")
    script = root / "sign.sh"
    argumentsPath = root / "arguments.json"
    app = root / "App with spaces.app"
    helper = quoteShell(getAppFilename())
  defer:
    removeDir(root)
  writeFile(script, readFile(SignScript)
    .replace("/usr/bin/security", helper & " --fake-security")
    .replace("/usr/bin/codesign", helper & " --fake-codesign"))

  proc sign(
    identities: string, identity = "", securityExit = 0, codesignExit = 0
  ): tuple[output: string, exitCode: int, selected: seq[string]] =
    ## Runs only the substitutes and returns their captured signing arguments.
    let environment = newStringTable(modeCaseSensitive)
    for name, value in envPairs():
      environment[name] = value
    environment.del("VOICE_SIGNING_IDENTITY")
    environment["SIGNING_TEST_IDENTITIES"] = identities
    environment["SIGNING_TEST_ARGUMENTS"] = argumentsPath
    environment["SIGNING_TEST_SECURITY_EXIT"] = $securityExit
    environment["SIGNING_TEST_CODESIGN_EXIT"] = $codesignExit
    if identity.len > 0:
      environment["VOICE_SIGNING_IDENTITY"] = identity
    removeFile(argumentsPath)
    let execution = execCmdEx(
      quoteShellCommand(["/bin/sh", script, app]), env = environment
    )
    result.output = execution.output
    result.exitCode = execution.exitCode
    if fileExists(argumentsPath):
      result.selected = readFile(argumentsPath).fromJson(seq[string])

  let one = "  1) " & first & " \"Apple Development: Local Developer\"\n"
  var result = sign(one & "     1 valid identities found\n")
  doAssert result.exitCode == 0, result.output
  doAssert result.selected ==
    @["--force", "--sign", first, "--timestamp=none", app]

  result = sign(one & "  2) " & first & " \"Duplicate keychain\"\n")
  doAssert result.exitCode == 0, result.output
  doAssert result.selected[2] == first

  result = sign("     0 valid identities found\n")
  doAssert result.exitCode == 0, result.output
  doAssert result.selected[2] == "-"
  doAssert "ad-hoc" in result.output

  result = sign(one & "  2) " & second & " \"Other Developer\"\n")
  doAssert result.exitCode != 0
  doAssert result.selected.len == 0
  doAssert "VOICE_SIGNING_IDENTITY" in result.output

  let explicit = "Apple Development: Example 'quoted' $(not-executed)"
  result = sign("", identity = explicit, securityExit = 2)
  doAssert result.exitCode == 0, result.output
  doAssert result.selected[2] == explicit

  result = sign(one, securityExit = 2)
  doAssert result.exitCode == 2
  doAssert result.selected.len == 0

  result = sign(one, codesignExit = 3)
  doAssert result.exitCode == 3
  doAssert result.selected[2] == first

  echo "Signing selection checks passed; no keychain or app was accessed."

fakeCommand()
when defined(windows):
  echo "Skipping POSIX signing script checks on this platform."
else:
  testSignings()
