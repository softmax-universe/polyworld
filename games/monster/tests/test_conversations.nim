import
  std/[json, monotimes, net, os, strutils, tempfiles, times],
  vmath,
  polyworld/llms,
  ../[brains, common, conversations, resources, sim]

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
    if current.contains("delayed-attack-fixture"):
      sleep(120)
    if current.contains("service-failure"):
      socket.send("HTTP/1.1 429 Too Many Requests\r\n" &
        "Content-Length: 2\r\nConnection: close\r\n\r\n{}")
      continue
    let answer =
      if current.contains("[Explain action feedback]"):
        response(Explanation, newJArray())
      elif current.contains("conversation-only"):
        response("I'm listening.", newJArray())
      elif current.contains("attack-fixture"):
        response("I'll hit Ada once.", %*[{
          "kind": "attack", "target": "ada", "x": 0,
          "z": 0, "duration": 0
        }])
      elif current.contains("rival-delivery"):
        response("I'll bring some stone to Bracken's hall.", %*[
          {"kind": "gather", "target": "stone", "x": 0,
            "z": 0, "duration": 0},
          {"kind": "give", "target": "bracken", "x": 0,
            "z": 0, "duration": 0}
        ])
      elif current.contains("resource-delivery"):
        response("I'll bring some stone to the village hall.", %*[
          {"kind": "gather", "target": "stone", "x": 0,
            "z": 0, "duration": 0},
          {"kind": "give", "target": "hall", "x": 0,
            "z": 0, "duration": 0}
        ])
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
  let middle = MapSize div 2
  map.blocked[middle * MapSize + middle] = true
  if disconnected:
    for z in 0 ..< MapSize:
      map.blocked[z * MapSize + middle] = true
  newWorld(map)

proc frame(world: var World, brain: Brain) =
  ## Uses the same simulation, response, and outcome order as the game.
  world.step()
  discard world.receive(brain)
  world.outcomes(brain, "")

proc attackFixture(): World =
  ## Provides a real target while keeping unrelated NPC errands idle.
  result = newWorld(MonsterMap(
    seed: 42,
    blocked: newSeq[bool](MapSize * MapSize),
    landmarks: @[
      Landmark(id: "home", name: "Sleeping glade",
        position: vec2(-6.5'f, 0.5'f)),
      Landmark(id: "village", name: "Willow village hall",
        position: vec2(0.5'f, 6.5'f)),
      Landmark(id: "miller_hut", name: "Miller's hut",
        position: vec2(6.5'f, 0.5'f))
    ]
  ))
  for person in result.villagers.mitems:
    person.hunger = 0
    person.retry = 1000

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

  for recipient in ["hall", "bracken"]:
    var world = newWorld(MonsterMap(
      seed: 42,
      blocked: newSeq[bool](MapSize * MapSize),
      landmarks: @[
        Landmark(id: "home", name: "Sleeping glade",
          position: vec2(-6.5'f, 0.5'f)),
        Landmark(id: "village", name: "Willow village hall",
          position: vec2(0.5'f, 6.5'f)),
        Landmark(id: "bracken", name: "Bracken hall",
          position: vec2(40.5'f, 6.5'f)),
        Landmark(id: "stone", name: "Loose stone",
          position: vec2(6.5'f, 0.5'f))
      ]
    ))
    let
      brain = fixtureBrain()
      source = world.sourceIndex("stone")
      destination = world.villageIndex(recipient)
      other = world.villageIndex(
        if recipient == "hall": "bracken" else: "village")
      # Long regional trips need room for coarse OS sleep scheduling.
      deadline = getMonoTime() + initDuration(seconds = 15)
    doAssert source >= 0 and destination >= 0 and other >= 0
    let
      originalStone = world.sources[source].amount
      originalStock = world.villages[destination].stock[StoneResource]
      otherStock = world.villages[other].stock
      destinationPosition = world.villages[destination].position
    defer:
      brain.close()
    let instruction =
      if recipient == "hall": "resource-delivery: bring stone to our hall"
      else: "rival-delivery: bring stone to Bracken's hall"
    doAssert world.speak(brain, instruction)
    while true:
      world.frame(brain)
      doAssert brain.failure.len == 0, brain.failure
      if not brain.pending and not brain.explanationPending and
        not world.active and world.actions.len == 0:
          break
      doAssert getMonoTime() < deadline,
        "Resource delivery did not settle: " & recipient &
          " tick=" & $world.tick & " active=" & $world.active &
          " pending=" & $brain.pending & " position=" & $world.creature.position
      sleep(2)
    doAssert world.creature.cargo.total() == 0
    doAssert world.villages[destination].stock[StoneResource] ==
      originalStock + CarryLimit
    doAssert world.villages[other].stock == otherStock,
      "A delivery must not affect the other village's stock."
    doAssert world.sources[source].amount == originalStone - CarryLimit
    doAssert world.creature.position == destinationPosition
    doAssert requests.peek() == 1
    let
      request = parseDocument(receiveRequest())
      current = request["input"].elems[^1]{"content"}.getStr()
      observation = parseDocument(current.split("\n[Teacher says]\n")[0]
        .split('\n', 1)[1])
    doAssert observation["villages"].len == 2
    doAssert current.contains("Willow") and current.contains("Bracken"),
      "The model must observe separate village destinations."
    doAssert observation["sources"][0]["name"].getStr() == "Loose stone"
    doAssert observation["sources"][0].hasKey("owner"),
      "The model must observe source ownership."
    var deliveryRecorded = false
    for message in brain.messages:
      if message.role == EventMessage and message.text.contains("stone") and
        message.text.contains(
          if recipient == "hall": "Willow" else: "Bracken"):
          deliveryRecorded = true
    doAssert deliveryRecorded, "The model must receive the actual delivery."

  block singleStrike:
    var world = attackFixture()
    let
      brain = fixtureBrain()
      target = world.villagerIndex("ada")
      deadline = getMonoTime() + initDuration(seconds = 5)
    doAssert target >= 0
    doAssert world.villagers[target].health == 100
    defer:
      brain.close()
    doAssert world.speak(brain, "attack-fixture: hit Ada once")
    while true:
      world.frame(brain)
      doAssert brain.failure.len == 0, brain.failure
      if not brain.pending and not brain.explanationPending and
        not world.active and world.actions.len == 0:
          break
      doAssert getMonoTime() < deadline, "single attack did not settle"
      sleep(2)
    doAssert world.villagers[target].health == 100 - AttackDamage
    doAssert world.villagers[target].fear > 0
    doAssert world.villages[0].alarm > 0
    doAssert requests.peek() == 1
    let
      request = parseDocument(receiveRequest())
      current = request["input"].elems[^1]{"content"}.getStr()
      observation = parseDocument(current.split("\n[Teacher says]\n")[0]
        .split('\n', 1)[1])
      schema = request["text"]["format"]["schema"]["properties"]
      actionKinds = schema["actions"]["items"]["properties"]["kind"]["enum"]
    doAssert %"attack" in actionKinds.elems,
      "The structured output schema must allow the attack action."
    doAssert observation["villagers"][target]["health"].getFloat() == 100
    doAssert observation["villagers"][target]["alive"].getBool()
    var hits = 0
    for message in brain.messages:
      if message.role == EventMessage and
        message.text.startsWith("Struck Ada for 35 damage."):
          inc hits
    doAssert hits == 1, "The actual hit must reach creature memory once."
    let messageCount = brain.messages.len
    for tick in 0 ..< TickRate * 5:
      world.frame(brain)
    doAssert world.villagers[target].health == 100 - AttackDamage,
      "One instruction must not start automatic follow-up attacks."
    doAssert brain.messages.len == messageCount
    doAssert requests.peek() == 0
    doAssert not world.active and world.actions.len == 0

  block stopPendingAttack:
    var world = attackFixture()
    let
      brain = fixtureBrain()
      target = world.villagerIndex("ada")
      deadline = getMonoTime() + initDuration(seconds = 5)
    defer:
      brain.close()
    doAssert world.speak(brain, "delayed-attack-fixture: hit Ada once")
    while requests.peek() == 0:
      world.frame(brain)
      doAssert getMonoTime() < deadline, "attack request was not sent"
      sleep(2)
    doAssert brain.pending
    doAssert world.speak(brain, "stop"),
      "Stop must interrupt a pending model request immediately."
    doAssert not brain.pending
    doAssert not world.active and world.actions.len == 0
    discard receiveRequest()
    let drainUntil = getMonoTime() + initDuration(milliseconds = 300)
    while getMonoTime() < drainUntil:
      world.frame(brain)
      sleep(2)
    doAssert world.villagers[target].health == 100,
      "An interrupted model reply must never start its attack."
    doAssert not world.active and world.actions.len == 0
    doAssert requests.peek() == 0

  block stopOfflineAttack:
    var world = attackFixture()
    let
      brain = newBrain("", enabled = false)
      target = world.villagerIndex("ada")
    defer:
      brain.close()
    world.instruct(@[CreatureAction(kind: AttackAction, target: "ada")])
    for tick in 0 ..< TickRate * 30:
      world.step()
      if world.active and world.elapsed > 0:
        break
    doAssert world.active and world.elapsed > 0,
      "The offline stop check must interrupt an actual attack windup."
    doAssert world.speak(brain, "stop"),
      "Stop must work even when the model connection is disabled."
    doAssert not world.active and world.actions.len == 0
    for tick in 0 ..< TickRate * 2:
      world.frame(brain)
    doAssert world.villagers[target].health == 100
    doAssert requests.peek() == 0

  block stopWithFullTranscript:
    let directory = createTempDir("monster-stop-", "")
    defer: removeDir(directory)
    let
      worldPath = directory / "world.json"
      memoryPath = directory / "conversation.json"
      brain = newBrain(memoryPath, enabled = false)
    defer: brain.close()
    for i in 0 ..< MaxMessages:
      brain.messages.add Message(role: PlayerMessage, text: "Order " & $i)
    brain.saveBrain()
    let full = readFile(memoryPath)

    var world = fixture(false)
    let start = world.creature.position
    world.instruct(@[
      CreatureAction(kind: MoveAction, target: "river"),
      CreatureAction(kind: MoveAction, target: "home")
    ])
    for i in 0 ..< TickRate:
      world.step()
      if world.creature.position != start: break
    let interrupted = world.creature.position
    doAssert interrupted != start and world.creature.moving
    doAssert world.active and world.actions.len == 1
    doAssert world.speak(brain, "stop") and brain.failure.len == 0
    doAssert not world.active and not world.creature.moving and world.actions.len == 0
    for i in 0 ..< TickRate * 2:
      world.frame(brain)
    doAssert world.creature.position == interrupted
    world.saveWorld(worldPath)

    var reopened = fixture(false)
    reopened.restoreWorld(worldPath)
    for i in 0 ..< TickRate * 2:
      reopened.frame(brain)
    doAssert reopened.creature.position == interrupted
    doAssert not reopened.active and not reopened.creature.moving and reopened.actions.len == 0
    doAssert readFile(memoryPath) == full
    doAssert requests.peek() == 0

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
