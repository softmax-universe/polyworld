import
  std/[asyncdispatch, base64, deques, httpclient, json, os, sha1,
    strutils, sysrand, times, uri],
  jsony, ws

const
  DefaultModel* = "gpt-realtime-2.1-mini"
  DefaultVoice* = "marin"
  MaxTranscriptEntries = 80
  MaxTranscriptBytes = 16000
  MaxQueuedBytes = 2 * 1024 * 1024
  Instructions = "You are a friendly voice companion in a small Polyworld " &
    "experiment. Speak naturally and briefly, usually one or two sentences. " &
    "Answer the user directly. You cannot see their screen or control games."

type
  VoiceError* = object of CatchableError
  VoiceState* = enum
    Disconnected, Connecting, Connected, Failed
  TranscriptRole* = enum
    User, Assistant
  Transcript* = object
    role*: TranscriptRole
    itemId*, text*: string
    final*: bool
  VoiceClient* = ref object
    state*: VoiceState
    status*, model*, voice*: string
    credential: string
    transcripts*: seq[Transcript]
    responseActive*, handsFree*: bool
    onAudio*: proc(pcm: string)
    onAudioStart*, onSpeechStart*: proc()
    socket: WebSocket
    http: AsyncHttpClient
    outgoing: Deque[string]
    queuedBytes, inputBytes, generation: int
    writing: bool
    pendingResponses: Deque[bool]
    responseId, audioItem, suppressedResponse: string
    audioBytes: int
    connectedAt: float64
    eventCounter: int
    testMode: bool
    testEvents*: seq[string]

proc stopTransport(client: VoiceClient) =
  ## Invalidates pending work before detaching and closing its transport.
  inc client.generation
  let
    socket = client.socket
    http = client.http
  client.socket = nil
  client.http = nil
  client.credential = ""
  client.outgoing.clear()
  client.queuedBytes = 0
  client.writing = false
  client.pendingResponses.clear()
  if socket != nil:
    socket.hangup()
  if http != nil:
    http.close()

proc fail(client: VoiceClient, message: string) =
  ## Stops the session while preserving the original user-facing error.
  client.stopTransport()
  client.state = Failed
  client.status = message
  client.responseActive = false

proc key(): string =
  ## Reads the same credential sources as the existing Polyworld OpenAI code.
  result = getEnv("OPENAI_API_KEY").strip()
  if result.len == 0:
    let path = getHomeDir() / "secrets" / "openai.key"
    if fileExists(path):
      result = readFile(path).strip()
  if result.len == 0:
    raise newException(VoiceError,
      "Set OPENAI_API_KEY or add ~/secrets/openai.key, then reconnect.")
  if '\r' in result or '\n' in result:
    raise newException(VoiceError, "The OpenAI key contains a newline.")

proc newVoiceClient*(testMode = false): VoiceClient =
  ## Creates a disconnected client without reading credentials or networking.
  VoiceClient(
    model: getEnv("OPENAI_REALTIME_MODEL", DefaultModel),
    voice: getEnv("OPENAI_REALTIME_VOICE", DefaultVoice),
    status: "Connect to start a conversation.",
    testMode: testMode
  )

proc sessionEvent*(client: VoiceClient): JsonNode =
  ## Builds the current GA Realtime session configuration.
  let turn =
    if client.handsFree:
      %*{"type": "server_vad", "threshold": 0.55,
        "prefix_padding_ms": 300, "silence_duration_ms": 450,
        "create_response": true, "interrupt_response": true}
    else:
      newJNull()
  %*{
    "type": "session.update",
    "session": {
      "type": "realtime",
      "instructions": Instructions,
      "output_modalities": ["audio"],
      "max_output_tokens": 600,
      "audio": {
        "input": {
          "format": {"type": "audio/pcm", "rate": 24000},
          "noise_reduction": {"type": "near_field"},
          "transcription": {"model": "gpt-4o-mini-transcribe"},
          "turn_detection": turn
        },
        "output": {
          "format": {"type": "audio/pcm", "rate": 24000},
          "voice": client.voice
        }
      }
    }
  }

proc flush(client: VoiceClient, generation: int) {.async.} =
  ## Serializes queued writes so audio and turn events cannot overtake each other.
  let socket = client.socket
  try:
    while generation == client.generation and client.outgoing.len > 0:
      if socket == nil or socket.readyState != Open:
        raise newException(VoiceError, "Connection closed while sending.")
      let message = client.outgoing.popFirst()
      client.queuedBytes -= message.len
      await socket.send(message)
      if generation != client.generation:
        return
      if socket.readyState != Open:
        raise newException(VoiceError, "Connection closed while sending.")
  except CatchableError:
    if generation == client.generation:
      client.fail("Connection lost while sending. Reconnect to try again.")
  finally:
    if generation == client.generation:
      client.writing = false

proc emit(client: VoiceClient, event: JsonNode) =
  ## Queues one event within a bounded transport buffer.
  let message = event.toJson()
  if client.testMode:
    client.testEvents.add(message)
    return
  if client.socket == nil or client.socket.readyState != Open:
    return
  if client.queuedBytes + message.len > MaxQueuedBytes:
    client.fail("Network cannot keep up with audio. Reconnect to try again.")
    return
  client.outgoing.addLast(message)
  client.queuedBytes += message.len
  if not client.writing:
    client.writing = true
    asyncCheck client.flush(client.generation)

proc entry(client: VoiceClient, id: string, role: TranscriptRole): int =
  ## Finds or creates a transcript entry with bounded conversation history.
  for i, item in client.transcripts:
    if item.itemId == id:
      return i
  if client.transcripts.len >= MaxTranscriptEntries:
    client.transcripts.delete(0)
  result = client.transcripts.len
  client.transcripts.add(Transcript(itemId: id, role: role))

proc prefix(text: string, limit: int): string =
  ## Limits text storage without splitting a UTF-8 character.
  var count = min(text.len, max(0, limit))
  if count < text.len:
    while count > 0 and (text[count].ord and 0xc0) == 0x80:
      dec count
  text[0 ..< count]

proc safeDetail(client: VoiceClient, text: string, limit = 360): string =
  ## Bounds diagnostics and removes credentials before displaying API errors.
  var cleaned = text
  if client.credential.len > 0:
    cleaned = cleaned.replace(client.credential, "[redacted]")
  var index = 0
  while index < cleaned.len:
    if cleaned.continuesWith("sk-", index):
      result.add("[redacted]")
      index += 3
      while index < cleaned.len and
        cleaned[index] in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '-', '_', '*'}:
          inc index
    else:
      result.add(cleaned[index])
      inc index
  result = result.splitWhitespace().join(" ").prefix(limit)

proc apiError(client: VoiceClient, error: JsonNode, fallback: string): string =
  ## Preserves the server's code, parameter and explanation without secrets.
  let
    code = client.safeDetail(error{"code"}.getStr(), 80)
    param = client.safeDetail(error{"param"}.getStr(), 100)
    message = client.safeDetail(error{"message"}.getStr())
  result = fallback
  if code.len > 0:
    result.add(" [" & code & "]")
  if param.len > 0:
    result.add(" (" & param & ")")
  if message.len > 0:
    result.add(": " & message)

proc putText(
  client: VoiceClient, id: string, role: TranscriptRole,
  text: string, final = false
) =
  ## Replaces a final transcript or appends one streaming delta.
  if id.len == 0:
    return
  let i = client.entry(id, role)
  if final:
    client.transcripts[i].text = text.prefix(MaxTranscriptBytes)
  elif not client.transcripts[i].final:
    let remaining = MaxTranscriptBytes - client.transcripts[i].text.len
    client.transcripts[i].text.add(text.prefix(remaining))
  client.transcripts[i].final = final

proc receiveEvent*(client: VoiceClient, message: string) =
  ## Applies a server event and emits audio callbacks on the UI thread.
  let
    event = message.fromJson(JsonNode)
    kind = event{"type"}.getStr()
    itemId = event{"item_id"}.getStr()
    responseId = event{"response_id"}.getStr()
  if responseId.len > 0 and responseId == client.suppressedResponse:
    return
  case kind
  of "session.created":
    client.emit(client.sessionEvent())
  of "session.updated":
    client.state = Connected
    client.status = "Ready. Hold to talk, or type a message."
  of "input_audio_buffer.committed":
    discard client.entry(itemId, User)
    client.inputBytes = 0
  of "input_audio_buffer.speech_started":
    client.status = "Listening..."
    if client.onSpeechStart != nil:
      client.onSpeechStart()
  of "input_audio_buffer.speech_stopped":
    client.status = "Thinking..."
  of "conversation.item.input_audio_transcription.delta":
    client.putText(itemId, User, event{"delta"}.getStr())
  of "conversation.item.input_audio_transcription.completed":
    client.putText(itemId, User, event{"transcript"}.getStr(), true)
  of "conversation.item.input_audio_transcription.failed":
    client.putText(itemId, User, "[Transcription unavailable]", true)
  of "response.created":
    client.responseId = event{"response", "id"}.getStr()
    if client.pendingResponses.len > 0 and client.pendingResponses.popFirst():
      client.suppressedResponse = client.responseId
      return
    client.responseActive = true
    client.status = "Thinking..."
  of "response.output_audio.delta":
    if itemId != client.audioItem:
      client.audioItem = itemId
      client.audioBytes = 0
      if client.onAudioStart != nil:
        client.onAudioStart()
    let pcm = base64.decode(event{"delta"}.getStr())
    client.audioBytes += pcm.len
    client.status = "Speaking..."
    if client.onAudio != nil:
      client.onAudio(pcm)
  of "response.output_audio_transcript.delta", "response.output_text.delta":
    client.putText(itemId, Assistant, event{"delta"}.getStr())
  of "response.output_audio_transcript.done":
    client.putText(itemId, Assistant, event{"transcript"}.getStr(), true)
  of "response.output_text.done":
    client.putText(itemId, Assistant, event{"text"}.getStr(), true)
  of "response.done":
    let
      response = event{"response"}
      id = response{"id"}.getStr()
    if id == client.suppressedResponse:
      return
    if id.len > 0 and id != client.responseId:
      return
    client.responseActive = false
    if response{"status"}.getStr() == "failed":
      client.status = client.apiError(response{"status_details", "error"},
        "OpenAI response failed")
    else:
      client.status = "Ready. Hold to talk, or type a message."
  of "error":
    let code = event{"error", "code"}.getStr()
    if code notin ["response_cancel_not_active", "input_audio_buffer_commit_empty"]:
      client.status = client.apiError(event{"error"}, "OpenAI rejected an event")
      client.pendingResponses.clear()
      if client.state == Connecting:
        client.fail(client.status)
      else:
        client.responseActive = false
  else:
    discard

proc disconnect*(client: VoiceClient) =
  ## Closes transport and makes late callbacks from prior sessions harmless.
  client.stopTransport()
  client.state = Disconnected
  client.responseActive = false
  client.status = "Disconnected."
  client.outgoing.clear()
  client.queuedBytes = 0
  client.inputBytes = 0
  client.writing = false
  client.audioItem = ""
  client.responseId = ""
  client.suppressedResponse = ""
  client.pendingResponses.clear()

proc run(
  client: VoiceClient, generation: int, apiKey: string,
  endpoint = "https://api.openai.com/v1/realtime"
) {.async.} =
  ## Opens an authenticated upgrade using the existing Windy ws dependency.
  var http: AsyncHttpClient
  try:
    http = newAsyncHttpClient()
    client.http = http
    client.credential = apiKey
    let
      randomBytes = urandom(16)
      socketKey = base64.encode(randomBytes)
    http.headers = newHttpHeaders({
      "Authorization": "Bearer " & apiKey,
      "Connection": "Upgrade",
      "Upgrade": "websocket",
      "Sec-WebSocket-Version": "13",
      "Sec-WebSocket-Key": socketKey
    })
    let request = http.get(
      endpoint & "?model=" & encodeUrl(client.model)
    )
    if not await request.withTimeout(20000):
      raise newException(VoiceError, "Connection timed out.")
    let response = request.read()
    if generation != client.generation:
      http.close()
      return
    if response.code.int != 101:
      var message = "OpenAI connection returned HTTP " & $response.code.int
      let body = response.body()
      if await body.withTimeout(2000):
        try:
          let error = body.read().fromJson(JsonNode){"error"}
          message = client.apiError(error, message)
        except CatchableError:
          discard
      if generation == client.generation:
        client.fail(message)
      return
    let expected = base64.encode(ws.decodeBase16($secureHash(
      socketKey & "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    )))
    if response.headers.getOrDefault("Sec-WebSocket-Accept") != expected:
      raise newException(VoiceError, "Invalid WebSocket upgrade.")
    let socket = WebSocket(
      tcpSocket: http.getSocket(), masked: true, readyState: Open
    )
    client.socket = socket
    while generation == client.generation and
      client.state in {Connecting, Connected} and socket.readyState == Open:
        let message = await socket.receiveStrPacket()
        if generation == client.generation and message.len > 0:
          client.receiveEvent(message)
    if generation == client.generation and
      client.state in {Connecting, Connected}:
        client.fail("Voice connection closed. Reconnect to try again.")
  except CatchableError:
    if generation == client.generation and client.state != Failed:
      client.fail("Voice connection lost. Reconnect to try again.")
  finally:
    if http != nil:
      http.close()

proc connect*(client: VoiceClient) =
  ## Starts a fresh conversation without blocking window event processing.
  client.disconnect()
  client.transcripts.setLen(0)
  try:
    let apiKey = key()
    client.state = Connecting
    client.status = "Connecting to OpenAI..."
    client.connectedAt = epochTime()
    asyncCheck client.run(client.generation, apiKey)
  except CatchableError as error:
    client.fail(error.msg)

proc poll*(client: VoiceClient) =
  ## Advances this experiment's async transport without blocking the UI.
  if hasPendingOperations():
    asyncdispatch.poll(0)
  if client.state == Connecting and epochTime() - client.connectedAt > 25:
    client.disconnect()
    client.fail("Voice connection timed out. Reconnect to try again.")

proc clearAudio*(client: VoiceClient) =
  ## Discards an incomplete push-to-talk turn.
  client.inputBytes = 0
  if client.state == Connected:
    client.emit(%*{"type": "input_audio_buffer.clear"})

proc sendAudio*(client: VoiceClient, pcm: string) =
  ## Streams mono PCM16 samples at 24 kHz while a session is ready.
  if client.state != Connected or pcm.len == 0:
    return
  if pcm.len mod 2 != 0:
    raise newException(VoiceError, "PCM16 audio must contain whole samples.")
  client.inputBytes += pcm.len
  client.emit(%*{"type": "input_audio_buffer.append", "audio": base64.encode(pcm)})

proc commitAudio*(client: VoiceClient) =
  ## Commits a manual turn only after the API's 100 ms minimum audio length.
  if client.state != Connected or client.handsFree:
    return
  if client.pendingResponses.len >= 4:
    client.clearAudio()
    client.status = "Waiting for earlier turns. Try again shortly."
    return
  if client.inputBytes < 4800:
    client.clearAudio()
    client.status = "Hold to talk a little longer."
    return
  client.emit(%*{"type": "input_audio_buffer.commit"})
  client.emit(%*{"type": "response.create"})
  client.pendingResponses.addLast(false)
  client.inputBytes = 0
  client.responseActive = true
  client.status = "Thinking..."

proc interrupt*(client: VoiceClient, playedMs: int) =
  ## Cancels generation and removes unheard audio from the server conversation.
  if client.state != Connected:
    return
  if client.responseActive:
    client.emit(%*{"type": "response.cancel"})
    if client.pendingResponses.len > 0:
      client.pendingResponses[^1] = true
  if client.audioItem.len > 0 and playedMs < client.audioBytes div 48:
    client.emit(%*{
      "type": "conversation.item.truncate",
      "item_id": client.audioItem,
      "content_index": 0,
      "audio_end_ms": max(0, playedMs)
    })
  client.suppressedResponse = client.responseId
  client.audioItem = ""
  client.audioBytes = 0
  client.responseActive = false

proc sendText*(client: VoiceClient, text: string) =
  ## Adds a typed user turn and asks for the same streamed spoken response.
  let content = text.strip().prefix(MaxTranscriptBytes)
  if client.state != Connected or content.len == 0:
    return
  if client.pendingResponses.len >= 4:
    client.status = "Waiting for earlier turns. Try again shortly."
    return
  inc client.eventCounter
  let id = "user_" & $client.generation & "_" & $client.eventCounter
  client.putText(id, User, content, true)
  client.emit(%*{
    "type": "conversation.item.create",
    "item": {"id": id, "type": "message", "role": "user",
      "content": [{"type": "input_text", "text": content}]}
  })
  client.emit(%*{"type": "response.create"})
  client.pendingResponses.addLast(false)
  client.responseActive = true
  client.status = "Thinking..."

proc setHandsFree*(client: VoiceClient, enabled: bool) =
  ## Changes turn detection after the UI has stopped and drained capture.
  client.handsFree = enabled
  client.clearAudio()
  if client.state == Connected:
    client.emit(client.sessionEvent())
