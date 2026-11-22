import std/[os, strutils], webservers

const AssetDirectory = currentSourcePath().parentDir / "emscripten"

proc argumentValue(arguments: seq[string], index: var int): string =
  ## Consumes one required option value without interpreting shell syntax.
  let option = arguments[index]
  let separator = option.find('=')
  if separator >= 0:
    if separator == option.high:
      raise newException(ValueError, option & " requires a value.")
    return option[separator + 1 .. ^1]
  inc index
  if index >= arguments.len or arguments[index].len == 0:
    raise newException(ValueError, option & " requires a value.")
  arguments[index]

proc main() =
  ## Serves the browser build on loopback or behind private Tailscale Serve.
  var
    port = 8001
    origin, user: string
    index = 0
  let arguments = commandLineParams()
  while index < arguments.len:
    case arguments[index].split('=', maxsplit = 1)[0]
    of "--port":
      port = parseInt(arguments.argumentValue(index))
    of "--origin":
      origin = arguments.argumentValue(index)
    of "--tailscale-user":
      user = arguments.argumentValue(index)
    of "--help", "-h":
      echo "Usage: serve [--port NUMBER] [--origin HTTPS_ORIGIN] " &
        "[--tailscale-user LOGIN]"
      echo "Serves Voice Lab from its emscripten directory on 127.0.0.1."
      return
    else:
      raise newException(ValueError, "Unknown argument: " & arguments[index])
    inc index
  if port notin 1 .. 65535:
    raise newException(ValueError, "--port must be between 1 and 65535.")
  if not fileExists(AssetDirectory / "voice.html"):
    raise newException(ValueError,
      "Build Voice Lab for Emscripten before starting the server.")
  let server = newVoiceServer(
    AssetDirectory, port, externalOrigin = origin, tailscaleUser = user
  )
  let address = if origin.len > 0: origin else: "http://localhost:" & $port
  echo "Voice Lab: " & address & "/"
  server.serve()

try:
  main()
except CatchableError as error:
  stderr.writeLine(error.msg)
  quit(1)
