import
  std/[math, monotimes, os, times],
  openal, slappy

const
  VoiceSampleRate* = 24000
  VoiceBytesPerSecond* = VoiceSampleRate * 2
  MaxPlaybackBytes* = VoiceBytesPerSecond * 30
  MaxPlaybackChunks = 1500

type
  VoiceAudioError* = object of IOError
  VoiceAudio* = ref object
    microphone: Microphone
    speaker: StreamingSource
    captureStarted, initialized, closed: bool
    level: float32
    chunkBytes: seq[int]
    queuedBytes, completedBytes: int
    playbackAnchor: MonoTime
    anchorBytes: int
    wasPlaying: bool

when defined(macosx):
  {.compile: currentSourcePath().parentDir / "permissions.m".}
  {.passL: "-framework AVFoundation -framework Foundation".}
  {.passL: "-Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist " &
    "-Xlinker " & quoteShell(currentSourcePath().parentDir / "macos.plist").}
  proc voiceMicrophonePermission(): cint {.importc.}
    ## Returns the operating system microphone authorization state.
  proc voiceRequestMicrophonePermission() {.importc.}
    ## Asks macOS for microphone permission without blocking the UI.

proc microphonePermission*(): string =
  ## Returns microphone authorization or missing metadata without recording.
  when defined(macosx):
    case voiceMicrophonePermission()
    of -1:
      "unconfigured"
    of 3:
      "allowed"
    of 0:
      "pending"
    else:
      "denied"
  else:
    "allowed"

proc newVoiceAudio*(): VoiceAudio =
  ## Creates dormant audio state without opening or recording a microphone.
  VoiceAudio()

proc pcmLevel*(pcm: string): float32 =
  ## Measures RMS amplitude in signed little-endian PCM16 mono samples.
  if pcm.len mod 2 != 0:
    raise newException(VoiceAudioError, "PCM16 audio has an incomplete sample.")
  if pcm.len == 0:
    return 0
  var energy = 0.0
  for i in countup(0, pcm.high, 2):
    let
      sample = cast[int16](uint16(ord(pcm[i])) or
        (uint16(ord(pcm[i + 1])) shl 8))
      value = sample.float64 / 32768.0
    energy += value * value
  sqrt(energy / (pcm.len div 2).float64).float32

proc inputLevel*(audio: VoiceAudio): float32 =
  ## Returns the normalized RMS amplitude of the latest microphone chunk.
  audio.level

proc capturing*(audio: VoiceAudio): bool =
  ## Reports whether microphone samples are currently being recorded.
  audio.captureStarted

proc startCapture*(audio: VoiceAudio) =
  ## Opens and starts Slappy capture only after the user requests listening.
  if audio.closed:
    raise newException(VoiceAudioError, "Audio has been closed.")
  if audio.captureStarted:
    return
  when defined(macosx):
    case microphonePermission()
    of "unconfigured":
      raise newException(VoiceAudioError,
        "The executable is missing its microphone usage description. " &
        "Rebuild with nim r experiments/voice/voice.nim.")
    of "pending":
      voiceRequestMicrophonePermission()
      raise newException(VoiceAudioError,
        "Allow microphone access in the macOS prompt, then use Talk again.")
    of "denied":
      raise newException(VoiceAudioError,
        "Enable Voice Lab or your terminal in System Settings > " &
        "Privacy & Security > Microphone.")
    else:
      discard
  try:
    if audio.microphone == nil:
      audio.microphone = newMicrophone(
        frequency = VoiceSampleRate,
        channels = 1,
        bits = 16,
        bufferSize = VoiceSampleRate * 2
      )
    discard audio.microphone.readAll()
    audio.microphone.start()
    audio.captureStarted = true
  except SlappyError as error:
    raise newException(VoiceAudioError,
      "Could not open the microphone: " & error.msg)

proc stopCapture*(audio: VoiceAudio) =
  ## Stops microphone recording and clears its displayed level.
  if audio.microphone != nil and audio.captureStarted:
    audio.microphone.stop()
  audio.captureStarted = false
  audio.level = 0

proc readCapture*(audio: VoiceAudio): string =
  ## Drains available microphone samples as PCM16 mono at 24 kHz.
  if audio.microphone == nil:
    return
  let bytes = audio.microphone.readAll()
  if bytes.len > 0:
    result = newString(bytes.len)
    copyMem(addr result[0], unsafeAddr bytes[0], bytes.len)
  audio.level = pcmLevel(result)

proc checkPlayback(message: string) =
  ## Converts OpenAL failures at the experiment boundary into audio errors.
  if alGetError() != AL_NO_ERROR:
    raise newException(VoiceAudioError, message)

proc pollPlayback*(audio: VoiceAudio) =
  ## Reclaims completed streaming buffers and advances bounded bookkeeping.
  if audio.speaker == nil:
    return
  discard alGetError()
  audio.speaker.pump()
  checkPlayback("Could not reclaim streamed audio buffers.")
  let count = audio.chunkBytes.len - audio.speaker.queuedLen()
  for i in 0 ..< count:
    audio.completedBytes += audio.chunkBytes[i]
    audio.queuedBytes -= audio.chunkBytes[i]
  if count > 0:
    for i in count ..< audio.chunkBytes.len:
      audio.chunkBytes[i - count] = audio.chunkBytes[i]
    audio.chunkBytes.setLen(audio.chunkBytes.len - count)
  let playing = audio.speaker.playing()
  if not playing:
    audio.wasPlaying = false

proc playbackMilliseconds*(audio: VoiceAudio): int =
  ## Estimates played audio from completed chunks and the active play clock.
  audio.pollPlayback()
  var consumed = audio.completedBytes
  if audio.wasPlaying:
    let elapsed = (getMonoTime() - audio.playbackAnchor).inMilliseconds
    consumed = max(consumed,
      audio.anchorBytes + int(elapsed * VoiceBytesPerSecond div 1000))
  min(consumed, audio.completedBytes + audio.queuedBytes) * 1000 div
    VoiceBytesPerSecond

proc outputActive*(audio: VoiceAudio): bool =
  ## Reports whether any streamed speech remains queued for playback.
  audio.pollPlayback()
  audio.queuedBytes > 0

proc queuePcm*(audio: VoiceAudio, pcm: string) =
  ## Queues one ordered PCM16 chunk with a 30-second playback backlog limit.
  if audio.closed:
    raise newException(VoiceAudioError, "Audio has been closed.")
  if pcm.len == 0:
    return
  if pcm.len mod 2 != 0:
    raise newException(VoiceAudioError, "PCM16 audio has an incomplete sample.")
  try:
    if not audio.initialized:
      slappyInit()
      audio.initialized = true
    if audio.speaker == nil:
      discard alGetError()
      audio.speaker = newStreamingSource(
        frequency = VoiceSampleRate,
        channels = 1,
        bits = 16
      )
      checkPlayback("Could not create the speech output stream.")
  except SlappyError as error:
    raise newException(VoiceAudioError,
      "Could not open speech output: " & error.msg)
  audio.pollPlayback()
  if pcm.len > MaxPlaybackBytes - audio.queuedBytes or
    audio.chunkBytes.len >= MaxPlaybackChunks:
      raise newException(VoiceAudioError,
        "Speech playback queue is full. Stop the reply and try again.")
  var bytes = newSeq[uint8](pcm.len)
  copyMem(addr bytes[0], unsafeAddr pcm[0], pcm.len)
  discard alGetError()
  audio.speaker.queueData(bytes)
  checkPlayback("Could not queue streamed speech audio.")
  audio.chunkBytes.add(pcm.len)
  audio.queuedBytes += pcm.len
  if not audio.wasPlaying:
    audio.playbackAnchor = getMonoTime()
    audio.anchorBytes = audio.completedBytes
    audio.wasPlaying = true

proc stopPlayback*(audio: VoiceAudio) =
  ## Interrupts speech, discards pending buffers, and resets the turn clock.
  if audio.speaker != nil:
    audio.speaker.flush()
  audio.chunkBytes.setLen(0)
  audio.queuedBytes = 0
  audio.completedBytes = 0
  audio.anchorBytes = 0
  audio.wasPlaying = false

proc close*(audio: VoiceAudio) =
  ## Releases microphone, streaming buffers, and the experiment audio context.
  if audio.closed:
    return
  audio.stopCapture()
  var message: string
  if audio.microphone != nil:
    try:
      audio.microphone.close()
    except SlappyError as error:
      message = error.msg
    audio.microphone = nil
  if audio.speaker != nil:
    audio.speaker.close()
    audio.speaker = nil
  if audio.initialized:
    try:
      slappyClose()
    except SlappyError as error:
      message = error.msg
    audio.initialized = false
  audio.closed = true
  if message.len > 0:
    raise newException(VoiceAudioError, "Could not close audio: " & message)
