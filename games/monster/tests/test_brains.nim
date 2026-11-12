import
  std/[json, monotimes, net, os, strutils, tempfiles, times],
  polyworld/llms,
  ../[brains, common]

const
  Observation = """{"x":0,"z":0,"energy":90,"cargo":{},
    "places":[{"id":"village","name":"Willow hall","x":8,"z":2},
    {"id":"berries","name":"Wild berry patch","x":-7,"z":5}],
    "households":[{"id":"mason_hut","name":"Mason's hut",
    "integrity":45,"stock":{"stone":0,"oak":0}}],
    "villagers":[{"id":"eli","name":"Eli","hunger":70,
    "activity":"Gathering stone"}]}"""
  Lesson = "I gather wild berries when helping hungry villagers."
  Explanation = "I can't find a way across the river from here."
  InventedLesson = "I should always swim across rivers."

var
  ports: Channel[int]
  requests: Channel[string]
  credentials: Channel[string]

proc action(kind, target: string, x = 0.0, z = 0.0): JsonNode =
  ## Creates a complete structured physical action for parser tests.
  %*{
    "kind": kind, "target": target, "x": x, "z": z, "duration": 0
  }

proc answer(): JsonNode =
  ## Creates a useful food-gathering decision and its explicit standing lesson.
  let gather = action("gather", "berries")
  %*{
    "speech": "I'll gather wild berries and bring them to the village.",
    "actions": [gather], "lessons": [Lesson]
  }

proc envelope(reply: JsonNode): string =
  ## Wraps generated JSON in the Responses API's message envelope.
  let body = $reply
  $(%*{
    "object": "response", "status": "completed", "output": [{
      "type": "message", "role": "assistant", "content": [{
        "type": "output_text", "text": body
      }]
    }]
  })

proc sendReply(socket: Socket, body: string, status = "200 OK") =
  ## Sends a bounded JSON response from the local inference fixture.
  socket.send("HTTP/1.1 " & status &
    "\r\nContent-Type: application/json\r\nContent-Length: " & $body.len &
    "\r\nConnection: close\r\n\r\n" & body)

proc serve() {.thread.} =
  ## Emulates success, malformed plans, incomplete output, and HTTP failures.
  let server = newSocket()
  server.bindAddr(Port(0), "127.0.0.1")
  server.listen()
  ports.send(int(server.getLocalAddr()[1]))
  while true:
    var socket: Socket
    server.accept(socket)
    defer:
      socket.close()
    let first = socket.recvLine(timeout = 3000)
    if first.contains("/stop"):
      break
    var
      length = 0
      authorization: string
    while true:
      let line = socket.recvLine(timeout = 3000)
      if line.len == 0 or line == "\r\n":
        break
      if line.toLowerAscii().startsWith("content-length:"):
        length = parseInt(line.split(':', 1)[1].strip())
      elif line.toLowerAscii().startsWith("authorization:"):
        authorization = line.split(':', 1)[1].strip()
    var body: string
    while body.len < length:
      body.add socket.recv(length - body.len, timeout = 3000)
    requests.send(first & "\n" & body)
    let current = parseDocument(body)["input"].elems[^1]{"content"}.getStr()
    if current.contains("auth-"):
      credentials.send(authorization)
    if current.contains("http-failure"):
      socket.sendReply("{}", "429 Too Many Requests")
    elif current.contains("auth-") and
      authorization != "Bearer fixture-working-key":
        socket.sendReply("{}", "401 Unauthorized")
    elif current.contains("bad-plan"):
      var reply = answer()
      reply["actions"][0]["target"] = %"imaginary-castle"
      socket.sendReply(envelope(reply))
    elif current.contains("incomplete-output"):
      socket.sendReply("""{"status":"incomplete","output":[]}""")
    elif current.contains("[Explain action feedback]"):
      var reply = answer()
      reply["speech"] = %Explanation
      reply["lessons"] = %(@[InventedLesson])
      socket.sendReply(envelope(reply))
    else:
      socket.sendReply(envelope(answer()))
  server.close()
  # Channels grow on this thread. Free their buffers before its allocator exits.
  ports.close()
  requests.close()
  credentials.close()
  # Channel.close does not clear its old buffer pointer for a later open.
  reset(ports)
  reset(requests)
  reset(credentials)

proc receiveCopy(channel: var Channel[string]): string =
  ## Keeps fixture observations valid after the server thread has stopped.
  let received = channel.recv()
  result = newString(received.len)
  if received.len > 0:
    copyMem(result[0].addr, received[0].unsafeAddr, received.len)

proc settle(brain: Brain, tick: var int32, seconds = 5): bool =
  ## Polls without blocking the simulation API and bounds fixture failures.
  let deadline = getMonoTime() + initDuration(seconds = seconds)
  while brain.pending:
    doAssert getMonoTime() < deadline, "creature request did not settle"
    inc tick
    if brain.pollBrain(tick):
      result = true
    sleep(2)

proc rejects(body: JsonNode) =
  ## Requires malformed model output to fail before any actions can execute.
  var rejected = false
  try:
    discard parseReply($body)
  except MonsterError:
    rejected = true
  doAssert rejected, "malformed creature reply was accepted"

proc roleCount(brain: Brain, role: MessageRole): int =
  ## Counts recorded speakers without depending on internal feedback ordering.
  for message in brain.messages:
    if message.role == role:
      inc result

echo "Testing bounded creature decisions"
block:
  let parsed = parseReply($answer())
  doAssert parsed.actions.len == 1
  doAssert parsed.actions[0].kind == GatherAction
  doAssert parsed.actions[0].target == "berries"
  doAssert parsed.lessons == @[Lesson]
  for invalid in [
    action("teleport", "village"),
    action("order", "ada"),
    action("repair", "mason_hut"),
    action("move", "missing"),
    action("move", "", 32, 0),
    action("move", "", 0, -32),
    action("gather", "village"),
    action("gather", "miller_hut"),
    action("gather", "ada"),
    action("give", "farm"),
    action("rest", "river"),
    action("eat", "berries")
  ]:
    var reply = answer()
    reply["actions"].elems[0] = invalid
    rejects(reply)
  block:
    var reply = answer()
    reply["actions"][0]["duration"] = %31
    rejects(reply)
  block:
    var reply = answer()
    reply["actions"][0]["x"] = %"0"
    rejects(reply)
  block:
    var reply = answer()
    reply["actions"] = newJArray()
    for i in 0 .. MaxActions:
      reply["actions"].add action("wait", "")
    rejects(reply)
  block:
    var reply = answer()
    reply["lessons"] = %(@[repeat('x', 321)])
    rejects(reply)
  var rejected = false
  try:
    discard parseReply("broken json")
  except MonsterError:
    rejected = true
  doAssert rejected

echo "Testing resource sources and individual delivery targets"
block:
  for source in ["berries", "farm", "fish", "pine", "oak", "stone"]:
    var reply = answer()
    reply["actions"] = %*[action("move", source), action("gather", source)]
    let parsed = parseReply($reply)
    doAssert parsed.actions.len == 2
    doAssert parsed.actions[0].kind == MoveAction
    doAssert parsed.actions[1].kind == GatherAction
    doAssert parsed.actions[1].target == source
  for recipient in [
    "village", "hall", "miller_hut", "weaver_hut", "mason_hut",
    "ada", "ben", "clara", "dara", "eli", "finn"
  ]:
    var reply = answer()
    reply["actions"] = %*[
      action("gather", "stone"), action("move", recipient),
      action("give", recipient)
    ]
    let parsed = parseReply($reply)
    doAssert parsed.actions.len == 3
    doAssert parsed.actions[1].kind == MoveAction
    doAssert parsed.actions[2].kind == GiveAction
    doAssert parsed.actions[2].target == recipient

echo "Testing the direct OpenAI endpoint remains narrowly allowed"
block:
  for endpoint in [
    "https://api.openai.com", "https://API.OPENAI.COM:443/"
  ]:
    let client = newLlmClient(0, LlmConfig(baseUrl: endpoint))
    doAssert client.available()
    client.close()
  for endpoint in [
    "http://api.openai.com", "https://api.openai.com.evil.test",
    "https://api.openai.com:8443", "https://api.openai.com/v1",
    "https://api.openai.com?key=bad", "https://user@api.openai.com"
  ]:
    var rejected = false
    try:
      discard newLlmClient(0, LlmConfig(baseUrl: endpoint))
    except LlmError:
      rejected = true
    doAssert rejected

echo "Testing native credential fallback and environment precedence"
block:
  let
    names = [
      "COGAME_LLM", "COWORLD_LLM_ENDPOINT", "COGAME_LLM_BASE_URL",
      "COGAME_LLM_KEY", "OPENROUTER_API_KEY", "OPENAI_API_KEY",
      "COGAME_LLM_INTERVAL", "COGAME_LLM_TIMEOUT_MS", "COGAME_LLM_MODEL",
      "COWORLD_LLM_MODEL", "MONSTER_KEY_FILE"
    ]
    directory = createTempDir("monster-credentials-", "")
    path = directory / "openai.key"
  var saved: seq[(string, bool, string)]
  for name in names:
    saved.add (name, existsEnv(name), getEnv(name))
    delEnv(name)
  defer:
    for (name, existed, value) in saved:
      if existed:
        putEnv(name, value)
      else:
        delEnv(name)
    removeDir(directory)

  putEnv("MONSTER_KEY_FILE", path)
  writeFile(path, "  fixture-file-key\r\n")
  block:
    let config = brainConfig()
    doAssert config.baseUrl == "https://api.openai.com"
    doAssert config.key == "fixture-file-key"
    doAssert config.model == DefaultMonsterModel
    doAssert not existsEnv("OPENAI_API_KEY")
  putEnv("OPENAI_API_KEY", "  fixture-environment-key  ")
  doAssert brainConfig().key == "fixture-environment-key"
  doAssert getEnv("OPENAI_API_KEY") == "  fixture-environment-key  "
  putEnv("OPENAI_API_KEY", " \t")
  doAssert brainConfig().key == "fixture-file-key"
  delEnv("OPENAI_API_KEY")

  putEnv("COGAME_LLM_BASE_URL", "https://api.openai.com")
  doAssert brainConfig().key == "fixture-file-key"
  putEnv("COGAME_LLM_KEY", "fixture-provider-key")
  doAssert brainConfig().key == "fixture-provider-key"
  delEnv("COGAME_LLM_BASE_URL")
  block:
    let config = brainConfig()
    doAssert config.baseUrl == "https://openrouter.ai/api"
    doAssert config.key == "fixture-provider-key"
  delEnv("COGAME_LLM_KEY")

  putEnv("MONSTER_KEY_FILE", directory / "missing.key")
  putEnv("OPENAI_API_KEY", "fixture-environment-key")
  doAssert brainConfig().key == "fixture-environment-key"
  putEnv("COWORLD_LLM_ENDPOINT", "http://127.0.0.1:9100")
  block:
    let config = brainConfig()
    doAssert config.sidecar
    doAssert config.baseUrl == "http://127.0.0.1:9100"
    doAssert config.key.len == 0
  delEnv("COWORLD_LLM_ENDPOINT")
  putEnv("COGAME_LLM_BASE_URL", "https://openrouter.ai/api")
  block:
    let config = brainConfig()
    doAssert config.baseUrl == "https://openrouter.ai/api"
    doAssert config.key.len == 0
  delEnv("COGAME_LLM_BASE_URL")
  delEnv("OPENAI_API_KEY")
  doAssert brainConfig(enabled = false).baseUrl.len == 0
  putEnv("COGAME_LLM", "off")
  doAssert brainConfig().baseUrl.len == 0
  delEnv("COGAME_LLM")

  block:
    var rejected = false
    try:
      discard brainConfig()
    except MonsterError:
      rejected = true
    doAssert rejected, "missing explicit key file was silently ignored"
  putEnv("MONSTER_KEY_FILE", path)
  writeFile(path, " \r\n")
  block:
    var rejected = false
    try:
      discard brainConfig()
    except MonsterError:
      rejected = true
    doAssert rejected, "empty key file was silently ignored"

echo "Testing async plans, teaching memory, and visible inference failures"
block:
  ports.open()
  requests.open()
  credentials.open()
  var server: Thread[void]
  createThread(server, serve)
  let
    port = ports.recv()
    directory = createTempDir("monster-brains-", "")
    path = directory / "memory.json"
    client = newLlmClient(0, LlmConfig(
      baseUrl: "http://127.0.0.1:" & $port,
      model: "fixture-model",
      interval: 1,
      timeoutMs: 3000
    ))
    brain = newBrain(path, client, "fixture-model")
  defer:
    brain.close()
    let stop = newSocket()
    stop.connect("127.0.0.1", Port(port))
    stop.send("GET /stop HTTP/1.1\r\n\r\n")
    stop.close()
    joinThread(server)
    removeDir(directory)
  var tick: int32
  doAssert brain.available()
  doAssert brain.submit("Help with food. Always gather wild food.", Observation)
  doAssert brain.pending
  doAssert not brain.submit("Duplicate request", Observation)
  doAssert settle(brain, tick)
  doAssert brain.failure.len == 0
  doAssert brain.reply.actions[0].kind == GatherAction
  doAssert brain.lessons == @[Lesson]
  doAssert brain.messages.len == 2
  inc tick
  doAssert not brain.pollBrain(tick), "reply was consumed twice"
  let first = requests.receiveCopy()
  doAssert first.startsWith("POST /v1/responses ")
  let request = parseDocument(first.split('\n', 1)[1])
  doAssert request["model"].getStr() == "fixture-model"
  doAssert request["text"]["format"]["strict"].getBool()
  doAssert not request["store"].getBool()
  doAssert first.contains("Always gather wild food")
  let context = request["input"].elems[^1]["content"].getStr()
  doAssert context.contains(Observation)
  doAssert context.contains("Mason's hut")
  doAssert context.contains("Gathering stone")

  brain.addEvent("Moss gathered six berries.")
  doAssert brain.submit("What should you do next?", Observation)
  doAssert settle(brain, tick)
  let second = requests.receiveCopy()
  doAssert second.contains(Lesson)
  doAssert second.contains("Moss gathered six berries.")
  doAssert second.contains("I'll gather wild berries")
  doAssert brain.lessons.len == 1, "duplicate teaching added duplicate memory"
  doAssert brain.messages.len == 5
  let restored = newBrain(path, enabled = false)
  doAssert restored.messages == brain.messages
  doAssert restored.lessons == brain.lessons
  restored.close()
  let saved = readFile(path)
  doAssert not saved.contains("fixture-model")
  doAssert not saved.contains("baseUrl")
  doAssert not saved.contains("Authorization")

  let lessonCount = brain.lessons.len
  doAssert brain.submit("bad-plan", Observation)
  doAssert not settle(brain, tick)
  discard requests.receiveCopy()
  doAssert brain.failure.contains("Unknown") or
    brain.failure.contains("Gather target")
  doAssert brain.lessons.len == lessonCount
  doAssert not brain.pending

  doAssert brain.submit("http-failure", Observation)
  doAssert not settle(brain, tick)
  discard requests.receiveCopy()
  doAssert brain.failure.contains("429")

  doAssert brain.submit("incomplete-output", Observation)
  doAssert not settle(brain, tick)
  discard requests.receiveCopy()
  doAssert brain.failure.contains("did not complete")

  brain.messages.setLen(MaxMessages - 1)
  doAssert not brain.submit("Memory limit test", Observation)
  doAssert brain.failure.contains("full")
  doAssert brain.messages.len == MaxMessages - 1
  brain.messages.setLen(0)
  for i in 0 ..< 20:
    brain.messages.add Message(role: PlayerMessage, text: repeat('x', 4096))
  doAssert not brain.submit("Byte limit test", Observation)
  doAssert brain.failure.contains("request limit")
  doAssert brain.messages.len == 20

echo "Testing action feedback becomes one grounded creature explanation"
block:
  ports.open()
  requests.open()
  credentials.open()
  var server: Thread[void]
  createThread(server, serve)
  let
    port = ports.recv()
    directory = createTempDir("monster-feedback-", "")
    path = directory / "memory.json"
    client = newLlmClient(0, LlmConfig(
      baseUrl: "http://127.0.0.1:" & $port,
      model: "fixture-model", interval: 1, timeoutMs: 3000
    ))
    brain = newBrain(path, client, "fixture-model")
    problem = "move to (18, 3): That destination is not walkable."
  defer:
    brain.close()
    let stop = newSocket()
    stop.connect("127.0.0.1", Port(port))
    stop.send("GET /stop HTTP/1.1\r\n\r\n")
    stop.close()
    joinThread(server)
    removeDir(directory)
  var tick: int32
  doAssert brain.submit("Cross the river.", Observation)
  doAssert settle(brain, tick)
  discard requests.receiveCopy()
  let learned = brain.lessons
  brain.reportProblem(problem)
  doAssert brain.explanationPending
  doAssert brain.failure.len == 0
  doAssert brain.roleCount(PlayerMessage) == 1
  doAssert brain.roleCount(FeedbackMessage) == 1
  doAssert brain.roleCount(EventMessage) == 0
  doAssert brain.messages[^1].text == problem
  doAssert parseDocument(readFile(path))["messages"].elems[^1]["role"].getStr() ==
    "feedback"

  inc tick
  discard brain.pollBrain(tick)
  doAssert brain.explainProblems("Latest position: still on the west bank.")
  doAssert brain.pending
  doAssert not brain.explanationPending
  doAssert settle(brain, tick), brain.failure
  doAssert requests.peek() == 1
  let explanationRequest = requests.receiveCopy()
  doAssert explanationRequest.contains("Cross the river.")
  doAssert explanationRequest.contains(problem)
  doAssert explanationRequest.contains("[Action feedback]")
  doAssert explanationRequest.contains("still on the west bank")
  doAssert brain.messages[^1].role == CreatureMessage
  doAssert brain.messages[^1].text == Explanation
  doAssert brain.roleCount(PlayerMessage) == 1
  doAssert brain.roleCount(CreatureMessage) == 2
  doAssert brain.reply.actions.len == 0,
    "explaining a failure must not execute another physical plan"
  doAssert brain.reply.lessons.len == 0
  doAssert brain.lessons == learned,
    "execution feedback must not invent lasting teacher preferences"
  let restored = newBrain(path, enabled = false)
  doAssert restored.messages == brain.messages
  restored.close()
  for i in 0 ..< 3:
    inc tick
    doAssert not brain.pollBrain(tick)
    doAssert not brain.explainProblems(Observation)
  doAssert requests.peek() == 0, "explaining a failure created a retry loop"

  doAssert brain.submit("Go home.", Observation)
  brain.reportProblem("gather at berries: No wild berries remain.")
  doAssert brain.pending and brain.explanationPending
  doAssert not brain.explainProblems(Observation)
  doAssert settle(brain, tick)
  discard requests.receiveCopy()
  doAssert brain.explanationPending,
    "a completed teacher request discarded feedback received while pending"
  inc tick
  discard brain.pollBrain(tick)
  doAssert brain.explainProblems(Observation)
  doAssert settle(brain, tick)
  doAssert requests.receiveCopy().contains("No wild berries remain.")
  doAssert brain.roleCount(PlayerMessage) == 2
  doAssert brain.reply.actions.len == 0

  let replies = brain.roleCount(CreatureMessage)
  brain.reportProblem("eat: No food is being carried.")
  inc tick
  discard brain.pollBrain(tick)
  doAssert brain.explainProblems("http-failure")
  doAssert not settle(brain, tick)
  discard requests.receiveCopy()
  doAssert brain.failure.contains("429")
  doAssert brain.roleCount(CreatureMessage) == replies,
    "a failed model request must not pretend the creature answered"
  doAssert not brain.pending and not brain.explanationPending
  doAssert not brain.explainProblems(Observation)
  doAssert requests.peek() == 0

echo "Testing one authentication retry with a local fallback key"
block:
  ports.open()
  requests.open()
  credentials.open()
  var server: Thread[void]
  createThread(server, serve)
  let
    port = ports.recv()
    directory = createTempDir("monster-authentication-", "")
    keyPath = directory / "working.key"
    savePath = directory / "memory.json"
  defer:
    let stop = newSocket()
    stop.connect("127.0.0.1", Port(port))
    stop.send("GET /stop HTTP/1.1\r\n\r\n")
    stop.close()
    joinThread(server)
    removeDir(directory)

  proc fixtureBrain(keyFile: string, savePath = ""): Brain =
    ## Uses only fixture credentials against the local inference server.
    let client = newLlmClient(0, LlmConfig(
      baseUrl: "http://127.0.0.1:" & $port,
      key: "fixture-initial-key", model: "fixture-model",
      interval: 1, timeoutMs: 3000
    ))
    newBrain(savePath, client, "fixture-model", keyFile)

  writeFile(keyPath, "fixture-working-key\n")
  block:
    let brain = fixtureBrain(keyPath, savePath)
    defer:
      brain.close()
    var tick: int32
    doAssert brain.submit("auth-retry", Observation)
    doAssert settle(brain, tick), brain.failure
    doAssert brain.failure.len == 0
    doAssert requests.peek() == 2
    doAssert requests.receiveCopy() == requests.receiveCopy(),
      "authentication retry changed the request body"
    doAssert credentials.receiveCopy() == "Bearer fixture-initial-key"
    doAssert credentials.receiveCopy() == "Bearer fixture-working-key"
    doAssert brain.messages.len == 2
    doAssert brain.messages[0].role == PlayerMessage
    doAssert brain.messages[1].role == CreatureMessage
    let saved = readFile(savePath)
    doAssert not saved.contains("fixture-initial-key")
    doAssert not saved.contains("fixture-working-key")

    doAssert brain.submit("auth-followup", Observation)
    doAssert settle(brain, tick), brain.failure
    doAssert requests.peek() == 1
    discard requests.receiveCopy()
    doAssert credentials.receiveCopy() == "Bearer fixture-working-key"
    doAssert brain.messages.len == 4

  for (name, contents, prompt, count, error) in [
    ("rejected", "fixture-rejected-key", "auth-retry", 2, "401"),
    ("missing", "", "auth-retry", 1, "Could not read"),
    ("empty", " \r\n", "auth-retry", 1, "empty"),
    ("same", "fixture-initial-key", "auth-retry", 1, "401"),
    ("unconfigured", "fixture-working-key", "auth-retry", 1, "401"),
    ("rate-limit", "fixture-working-key", "auth-http-failure", 1, "429")
  ]:
    let path = directory / (name & ".key")
    if name != "missing":
      writeFile(path, contents)
    let brain = fixtureBrain(if name == "unconfigured": "" else: path)
    defer:
      brain.close()
    var tick: int32
    doAssert brain.submit(prompt, Observation)
    doAssert not settle(brain, tick)
    doAssert brain.failure.contains(error), brain.failure
    doAssert brain.messages.len == 1
    doAssert not brain.pending
    doAssert requests.peek() == count
    doAssert credentials.peek() == count
    for i in 0 ..< count:
      discard requests.receiveCopy()
      discard credentials.receiveCopy()

echo "Testing malformed saved memories report MonsterError"
block:
  let
    directory = createTempDir("monster-brain-invalid-", "")
    path = directory / "memory.json"
  defer:
    removeDir(directory)
  writeFile(path, """{"version":1,"messages":[],"lessons":[42]}""")
  var rejected = false
  try:
    discard newBrain(path, enabled = false)
  except MonsterError:
    rejected = true
  doAssert rejected

if "--live" in commandLineParams():
  echo "Testing one small live GPT Sol request"
  let brain = newBrain("")
  defer:
    brain.close()
  doAssert brain.available(), brain.failure
  doAssert brain.submit("Please go to the berries.", Observation), brain.failure
  var tick: int32
  doAssert settle(brain, tick, 45), brain.failure
  doAssert brain.reply.actions.len > 0, "live model did not return a plan"
  doAssert brain.reply.actions[0].target == "berries"
  echo "Live model: ", brain.model
  echo "Live reply: ", brain.reply.speech
  echo "Live actions: ", brain.reply.actions.len

echo "Creature brain tests passed"
