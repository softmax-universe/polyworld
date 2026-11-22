import
  std/[atomics, json, monotimes, os, strutils, times, uri],
  curly, jsony, mummy

from std/unicode import runeSubStr, validateUtf8

export httpheaders

const
  DefaultModel* = "gpt-realtime-2.1-mini"
  DefaultVoice* = "marin"
  TokenUrl* = "https://api.openai.com/v1/realtime/client_secrets"
  MaxRequestBytes* = 16_384
  MaxResponseBytes* = 1024 * 1024

type
  ServerState = enum
    CreatedServer, StartingServer, RunningServer, StoppingServer, StoppedServer

  VoiceServerError* = object of CatchableError
    status*: int
    code*: string

  ClientSecret* = object
    value*: string
    expires_at*: int64

  KeyProvider* = proc(): string {.gcsafe, raises: [CatchableError].}
  TokenProvider* = proc(key, model, voice: string): ClientSecret
    {.gcsafe, raises: [CatchableError].}

  VoiceResponse* = object
    status*: int
    headers*: HttpHeaders
    body*: string

  VoiceServer* = ref object
    port*: int
    address*: string
    directory, externalOrigin, externalHost, tailscaleUser: string
    model, voice: string
    keyProvider: KeyProvider
    tokenProvider: TokenProvider
    requestTimeoutMs, writeTimeoutMs: int
    native: Server
    state: Atomic[ServerState]

proc voiceError*(
  status: int, message: string, code = "voice_server_error"
): ref VoiceServerError {.raises: [].} =
  ## Creates an HTTP failure containing only browser-safe details.
  result = newException(VoiceServerError, message)
  result.status = status
  result.code = code

proc configuredKey*(keyFile: string): string
    {.gcsafe, raises: [VoiceServerError].} =
  ## Reads an environment credential before the specified local raw key file.
  result = getEnv("OPENAI_API_KEY").strip()
  if result.len == 0:
    try:
      if fileExists(keyFile):
        result = readFile(keyFile).strip()
        if result.validateUtf8() >= 0:
          raise voiceError(500, "Could not read the local OpenAI key.")
    except OSError, IOError:
      raise voiceError(500, "Could not read the local OpenAI key.")

proc configuredKey*(): string {.gcsafe, raises: [VoiceServerError].} =
  ## Uses the native experiment's usual raw key file after the environment.
  configuredKey(getHomeDir() / "secrets" / "openai.key")

proc redact*(message, key: string): string {.raises: [].} =
  ## Removes full and recognizable partial keys from bounded error details.
  let text = if key.len > 0: message.replace(key, "[redacted]") else: message
  var index = 0
  while index < text.len:
    if index + 3 < text.len and text[index ..< index + 3] == "sk-" and
      text[index + 3] in Letters + Digits + {'_', '.', '*', '-'}:
        index += 3
        while index < text.len and
          text[index] in Letters + Digits + {'_', '.', '*', '-'}:
            inc index
        result.add("[redacted]")
    else:
      result.add(text[index])
      inc index
  result = result.runeSubStr(0, 2000)

proc parseDocument(body: string): JsonNode {.raises: [ValueError].} =
  ## Parses bounded UTF-8 JSON without permitting an unbounded nesting stack.
  if body.validateUtf8() >= 0:
    raise newException(ValueError, "Invalid UTF-8")
  var depth = 0
  var quoted, escaped: bool
  for character in body:
    if escaped:
      escaped = false
    elif quoted:
      if character == '\\':
        escaped = true
      elif character == '"':
        quoted = false
    elif character == '"':
      quoted = true
    elif character in {'[', '{'}:
      inc depth
      if depth > 64:
        raise newException(ValueError, "JSON nesting exceeds the limit")
    elif character in {']', '}'}:
      dec depth
  result = body.fromJson(JsonNode)
  if result == nil:
    raise newException(ValueError, "Missing JSON value")

proc parseSecret*(status: int, body, key: string): ClientSecret
    {.raises: [VoiceServerError].} =
  ## Validates an upstream secret or returns sanitized API error details.
  if body.len > MaxResponseBytes:
    raise voiceError(502, "OpenAI returned an oversized session response.")
  if status notin 200 .. 299:
    var
      message = "OpenAI rejected the session request."
      code = "openai_error"
    try:
      let payload = parseDocument(body)
      if payload.kind == JObject and payload.hasKey("error") and
        payload["error"].kind == JObject:
          let detail = payload["error"]
          if detail.hasKey("message") and detail["message"].kind == JString:
            message = redact(detail["message"].getStr(), key)
          if detail.hasKey("code") and detail["code"].kind == JString:
            code = redact(detail["code"].getStr(), key)
    except ValueError, KeyError:
      discard
    raise voiceError(if status in 400 .. 599: status else: 502, message, code)
  try:
    let payload = parseDocument(body)
    if payload.kind != JObject or not payload.hasKey("value") or
      payload["value"].kind != JString or not payload.hasKey("expires_at") or
      payload["expires_at"].kind != JInt:
        raise newException(ValueError, "Invalid client secret")
    result.value = payload["value"].getStr()
    result.expires_at = payload["expires_at"].getBiggestInt()
    if result.value.len == 0 or result.value.len > 8192:
      raise newException(ValueError, "Invalid client secret")
  except ValueError, KeyError:
    raise voiceError(502, "OpenAI returned an invalid session response.")

proc createSecret*(key, model, voice: string, url = TokenUrl): ClientSecret
    {.gcsafe, raises: [VoiceServerError].} =
  ## Exchanges a server credential for a bounded, short-lived browser secret.
  let body = $(%*{"session": {
    "type": "realtime", "model": model,
    "audio": {"output": {"voice": voice}}
  }})
  try:
    let transport = newCurly(maxInFlight = 1)
    defer:
      transport.close()
    let stream = transport.request(
      "POST", url,
      @[("Authorization", "Bearer " & key),
        ("Content-Type", "application/json")],
      body,
      timeout = 20
    )
    defer:
      stream.close()
    var response: string
    while stream.read(response) > 0:
      if response.len > MaxResponseBytes:
        raise voiceError(502, "OpenAI returned an oversized session response.")
    result = parseSecret(stream.code, response, key)
  except VoiceServerError:
    raise
  except CatchableError:
    raise voiceError(502, "Could not reach OpenAI. Try connecting again.")

proc defaultSecret(key, model, voice: string): ClientSecret {.gcsafe.} =
  ## Adapts the optional test URL away from the production provider signature.
  createSecret(key, model, voice)

proc setting*(value, fallback, name: string): string
    {.raises: [VoiceServerError].} =
  ## Validates bounded model and voice names without interpreting syntax.
  result = if value.len == 0: fallback else: value
  if result.len notin 1 .. 128 or result[0] notin Letters + Digits:
    raise voiceError(400, "Invalid " & name & ".", "invalid_request")
  for character in result:
    if character notin Letters + Digits + {'_', '.', ':', '-'}:
      raise voiceError(400, "Invalid " & name & ".", "invalid_request")

proc values(headers: HttpHeaders, name: string): seq[string] {.raises: [].} =
  ## Preserves duplicates so singleton request headers can be rejected.
  for (key, value) in headers:
    if cmpIgnoreCase(key, name) == 0:
      result.add(value)

proc checkHost(server: VoiceServer, headers: HttpHeaders): string
    {.raises: [VoiceServerError].} =
  ## Checks the exact configured host and optional Tailscale Serve identity.
  if server.tailscaleUser.len > 0 and
    headers.values("Tailscale-User-Login") != @[server.tailscaleUser]:
      raise voiceError(403,
        "Open Voice Lab using the owner's Tailscale account.", "invalid_user")
  let hosts = headers.values("Host")
  var allowed = @[
    "127.0.0.1:" & $server.port, "localhost:" & $server.port
  ]
  if server.port == 80:
    allowed.add(["127.0.0.1", "localhost"])
  if server.externalHost.len > 0:
    allowed = @[server.externalHost]
  if hosts.len != 1 or hosts[0].toLowerAscii() notin allowed:
    raise voiceError(403, "Use the configured Voice Lab address.", "invalid_host")
  hosts[0].toLowerAscii()

proc checkOrigin(server: VoiceServer, host: string, headers: HttpHeaders)
    {.raises: [VoiceServerError].} =
  ## Restricts token creation to the explicitly configured same-origin page.
  let expected =
    if server.externalOrigin.len > 0: server.externalOrigin else: "http://" & host
  if headers.values("Origin") != @[expected]:
    raise voiceError(403, "Token requests must come from this page.", "invalid_origin")
  let sites = headers.values("Sec-Fetch-Site")
  if sites.len > 0 and sites != @["same-origin"]:
    raise voiceError(403, "Cross-origin token requests are not allowed.", "invalid_origin")

proc response(status: int, contentType, body: string): VoiceResponse =
  ## Applies the same cache and browser isolation headers to every response.
  VoiceResponse(status: status, body: body, headers: @[
    ("Content-Type", contentType), ("Content-Length", $body.len),
    ("Cache-Control", "no-store"), ("X-Content-Type-Options", "nosniff"),
    ("X-Frame-Options", "DENY"),
    ("Cross-Origin-Resource-Policy", "same-origin")
  ])

proc jsonResponse(status: int, payload: JsonNode): VoiceResponse =
  ## Encodes only public defaults, client secrets, or safe error details.
  response(status, "application/json; charset=utf-8", $payload)

proc assetType(extension: string): string {.raises: [].} =
  ## Limits served files to compiled browser assets and supported fonts.
  case extension.toLowerAscii()
  of ".html": "text/html; charset=utf-8"
  of ".js": "text/javascript; charset=utf-8"
  of ".wasm": "application/wasm"
  of ".data": "application/octet-stream"
  of ".css": "text/css; charset=utf-8"
  of ".png": "image/png"
  of ".svg": "image/svg+xml"
  of ".ico": "image/x-icon"
  of ".ttf": "font/ttf"
  of ".woff": "font/woff"
  of ".woff2": "font/woff2"
  else: ""

proc staticFile(server: VoiceServer, rawPath: string, head: bool): VoiceResponse
    {.raises: [VoiceServerError].} =
  ## Rejects traversal and symlinks before opening an allowed build asset.
  var path = decodeUrl(rawPath, decodePlus = false)
  if path == "/":
    path = "/voice.html"
  if not path.startsWith("/") or '\\' in path or '\0' in path:
    raise voiceError(404, "File not found.", "not_found")
  var candidate = server.directory
  for part in path[1 .. ^1].split('/'):
    if part in ["", ".", ".."]:
      raise voiceError(404, "File not found.", "not_found")
    candidate = candidate / part
    if symlinkExists(candidate):
      raise voiceError(404, "File not found.", "not_found")
  let contentType = candidate.splitFile().ext.assetType()
  if contentType.len == 0 or not fileExists(candidate):
    raise voiceError(404, "File not found.", "not_found")
  try:
    let resolved = expandFilename(candidate)
    let prefix = server.directory.strip(
      leading = false, trailing = true, chars = {DirSep}
    ) & DirSep
    if not resolved.startsWith(prefix):
      raise voiceError(404, "File not found.", "not_found")
    if head:
      result = response(200, contentType, "")
      result.headers["Content-Length"] = $getFileSize(resolved)
    else:
      result = response(200, contentType, readFile(resolved))
  except OSError, IOError:
    raise voiceError(404, "File not found.", "not_found")

proc requestSetting(
  payload: JsonNode, name, fallback: string
): string {.raises: [VoiceServerError].} =
  ## Requires text for optional model and voice fields before validation.
  let value = payload.getOrDefault(name)
  if value == nil:
    return fallback
  if value.kind != JString:
    raise voiceError(400, "Invalid " & name & ".", "invalid_request")
  setting(value.getStr(), fallback, name)

proc token(server: VoiceServer, headers: HttpHeaders, body: string): VoiceResponse
    {.raises: [CatchableError].} =
  ## Checks framing and fields before reading or exchanging any credential.
  if "Transfer-Encoding" in headers:
    raise voiceError(400, "Transfer encoding is not supported.", "invalid_request")
  let contentType = headers.values("Content-Type")
  if contentType.len != 1 or
    contentType[0].split(';')[0].strip().toLowerAscii() != "application/json":
      raise voiceError(415, "Send an application/json request.", "invalid_request")
  let lengths = headers.values("Content-Length")
  if lengths.len != 1 or lengths[0].len == 0 or
    lengths[0].find(AllChars - Digits) >= 0:
      raise voiceError(400, "A valid Content-Length is required.", "invalid_request")
  if lengths[0].len > 8:
    raise voiceError(413, "The token request is too large.", "invalid_request")
  let length = parseInt(lengths[0])
  if length notin 1 .. MaxRequestBytes:
    raise voiceError(413, "The token request is too large or empty.", "invalid_request")
  if body.len != length:
    raise voiceError(400, "The token request is incomplete.", "invalid_request")
  var payload: JsonNode
  try:
    payload = parseDocument(body)
  except ValueError:
    raise voiceError(400, "The token request is not valid JSON.", "invalid_request")
  if payload.kind != JObject:
    raise voiceError(400, "Invalid token request fields.", "invalid_request")
  for key in payload.keys:
    if key notin ["model", "voice", "apiKey"]:
      raise voiceError(400, "Invalid token request fields.", "invalid_request")
  let
    model = requestSetting(payload, "model", server.model)
    voice = requestSetting(payload, "voice", server.voice)
  var supplied: string
  if payload.hasKey("apiKey"):
    if payload["apiKey"].kind != JString:
      raise voiceError(400, "The API key must be text.", "invalid_request")
    supplied = payload["apiKey"].getStr().strip()
  var key = server.keyProvider()
  if key.len == 0:
    key = supplied
  if key.len == 0:
    raise voiceError(400,
      "Add an API key above, set OPENAI_API_KEY, or add ~/secrets/openai.key.",
      "missing_api_key")
  if key.len > 4096 or key.find(AllChars - {'!' .. '~'}) >= 0:
    raise voiceError(400, "The API key contains invalid characters.", "invalid_request")
  let secret = server.tokenProvider(key, model, voice)
  jsonResponse(200, %*{"value": secret.value, "expires_at": secret.expires_at})

proc handle*(
  server: VoiceServer, httpMethod, target: string,
  headers: HttpHeaders, body = ""
): VoiceResponse {.gcsafe.} =
  ## Routes complete requests and keeps all errors independent of credentials.
  try:
    let
      host = server.checkHost(headers)
      path = parseUri(target).path
    case httpMethod
    of "GET", "HEAD":
      if path == "/api/config":
        result = jsonResponse(200, %*{
          "keyAvailable": server.keyProvider().len > 0,
          "model": server.model, "voice": server.voice
        })
      else:
        result = server.staticFile(path, httpMethod == "HEAD")
    of "POST":
      server.checkOrigin(host, headers)
      if path != "/api/realtime/token":
        raise voiceError(404, "Endpoint not found.", "not_found")
      result = server.token(headers, body)
    else:
      raise voiceError(405, "Method not allowed.", "invalid_request")
  except VoiceServerError as error:
    result = jsonResponse(error.status, %*{"error": {
      "message": error.msg, "code": error.code
    }})
  except ValueError:
    result = jsonResponse(400, %*{"error": {
      "message": "Invalid request target.", "code": "invalid_request"
    }})
  except CatchableError:
    result = jsonResponse(500, %*{"error": {
      "message": "The voice server could not complete the request.",
      "code": "voice_server_error"
    }})
  if httpMethod == "HEAD":
    result.body.setLen(0)

proc validateOrigin(origin, user: string): string {.raises: [ValueError].} =
  ## Accepts an HTTPS authority without credentials, paths, or ambiguous ports.
  if user.len > 0 and origin.len == 0:
    raise newException(ValueError, "--tailscale-user requires --origin.")
  if user.len > 0 and user.strip() != user:
    raise newException(ValueError, "--tailscale-user must be a Tailscale login name.")
  if origin.len == 0:
    return
  let value = parseUri(origin)
  if not origin.startsWith("https://") or value.scheme != "https" or
    value.hostname.len == 0 or value.username.len > 0 or value.password.len > 0 or
    value.path.len > 0 or value.query.len > 0 or value.anchor.len > 0 or
    origin.find(Whitespace + {'\\', '@', '?', '#'}) >= 0:
      raise newException(ValueError, "--origin must be an HTTPS origin without a path.")
  let authority = origin[8 .. ^1]
  if '/' in authority or authority.len == 0:
    raise newException(ValueError, "--origin must be an HTTPS origin without a path.")
  if value.port.len > 0:
    if value.port.find(AllChars - Digits) >= 0 or value.port.len > 5 or
      parseInt(value.port) notin 1 .. 65535:
        raise newException(ValueError, "--origin contains an invalid port.")
  elif authority.endsWith(":"):
    raise newException(ValueError, "--origin contains an invalid port.")
  if authority.startsWith("["):
    let closing = authority.find(']')
    if closing < 2 or (closing + 1 < authority.len and
      authority[closing + 1] != ':'):
        raise newException(ValueError, "--origin contains an invalid host.")
  elif '[' in authority or ']' in authority or authority.count(':') > 1:
    raise newException(ValueError, "--origin contains an invalid host.")
  authority.toLowerAscii()

proc newVoiceServer*(
  directory: string, port = 8001,
  keyProvider: KeyProvider = configuredKey,
  tokenProvider: TokenProvider = defaultSecret,
  externalOrigin = "", tailscaleUser = "", requestTimeoutMs = 15_000,
  writeTimeoutMs = 15_000
): VoiceServer =
  ## Builds a loopback-only server with injectable offline credential providers.
  if port notin 1 .. 65535:
    raise newException(ValueError, "--port must be between 1 and 65535.")
  if keyProvider == nil or tokenProvider == nil:
    raise newException(ValueError, "Voice credential providers must be set.")
  if requestTimeoutMs < 0 or writeTimeoutMs < 0:
    raise newException(ValueError, "Voice server timeouts must not be negative.")
  let externalHost = validateOrigin(externalOrigin, tailscaleUser)
  result = VoiceServer(
    directory: expandFilename(directory), port: port, address: "127.0.0.1",
    externalOrigin: externalOrigin, externalHost: externalHost,
    tailscaleUser: tailscaleUser, keyProvider: keyProvider,
    tokenProvider: tokenProvider,
    requestTimeoutMs: requestTimeoutMs, writeTimeoutMs: writeTimeoutMs,
    model: setting(getEnv("OPENAI_REALTIME_MODEL", DefaultModel), DefaultModel, "model"),
    voice: setting(getEnv("OPENAI_REALTIME_VOICE", DefaultVoice), DefaultVoice, "voice")
  )

proc newNativeServer(server: VoiceServer): Server =
  ## Allocates callback environments on the thread that will destroy them.
  let context = cast[pointer](server)
  proc request(request: Request) {.gcsafe.} =
    ## Adapts Mummy's bounded complete request to the pure route handler.
    # The serve caller owns the wrapper until Mummy joins its workers. Keep
    # its shared callback free of GC references destroyed on another thread.
    let server {.cursor.} = cast[VoiceServer](context)
    let answer = server.handle(
      request.httpMethod, request.uri, request.headers, request.body
    )
    var headers = answer.headers
    if request.httpMethod != "HEAD":
      # Mummy computes the wire length after any negotiated compression.
      for index in countdown(headers.len - 1, 0):
        if cmpIgnoreCase(headers.toBase[index][0], "Content-Length") == 0:
          headers.toBase.delete(index)
    request.respond(answer.status, headers, answer.body)
  proc quiet(level: LogLevel, args: varargs[string]) {.gcsafe.} =
    ## Avoids logging request paths, supplied keys, or upstream response bodies.
    discard
  result = newServer(
    request, logHandler = quiet, workerThreads = 2,
    maxHeadersLen = 8192, maxBodyLen = MaxRequestBytes,
    requestTimeoutMs = server.requestTimeoutMs,
    writeTimeoutMs = server.writeTimeoutMs
  )

proc serve*(server: VoiceServer) =
  ## Runs the socket loop until another thread closes the server.
  var expected = CreatedServer
  if not server.state.compareExchange(expected, StartingServer):
    raise newException(ValueError, "The voice server has already started or closed.")
  try:
    server.native = server.newNativeServer()
    let context = cast[pointer](server)
    proc ready() {.gcsafe.} =
      ## Publishes a bound listener or honors a stop requested during startup.
      let owner {.cursor.} = cast[VoiceServer](context)
      var expected = StartingServer
      if not owner.state.compareExchange(expected, RunningServer):
        owner.native.close()
    server.native.serve(Port(server.port), "127.0.0.1", onReady = ready)
  finally:
    # Mummy releases its native server on both shutdown and bind failure.
    server.native = nil
    server.state.store(StoppedServer, moRelease)

proc waitUntilReady*(server: VoiceServer, timeout = 10.0) =
  ## Waits until the loopback listener is available for an offline test.
  let started = getMonoTime()
  while true:
    case server.state.load(moAcquire)
    of RunningServer:
      return
    of StoppingServer, StoppedServer:
      raise newException(ValueError, "The voice server closed before listening.")
    of CreatedServer, StartingServer:
      discard
    if (getMonoTime() - started).inMilliseconds.float64 >= timeout * 1000:
      raise newException(ValueError, "The voice server did not start in time.")
    sleep(1)

proc close*(server: VoiceServer) {.gcsafe.} =
  ## Stops networking and allows in-flight request handlers to finish.
  if server == nil:
    return
  var state = server.state.load(moAcquire)
  while true:
    case state
    of CreatedServer:
      if server.state.compareExchange(state, StoppedServer):
        return
    of StartingServer:
      if server.state.compareExchange(state, StoppingServer):
        return
    of RunningServer:
      if server.state.compareExchange(state, StoppingServer):
        server.native.close()
        return
    of StoppingServer, StoppedServer:
      return
