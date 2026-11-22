import
  std/[atomics, monotimes, net, os, strutils, times],
  polyworld/llms

var
  ports: Channel[int]
  threadFinished: Atomic[bool]

proc sendHeaders(socket: Socket, length: int) =
  ## Identifies HTTP/1 before delaying a body for an out-of-order reply.
  socket.send("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n" &
    "Content-Length: " & $length & "\r\nConnection: close\r\n\r\n")

proc sendReply(socket: Socket, body: string) =
  ## Echoes request data so response routing can be checked without a model.
  socket.sendHeaders(body.len)
  socket.send(body)

proc serve() {.thread.} =
  ## Replies to paired requests in reverse order and delays selected replies.
  let server = newSocket()
  server.bindAddr(Port(0), "127.0.0.1")
  server.listen()
  ports.send(server.getLocalAddr()[1].int)
  var
    paired: Socket
    pairedBody: string
  while true:
    var socket: Socket
    server.accept(socket)
    let first = socket.recvLine(timeout = 3000)
    if first.contains("/stop"):
      socket.close()
      break
    var length = 0
    while true:
      let line = socket.recvLine(timeout = 3000)
      if line.len == 0 or line == "\r\n":
        break
      if line.toLowerAscii().startsWith("content-length:"):
        length = parseInt(line.split(':', 1)[1].strip())
    var body: string
    while body.len < length:
      body.add socket.recv(length - body.len, timeout = 3000)
    if first.contains("/pair"):
      if paired == nil:
        paired = socket
        pairedBody = body
        paired.sendHeaders(body.len)
        continue
      socket.sendReply(body)
      socket.close()
      paired.send(pairedBody)
      paired.close()
      paired = nil
      pairedBody.setLen(0)
    else:
      if first.contains("/slow"):
        sleep(120)
      socket.sendReply(body)
      socket.close()
  doAssert paired == nil, "A paired request was left unanswered."
  server.close()
  ports.close()
  reset(ports)

proc client(port: int, timeoutMs = 3000): LlmClient =
  ## Uses only a local fixture while retaining normal native transport behavior.
  newLlmClient(0, LlmConfig(
    baseUrl: "http://127.0.0.1:" & $port,
    interval: 1, timeoutMs: timeoutMs
  ))

proc settle(client: LlmClient, request: int32, tick = 1'i32) =
  ## Bounds polling while preserving each client's independent request state.
  let deadline = getMonoTime() + initDuration(seconds = 3)
  while client.poll(request) == 0:
    doAssert getMonoTime() < deadline, "Request did not settle."
    client.beginTick(tick)
    sleep(1)

proc useOnCallerThread(port: int) {.thread.} =
  ## Releases a short-lived caller's logical client before that thread exits.
  let connection = client(port)
  connection.beginTick(0)
  let id = connection.ask("POST", "/v1/echo", "{\"thread\":true}")
  connection.settle(id)
  doAssert connection.response(id) == "{\"thread\":true}"
  connection.close()
  threadFinished.store(true)

ports.open()
var server: Thread[void]
createThread(server, serve)
let port = ports.recv()

echo "Testing shared transport keeps interleaved client replies separate"
block:
  let
    first = client(port)
    second = client(port)
  # PIPEWAIT can serialize HTTP/1 requests to one origin until it responds.
  second.config.baseUrl = "http://localhost:" & $port
  first.beginTick(0)
  second.beginTick(0)
  let
    firstId = first.ask("POST", "/v1/pair", "{\"name\":\"first\"}")
    secondId = second.ask("POST", "/v1/pair", "{\"name\":\"second\"}")
  doAssert firstId == 1 and secondId == 1
  second.settle(secondId)
  first.settle(firstId)
  doAssert first.poll(firstId) == 1, first.error(firstId)
  doAssert second.poll(secondId) == 1, second.error(secondId)
  doAssert first.response(firstId) == "{\"name\":\"first\"}"
  doAssert second.response(secondId) == "{\"name\":\"second\"}"
  first.close()
  second.close()

echo "Testing closing one client preserves another pending reply"
block:
  let
    closing = client(port)
    waiting = client(port)
  waiting.config.baseUrl = "http://localhost:" & $port
  closing.beginTick(0)
  waiting.beginTick(0)
  let
    discarded = closing.ask("POST", "/v1/pair", "{\"discard\":true}")
    wanted = waiting.ask("POST", "/v1/pair", "{\"keep\":true}")
  closing.close()
  doAssert closing.poll(discarded) == -1
  doAssert closing.response(discarded) == ""
  waiting.settle(wanted)
  doAssert waiting.response(wanted) == "{\"keep\":true}"
  closing.beginTick(1)
  let reopened = closing.ask("POST", "/v1/echo", "{\"reopened\":true}")
  closing.settle(reopened)
  doAssert closing.response(reopened) == "{\"reopened\":true}"
  closing.close()
  waiting.close()

echo "Testing late replies cannot replace timed-out or reset requests"
for resetting in [false, true]:
  let
    stale = client(port, if resetting: 3000 else: 20)
    other = client(port)
  stale.beginTick(10)
  let abandoned = stale.ask("POST", "/v1/slow", "{\"stale\":true}")
  if resetting:
    stale.beginTick(0)
  else:
    stale.settle(abandoned, 10)
    doAssert stale.error(abandoned).contains("timed out")
  doAssert stale.poll(abandoned) == -1
  doAssert stale.ready == -1
  doAssert stale.ask("POST", "/v1/echo", "{}") == 0
  other.beginTick(0)
  let current = other.ask("POST", "/v1/echo", "{\"current\":true}")
  other.settle(current)
  doAssert other.response(current) == "{\"current\":true}"
  stale.beginTick(if resetting: 0 else: 12)
  doAssert stale.ready == 0
  doAssert stale.poll(abandoned) == -1
  doAssert stale.response(abandoned) == ""
  let replacement = stale.ask("POST", "/v1/echo", "{\"replacement\":true}")
  stale.settle(replacement, if resetting: 0 else: 12)
  doAssert replacement > abandoned
  doAssert stale.response(replacement) == "{\"replacement\":true}"
  stale.close()
  other.close()

echo "Testing repeated logical clients reuse the live transport safely"
for i in 0 ..< 32:
  let connection = client(port)
  connection.beginTick(0)
  let
    expected = "{\"iteration\":" & $i & "}"
    id = connection.ask("POST", "/v1/echo", expected)
  doAssert id == 1
  if i mod 2 == 0:
    connection.close()
    doAssert connection.response(id) == ""
  else:
    connection.settle(id)
    var retained = connection.response(id)
    connection.close()
    doAssert retained == expected
    retained.add repeat('!', 2048)

echo "Testing the transport survives a caller thread exiting"
var caller: Thread[int]
createThread(caller, useOnCallerThread, port)
joinThread(caller)
doAssert threadFinished.load()
block:
  let connection = client(port)
  connection.beginTick(0)
  let id = connection.ask("POST", "/v1/echo", "{\"afterThread\":true}")
  connection.settle(id)
  doAssert connection.response(id) == "{\"afterThread\":true}"
  connection.close()

let stop = newSocket()
stop.connect("127.0.0.1", Port(port))
stop.send("GET /stop HTTP/1.1\r\n\r\n")
stop.close()
joinThread(server)
echo "LLM transport reuse and isolation passed"
