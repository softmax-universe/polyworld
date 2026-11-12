import
  std/[json, monotimes, net, os, strutils, tempfiles, times],
  vmath,
  polyworld/llms,
  ../[brains, common, conversations, sim]

const Explanation = "I can't find a way across the river from here."

var
  ports: Channel[int]
  requests: Channel[string]

proc response(speech: string, actions: JsonNode): string =
  ## Wraps a complete creature decision in a local Responses API fixture.
  let reply = $(%*{
    "speech": speech, "actions": actions, "lessons": []
  })
  $(%*{
    "status": "completed", "output": [{
      "type": "message", "role": "assistant", "content": [{
        "type": "output_text", "text": reply
      }]
    }]
  })

proc serve() {.thread.} =
  ## Proposes a failed river crossing, then explains its actual feedback.
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
    requests.send(body)
    let current = parseDocument(body)["input"].elems[^1]{"content"}.getStr()
    if current.contains("service-failure"):
      socket.send("HTTP/1.1 429 Too Many Requests\r\n" &
        "Content-Length: 2\r\nConnection: close\r\n\r\n{}")
      continue
    let answer =
      if current.contains("[Explain action feedback]"):
        response(Explanation, newJArray())
      elif current.contains("conversation-only"):
        response("I'm listening.", newJArray())
      else:
        response("I'll try to cross the river.", %*[{
          "kind": "move", "target": "",
          "x": (if current.contains("disconnected"): 6.5 else: 0.5),
          "z": 0.5, "duration": 0
        }])
    socket.send("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n" &
      "Content-Length: " & $answer.len &
      "\r\nConnection: close\r\n\r\n" & answer)
  server.close()
  ports.close()
  requests.close()
  reset(ports)
  reset(requests)

proc receiveRequest(): string =
  ## Copies a worker-owned request into the caller's allocation domain.
  let body = requests.recv()
  result = newString(body.len)
  if body.len > 0:
    copyMem(result[0].addr, body[0].unsafeAddr, body.len)

proc fixture(disconnected: bool): World =
  ## Separates an impassable destination from a walkable unreachable bank.
  var map = MonsterMap(
    seed: 42,
    blocked: newSeq[bool](MapSize * MapSize),
    landmarks: @[
      Landmark(id: "home", position: vec2(-6.5'f, 0.5'f)),
      Landmark(id: "river", position: vec2(6.5'f, 0.5'f))
    ]
  )
  map.blocked[32 * MapSize + 32] = true
  if disconnected:
    for z in 0 ..< MapSize:
      map.blocked[z * MapSize + 32] = true
  newWorld(map)

proc frame(world: var World, brain: Brain) =
  ## Uses the same simulation, response, and outcome order as the game.
  world.step()
  discard world.receive(brain)
  world.outcomes(brain, "")

proc settle(brain: Brain, tick: var int32) =
  ## Completes one model request without automatically sending queued feedback.
  let deadline = getMonoTime() + initDuration(seconds = 5)
  while brain.pending:
    inc tick
    discard brain.pollBrain(tick)
    doAssert getMonoTime() < deadline, "creature response did not settle"
    sleep(2)

echo "Testing blocked plans and runtime failures become creature replies"
block:
  ports.open()
  requests.open()
  var server: Thread[void]
  createThread(server, serve)
  let port = ports.recv()
  defer:
    let stop = newSocket()
    stop.connect("127.0.0.1", Port(port))
    stop.send("GET /stop HTTP/1.1\r\n\r\n")
    stop.close()
    joinThread(server)

  proc fixtureBrain(path = ""): Brain =
    ## Creates an isolated conversation connected only to the local fixture.
    newBrain(path, newLlmClient(0, LlmConfig(
      baseUrl: "http://127.0.0.1:" & $port,
      model: "fixture-model", interval: 1, timeoutMs: 3000
    )), "fixture-model")

  for disconnected in [false, true]:
    var world = fixture(disconnected)
    let
      start = world.creature.position
      instruction =
        if disconnected: "Cross to the disconnected river bank."
        else: "Cross to the blocked river destination."
      brain = fixtureBrain()
      deadline = getMonoTime() + initDuration(seconds = 5)
    defer:
      brain.close()
    doAssert world.speak(brain, instruction)
    while true:
      world.frame(brain)
      doAssert brain.failure.len == 0, brain.failure
      if not brain.pending and not brain.explanationPending and
        not world.active and world.actions.len == 0:
          break
      doAssert getMonoTime() < deadline, "failure explanation did not settle"
      sleep(2)
    doAssert world.creature.position == start
    doAssert world.events.len == 0 and world.problems.len == 0
    doAssert brain.messages.len == 4
    doAssert brain.messages[0] == Message(
      role: PlayerMessage, text: instruction
    )
    doAssert brain.messages[1].role == CreatureMessage
    doAssert brain.messages[2].role == FeedbackMessage
    doAssert brain.messages[2].text.contains(
      if disconnected: "cannot find a path" else: "not walkable"
    )
    doAssert brain.messages[3] == Message(
      role: CreatureMessage, text: Explanation
    )
    doAssert brain.reply.actions.len == 0 and brain.reply.lessons.len == 0
    doAssert requests.peek() == 2
    let
      original = receiveRequest()
      feedback = receiveRequest()
    doAssert original.contains(instruction)
    doAssert feedback.contains(instruction)
    doAssert feedback.contains("[Action feedback]")
    doAssert feedback.contains("[Explain action feedback]")
    doAssert feedback.contains("[Current world observation]")
    for i in 0 ..< 60:
      world.frame(brain)
    doAssert requests.peek() == 0
    doAssert brain.messages.len == 4
    doAssert not brain.pending and not brain.explanationPending
    doAssert not world.active and world.actions.len == 0

  block serviceFailure:
    var world = fixture(true)
    let brain = fixtureBrain()
    defer:
      brain.close()
    world.instruct(@[CreatureAction(kind: MoveAction, x: 6.5'f, z: 0.5'f)])
    doAssert world.speak(brain, "service-failure")
    let deadline = getMonoTime() + initDuration(seconds = 5)
    while brain.pending:
      world.frame(brain)
      doAssert getMonoTime() < deadline
      sleep(2)
    for i in 0 ..< 60:
      world.frame(brain)
    doAssert brain.failure.contains("429")
    doAssert not brain.explanationPending
    doAssert requests.peek() == 1
    discard receiveRequest()
    doAssert brain.messages[^1].role == FeedbackMessage
    doAssert world.speak(brain, "conversation-only retry")
    doAssert brain.failure.len == 0
    var tick = world.tick
    brain.settle(tick)
    doAssert brain.messages[^1].role == CreatureMessage
    doAssert not brain.explanationPending
    doAssert requests.peek() == 1
    discard receiveRequest()

  block persistence:
    let
      directory = createTempDir("monster-feedback-reload-", "")
      path = directory / "memory.json"
    defer:
      removeDir(directory)
    var tick: int32
    block:
      let brain = fixtureBrain(path)
      defer:
        brain.close()
      doAssert brain.submit("conversation-only", "original state")
      brain.reportProblem("Action move to river failed: no route.")
      brain.settle(tick)
      doAssert brain.messages[^1].role == CreatureMessage
      doAssert brain.explanationPending
      discard receiveRequest()
    block:
      let brain = fixtureBrain(path)
      doAssert brain.explanationPending,
        "Queued feedback must survive a later creature message."
      doAssert brain.explainProblems("state before closing")
      brain.close()
      discard receiveRequest()
    block:
      let brain = fixtureBrain(path)
      defer:
        brain.close()
      doAssert brain.explanationPending,
        "An undelivered explanation must resume after reload."
      var
        world = fixture(false)
        attempted = false
      doAssert not world.sendPrompt(brain, "conversation-only next", attempted)
      doAssert not attempted
      doAssert brain.explainProblems(world.observation())
      doAssert not world.sendPrompt(brain, "conversation-only next", attempted)
      doAssert not attempted
      brain.settle(tick)
      discard receiveRequest()
      inc tick
      discard brain.pollBrain(tick)
      doAssert world.sendPrompt(brain, "conversation-only next", attempted)
      doAssert attempted
      brain.settle(tick)
      discard receiveRequest()
      doAssert brain.messages[^1].text == "I'm listening."
      doAssert not brain.explanationPending
    let completed = fixtureBrain(path)
    doAssert not completed.explanationPending,
      "Delivered feedback must not repeat on the next launch."
    completed.close()
    let offline = newBrain("", enabled = false)
    var
      world = fixture(false)
      attempted = false
    doAssert not world.sendPrompt(offline, "conversation-only", attempted)
    doAssert attempted, "An unavailable startup prompt is attempted once."
    doAssert not world.sendPrompt(offline, "conversation-only", attempted)
    offline.close()

echo "Monster conversation feedback integration passed"
