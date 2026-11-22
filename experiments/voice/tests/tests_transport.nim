import std/[asyncnet, net]
include ../realtimes

const
  TestKey = "local-transport-test"
  SessionError = "Unknown parameter: 'session.model'."
  ModelError = "The model 'unavailable-test-model' does not exist."

type
  Fixture = ref object
    listener: AsyncSocket
    peer: WebSocket
    endpoint: string

proc newFixture(): Fixture =
  ## Binds an ephemeral loopback port without external credentials.
  let listener = newAsyncSocket()
  listener.bindAddr(Port(0), "127.0.0.1")
  listener.listen()
  Fixture(
    listener: listener,
    endpoint: "http://127.0.0.1:" & $listener.getLocalAddr()[1] & "/realtime"
  )

proc acceptUpgrade(fixture: Fixture) {.async.} =
  ## Accepts the real client handshake and opens a local WebSocket peer.
  let peer = await fixture.listener.accept()
  var socketKey = ""
  while true:
    let line = await peer.recvLine()
    if line == "\r\n" or line.len == 0:
      break
    if line.toLowerAscii().startsWith("sec-websocket-key:"):
      socketKey = line.split(':', 1)[1].strip()
  doAssert socketKey.len > 0, "Client omitted its upgrade key"
  let accept = base64.encode(ws.decodeBase16($secureHash(
    socketKey & "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
  )))
  await peer.send("HTTP/1.1 101 Switching Protocols\r\n" &
    "Connection: Upgrade\r\nUpgrade: websocket\r\n" &
    "Sec-WebSocket-Accept: " & accept & "\r\n\r\n")
  fixture.peer = WebSocket(tcpSocket: peer, readyState: Open)

proc configure(fixture: Fixture) {.async.} =
  ## Drives the normal created, update, updated session exchange.
  await fixture.acceptUpgrade()
  await fixture.peer.send("{\"type\":\"session.created\"}")
  let update = (await fixture.peer.receiveStrPacket()).fromJson(JsonNode)
  doAssert update{"type"}.getStr() == "session.update"

proc close(fixture: Fixture) =
  ## Releases both sides of the local fixture.
  if fixture.peer != nil:
    fixture.peer.hangup()
  fixture.listener.close()

proc start(client: VoiceClient, fixture: Fixture): Future[void] =
  ## Starts the production transport against the local fake service.
  client.disconnect()
  client.state = Connecting
  client.connectedAt = epochTime()
  client.run(client.generation, TestKey, fixture.endpoint)

proc finish(future: Future[void]) {.async.} =
  ## Requires shutdown to settle without unobserved asynchronous failures.
  doAssert await future.withTimeout(2000), "Transport did not shut down"
  await future
  await sleepAsync(20)

proc waitReady(client: VoiceClient) {.async.} =
  ## Waits for an acknowledged session with a bounded test deadline.
  let deadline = epochTime() + 2
  while client.state == Connecting and epochTime() < deadline:
    await sleepAsync(1)
  doAssert client.state == Connected, client.status

proc rejectSession() {.async.} =
  ## Reproduces a service rejection followed by local transport shutdown.
  let
    fixture = newFixture()
    client = newVoiceClient()
    accepted = fixture.configure()
    running = client.start(fixture)
  try:
    await accepted
    await fixture.peer.send((%*{
      "type": "error",
      "error": {
        "type": "invalid_request_error",
        "code": "unknown_parameter",
        "param": "session.model",
        "message": SessionError & " Credential: " & TestKey
      }
    }).toJson())
    await running.finish()
    doAssert client.state == Failed
    doAssert "unknown_parameter" in client.status, client.status
    doAssert "session.model" in client.status, client.status
    doAssert SessionError in client.status, client.status
    doAssert TestKey notin client.status, "Credential appeared in an error"
    doAssert "[redacted]" in client.status, client.status
    doAssert client.credential.len == 0
  finally:
    client.disconnect()
    fixture.close()

proc rejectUpgrade(fixture: Fixture) {.async.} =
  ## Returns a structured model error before the WebSocket upgrade.
  let peer = await fixture.listener.accept()
  fixture.peer = WebSocket(tcpSocket: peer, readyState: Open)
  while true:
    let line = await peer.recvLine()
    if line == "\r\n" or line.len == 0:
      break
  let body = (%*{"error": {
    "type": "invalid_request_error",
    "code": "model_not_found",
    "param": "model",
    "message": ModelError
  }}).toJson()
  await peer.send("HTTP/1.1 404 Not Found\r\n" &
    "Content-Type: application/json\r\n" &
    "Content-Length: " & $body.len & "\r\n\r\n" & body)

proc rejectedModel() {.async.} =
  ## Preserves actionable error details from an unsuccessful HTTP upgrade.
  let
    fixture = newFixture()
    client = newVoiceClient()
    rejected = fixture.rejectUpgrade()
    running = client.start(fixture)
  try:
    await rejected
    await running.finish()
    doAssert client.state == Failed
    doAssert "404" in client.status, client.status
    doAssert "model_not_found" in client.status, client.status
    doAssert ModelError in client.status, client.status
  finally:
    client.disconnect()
    fixture.close()

proc disconnectDuringFrame(fragment: string) {.async.} =
  ## Cancels a pending receive at each variable-length frame boundary.
  let
    fixture = newFixture()
    client = newVoiceClient()
    accepted = fixture.configure()
    running = client.start(fixture)
  try:
    await accepted
    await fixture.peer.send("{\"type\":\"session.updated\"}")
    await client.waitReady()
    if fragment.len > 0:
      await fixture.peer.tcpSocket.send(fragment)
    await sleepAsync(5)
    client.disconnect()
    await running.finish()
    doAssert client.state == Disconnected
    doAssert client.status == "Disconnected."
  finally:
    client.disconnect()
    fixture.close()

proc peerClose() {.async.} =
  ## Requires an unexpected peer closure to fail without crashing.
  let
    fixture = newFixture()
    client = newVoiceClient()
    accepted = fixture.configure()
    running = client.start(fixture)
  try:
    await accepted
    await fixture.peer.send("{\"type\":\"session.updated\"}")
    await client.waitReady()
    fixture.peer.hangup()
    await running.finish()
    doAssert client.state == Failed
  finally:
    client.disconnect()
    fixture.close()

proc reconnectDuringReceive() {.async.} =
  ## Keeps an old receive completion from damaging a replacement session.
  let
    oldFixture = newFixture()
    newFixture = newFixture()
    client = newVoiceClient()
    oldAccepted = oldFixture.configure()
    oldRunning = client.start(oldFixture)
  try:
    await oldAccepted
    await oldFixture.peer.send("{\"type\":\"session.updated\"}")
    await client.waitReady()
    await oldFixture.peer.tcpSocket.send("\x81\x7e\x00")
    await sleepAsync(5)
    let
      newAccepted = newFixture.configure()
      newRunning = client.start(newFixture)
    await newAccepted
    await newFixture.peer.send("{\"type\":\"session.updated\"}")
    await client.waitReady()
    await oldRunning.finish()
    doAssert client.state == Connected, client.status
    client.disconnect()
    await newRunning.finish()
  finally:
    client.disconnect()
    oldFixture.close()
    newFixture.close()

echo "Testing session rejection preserves details and closes safely"
waitFor rejectSession()
echo "Testing structured HTTP model rejection"
waitFor rejectedModel()
echo "Testing disconnect during pending header, length, and payload reads"
for fragment in [
  "", "\x81", "\x81\x7e\x00", "\x81\x7f\x00", "\x81\x0aabc"
]:
  waitFor disconnectDuringFrame(fragment)
echo "Testing peer closure and reconnect with an old pending receive"
waitFor peerClose()
waitFor reconnectDuringReceive()
echo "Realtime transport regression tests passed"
