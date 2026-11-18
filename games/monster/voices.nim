import
  std/[monotimes, os, strutils, times],
  ../../experiments/voice/[audios, realtimes],
  brains, common, conversations

export realtimes.VoiceState

const
  CreatureVoice* = "cedar"
  CreatureDelivery* = "You perform the voice of Moss, a large, curious " &
    "woodland creature. Use a low, warm, gently gravelly, rumbling voice, " &
    "with a little playful creature texture. Speak clearly and naturally, " &
    "never like an announcer. Read the supplied dialogue exactly; do not " &
    "answer it, improvise, add growls as words, or describe actions."
  MaxQueuedSpeech = 4
  MaxQueuedCommands = 8

type
  ChatMode* = enum
    TextMode, ConversationMode
  MonsterVoice* = ref object
    client*: VoiceClient
    mode*: ChatMode
    enabled*, hasKey*: bool
    error*, pendingText*: string
    waitingForTranscript*: bool
    audio: VoiceAudio
    messageCursor, inputPending: int
    speech, commands: seq[string]
    transcriptionStarted: MonoTime
    credential: string
    retriedKey, playbackSuppressed, audioActive: bool
    deviceFree, captureActive, userSpeaking, suspended: bool
    waitingPermission: bool

proc listening*(voice: MonsterVoice): bool =
  ## Reports an active continuous microphone session without opening devices.
  voice.captureActive

proc speaking*(voice: MonsterVoice): bool =
  ## Reports generated speech still queued on the speaker.
  voice.audioActive

proc stopSpeech(voice: MonsterVoice) =
  ## Cancels audible speech while leaving the continuous microphone running.
  var played = 0
  try:
    played = voice.audio.playbackMilliseconds()
  except VoiceAudioError as error:
    voice.error = error.msg
  voice.client.interrupt(played)
  voice.audio.stopPlayback()
  voice.audioActive = false
  voice.playbackSuppressed = true
  voice.speech.setLen(0)

proc discardInput(voice: MonsterVoice) =
  ## Invalidates unfinished and queued speech without changing the chat mode.
  voice.client.discardTranscripts()
  voice.client.clearAudio()
  if not voice.deviceFree:
    try:
      discard voice.audio.readCapture()
    except VoiceAudioError as error:
      voice.error = error.msg
  voice.waitingForTranscript = false
  voice.inputPending = 0
  voice.userSpeaking = false
  voice.pendingText.setLen(0)
  voice.commands.setLen(0)

proc stopListening(voice: MonsterVoice) =
  ## Closes continuous capture and rejects unfinished speech from that session.
  voice.audio.stopCapture()
  voice.captureActive = false
  voice.waitingPermission = false
  voice.discardInput()

proc interrupt*(voice: MonsterVoice, discardInput = true) =
  ## Interrupts a reply without switching off conversation-mode listening.
  voice.stopSpeech()
  if discardInput:
    voice.discardInput()

proc refreshKey*(voice: MonsterVoice) =
  ## Checks native OpenAI credentials without opening a voice connection.
  voice.hasKey = false
  if not voice.enabled:
    return
  try:
    voice.credential = openaiKey()
    voice.hasKey = voice.credential.len > 0
  except MonsterError as error:
    voice.error = error.msg

proc connect*(voice: MonsterVoice) =
  ## Connects voice only with a separately configured native OpenAI key.
  if not voice.enabled:
    return
  voice.stopSpeech()
  voice.stopListening()
  voice.client.disconnect()
  voice.error.setLen(0)
  voice.retriedKey = false
  voice.refreshKey()
  if not voice.hasKey:
    voice.mode = TextMode
    if voice.error.len == 0:
      voice.error = "Conversation requires an OpenAI key. Set " &
        "OPENAI_API_KEY or add ~/secrets/openai.key. Text chat is available."
    return
  voice.client.connect(voice.credential)

proc setMode*(voice: MonsterVoice, mode: ChatMode) =
  ## Chooses continuous conversation or text with no microphone or voice output.
  if mode == TextMode:
    voice.stopSpeech()
    voice.stopListening()
    voice.client.disconnect()
    voice.credential.setLen(0)
    voice.mode = TextMode
    voice.error.setLen(0)
    return
  if not voice.enabled:
    return
  voice.error.setLen(0)
  voice.refreshKey()
  if not voice.hasKey:
    let keyError = voice.error
    voice.setMode(TextMode)
    voice.error =
      if keyError.len > 0: keyError
      else: "Conversation requires an OpenAI key. Text chat is available."
    return
  voice.mode = ConversationMode
  voice.suspended = false
  if voice.client.state notin [Connected, Connecting]:
    voice.connect()

proc queueCommand(voice: MonsterVoice, text: string) =
  ## Preserves complete spoken turns while allowing an urgent stop to pass.
  let spoken = text.strip()
  if spoken.len == 0:
    return
  if spoken.len > 4096:
    voice.error = "That spoken message was too long. Try a shorter command."
    return
  if spoken.isStopCommand():
    voice.pendingText = spoken
    voice.commands.setLen(0)
  elif voice.pendingText.len == 0:
    voice.pendingText = spoken
  elif voice.commands.len < MaxQueuedCommands:
    voice.commands.add(spoken)
  else:
    voice.error = "Moss has too many queued instructions. Wait for a reply."

proc newMonsterVoice*(
  historyCount = 0,
  enabled = true,
  testMode = false,
  deviceFree = false
): MonsterVoice =
  ## Begins in text mode with dormant microphone and network resources.
  result = MonsterVoice(
    client: newVoiceClient(testMode), audio: newVoiceAudio(duplex = true),
    enabled: enabled, messageCursor: historyCount,
    deviceFree: testMode or deviceFree
  )
  let voice = result
  voice.client.voice = getEnv("OPENAI_REALTIME_VOICE", CreatureVoice)
  voice.client.instructions = CreatureDelivery
  voice.client.autoRespond = false
  voice.client.handsFree = true
  voice.client.semanticVad = true
  voice.client.onSpeechStart = proc() =
    ## Lets the player interrupt Moss without closing the microphone.
    if voice.mode != ConversationMode or not voice.listening():
      return
    voice.stopSpeech()
    voice.userSpeaking = true
  voice.client.onSpeechStop = proc() =
    ## Waits for the automatically committed turn after a natural pause.
    if voice.mode != ConversationMode or not voice.listening():
      return
    voice.userSpeaking = false
    voice.waitingForTranscript = true
    voice.transcriptionStarted = getMonoTime()
  voice.client.onInputCommit = proc() =
    ## Counts complete utterances whose final transcripts are still pending.
    if voice.mode != ConversationMode or not voice.listening():
      return
    inc voice.inputPending
    voice.waitingForTranscript = true
    voice.transcriptionStarted = getMonoTime()
  voice.client.onTranscript = proc(text: string) =
    ## Queues recognized speech through the same planner as typed commands.
    if voice.mode != ConversationMode or not voice.listening():
      return
    voice.inputPending = max(0, voice.inputPending - 1)
    voice.waitingForTranscript = voice.inputPending > 0
    voice.queueCommand(text)
  voice.client.onTranscriptError = proc(message: string) =
    ## Recovers from one unclear utterance while preserving newer speech.
    if voice.mode != ConversationMode or not voice.listening():
      return
    voice.inputPending = max(0, voice.inputPending - 1)
    voice.waitingForTranscript = voice.inputPending > 0
    voice.error = message
  voice.client.onAudioStart = proc() =
    ## Starts a fresh playback timeline for one approved creature reply.
    voice.audio.stopPlayback()
    voice.playbackSuppressed = voice.mode != ConversationMode
  voice.client.onAudio = proc(pcm: string) =
    ## Streams Moss's speech while the microphone continues listening.
    if voice.mode != ConversationMode or voice.playbackSuppressed or
      voice.deviceFree:
        return
    try:
      voice.audio.queuePcm(pcm)
    except VoiceAudioError as error:
      voice.setMode(TextMode)
      voice.error = error.msg

proc startListening(voice: MonsterVoice) =
  ## Enables continuous capture once after choosing conversation mode.
  if voice.listening() or voice.waitingPermission:
    return
  try:
    voice.client.clearAudio()
    if not voice.deviceFree:
      voice.audio.startCapture()
    voice.captureActive = true
    voice.suspended = false
  except VoiceAudioError as error:
    if microphonePermission() == "pending":
      voice.waitingPermission = true
      voice.error = "Allow microphone access to start Conversation."
    else:
      voice.setMode(TextMode)
      voice.error = error.msg

proc observe*(voice: MonsterVoice, messages: openArray[Message]) =
  ## Speaks only new creature dialogue produced during conversation mode.
  for i in min(voice.messageCursor, messages.len) ..< messages.len:
    if messages[i].role == CreatureMessage and voice.enabled and
      voice.mode == ConversationMode and not voice.suspended:
        if voice.speech.len == MaxQueuedSpeech:
          voice.speech.delete(0)
        voice.speech.add(messages[i].text)
  voice.messageCursor = messages.len

proc submitPending*(voice: MonsterVoice, world: var World, brain: Brain) =
  ## Delivers complete spoken turns in order through normal action validation.
  if voice.mode != ConversationMode or voice.pendingText.len == 0:
    return
  let stopping = voice.pendingText.isStopCommand()
  if not stopping and (brain.pending or brain.explanationPending):
    return
  let spoken = voice.pendingText
  voice.stopSpeech()
  if stopping:
    voice.discardInput()
  else:
    voice.pendingText =
      if voice.commands.len > 0: voice.commands[0]
      else: ""
    if voice.commands.len > 0:
      voice.commands.delete(0)
  if not world.speak(brain, spoken):
    voice.error = "Spoken command could not be sent. " & brain.failure

proc retryCredential(voice: MonsterVoice) =
  ## Retries an authentication rejection once with the configured local key.
  if voice.retriedKey or voice.client.state != Failed or
    ("HTTP 401" notin voice.client.status and
      "invalid_api_key" notin voice.client.status):
        return
  voice.retriedKey = true
  try:
    let fallback = openaiKey(preferFile = true)
    if fallback.len > 0 and fallback != voice.credential:
      voice.credential = fallback
      voice.client.connect(fallback)
  except MonsterError as error:
    voice.error = error.msg

proc poll*(voice: MonsterVoice, focused = true) =
  ## Streams both directions while VAD decides turns and the UI stays responsive.
  if not voice.enabled:
    return
  voice.client.poll()
  voice.retryCredential()
  if voice.client.state == Failed:
    let failure = voice.client.failure
    voice.stopSpeech()
    voice.stopListening()
    voice.mode = TextMode
    if "HTTP 401" in failure or "invalid_api_key" in failure:
      voice.hasKey = false
    voice.error = failure
    return
  if voice.mode == TextMode:
    return
  if not focused:
    if not voice.suspended:
      voice.stopSpeech()
      voice.stopListening()
      voice.suspended = true
    return
  if voice.waitingPermission:
    case microphonePermission()
    of "allowed":
      voice.waitingPermission = false
      voice.error.setLen(0)
    of "denied", "unconfigured":
      voice.setMode(TextMode)
      voice.error = "Microphone access is required for Conversation."
    else:
      return
  if voice.mode != ConversationMode:
    return
  if voice.client.state == Connected:
    voice.startListening()
  if voice.listening() and not voice.deviceFree:
    try:
      voice.client.sendAudio(voice.audio.readCapture())
    except VoiceAudioError as error:
      voice.setMode(TextMode)
      voice.error = error.msg
      return
  if voice.client.failure.len > 0:
    voice.error = voice.client.failure
    voice.client.failure.setLen(0)
  if voice.waitingForTranscript and
    (getMonoTime() - voice.transcriptionStarted).inSeconds > 30:
      voice.discardInput()
      voice.error = "Voice transcription timed out. Please say that again."
  try:
    voice.audio.pollPlayback()
    voice.audioActive = voice.audio.outputActive()
    if voice.mode == ConversationMode and voice.client.state == Connected and
      voice.listening() and not voice.userSpeaking and
      not voice.waitingForTranscript and voice.pendingText.len == 0 and
      not voice.client.responseActive and not voice.speaking() and
      voice.speech.len > 0:
        if voice.client.speakText(voice.speech[0]):
          voice.speech.delete(0)
  except VoiceAudioError as error:
    voice.setMode(TextMode)
    voice.error = error.msg

proc status*(voice: MonsterVoice): string =
  ## Describes the selected mode and automatic conversation activity.
  if voice.mode == TextMode:
    if voice.hasKey: "Type to Moss"
    else: "Conversation requires an OpenAI key"
  elif voice.waitingPermission: "Allow microphone access"
  elif voice.suspended: "Conversation paused"
  elif voice.client.state == Connecting: "Connecting..."
  elif voice.userSpeaking: "Listening to you..."
  elif voice.waitingForTranscript: "Understanding..."
  elif voice.pendingText.len > 0: "Command queued"
  elif voice.speaking() or voice.client.responseActive: "Moss is speaking"
  else: "Listening"

proc close*(voice: MonsterVoice) =
  ## Releases microphone, callbacks, playback, and connection on game exit.
  voice.stopSpeech()
  voice.stopListening()
  voice.client.onTranscript = nil
  voice.client.onTranscriptError = nil
  voice.client.onInputCommit = nil
  voice.client.onSpeechStart = nil
  voice.client.onSpeechStop = nil
  voice.client.onAudio = nil
  voice.client.onAudioStart = nil
  voice.client.disconnect()
  voice.client.poll()
  voice.credential.setLen(0)
  voice.audio.close()
