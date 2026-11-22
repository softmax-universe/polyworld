import
  std/[base64, json, monotimes, net, os, strutils, tempfiles, times],
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

proc beginTurn(voice: MonsterVoice, id: string) =
  ## Starts one server-detected utterance while the microphone stays open.
  voice.event(%*{"type": "input_audio_buffer.speech_started", "item_id": id})

proc commitTurn(voice: MonsterVoice, id: string) =
  ## Finishes a detected utterance without a manual audio commit.
  voice.event(%*{"type": "input_audio_buffer.speech_stopped", "item_id": id})
  voice.event(%*{"type": "input_audio_buffer.committed", "item_id": id})

proc finishTurn(voice: MonsterVoice, id, text: string) =
  ## Delivers one final transcription after automatic turn detection.
  voice.event(%*{
    "type": "conversation.item.input_audio_transcription.completed",
    "item_id": id, "transcript": text
  })

proc complete(voice: MonsterVoice, id, text: string) =
  ## Detects and transcribes an entire spoken turn without manual controls.
  voice.beginTurn(id)
  voice.commitTurn(id)
  voice.finishTurn(id, text)

proc readyVoice(historyCount = 0): MonsterVoice =
  ## Enters conversation using fake credentials and virtual audio devices.
  result = newMonsterVoice(historyCount = historyCount, testMode = true)
  result.setMode(ConversationMode)
  doAssert result.client.state == Connecting
  result.event(%*{"type": "session.updated"})
  result.poll()
  doAssert result.mode == ConversationMode
  doAssert result.listening()

proc speeches(voice: MonsterVoice): seq[string] =
  ## Collects only approved scripts from outbound speech requests.
  for message in voice.client.testEvents:
    let event = parseJson(message)
    if event{"type"}.getStr() == "response.create":
      result.add event{"response", "input"}[0]{"content"}[0]{"text"}.getStr()

proc hasEvent(voice: MonsterVoice, kind: string): bool =
  ## Finds a transport event without exposing credentials or audio bytes.
  for message in voice.client.testEvents:
    if parseJson(message){"type"}.getStr() == kind:
      return true

proc finishReply(voice: MonsterVoice, id: string) =
  ## Completes an isolated response without requiring a speaker.
  voice.event(%*{"type": "response.created", "response": {"id": id}})
  voice.event(%*{"type": "response.done", "response": {
    "id": id, "status": "completed"
  }})

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
  ## Answers the planner locally while leaving voice transport simulated.
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

proc testModes() =
  ## Checks text-only startup and explicit full-conversation activation.
  echo "Testing Text mode and automatic conversation turns"
  let voice = newMonsterVoice(testMode = true)
  defer:
    voice.close()
  doAssert voice.mode == TextMode
  voice.poll()
  doAssert not voice.listening()
  doAssert voice.client.state == Disconnected
  var messages = @[Message(role: CreatureMessage, text: "Text-only reply.")]
  voice.observe(messages)
  voice.poll()
  doAssert voice.speeches().len == 0
  voice.setMode(ConversationMode)
  doAssert voice.hasKey
  doAssert voice.client.state == Connecting
  doAssert not voice.listening()
  voice.event(%*{"type": "session.updated"})
  voice.poll()
  doAssert voice.listening()
  let turn = voice.client.sessionEvent(){"session", "audio", "input",
    "turn_detection"}
  doAssert turn{"type"}.getStr() == "semantic_vad"
  doAssert not turn{"create_response"}.getBool()
  doAssert turn{"interrupt_response"}.getBool()
  voice.observe(messages)
  voice.poll()
  doAssert voice.speeches().len == 0,
    "Changing mode must not read earlier text replies aloud."
  messages.add Message(role: EventMessage, text: "An engine event.")
  messages.add Message(role: FeedbackMessage, text: "Private planner feedback.")
  messages.add Message(role: CreatureMessage, text: "Hello, I am listening.")
  voice.observe(messages)
  voice.poll()
  doAssert voice.speeches() == @["Hello, I am listening."]
  doAssert voice.listening(), "Output must not close the microphone."
  voice.finishReply("greeting")
  voice.observe(messages)
  voice.poll()
  doAssert voice.speeches().len == 1
  voice.setMode(TextMode)
  doAssert not voice.listening()
  doAssert voice.client.state == Disconnected
  messages.add Message(role: CreatureMessage, text: "Another text reply.")
  voice.observe(messages)
  voice.poll()
  doAssert voice.speeches().len == 1
  doAssert not voice.hasEvent("input_audio_buffer.commit"),
    "Conversation must not require manual audio commits."

proc testInterruptions() =
  ## Confirms barge-in and typed commands leave continuous capture available.
  echo "Testing full-duplex interruptions and replacement speech"
  let voice = readyVoice()
  defer:
    voice.close()
  var messages = @[Message(role: CreatureMessage, text: "Older reply.")]
  voice.observe(messages)
  voice.poll()
  voice.event(%*{"type": "response.created", "response": {"id": "older"}})
  voice.event(%*{"type": "response.output_audio.delta", "item_id": "audio",
    "response_id": "older", "delta": base64.encode("\x00\x00")})
  voice.beginTurn("interrupting")
  doAssert voice.listening()
  doAssert not voice.client.responseActive
  doAssert voice.hasEvent("response.cancel")
  voice.commitTurn("interrupting")
  voice.finishTurn("interrupting", "Help Willow.")
  doAssert voice.pendingText == "Help Willow."
  voice.interrupt()
  doAssert voice.pendingText.len == 0
  doAssert voice.listening(), "Typing must not disable Conversation mode."
  messages.add Message(role: CreatureMessage, text: "Replacement reply.")
  voice.observe(messages)
  voice.poll()
  doAssert voice.speeches() == @["Older reply.", "Replacement reply."]
  voice.interrupt()
  messages.add Message(role: CreatureMessage, text: "Another reply.")
  voice.observe(messages)
  voice.poll()
  doAssert voice.speeches().len == 2
  voice.event(%*{"type": "response.created", "response": {"id": "pending"}})
  voice.poll()
  doAssert voice.speeches()[^1] == "Another reply.",
    "A pending cancellation must not discard replacement speech."

proc testTranscripts() =
  ## Rejects canceled utterances while maintaining ordered complete turns.
  echo "Testing stale transcripts, focus changes, errors, and empty turns"
  let voice = readyVoice()
  defer:
    voice.close()
  voice.beginTurn("old")
  voice.poll(focused = false)
  doAssert not voice.listening()
  voice.poll(focused = true)
  doAssert voice.listening()
  voice.beginTurn("new")
  voice.commitTurn("old")
  voice.finishTurn("old", "Destroy Willow.")
  doAssert voice.pendingText.len == 0
  voice.commitTurn("new")
  voice.finishTurn("new", "Help Willow.")
  doAssert voice.pendingText == "Help Willow."
  voice.interrupt()
  voice.beginTurn("failed")
  voice.commitTurn("failed")
  voice.event(%*{
    "type": "conversation.item.input_audio_transcription.failed",
    "item_id": "failed", "error": {"message": "Recording was unclear."}
  })
  voice.poll()
  doAssert voice.pendingText.len == 0
  doAssert not voice.waitingForTranscript
  doAssert "Recording was unclear" in voice.error
  doAssert voice.mode == ConversationMode
  doAssert voice.listening(), "A bad transcript must not close the microphone."
  voice.complete("empty", "")
  doAssert voice.pendingText.len == 0
  doAssert not voice.waitingForTranscript
  voice.beginTurn("canceled")
  voice.setMode(TextMode)
  voice.commitTurn("canceled")
  voice.finishTurn("canceled", "Destroy Willow.")
  doAssert voice.pendingText.len == 0
  doAssert not voice.listening()

proc testKeys(path: string) =
  ## Requires a key for conversation while retaining usable text mode.
  echo "Testing OpenAI key gate and one file fallback"
  delEnv("OPENAI_API_KEY")
  writeFile(path, "")
  let voice = newMonsterVoice(testMode = true)
  defer:
    voice.close()
  voice.refreshKey()
  doAssert not voice.hasKey
  voice.setMode(ConversationMode)
  doAssert voice.mode == TextMode
  doAssert not voice.listening()
  doAssert voice.client.state == Disconnected
  doAssert voice.error.len > 0
  putEnv("OPENAI_API_KEY", "fixture-environment-key")
  writeFile(path, "invalid\nfile-key")
  voice.setMode(ConversationMode)
  doAssert voice.client.state == Connecting,
    "Environment credentials must take precedence over the key file."
  writeFile(path, "fixture-file-key")
  voice.event(%*{"type": "error", "error": {
    "code": "invalid_api_key", "message": "Authentication failed."
  }})
  voice.poll()
  doAssert voice.client.state == Connecting
  voice.event(%*{"type": "error", "error": {
    "code": "invalid_api_key", "message": "Authentication failed again."
  }})
  voice.poll()
  doAssert voice.mode == TextMode
  doAssert not voice.listening()
  doAssert "Authentication failed again" in voice.error
  doAssert "fixture" notin voice.error
  delEnv("OPENAI_API_KEY")
  voice.setMode(ConversationMode)
  doAssert voice.client.state == Connecting,
    "Conversation should load the key file when the environment is unset."
  voice.event(%*{"type": "session.updated"})
  voice.poll()
  doAssert voice.listening()
  removeFile(path)
  voice.setMode(ConversationMode)
  doAssert voice.mode == TextMode
  doAssert not voice.listening(),
    "Removing credentials must close an already active microphone."
  doAssert voice.client.state == Disconnected
  doAssert voice.error.len > 0
  writeFile(path, "fixture-file-key")
  putEnv("OPENAI_API_KEY", "fixture-environment-key")

proc testPlanner() =
  ## Shares actions, persistent lessons, ordered commands, and immediate stops.
  echo "Testing conversation planning, queued turns, memory, and urgent stops"
  ports.open()
  requests.open()
  var server: Thread[void]
  createThread(server, serve)
  let
    port = ports.recv()
    directory = createTempDir("monster-conversation-memory-", "")
    path = directory / "conversation.json"
    brain = newBrain(path, newLlmClient(0, LlmConfig(
      baseUrl: "http://127.0.0.1:" & $port,
      model: "fixture-model", interval: 1, timeoutMs: 3000
    )), "fixture-model")
    voice = readyVoice()
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
  doAssert instruction in requests.recv()
  let restored = newBrain(path, enabled = false)
  doAssert restored.messages[0].text == instruction
  doAssert restored.lessons == brain.lessons
  restored.close()
  voice.observe(brain.messages)
  voice.poll()
  doAssert voice.speeches() ==
    @["I'll walk to Willow and remember your lesson."]
  voice.finishReply("first")

  voice.complete("busy", "delayed voice order")
  voice.submitPending(world, brain)
  doAssert brain.pending
  voice.beginTurn("second")
  voice.commitTurn("second")
  voice.beginTurn("third")
  voice.commitTurn("third")
  voice.finishTurn("third", "Third command.")
  doAssert voice.pendingText.len == 0,
    "A later transcript must wait for the earlier committed turn."
  voice.finishTurn("second", "Second command.")
  doAssert voice.pendingText == "Second command."
  voice.submitPending(world, brain)
  doAssert voice.pendingText == "Second command."
  while brain.pending:
    world.step()
    discard world.receive(brain)
    doAssert getMonoTime() < deadline
    sleep(2)
  voice.submitPending(world, brain)
  doAssert brain.messages[^1].text == "Second command."
  doAssert voice.pendingText == "Third command."
  world.instruct(@[CreatureAction(kind: DanceAction, duration: 30)])
  world.step()
  doAssert world.active
  voice.complete("stop", "stop")
  voice.submitPending(world, brain)
  doAssert not brain.pending
  doAssert not world.active and world.actions.len == 0
  doAssert brain.messages[^1].text == "I stopped."
  doAssert voice.pendingText.len == 0
  doAssert voice.listening()
  let drain = getMonoTime() + initDuration(milliseconds = 400)
  while getMonoTime() < drain:
    world.step()
    discard world.receive(brain)
    voice.submitPending(world, brain)
    sleep(2)
  doAssert not world.active and world.actions.len == 0,
    "A late planner reply must not revive a stopped command."
  doAssert brain.messages[^1].text == "I stopped.",
    "An urgent stop must also discard queued commands."

proc run() =
  ## Isolates every test from the user's actual key files and environment.
  let
    directory = createTempDir("monster-conversation-keys-", "")
    path = directory / "openai.key"
    names = ["OPENAI_API_KEY", "MONSTER_KEY_FILE", "OPENAI_REALTIME_VOICE"]
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
  writeFile(path, "fixture-file-key")
  testModes()
  testInterruptions()
  testTranscripts()
  testKeys(path)
  testPlanner()
  echo "Monster conversation integration passed"

run()
