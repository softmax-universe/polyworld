import
  std/[base64, json, strutils],
  jsony,
  ../realtimes

proc event(client: VoiceClient, data: JsonNode) =
  ## Replays a server event without opening an audio device or network.
  client.receiveEvent(data.toJson())

proc sent(client: VoiceClient, index: int): JsonNode =
  ## Decodes one emitted protocol event for assertions.
  client.testEvents[index].fromJson(JsonNode)

let client = newVoiceClient(testMode = true)
var
  audio = ""
  starts = 0
  speech = 0
client.onAudio = proc(pcm: string) =
  ## Collects the audio bytes passed to playback.
  audio.add(pcm)
client.onAudioStart = proc() =
  ## Counts playback timeline resets.
  inc starts
client.onSpeechStart = proc() =
  ## Records a server voice activity event.
  inc speech

echo "Testing GA audio configuration and session readiness"
client.event(%*{"type": "session.created"})
doAssert client.state == Disconnected
doAssert client.autoRespond
doAssert client.instructions.len > 0
doAssert not client.sent(0){"session"}.hasKey("model")
doAssert client.sent(0){"session", "audio", "input", "format", "rate"}.getInt() == 24000
doAssert client.sent(0){"session", "audio", "input", "turn_detection"}.kind == JNull
client.event(%*{"type": "session.updated"})
doAssert client.state == Connected

echo "Testing input and output transcripts and streamed PCM"
client.event(%*{"type": "input_audio_buffer.committed", "item_id": "u1"})
client.event(%*{"type": "response.created", "response": {"id": "r1"}})
client.event(%*{"type": "conversation.item.input_audio_transcription.delta",
  "item_id": "u1", "delta": "Hel"})
client.event(%*{"type": "conversation.item.input_audio_transcription.completed",
  "item_id": "u1", "transcript": "Hello there"})
client.event(%*{"type": "response.output_audio_transcript.delta",
  "item_id": "a1", "response_id": "r1", "delta": "Hi "})
client.event(%*{"type": "response.output_audio_transcript.delta",
  "item_id": "a1", "response_id": "r1", "delta": "there!"})
let pcm = repeat("\x01\x02", 2400)
client.event(%*{"type": "response.output_audio.delta", "item_id": "a1",
  "response_id": "r1", "delta": base64.encode(pcm)})
client.event(%*{"type": "response.output_audio.delta", "item_id": "a1",
  "response_id": "r1", "delta": base64.encode(pcm)})
doAssert starts == 1
doAssert audio == pcm & pcm
doAssert client.transcripts.len == 2
doAssert client.transcripts[0].text == "Hello there"
doAssert client.transcripts[0].final
doAssert client.transcripts[1].text == "Hi there!"

echo "Testing interruption truncates unheard audio and ignores late deltas"
let first = client.testEvents.len
client.interrupt(80)
doAssert client.sent(first){"type"}.getStr() == "response.cancel"
doAssert client.sent(first + 1){"type"}.getStr() == "conversation.item.truncate"
doAssert client.sent(first + 1){"audio_end_ms"}.getInt() == 80
client.event(%*{"type": "response.output_audio.delta", "item_id": "a1",
  "response_id": "r1", "delta": base64.encode(pcm)})
doAssert audio.len == pcm.len * 2
client.event(%*{"type": "response.created", "response": {"id": "r2"}})
client.event(%*{"type": "response.done", "response": {"id": "r1", "status": "cancelled"}})
doAssert client.responseActive
client.event(%*{"type": "response.done", "response": {"id": "r2", "status": "completed"}})
doAssert not client.responseActive

echo "Testing short and valid push-to-talk turns"
client.testEvents.setLen(0)
client.sendAudio("\x00\x00")
client.commitAudio()
doAssert client.testEvents.len == 2
doAssert client.sent(1){"type"}.getStr() == "input_audio_buffer.clear"
client.testEvents.setLen(0)
client.sendAudio(pcm)
client.commitAudio()
doAssert client.sent(0){"type"}.getStr() == "input_audio_buffer.append"
doAssert client.sent(1){"type"}.getStr() == "input_audio_buffer.commit"
doAssert client.sent(2){"type"}.getStr() == "response.create"

echo "Testing hands-free updates and typed turns"
client.setHandsFree(true)
doAssert client.sessionEvent(){"session", "audio", "input", "turn_detection", "type"}.getStr() == "server_vad"
client.event(%*{"type": "input_audio_buffer.speech_started"})
doAssert speech == 1
client.sendText("A typed question")
doAssert client.transcripts[^1].role == User
doAssert client.transcripts[^1].text == "A typed question"

echo "Testing stop before response.created followed by a new prompt"
let rapid = newVoiceClient(testMode = true)
rapid.state = Connected
var rapidAudio = ""
rapid.onAudio = proc(data: string) =
  ## Collects only the replacement response's audio.
  rapidAudio.add(data)
rapid.sendText("Old prompt")
rapid.interrupt(0)
rapid.sendText("New prompt")
rapid.event(%*{"type": "response.created", "response": {"id": "old"}})
rapid.event(%*{"type": "response.output_audio.delta", "item_id": "old-item",
  "response_id": "old", "delta": base64.encode(pcm)})
doAssert rapidAudio.len == 0
doAssert rapid.responseActive
rapid.event(%*{"type": "response.created", "response": {"id": "new"}})
rapid.event(%*{"type": "response.output_audio.delta", "item_id": "new-item",
  "response_id": "new", "delta": base64.encode(pcm)})
rapid.event(%*{"type": "response.done", "response": {"id": "old", "status": "cancelled"}})
doAssert rapid.responseActive
doAssert rapidAudio == pcm

echo "Testing bounded history and text storage"
for i in 0 ..< 100:
  client.event(%*{"type": "conversation.item.input_audio_transcription.completed",
    "item_id": "bounded_" & $i, "transcript": "word"})
doAssert client.transcripts.len == 80
client.event(%*{"type": "conversation.item.input_audio_transcription.completed",
  "item_id": "long", "transcript": repeat("x", 20000)})
doAssert client.transcripts[^1].text.len == 16000
client.disconnect()
doAssert client.state == Disconnected
client.sendAudio(pcm)

echo "Testing API rejection diagnostics preserve details and redact keys"
let rejected = newVoiceClient(testMode = true)
rejected.state = Connecting
rejected.event(%*{"type": "error", "error": {
  "code": "invalid_api_key", "param": "authorization",
  "message": "Incorrect API key: sk-proj-test_secret. Check credentials."
}})
doAssert rejected.state == Failed
doAssert "invalid_api_key" in rejected.status
doAssert "authorization" in rejected.status
doAssert "Check credentials" in rejected.status
doAssert "sk-proj-test_secret" notin rejected.status
doAssert "[redacted]" in rejected.status
doAssert rejected.failure == rejected.status

echo "Testing failed response diagnostics keep the underlying API error"
let failed = newVoiceClient(testMode = true)
failed.state = Connected
failed.event(%*{"type": "response.created", "response": {"id": "failed"}})
failed.event(%*{"type": "response.done", "response": {
  "id": "failed", "status": "failed", "status_details": {"error": {
    "code": "rate_limit_exceeded", "message": "Please retry shortly."
  }}
}})
doAssert not failed.responseActive
doAssert "rate_limit_exceeded" in failed.status
doAssert "Please retry shortly" in failed.status
doAssert failed.failure == failed.status

echo "Testing manual transcripts without an independent response"
let transcriber = newVoiceClient(testMode = true)
transcriber.autoRespond = false
transcriber.instructions = "Speak as Moss, a gentle woodland creature."
transcriber.voice = "cedar"
transcriber.connect("test-credential")
doAssert transcriber.state == Connecting
doAssert transcriber.testEvents.len == 0
transcriber.event(%*{"type": "session.created"})
doAssert transcriber.sent(0){"session", "instructions"}.getStr() ==
  transcriber.instructions
doAssert transcriber.sent(0){"session", "audio", "output", "voice"}.getStr() ==
  "cedar"
transcriber.event(%*{"type": "session.updated"})
transcriber.testEvents.setLen(0)
transcriber.sendAudio(pcm)
transcriber.commitAudio()
doAssert transcriber.testEvents.len == 2
doAssert transcriber.sent(1){"type"}.getStr() == "input_audio_buffer.commit"
doAssert not transcriber.responseActive
transcriber.setHandsFree(true)
doAssert not transcriber.sessionEvent(){
  "session", "audio", "input", "turn_detection", "create_response"}.getBool()
var commands: seq[string]
transcriber.onTranscript = proc(text: string) =
  ## Collects complete successful commands for the existing game planner.
  commands.add(text)
transcriber.event(%*{"type": "input_audio_buffer.committed", "item_id": "walk"})
transcriber.event(%*{"type": "conversation.item.input_audio_transcription.delta",
  "item_id": "walk", "delta": "Go to"})
doAssert commands.len == 0
transcriber.event(%*{"type": "conversation.item.input_audio_transcription.completed",
  "item_id": "walk", "transcript": "Go to Willow."})
transcriber.event(%*{"type": "conversation.item.input_audio_transcription.completed",
  "item_id": "walk", "transcript": "Go to Willow."})
doAssert commands == @["Go to Willow."]
transcriber.event(%*{"type": "input_audio_buffer.committed", "item_id": "bad"})
transcriber.event(%*{"type": "conversation.item.input_audio_transcription.failed",
  "item_id": "bad", "error": {"message": "Recording was unclear."}})
doAssert "Recording was unclear" in transcriber.failure
transcriber.event(%*{"type": "conversation.item.input_audio_transcription.completed",
  "item_id": "bad", "transcript": "Invented late command"})
transcriber.event(%*{"type": "input_audio_buffer.committed", "item_id": "empty"})
transcriber.event(%*{"type": "conversation.item.input_audio_transcription.completed",
  "item_id": "empty", "transcript": "   "})
transcriber.event(%*{"type": "conversation.item.input_audio_transcription.completed",
  "transcript": "Missing identity"})
doAssert commands == @["Go to Willow.", ""]

echo "Testing discarded recordings remain invalid during a replacement turn"
let reordered = newVoiceClient(testMode = true)
reordered.state = Connected
reordered.autoRespond = false
var reorderedCommands: seq[string]
reordered.onTranscript = proc(text: string) =
  ## Collects only the current input epoch even when older results arrive late.
  reorderedCommands.add(text)
reordered.sendAudio(pcm)
reordered.commitAudio()
reordered.discardTranscripts()
reordered.sendAudio(pcm[0 ..< 2400])
reordered.event(%*{"type": "input_audio_buffer.committed", "item_id": "old"})
reordered.sendAudio(pcm[2400 .. ^1])
reordered.commitAudio()
doAssert reordered.sent(reordered.testEvents.len - 1){"type"}.getStr() ==
  "input_audio_buffer.commit",
  "An older acknowledgment must not clear bytes of the new manual turn."
reordered.event(%*{"type": "conversation.item.input_audio_transcription.completed",
  "item_id": "new", "transcript": "Only this order."})
doAssert reorderedCommands.len == 0,
  "Unassociated completion waits for its committed item identity."
reordered.event(%*{"type": "conversation.item.input_audio_transcription.completed",
  "item_id": "old", "transcript": "Discarded dangerous order."})
doAssert reorderedCommands.len == 0
reordered.event(%*{"type": "input_audio_buffer.committed", "item_id": "new"})
doAssert reorderedCommands == @["Only this order."]
reordered.event(%*{"type": "conversation.item.input_audio_transcription.completed",
  "item_id": "new", "transcript": "Only this order."})
doAssert reorderedCommands == @["Only this order."]
for i in 0 ..< 10:
  reordered.sendAudio(pcm)
  reordered.commitAudio()
doAssert "not been acknowledged" in reordered.failure

echo "Testing isolated speech repeats the approved reply"
transcriber.testEvents.setLen(0)
let reply = "I could not find a way across the Willow Stream."
doAssert transcriber.speakText(reply)
doAssert transcriber.failure.len == 0
doAssert transcriber.testEvents.len == 1
let speechRequest = transcriber.sent(0){"response"}
doAssert speechRequest{"conversation"}.getStr() == "none"
doAssert speechRequest{"output_modalities"}[0].getStr() == "audio"
doAssert speechRequest{"input"}[0]{"content"}[0]{"text"}.getStr() == reply
doAssert speechRequest{"tools"}.len == 0
doAssert speechRequest{"tool_choice"}.getStr() == "none"
doAssert "exactly as written" in speechRequest{"instructions"}.getStr()
doAssert not transcriber.speakText("Do not start two overlapping replies.")
transcriber.event(%*{"type": "response.created", "response": {"id": "spoken"}})
transcriber.event(%*{"type": "response.output_audio.delta", "item_id": "outside",
  "response_id": "spoken", "delta": base64.encode(pcm)})
transcriber.interrupt(0)
doAssert transcriber.testEvents.len == 2
doAssert transcriber.sent(1){"type"}.getStr() == "response.cancel"
doAssert transcriber.sent(1){"response_id"}.getStr() == "spoken"
# Out-of-conversation output is not a stored item that can be truncated.
doAssert not transcriber.responseActive
transcriber.event(%*{"type": "response.done",
  "response": {"id": "spoken", "status": "cancelled"}})
doAssert transcriber.speakText("Ready again.")
let beforeEarlyCancel = transcriber.testEvents.len
transcriber.interrupt(0)
doAssert transcriber.testEvents.len == beforeEarlyCancel
transcriber.event(%*{"type": "response.created", "response": {"id": "early"}})
doAssert transcriber.sent(beforeEarlyCancel){"type"}.getStr() == "response.cancel"
doAssert transcriber.sent(beforeEarlyCancel){"response_id"}.getStr() == "early"
doAssert not transcriber.responseActive
transcriber.disconnect()
doAssert not transcriber.speakText("Disconnected.")
transcriber.connect("bad\ncredential")
doAssert transcriber.state == Failed
doAssert "newline" in transcriber.failure
doAssert "credential" notin transcriber.failure

echo "Realtime protocol tests passed"
