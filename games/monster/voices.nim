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
  MaxRecordingSeconds = 30
  MaxQueuedSpeech = 4

type MonsterVoice* = ref object
  client*: VoiceClient
  audio: VoiceAudio
  enabled*, muted*: bool
  error*: string
  pendingText*: string
  waitingForTranscript*: bool
  messageCursor: int
  speech: seq[string]
  capturedBytes: int
  recordingStarted, transcriptionStarted: MonoTime
  credential: string
  retriedKey, playbackSuppressed, audioActive, testMode: bool

proc listening*(voice: MonsterVoice): bool =
  ## Reports live capture without opening a microphone.
  voice.audio.capturing()

proc speaking*(voice: MonsterVoice): bool =
  ## Reports generated speech still queued on the speaker.
  voice.audioActive

proc stopListening*(voice: MonsterVoice, commit = false) =
  ## Stops capture and submits only complete, explicitly finished recordings.
  if not voice.listening():
    return
  voice.audio.stopCapture()
  let tail = voice.audio.readCapture()
  if commit and voice.client.state == Connected:
    voice.capturedBytes += tail.len
    voice.client.sendAudio(tail)
    voice.waitingForTranscript = voice.capturedBytes >= 4800
    voice.transcriptionStarted = getMonoTime()
    voice.client.commitAudio()
  else:
    voice.client.clearAudio()
  voice.capturedBytes = 0

proc stopSpeech(voice: MonsterVoice) =
  ## Interrupts playback without discarding an active microphone recording.
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

proc interrupt*(voice: MonsterVoice, discardInput = true) =
  ## Stops older speech and optionally invalidates an unfinished spoken order.
  voice.stopSpeech()
  if discardInput:
    voice.stopListening()
    voice.client.discardTranscripts()
    voice.waitingForTranscript = false
    voice.pendingText.setLen(0)

proc connect*(voice: MonsterVoice) =
  ## Starts the voice connection using Monster's native OpenAI credentials.
  if not voice.enabled:
    return
  voice.interrupt()
  voice.error.setLen(0)
  voice.retriedKey = false
  try:
    voice.credential = openaiKey()
    if voice.credential.len == 0:
      raise newException(MonsterError,
        "Set OPENAI_API_KEY or add ~/secrets/openai.key to enable voice.")
    voice.client.connect(voice.credential)
  except MonsterError as error:
    voice.error = error.msg

proc newMonsterVoice*(
  historyCount = 0,
  enabled = true,
  muted = false,
  testMode = false
): MonsterVoice =
  ## Prepares one creature voice without replaying saved conversation.
  result = MonsterVoice(
    client: newVoiceClient(testMode), audio: newVoiceAudio(),
    enabled: enabled, muted: muted, messageCursor: historyCount,
    testMode: testMode
  )
  let voice = result
  voice.client.voice = getEnv("OPENAI_REALTIME_VOICE", CreatureVoice)
  voice.client.instructions = CreatureDelivery
  voice.client.autoRespond = false
  voice.client.onTranscript = proc(text: string) =
    ## Makes only the current, completed microphone turn a game instruction.
    if not voice.waitingForTranscript:
      return
    voice.waitingForTranscript = false
    let spoken = text.strip()
    if spoken.len == 0:
      voice.error = "I didn't catch that. Try Talk again."
    elif spoken.len > 4096:
      voice.error = "That spoken message was too long. Try a shorter command."
    else:
      voice.pendingText = spoken
  voice.client.onAudioStart = proc() =
    ## Starts a fresh playback timeline for one approved creature reply.
    voice.audio.stopPlayback()
    voice.playbackSuppressed = voice.muted
  voice.client.onAudio = proc(pcm: string) =
    ## Streams voice without turning playback failures into game failures.
    if voice.muted or voice.playbackSuppressed or voice.testMode:
      return
    try:
      voice.audio.queuePcm(pcm)
    except VoiceAudioError as error:
      voice.error = error.msg
      voice.playbackSuppressed = true
      voice.muted = true
      voice.audio.stopPlayback()

proc beginListening*(voice: MonsterVoice) =
  ## Records only after Talk, keeping pending transcriptions in order.
  if not voice.enabled or voice.client.state != Connected:
    return
  if voice.waitingForTranscript or voice.pendingText.len > 0:
    voice.error = "Your spoken command is still being processed."
    return
  voice.interrupt()
  voice.error.setLen(0)
  voice.client.failure.setLen(0)
  voice.client.clearAudio()
  try:
    voice.audio.startCapture()
    voice.recordingStarted = getMonoTime()
    voice.capturedBytes = 0
  except VoiceAudioError as error:
    voice.error = error.msg

proc toggleListening*(voice: MonsterVoice) =
  ## Uses the same Talk control to finish a recording and request its transcript.
  if voice.listening():
    voice.stopListening(commit = true)
  else:
    voice.beginListening()

proc setMuted*(voice: MonsterVoice, muted: bool) =
  ## Changes audible replies without disabling typed or spoken commands.
  voice.muted = muted
  if muted:
    voice.stopSpeech()

proc observe*(voice: MonsterVoice, messages: openArray[Message]) =
  ## Speaks new creature lines once, excluding events and private feedback.
  for i in min(voice.messageCursor, messages.len) ..< messages.len:
    if messages[i].role == CreatureMessage and voice.enabled and
      not voice.muted:
        if voice.speech.len == MaxQueuedSpeech:
          voice.speech.delete(0)
        voice.speech.add(messages[i].text)
  voice.messageCursor = messages.len

proc submitPending*(voice: MonsterVoice, world: var World, brain: Brain) =
  ## Routes transcribed speech through the same memory and action validation.
  if voice.pendingText.len == 0:
    return
  let stopping = voice.pendingText.isStopCommand()
  if not stopping and (brain.pending or brain.explanationPending):
    return
  let spoken = voice.pendingText
  if stopping:
    voice.interrupt()
  else:
    voice.stopSpeech()
  if world.speak(brain, spoken):
    voice.pendingText.setLen(0)
  else:
    voice.error = "Spoken command could not be sent. " & brain.failure
    voice.pendingText.setLen(0)

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
  ## Advances voice networking, bounded capture, and speech without blocking.
  if not voice.enabled:
    return
  voice.client.poll()
  voice.retryCredential()
  if voice.client.state in [Disconnected, Failed]:
    voice.stopListening()
    voice.audio.stopPlayback()
    voice.audioActive = false
    voice.waitingForTranscript = false
    voice.speech.setLen(0)
  if voice.listening():
    if not focused:
      voice.stopListening()
    else:
      let pcm = voice.audio.readCapture()
      voice.capturedBytes += pcm.len
      voice.client.sendAudio(pcm)
      if (getMonoTime() - voice.recordingStarted).inSeconds >=
        MaxRecordingSeconds:
          voice.stopListening(commit = true)
  if voice.client.failure.len > 0:
    voice.error = voice.client.failure
    voice.waitingForTranscript = false
  if voice.waitingForTranscript and
    (getMonoTime() - voice.transcriptionStarted).inSeconds > 30:
      voice.waitingForTranscript = false
      voice.error = "Voice transcription timed out. Try Talk again."
  try:
    voice.audio.pollPlayback()
    voice.audioActive = voice.audio.outputActive()
    if voice.client.state == Connected and not voice.muted and
      not voice.listening() and not voice.waitingForTranscript and
      voice.pendingText.len == 0 and not voice.client.responseActive and
      not voice.speaking() and voice.speech.len > 0:
        if voice.client.speakText(voice.speech[0]):
          voice.speech.delete(0)
  except VoiceAudioError as error:
    voice.error = error.msg
    voice.setMuted(true)

proc status*(voice: MonsterVoice): string =
  ## Summarizes voice activity for the chat's compact microphone control.
  if voice.listening(): "Listening... click Finish"
  elif voice.waitingForTranscript: "Transcribing..."
  elif voice.pendingText.len > 0: "Command queued"
  elif voice.client.state == Connecting: "Connecting voice..."
  elif voice.client.state == Failed: "Voice unavailable"
  elif voice.client.state != Connected: "Voice disconnected"
  elif voice.speaking() or voice.client.responseActive: "Moss is speaking"
  else: "Ready to talk"

proc close*(voice: MonsterVoice) =
  ## Releases microphone, callbacks, playback, and connection on game exit.
  voice.stopListening()
  voice.client.onTranscript = nil
  voice.client.onAudio = nil
  voice.client.onAudioStart = nil
  voice.client.disconnect()
  voice.client.poll()
  voice.credential.setLen(0)
  voice.audio.close()
