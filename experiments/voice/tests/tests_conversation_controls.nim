{.define: voiceLabTesting.}

include ../voice

import std/[base64, importutils, json]

privateAccess(VoiceAudio)

proc testApp(connected = false): App =
  ## Creates dormant controls with an offline transport and no window.
  let manual = newVoiceAudio()
  result = App(
    client: newVoiceClient(testMode = true),
    view: VoiceView(speakReplies: true),
    audio: manual,
    manualAudio: manual,
    conversationAudio: newVoiceAudio(duplex = true)
  )
  if connected:
    result.client.state = Connected

proc closeTest(app: App) =
  ## Releases dormant state without opening audio hardware or networking.
  app.client.disconnect()
  app.conversationAudio.close()
  app.manualAudio.close()

proc event(client: VoiceClient, value: JsonNode) =
  ## Replays one server event into the real transport state machine.
  client.receiveEvent($value)

echo "Testing Start conversation connects and enables automatic speech"
block:
  let app = testApp()
  doAssert app.audio == app.manualAudio
  doAssert app.view.speakReplies
  doAssert not app.audio.capturing()
  app.beginConversation("offline-test-key")
  doAssert app.client.state == Connecting
  doAssert app.conversationRequested
  doAssert app.audio == app.conversationAudio
  doAssert app.client.handsFree
  doAssert app.client.semanticVad
  doAssert app.client.autoRespond
  doAssert not app.audio.capturing()
  let turn = app.client.sessionEvent(){"session", "audio", "input",
    "turn_detection"}
  doAssert turn{"type"}.getStr() == "semantic_vad"
  doAssert turn{"create_response"}.getBool()
  doAssert turn{"interrupt_response"}.getBool()

  echo "Testing Stop conversation cancels a pending connection"
  app.permissionPending = true
  app.handle(ConversationAction)
  doAssert not app.conversationRequested
  doAssert not app.permissionPending
  doAssert not app.client.handsFree
  doAssert app.client.state == Disconnected
  doAssert app.audio == app.manualAudio
  doAssert not app.acceptResponses
  app.tick()
  doAssert app.client.state == Disconnected
  doAssert not app.audio.capturing()
  app.closeTest()

echo "Testing connected conversation controls preserve continuous listening"
block:
  let app = testApp(connected = true)
  app.handle(ConversationAction)
  doAssert app.conversationRequested
  doAssert app.audio == app.conversationAudio
  doAssert app.client.state == Connected
  doAssert not app.audio.capturing()

  echo "Testing typed messages wait for microphone permission"
  app.permissionPending = true
  app.view.draft = "Hello from the offline control test."
  let pendingEvents = app.client.testEvents.len
  app.handle(SubmitAction)
  doAssert app.client.testEvents.len == pendingEvents
  doAssert app.view.draft == "Hello from the offline control test."
  doAssert app.conversationRequested
  doAssert not app.acceptResponses
  app.permissionPending = false

  # Simulate active capture without creating a native handle or audio device.
  app.conversationAudio.captureStarted = true
  app.acceptResponses = true
  app.handle(InterruptAction)
  doAssert app.conversationRequested
  doAssert app.client.handsFree
  doAssert app.audio == app.conversationAudio
  doAssert app.audio.capturing()
  doAssert not app.acceptResponses

  app.handle(SubmitAction)
  doAssert app.conversationRequested
  doAssert app.client.handsFree
  doAssert app.audio == app.conversationAudio
  doAssert app.audio.capturing()
  doAssert app.acceptResponses
  doAssert app.view.draft.len == 0
  doAssert app.client.responseActive
  doAssert app.client.transcripts[^1].text ==
    "Hello from the offline control test."

  echo "Testing stop restores manual playback and rejects late speech"
  var chunks = 0
  app.client.onAudio = proc(pcm: string) =
    ## Counts test audio without playing it or opening a device.
    inc chunks
  app.client.event(%*{
    "type": "response.created", "response": {"id": "reply"}
  })
  let chunk = %*{
    "type": "response.output_audio.delta", "response_id": "reply",
    "item_id": "speech", "delta": base64.encode(newString(2400))
  }
  app.client.event(chunk)
  doAssert chunks == 1
  app.handle(ConversationAction)
  doAssert app.audio == app.manualAudio
  doAssert not app.conversationRequested
  doAssert not app.client.handsFree
  doAssert app.playbackSuppressed
  doAssert not app.acceptResponses
  doAssert not app.client.responseActive
  doAssert app.view.speakReplies
  app.client.event(chunk)
  doAssert chunks == 1
  doAssert not app.manualAudio.capturing()
  doAssert not app.conversationAudio.capturing()
  app.closeTest()

echo "Testing failed connections stop conversation without reconnecting"
block:
  let app = testApp(connected = true)
  app.beginConversation()
  app.permissionPending = true
  app.acceptResponses = true
  app.client.state = Failed
  app.client.status = "Offline connection failure."
  app.client.failure = app.client.status
  app.tick()
  doAssert not app.conversationRequested
  doAssert not app.permissionPending
  doAssert not app.acceptResponses
  doAssert app.audio == app.manualAudio
  doAssert app.client.state == Failed
  doAssert app.client.status == "Offline connection failure."
  app.tick()
  doAssert app.client.state == Failed
  app.closeTest()

echo "Testing selected audio devices remain dormant until explicitly started"
block:
  let app = testApp()
  app.inputs = @[AudioDevice(uid: ""), AudioDevice(uid: "test-microphone")]
  app.outputs = @[AudioDevice(uid: ""), AudioDevice(uid: "test-speaker")]
  app.view.inputDevice = 1
  app.view.outputDevice = 1
  app.applyDevices()
  doAssert not app.audio.capturing()
  doAssert app.manualAudio.inputDevice == "test-microphone"
  doAssert app.manualAudio.outputDevice == "test-speaker"
  doAssert app.conversationAudio.inputDevice == "test-microphone"
  doAssert app.conversationAudio.outputDevice == "test-speaker"
  doAssert app.manualAudio.nativeDuplex == nil
  doAssert app.conversationAudio.nativeDuplex == nil
  app.conversationRequested = true
  var refused = false
  try:
    app.applyDevices()
  except VoiceAudioError:
    refused = true
  doAssert refused
  app.conversationRequested = false
  app.closeTest()

echo "Conversation control tests passed"
