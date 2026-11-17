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
echo "Realtime protocol tests passed"
