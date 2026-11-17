import
  std/[json, monotimes, net, os, strutils, tempfiles, times],
  vmath,
  polyworld/llms,
  ../../../experiments/voice/realtimes,
  ../[brains, common, conversations, sim, voices]

var
  ports: Channel[int]
  requests: Channel[string]

proc event(voice: MonsterVoice, data: JsonNode) =
  ## Replays voice events without a network or audio device.
  voice.client.receiveEvent($data)

proc record(voice: MonsterVoice) =
  ## Commits a synthetic silent recording without opening the microphone.
  voice.client.sendAudio(repeat("\x00\x00", 2400))
  voice.client.commitAudio()
  voice.waitingForTranscript = true

proc complete(voice: MonsterVoice, id, text: string) =
  ## Delivers the acknowledgment and transcript of one synthetic recording.
  voice.record()
  voice.event(%*{"type": "input_audio_buffer.committed", "item_id": id})
  voice.event(%*{
    "type": "conversation.item.input_audio_transcription.completed",
    "item_id": id, "transcript": text
  })

proc speeches(voice: MonsterVoice): seq[string] =
  ## Collects the approved scripts from outbound speech requests.
  for message in voice.client.testEvents:
    let event = parseJson(message)
    if event{"type"}.getStr() == "response.create":
      result.add event{"response", "input"}[0]{"content"}[0]{"text"}.getStr()

proc fixture(): World =
  ## Provides two reachable landmarks without loading rendering assets.
  newWorld(MonsterMap(
    seed: 42,
    blocked: newSeq[bool](MapSize * MapSize),
    landmarks: @[
      Landmark(id: "home", name: "Sleeping glade",
        position: vec2(-6.5'f, 0.5'f)),
      Landmark(id: "village", name: "Willow village hall",
        position: vec2(0.5'f, 6.5'f))
    ]
  ))

proc serve() {.thread.} =
  ## Answers the game planner locally while leaving the voice transport fake.
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
    if body.contains("delayed voice order"):
      sleep(150)
    let
      decision = $(%*{
        "speech": "I'll walk to Willow and remember your lesson.",
        "actions": [{"kind": "move", "target": "village", "x": 0,
          "z": 0, "duration": 0}],
        "lessons": ["I leave the farm alone."]
      })
      answer = $(%*{
        "status": "completed", "output": [{
          "type": "message", "role": "assistant", "content": [{
            "type": "output_text", "text": decision
          }]
        }]
      })
    socket.send("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n" &
      "Content-Length: " & $answer.len &
      "\r\nConnection: close\r\n\r\n" & answer)
  server.close()
  ports.close()
  requests.close()
  reset(ports)
  reset(requests)

echo "Testing saved dialogue stays silent and only new creature replies speak"
block:
  var messages = @[
    Message(role: PlayerMessage, text: "An old command."),
    Message(role: CreatureMessage, text: "An old answer.")
  ]
  let voice = newMonsterVoice(historyCount = messages.len, testMode = true)
  defer:
    voice.close()
  voice.client.state = Connected
  voice.observe(messages)
  voice.poll()
  doAssert voice.speeches().len == 0
  messages.add Message(role: PlayerMessage, text: "Go to Willow.")
  messages.add Message(role: EventMessage, text: "An engine event.")
  messages.add Message(role: FeedbackMessage, text: "Private planner feedback.")
  messages.add Message(role: CreatureMessage, text: "I'll head to Willow.")
  voice.observe(messages)
  voice.poll()
  doAssert voice.speeches() == @["I'll head to Willow."]
  voice.event(%*{"type": "response.created", "response": {"id": "reply"}})
  voice.event(%*{"type": "response.done", "response": {
    "id": "reply", "status": "completed"
  }})
  voice.observe(messages)
  voice.poll()
  doAssert voice.speeches().len == 1
  messages.add Message(role: CreatureMessage, text: "Queued before mute.")
  voice.observe(messages)
  voice.setMuted(true)
  messages.add Message(role: CreatureMessage, text: "Produced while muted.")
  voice.observe(messages)
  voice.poll()
  voice.setMuted(false)
  voice.poll()
  doAssert voice.speeches().len == 1,
    "Unmuting must not replay suppressed or queued replies."

echo "Testing a replacement reply waits for an early cancellation acknowledgment"
block:
  let voice = newMonsterVoice(testMode = true)
  defer:
    voice.close()
  voice.client.state = Connected
  var messages = @[Message(role: CreatureMessage, text: "Older reply.")]
  voice.observe(messages)
  voice.poll()
  voice.interrupt()
  messages.add Message(role: CreatureMessage, text: "Replacement reply.")
  voice.observe(messages)
  voice.poll()
  doAssert voice.speeches() == @["Older reply."]
  voice.event(%*{"type": "response.created", "response": {"id": "older"}})
  voice.poll()
  doAssert voice.speeches() == @["Older reply.", "Replacement reply."],
    "A temporarily busy speech transport must not discard the replacement."

echo "Testing stale, failed and empty transcriptions cannot become commands"
block:
  let voice = newMonsterVoice(testMode = true)
  defer:
    voice.close()
  voice.client.state = Connected
  voice.record()
  voice.interrupt()
  voice.record()
  voice.event(%*{"type": "input_audio_buffer.committed", "item_id": "old"})
  voice.event(%*{"type": "input_audio_buffer.committed", "item_id": "new"})
  voice.event(%*{
    "type": "conversation.item.input_audio_transcription.completed",
    "item_id": "old", "transcript": "Destroy Willow."
  })
  doAssert voice.pendingText.len == 0
  doAssert voice.waitingForTranscript
  voice.event(%*{
    "type": "conversation.item.input_audio_transcription.completed",
    "item_id": "new", "transcript": "Help Willow."
  })
  doAssert voice.pendingText == "Help Willow."
  voice.interrupt()
  voice.record()
  voice.event(%*{"type": "input_audio_buffer.committed", "item_id": "failed"})
  voice.event(%*{
    "type": "conversation.item.input_audio_transcription.failed",
    "item_id": "failed", "error": {"message": "Recording was unclear."}
  })
  voice.poll()
  doAssert voice.pendingText.len == 0
  doAssert not voice.waitingForTranscript
  doAssert "Recording was unclear" in voice.error
  voice.complete("empty", "")
  doAssert voice.pendingText.len == 0
  doAssert not voice.waitingForTranscript
  doAssert "didn't catch" in voice.error

echo "Testing voice credentials prefer the environment and retry a file once"
block:
  let
    directory = createTempDir("monster-voice-keys-", "")
    path = directory / "openai.key"
    names = ["OPENAI_API_KEY", "MONSTER_KEY_FILE"]
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
  putEnv("OPENAI_API_KEY", "fixture-environment-key")
  writeFile(path, "invalid\nfile-key")
  let voice = newMonsterVoice(testMode = true)
  defer:
    voice.close()
  voice.connect()
  doAssert voice.client.state == Connecting,
    "A valid environment value must take precedence over the bad file."
  writeFile(path, "fixture-file-key")
  voice.event(%*{"type": "error", "error": {
    "code": "invalid_api_key", "message": "Authentication failed."
  }})
  doAssert voice.client.state == Failed
  voice.poll()
  doAssert voice.client.state == Connecting,
    "A rejected environment credential should retry the configured file."
  voice.event(%*{"type": "error", "error": {
    "code": "invalid_api_key", "message": "Authentication failed again."
  }})
  voice.poll()
  doAssert voice.client.state == Failed,
    "A second authentication rejection must not retry forever."
  doAssert "Authentication failed again" in voice.error
  doAssert "fixture" notin voice.error
  delEnv("OPENAI_API_KEY")
  voice.connect()
  doAssert voice.client.state == Connecting,
    "Startup must also load the file when the environment is unset."

echo "Testing spoken commands share planning, memory, movement and urgent stops"
block:
  ports.open()
  requests.open()
  var server: Thread[void]
  createThread(server, serve)
  let
    port = ports.recv()
    directory = createTempDir("monster-voice-memory-", "")
    path = directory / "conversation.json"
    brain = newBrain(path, newLlmClient(0, LlmConfig(
      baseUrl: "http://127.0.0.1:" & $port,
      model: "fixture-model", interval: 1, timeoutMs: 3000
    )), "fixture-model")
    voice = newMonsterVoice(testMode = true)
  defer:
    voice.close()
    brain.close()
    let stop = newSocket()
    stop.connect("127.0.0.1", Port(port))
    stop.send("GET /stop HTTP/1.1\r\n\r\n")
    stop.close()
    joinThread(server)
    removeDir(directory)
  var world = fixture()
  let instruction = "Go to Willow. Remember to leave the farm alone."
  voice.client.state = Connected
  voice.complete("order", instruction)
  voice.submitPending(world, brain)
  doAssert voice.pendingText.len == 0
  doAssert brain.pending
  doAssert brain.messages[^1] == Message(role: PlayerMessage, text: instruction)
  let deadline = getMonoTime() + initDuration(seconds = 5)
  while brain.pending or world.active or world.actions.len > 0:
    world.step()
    discard world.receive(brain)
    world.outcomes(brain, "")
    doAssert getMonoTime() < deadline, "spoken movement did not complete"
    sleep(2)
  doAssert brain.failure.len == 0, brain.failure
  doAssert world.creature.position == world.map.landmarks[1].position
  doAssert brain.lessons == @["I leave the farm alone."]
  let body = requests.recv()
  doAssert instruction in body
  let restored = newBrain(path, enabled = false)
  doAssert restored.messages[0].text == instruction
  doAssert restored.lessons == brain.lessons
  restored.close()
  voice.observe(brain.messages)
  voice.poll()
  doAssert voice.speeches() ==
    @["I'll walk to Willow and remember your lesson."]

  voice.complete("later", "delayed voice order")
  voice.submitPending(world, brain)
  doAssert brain.pending
  world.instruct(@[CreatureAction(kind: DanceAction, duration: 30)])
  world.step()
  doAssert world.active
  voice.complete("stop", "stop")
  voice.submitPending(world, brain)
  doAssert not brain.pending
  doAssert not world.active and world.actions.len == 0
  doAssert brain.messages[^1].text == "I stopped."
  doAssert voice.pendingText.len == 0
  let drain = getMonoTime() + initDuration(milliseconds = 400)
  while getMonoTime() < drain:
    world.step()
    discard world.receive(brain)
    sleep(2)
  doAssert not world.active and world.actions.len == 0,
    "A late planner reply must not resurrect a stopped spoken order."

echo "Monster voice integration passed"
