import
  std/[atomics, json, locks, monotimes, net, os, strutils, tables, tempfiles,
    times],
  webby/httpheaders, zippy,
  ../webservers

from std/unicode import validateUtf8, runeLen

type
  SecretCall = tuple[key, model, voice: string]
  Reply = object
    status: int
    headers: Table[string, string]
    body: string
  Fixture = ref object
    server: VoiceServer
    thread: Thread[pointer]

var
  credentialLock: Lock
  credential: array[4096, char]
  credentialLength: int
  credentialReads: Atomic[int]
  secretCalls: Channel[SecretCall]
  upstreamPorts: Channel[int]
  upstreamRequests: Channel[string]

proc setKey(value: string) =
  ## Changes only the synthetic credential read by the current fixture.
  doAssert value.len <= credential.len
  withLock credentialLock:
    credentialLength = value.len
    for i, character in value:
      credential[i] = character

proc testKey(): string {.gcsafe.} =
  ## Counts authorized credential reads without touching local user secrets.
  discard credentialReads.fetchAdd(1)
  withLock credentialLock:
    result = newString(credentialLength)
    for i in 0 ..< credentialLength:
      result[i] = credential[i]

proc testSecret(key, model, voice: string): ClientSecret {.gcsafe.} =
  ## Records synthetic token requests without contacting an external service.
  secretCalls.send((key, model, voice))
  ClientSecret(value: "ek_test_only", expires_at: 1234567890)

proc drainCalls(): seq[SecretCall] =
  ## Collects completed provider calls after receiving their HTTP responses.
  while true:
    let call = secretCalls.tryRecv()
    if not call.dataAvailable:
      break
    result.add(call.msg)

proc freePort(): int =
  ## Reserves an ephemeral loopback port for the fixture's sole listener.
  let socket = newSocket()
  defer: socket.close()
  socket.bindAddr(Port(0), "127.0.0.1")
  socket.getLocalAddr()[1].int

proc serveFixture(context: pointer) {.thread.} =
  ## Runs the production HTTP loop independently from the test client.
  let server {.cursor.} = cast[VoiceServer](context)
  server.serve()

proc startFixture(
  assets: string, key = "sk-server-test-secret",
  externalOrigin = "", tailscaleUser = "", requestTimeoutMs = 15000
): Fixture =
  ## Starts one local server with offline providers and a fresh request log.
  discard drainCalls()
  credentialReads.store(0)
  setKey(key)
  result = Fixture(server: newVoiceServer(
    assets, freePort(), testKey, testSecret, externalOrigin, tailscaleUser,
    requestTimeoutMs = requestTimeoutMs
  ))
  createThread(result.thread, serveFixture, cast[pointer](result.server))
  result.server.waitUntilReady()
  doAssert result.server.address == "127.0.0.1"

proc close(fixture: var Fixture) =
  ## Stops the listener and joins its owner before releasing the fixture.
  fixture.server.close()
  joinThread(fixture.thread)

proc request(
  server: VoiceServer, path = "/", verb = "GET", body = "",
  headers: seq[(string, string)] = @[], automaticHost = true
): Reply =
  ## Sends exact headers, including duplicates, through a real loopback socket.
  var entries = headers
  var hasHost = false
  for (name, value) in entries:
    if name.toLowerAscii() == "host":
      hasHost = true
  if automaticHost and not hasHost:
    entries.add(("Host", "127.0.0.1:" & $server.port))
  var bytes = verb & " " & path & " HTTP/1.1\r\nConnection: close\r\n"
  for (name, value) in entries:
    bytes.add(name & ": " & value & "\r\n")
  bytes.add("\r\n" & body)
  let socket = newSocket()
  defer: socket.close()
  socket.connect("127.0.0.1", Port(server.port), timeout = 5000)
  var response = ""
  try:
    socket.send(bytes)
    while true:
      let part = socket.recv(4096, timeout = 5000)
      if part.len == 0:
        break
      response.add(part)
  except OSError:
    # The HTTP parser may close malformed framing before dispatching a handler.
    if response.len == 0:
      return
    raise
  if response.len == 0:
    return
  let separator = response.find("\r\n\r\n")
  doAssert separator >= 0, response
  let lines = response[0 ..< separator].split("\r\n")
  result.status = parseInt(lines[0].splitWhitespace()[1])
  for i in 1 ..< lines.len:
    let colon = lines[i].find(':')
    doAssert colon > 0, lines[i]
    result.headers[lines[i][0 ..< colon].toLowerAscii()] =
      lines[i][colon + 1 .. ^1].strip()
  result.body = response[separator + 4 .. ^1]

proc token(
  server: VoiceServer, payload = %*{}, origin = true,
  headers: seq[(string, string)] = @[]
): Reply =
  ## Sends the browser's normal JSON exchange through the production listener.
  let body = $payload
  var entries = @[
    ("Content-Type", "application/json"), ("Content-Length", $body.len)
  ]
  if origin:
    entries.add(("Origin", "http://127.0.0.1:" & $server.port))
  entries.add(headers)
  server.request("/api/realtime/token", "POST", body, entries)

proc testLocal(assets: string, hasSymlinks: bool) =
  ## Checks assets, credential precedence, token routes, and request rejection.
  echo "Testing native Voice Lab localhost routes"
  var fixture = startFixture(assets)
  defer: fixture.close()
  let server = fixture.server
  let page = server.request()
  doAssert page.status == 200 and page.body == "Voice Lab test page"
  doAssert page.headers["cache-control"] == "no-store"
  doAssert page.headers["x-frame-options"] == "DENY"
  doAssert page.headers["x-content-type-options"] == "nosniff"
  doAssert page.headers["cross-origin-resource-policy"] == "same-origin"
  let wasm = server.request("/voice.wasm")
  doAssert wasm.status == 200
  doAssert wasm.headers["content-type"] == "application/wasm"
  doAssert wasm.body == "\0asm"
  doAssert server.request("/voice.data").status == 200
  let compressed = server.request("/large.js",
    headers = @[("Accept-Encoding", "gzip")])
  doAssert compressed.status == 200
  doAssert parseInt(compressed.headers["content-length"]) == compressed.body.len
  let decoded =
    if compressed.headers.getOrDefault("content-encoding") == "gzip":
      uncompress(compressed.body)
    else:
      compressed.body
  doAssert decoded == repeat("console.log('voice');\n", 100)
  let head = server.request("/voice.js", "HEAD")
  doAssert head.status == 200 and head.body.len == 0
  doAssert head.headers["content-length"] == "20"
  for path in [
    "/secret.key", "/tmp/", "/tmp/generated.c", "/../outside.js",
    "/%2e%2e/outside.js",
    "/%5c..%5coutside.js", "/voice.js%00", "/voice.js/", "/./voice.js"
  ]:
    doAssert server.request(path).status == 404, path
  if hasSymlinks:
    for path in ["/escape.js", "/alias.js"]:
      doAssert server.request(path).status == 404, path
  for headers in [
    @[("Host", "attacker.example")], @[("Host", "localhost:1")],
    @[("Host", "localhost:1"), ("Host", "localhost:1")]
  ]:
    doAssert server.request(headers = headers).status == 403
  doAssert server.request(automaticHost = false).status == 403
  let config = server.request("/api/config")
  doAssert config.status == 200
  let data = parseJson(config.body)
  doAssert data["keyAvailable"].getBool()
  doAssert data["model"].getStr() == DefaultModel
  doAssert "sk-server-test-secret" notin config.body
  doAssert not data.hasKey("apiKey")
  let secret = server.token(%*{"model": DefaultModel, "voice": "marin"})
  doAssert secret.status == 200
  doAssert secret.headers["cache-control"] == "no-store"
  doAssert parseJson(secret.body) ==
    %*{"value": "ek_test_only", "expires_at": 1234567890}
  doAssert drainCalls() == @[("sk-server-test-secret", DefaultModel, "marin")]
  doAssert "sk-server-test-secret" notin secret.body
  doAssert server.token(%*{"apiKey": "sk-ignored-test"}).status == 200
  doAssert drainCalls()[0].key == "sk-server-test-secret"
  setKey("")
  doAssert not parseJson(server.request("/api/config").body)["keyAvailable"].getBool()
  doAssert server.token().status == 400
  let supplied = server.token(%*{"apiKey": "sk-browser-test"})
  doAssert supplied.status == 200
  doAssert drainCalls()[0].key == "sk-browser-test"
  doAssert "sk-browser-test" notin supplied.body
  for payload in [
    %*{"apiKey": 123}, %*{"apiKey": "sk-test\r\nHeader: injected"},
    %*{"model": []}, %*{"voice": "voice\ninvalid"}, %*{"extra": true},
    %*{"apiKey": repeat('x', 4097)}
  ]:
    doAssert server.token(payload).status == 400, $payload
  let reads = credentialReads.load()
  doAssert server.token(origin = false).status == 403
  for origin in ["null", "http://evil.example", "http://localhost:1"]:
    doAssert server.token(origin = false,
      headers = @[("Origin", origin)]).status == 403
  doAssert server.token(headers = @[("Sec-Fetch-Site", "cross-site")]).status == 403
  doAssert server.token(headers = @[("Origin", "null")]).status == 403
  doAssert credentialReads.load() == reads
  doAssert drainCalls().len == 0
  let
    origin = ("Origin", "http://127.0.0.1:" & $server.port)
    common = @[origin, ("Content-Type", "application/json")]
  for lengths in [
    @[("Content-Length", "²")], @[("Content-Length", "-1")],
    @[("Content-Length", "999999999")],
    @[("Content-Length", "2"), ("Content-Length", "2")]
  ]:
    let reply = server.request(
      "/api/realtime/token", "POST", "{}", common & lengths
    )
    doAssert reply.status in [0, 400, 413], $lengths
  let chunked = server.request(
    "/api/realtime/token", "POST", "0\r\n\r\n",
    common & @[("Transfer-Encoding", "chunked")]
  )
  doAssert chunked.status in [0, 400, 413]
  doAssert server.request("/api/realtime/token", "POST", "{}",
    @[origin, ("Content-Length", "2")]).status == 415
  for body in ["x!", "[]", "null", repeat('[', 65) & repeat(']', 65),
    "{\"apiKey\":\"\xff\"}"]:
    doAssert server.request("/api/realtime/token", "POST", body,
      common & @[("Content-Length", $body.len)]).status == 400
  doAssert server.request("http://[", "POST", "{}",
    common & @[("Content-Length", "2")]).status in [0, 400]
  doAssert drainCalls().len == 0

proc testFraming(assets: string) =
  ## Keeps exact application-level errors for framing rejected by the parser.
  echo "Testing native Voice Lab request framing validation"
  var fixture = startFixture(assets)
  defer: fixture.close()
  let
    server = fixture.server
    host = "127.0.0.1:" & $server.port
    common = @[("Host", host), ("Origin", "http://" & host),
      ("Content-Type", "application/json")]
  for lengths in [
    @[("Content-Length", "²")], @[("Content-Length", "-1")],
    @[("Content-Length", "999999999")],
    @[("Content-Length", "2"), ("Content-Length", "2")],
    @[("Transfer-Encoding", "chunked")], newSeq[(string, string)](),
    @[("Content-Length", "0")], @[("Content-Length", "3")]
  ]:
    let reply = server.handle("POST", "/api/realtime/token",
      HttpHeaders(common & lengths), "{}")
    doAssert reply.status in [400, 413], $lengths
  doAssert credentialReads.load() == 0 and drainCalls().len == 0

proc testRequestTimeout(assets: string) =
  ## Closes stalled headers and bodies before invoking credential providers.
  echo "Testing native Voice Lab stalled-request deadlines"
  var fixture = startFixture(assets, requestTimeoutMs = 100)
  defer: fixture.close()
  let server = fixture.server
  for partial in [
    "GET / HTTP/1.1\r\nHost: 127.0.0.1:" & $server.port & "\r\n",
    "POST /api/realtime/token HTTP/1.1\r\nHost: 127.0.0.1:" & $server.port &
      "\r\nContent-Type: application/json\r\nContent-Length: 20\r\n" &
      "Origin: http://127.0.0.1:" & $server.port & "\r\n\r\n{"
  ]:
    let socket = newSocket()
    defer: socket.close()
    socket.connect("127.0.0.1", Port(server.port), timeout = 3000)
    let started = getMonoTime()
    socket.send(partial)
    doAssert socket.recv(1, timeout = 3000).len == 0
    doAssert (getMonoTime() - started).inMilliseconds < 1500
  doAssert credentialReads.load() == 0 and drainCalls().len == 0

proc testKeySources(root: string) =
  ## Uses a disposable key file while preserving the inherited environment.
  echo "Testing native Voice Lab credential source precedence"
  let
    existed = existsEnv("OPENAI_API_KEY")
    saved = getEnv("OPENAI_API_KEY")
    path = root / "test-openai.key"
  defer:
    if existed: putEnv("OPENAI_API_KEY", saved)
    else: delEnv("OPENAI_API_KEY")
  writeFile(path, " sk-file-test \n")
  putEnv("OPENAI_API_KEY", "")
  doAssert configuredKey(path) == "sk-file-test"
  doAssert configuredKey(root / "missing.key") == ""
  putEnv("OPENAI_API_KEY", " sk-environment-test ")
  doAssert configuredKey(path) == "sk-environment-test"

proc testTailscale(assets: string) =
  ## Requires the configured proxy host, origin, and optional single identity.
  echo "Testing native Voice Lab Tailscale authorization"
  const
    Host = "voice.example.ts.net:8443"
    Origin = "https://" & Host
    Owner = "owner@example.com"
  let proxy = @[("Host", Host), ("Tailscale-User-Login", Owner)]
  block:
    var fixture = startFixture(assets, "sk-proxy-test-secret", Origin, Owner)
    defer: fixture.close()
    let server = fixture.server
    doAssert server.request(headers = proxy).status == 200
    doAssert server.request("/voice.js", "HEAD", headers = proxy).status == 200
    let config = server.request("/api/config", headers = proxy)
    doAssert config.status == 200
    doAssert parseJson(config.body)["keyAvailable"].getBool()
    doAssert "sk-proxy-test-secret" notin config.body
    let secret = server.token(origin = false,
      headers = proxy & @[("Origin", Origin)])
    doAssert secret.status == 200
    doAssert parseJson(secret.body)["value"].getStr() == "ek_test_only"
    doAssert drainCalls() == @[("sk-proxy-test-secret", DefaultModel, DefaultVoice)]
    doAssert credentialReads.load() == 2
    for identity in [
      newSeq[(string, string)](), @[("Tailscale-User-Login", "other@example.com")],
      @[("Tailscale-User-Login", Owner), ("Tailscale-User-Login", Owner)],
      @[("Tailscale-User-Login", Owner & ",other@example.com")]
    ]:
      let headers = @[("Host", Host)] & identity
      for route in [("/", "GET"), ("/api/config", "GET"),
        ("/", "HEAD"), ("/api/config", "HEAD")]:
          doAssert server.request(route[0], route[1], headers = headers).status == 403
      doAssert server.token(origin = false,
        headers = headers & @[("Origin", Origin)]).status == 403
    for hosts in [
      newSeq[(string, string)](), @[("Host", "attacker.example")],
      @[("Host", "voice.example.ts.net")], @[("Host", Host), ("Host", Host)],
      @[("Host", "attacker.example"), ("X-Forwarded-Host", Host)]
    ]:
      let headers = hosts & @[("Tailscale-User-Login", Owner)]
      doAssert server.request("/api/config", headers = headers).status == 403
      doAssert server.token(origin = false,
        headers = headers & @[("Origin", Origin)]).status == 403
    for origins in [
      newSeq[(string, string)](), @[("Origin", "null")],
      @[("Origin", "http://" & Host)], @[("Origin", "https://voice.example.ts.net")],
      @[("Origin", "https://voice.example.ts.net.attacker.example:8443")],
      @[("Origin", Origin), ("Origin", Origin)],
      @[("Origin", "https://attacker.example"), ("X-Forwarded-Host", Host)],
      @[("Origin", Origin), ("Sec-Fetch-Site", "cross-site")]
    ]:
      doAssert server.token(origin = false,
        headers = proxy & origins).status == 403
    doAssert credentialReads.load() == 2
    doAssert drainCalls().len == 0
  block:
    var fixture = startFixture(assets, "sk-shared-test-secret", Origin)
    defer: fixture.close()
    let server = fixture.server
    for identity in [
      newSeq[(string, string)](), @[("Tailscale-User-Login", "friend@example.com")]
    ]:
      let headers = @[("Host", Host)] & identity
      doAssert server.request(headers = headers).status == 200
      doAssert server.request("/voice.js", "HEAD", headers = headers).status == 200
      let config = server.request("/api/config", headers = headers)
      doAssert config.status == 200
      doAssert parseJson(config.body)["keyAvailable"].getBool()
      let secret = server.token(origin = false,
        headers = headers & @[("Origin", Origin)])
      doAssert secret.status == 200 and "sk-shared-test-secret" notin secret.body
    doAssert drainCalls().len == 2 and credentialReads.load() == 4
    doAssert server.request(headers = @[("Host", "attacker.example")]).status == 403
    for headers in [
      @[("Host", "attacker.example"), ("Origin", Origin)],
      @[("Host", Host), ("Origin", "https://attacker.example")],
      @[("Host", Host)]
    ]:
      doAssert server.token(origin = false, headers = headers).status == 403
    doAssert drainCalls().len == 0 and credentialReads.load() == 4

proc testConfiguration(assets: string) =
  ## Rejects malformed proxy origins before opening any listener or provider.
  echo "Testing native Voice Lab origin configuration"
  for origin in [
    "", "http://voice.example.ts.net:8443", "//voice.example.ts.net:8443",
    "https:///", "https://voice.example.ts.net:8443/",
    "https://voice.example.ts.net:8443/path", "https://voice.example.ts.net:8443?x=1",
    "https://voice.example.ts.net:8443#fragment",
    "https://owner@voice.example.ts.net:8443",
    "https://owner:password@voice.example.ts.net:8443",
    "https://voice.example.ts.net:invalid", "https://voice.example.ts.net:0",
    "https://voice.example.ts.net:65536", "https://["
  ]:
    var rejected = false
    try:
      let server = newVoiceServer(
        assets, freePort(), testKey, testSecret, origin, "owner@example.com"
      )
      server.close()
    except ValueError, VoiceServerError:
      rejected = true
    doAssert rejected, origin

proc testLifecycle(assets: string) =
  ## Covers cleanup before serving and a failed bind without double disposal.
  echo "Testing native Voice Lab pre-start and failed-bind cleanup"
  block:
    let server = newVoiceServer(assets, freePort(), testKey, testSecret)
    server.close()
    server.close()
    var rejected = false
    try:
      server.serve()
    except ValueError:
      rejected = true
    doAssert rejected
  block:
    let listener = newSocket()
    defer: listener.close()
    listener.bindAddr(Port(0), "127.0.0.1")
    listener.listen()
    let server = newVoiceServer(
      assets, listener.getLocalAddr()[1].int, testKey, testSecret
    )
    var rejected = false
    try:
      server.serve()
    except CatchableError:
      rejected = true
    doAssert rejected
    server.close()
    server.close()

proc testResponses() =
  ## Validates bounded upstream JSON while removing key-bearing error text.
  echo "Testing native Voice Lab upstream token validation"
  const Credential = "sk-redaction-test-secret"
  let secret = parseSecret(200,
    $(%*{"value": "ek-short-lived", "expires_at": 123, "internal": Credential}),
    Credential)
  doAssert secret.value == "ek-short-lived" and secret.expires_at == 123
  for status in [401, 429]:
    let body = $(%*{"error": {
      "message": "Incorrect key " & Credential & " or sk-part***test",
      "code": "invalid_api_key"
    }})
    var rejected = false
    try:
      discard parseSecret(status, body, Credential)
    except VoiceServerError as error:
      rejected = true
      doAssert error.status == status
      doAssert Credential notin error.msg and "sk-part" notin error.msg
      doAssert error.code == "invalid_api_key"
    doAssert rejected
  let unicodeBody = $(%*{"error": {
    "message": repeat("界", 1995) & " " & Credential & " " & repeat("é", 100),
    "code": "invalid_api_key"
  }})
  var unicodeRejected = false
  try:
    discard parseSecret(401, unicodeBody, Credential)
  except VoiceServerError as error:
    unicodeRejected = true
    doAssert error.status == 401
    doAssert error.msg.validateUtf8() == -1
    doAssert error.msg.runeLen() <= 2000
    doAssert Credential notin error.msg
    doAssert parseJson($(%*{"error": {"message": error.msg}}))["error"][
      "message"].getStr() == error.msg
  doAssert unicodeRejected
  for body in [
    "", "not JSON", "{}", "[]", "null",
    "{\"value\":\"ek-test\",\"expires_at\":true}",
    "{\"value\":\"\",\"expires_at\":123}",
    $(%*{"value": repeat('x', 8193), "expires_at": 123}),
    repeat('x', MaxResponseBytes + 1)
  ]:
    var rejected = false
    try:
      discard parseSecret(200, body, Credential)
    except VoiceServerError as error:
      rejected = true
      doAssert error.status == 502
    doAssert rejected

proc upstream() {.thread.} =
  ## Receives one real Curly request and returns a synthetic bounded response.
  let listener = newSocket()
  defer: listener.close()
  listener.bindAddr(Port(0), "127.0.0.1")
  listener.listen()
  upstreamPorts.send(listener.getLocalAddr()[1].int)
  var socket: Socket
  listener.accept(socket)
  defer: socket.close()
  var
    received = socket.recvLine(timeout = 5000) & "\n"
    length = 0
  while true:
    let line = socket.recvLine(timeout = 5000)
    if line.len == 0 or line == "\r\n":
      break
    received.add(line & "\n")
    if line.toLowerAscii().startsWith("content-length:"):
      length = parseInt(line.split(':', 1)[1].strip())
  received.add("\n")
  var body = ""
  while body.len < length:
    let part = socket.recv(length - body.len, timeout = 5000)
    doAssert part.len > 0
    body.add(part)
  received.add(body)
  upstreamRequests.send(received)
  let reply = "{\"value\":\"ek-short-lived\",\"expires_at\":123}"
  socket.send("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n" &
    "Content-Length: " & $reply.len & "\r\nConnection: close\r\n\r\n" & reply)

proc testExchange() =
  ## Verifies the real HTTP exchange uses only the intended credential and JSON.
  echo "Testing native Voice Lab HTTP token exchange against loopback"
  var thread: Thread[void]
  createThread(thread, upstream)
  let port = upstreamPorts.recv()
  let secret = createSecret("sk-redaction-test-secret", DefaultModel, "marin",
    "http://127.0.0.1:" & $port & "/v1/realtime/client_secrets")
  joinThread(thread)
  doAssert secret.value == "ek-short-lived" and secret.expires_at == 123
  let received = upstreamRequests.recv()
  doAssert received.startsWith("POST /v1/realtime/client_secrets HTTP/1.1\n")
  doAssert "authorization: Bearer sk-redaction-test-secret\n" in
    received.replace("Authorization:", "authorization:")
  let body = parseJson(received[received.find("\n\n") + 2 .. ^1])
  doAssert body == %*{"session": {
    "type": "realtime", "model": DefaultModel,
    "audio": {"output": {"voice": "marin"}}
  }}
  var rejected = false
  try:
    discard createSecret("sk-redaction-test-secret", DefaultModel, "marin",
      "http://127.0.0.1:" & $port & "/offline")
  except VoiceServerError as error:
    rejected = true
    doAssert error.status == 502
    doAssert "sk-redaction-test-secret" notin error.msg
  doAssert rejected

proc run() =
  ## Exercises only disposable assets, loopback services, and synthetic keys.
  let
    root = createTempDir("voice-web-test-", "")
    modelExisted = existsEnv("OPENAI_REALTIME_MODEL")
    modelSaved = getEnv("OPENAI_REALTIME_MODEL")
    voiceExisted = existsEnv("OPENAI_REALTIME_VOICE")
    voiceSaved = getEnv("OPENAI_REALTIME_VOICE")
  defer:
    removeDir(root)
    if modelExisted: putEnv("OPENAI_REALTIME_MODEL", modelSaved)
    else: delEnv("OPENAI_REALTIME_MODEL")
    if voiceExisted: putEnv("OPENAI_REALTIME_VOICE", voiceSaved)
    else: delEnv("OPENAI_REALTIME_VOICE")
  putEnv("OPENAI_REALTIME_MODEL", DefaultModel)
  putEnv("OPENAI_REALTIME_VOICE", DefaultVoice)
  let assets = root / "emscripten"
  createDir(assets / "tmp")
  writeFile(assets / "voice.html", "Voice Lab test page")
  writeFile(assets / "voice.js", "console.log('test');")
  writeFile(assets / "large.js", repeat("console.log('voice');\n", 100))
  writeFile(assets / "voice.wasm", "\0asm")
  writeFile(assets / "voice.data", "assets")
  writeFile(assets / "secret.key", "should not be served")
  writeFile(assets / "tmp/generated.c", "source code")
  writeFile(root / "outside.js", "private outside artifact")
  var hasSymlinks = true
  try:
    createSymlink(root / "outside.js", assets / "escape.js")
    createSymlink(assets / "voice.js", assets / "alias.js")
  except OSError as error:
    when defined(windows):
      if error.errorCode != 1314: # ERROR_PRIVILEGE_NOT_HELD
        raise
      hasSymlinks = false
      echo "Skipping symlink fixtures: Windows requires symlink permission."
    else:
      raise
  testLocal(assets, hasSymlinks)
  testFraming(assets)
  testRequestTimeout(assets)
  testTailscale(assets)
  testConfiguration(assets)
  testLifecycle(assets)
  testKeySources(root)
  testResponses()
  testExchange()

initLock(credentialLock)
secretCalls.open()
upstreamPorts.open()
upstreamRequests.open()
run()
upstreamRequests.close()
upstreamPorts.close()
secretCalls.close()
deinitLock(credentialLock)
echo "Voice web server tests passed using loopback and synthetic credentials."
