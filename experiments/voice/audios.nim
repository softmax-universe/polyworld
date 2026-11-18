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
    captureStarted, initialized, closed, closeDevice: bool
    level: float32
    levelUpdated: MonoTime
    chunkBytes: seq[int]
    queuedBytes, completedBytes: int
    playbackAnchor: MonoTime
    anchorBytes: int
    wasPlaying: bool
    duplex: bool
    nativeDuplex: pointer
    inputDevice, outputDevice: string

when defined(emscripten):
  var browserOutputUsers: int

when defined(macosx) and not defined(emscripten):
  import devices

  {.compile: currentSourcePath().parentDir / "permissions.m".}
  {.compile: currentSourcePath().parentDir / "duplex.m".}
  {.passL: "-framework AVFoundation -framework AVFAudio -framework Foundation".}
  {.passL: "-Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist " &
    "-Xlinker " & quoteShell(currentSourcePath().parentDir / "macos.plist").}
  proc voiceMicrophonePermission(): cint {.importc.}
    ## Returns the operating system microphone authorization state.
  proc voiceRequestMicrophonePermission() {.importc.}
    ## Asks macOS for microphone permission without blocking the UI.
  proc voiceAudioCreate(voiceProcessing: bool,
    inputDevice, outputDevice: cstring): pointer {.importc.}
    ## Copies mode and routes without opening any hardware or requesting access.
  proc voiceDuplexStart(handle: pointer): bool {.importc.}
    ## Starts microphone and playback with native echo cancellation.
  proc voiceDuplexStop(handle: pointer) {.importc.}
    ## Stops the native audio hardware after conversation mode ends.
  proc voiceDuplexPoll(handle: pointer): bool {.importc.}
    ## Recovers a device configuration transition only while capture is active.
  proc voiceDuplexError(handle: pointer): cstring {.importc.}
    ## Retrieves a bounded error from setup or an audio callback.
  proc voiceDuplexAvailable(handle: pointer): cint {.importc.}
    ## Returns the available processed microphone frames.
  proc voiceDuplexRead(handle, samples: pointer, capacity: cint): cint {.importc.}
    ## Drains processed PCM16 samples into caller-owned memory.
  proc voiceDuplexQueue(handle, samples: pointer, count: cint): bool {.importc.}
    ## Appends speech to the same echo-cancelled audio graph.
  proc voiceDuplexFlush(handle: pointer) {.importc.}
    ## Discards queued speech while microphone capture continues.
  proc voiceDuplexQueued(handle: pointer): cint {.importc.}
    ## Reports remaining speech frames without pumping the device.
  proc voiceDuplexMilliseconds(handle: pointer): cint {.importc.}
    ## Returns the current utterance's rendered duration.
  proc voiceDuplexClose(handle: pointer) {.importc.}
    ## Releases native graph callbacks and audio queues.
  proc voiceAudioCaptureDiagnostics(handle: pointer): cstring {.importc.}
    ## Reports frame counts and peaks without retaining microphone recordings.
  when defined(voiceAudioTesting):
    proc voiceDuplexTest(): bool {.importc.}
      ## Exercises native queues and conversion without hardware.
    proc testDuplexAudio*(): bool =
      ## Runs deterministic native audio checks without microphone access.
      voiceDuplexTest()

  proc checkDuplex(audio: VoiceAudio) =
    ## Maps native callback failures into the shared voice audio exception.
    discard voiceDuplexPoll(audio.nativeDuplex)
    let message = $voiceDuplexError(audio.nativeDuplex)
    if message.len > 0:
      raise newException(VoiceAudioError, message)

proc microphonePermission*(): string =
  ## Returns microphone authorization or missing metadata without recording.
  when defined(macosx) and not defined(emscripten):
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

proc newVoiceAudio*(closeDevice = true, duplex = false,
  inputDevice = "", outputDevice = ""): VoiceAudio =
  ## Creates dormant audio state without opening or recording a microphone.
  VoiceAudio(closeDevice: closeDevice, duplex: duplex,
    inputDevice: inputDevice, outputDevice: outputDevice)

when defined(macosx) and not defined(emscripten):
  proc prepareNative(audio: VoiceAudio) =
    ## Lazily creates the native queues with immutable per-app route choices.
    if audio.nativeDuplex == nil:
      audio.nativeDuplex = voiceAudioCreate(audio.duplex,
        audio.inputDevice.cstring, audio.outputDevice.cstring)
      if audio.nativeDuplex == nil:
        raise newException(VoiceAudioError,
          "Could not allocate audio buffers.")

proc captureDiagnostics*(audio: VoiceAudio): string =
  ## Reports local capture counters and peaks without saving or sending audio.
  when defined(macosx) and not defined(emscripten):
    if audio.nativeDuplex != nil:
      return $voiceAudioCaptureDiagnostics(audio.nativeDuplex)
  "Microphone has not started."

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
  ## Returns a meter envelope that remains visible between microphone chunks.
  audio.level

proc updateInputLevel(audio: VoiceAudio, pcm: string) =
  ## Releases the meter gradually between batched hardware capture callbacks.
  let
    now = getMonoTime()
    elapsed = (now - audio.levelUpdated).inMilliseconds.float64 / 1000
    previous = audio.level * exp(-elapsed / 0.18).float32
  audio.level = max(previous, pcmLevel(pcm))
  audio.levelUpdated = now

proc capturing*(audio: VoiceAudio): bool =
  ## Reports whether capture is requested, including browser permission waits.
  audio.captureStarted

proc capturePending*(audio: VoiceAudio): bool =
  ## Reports browser permission or audio setup pending after a capture request.
  when defined(emscripten):
    if audio.microphone != nil and audio.captureStarted:
      try:
        return not audio.microphone.ready
      except SlappyError as error:
        raise newException(VoiceAudioError, error.msg)
  false

proc captureStopping*(audio: VoiceAudio): bool =
  ## Reports whether a stopped browser input still has audio-thread frames.
  when defined(emscripten):
    if audio.microphone != nil:
      try:
        return audio.microphone.stopping
      except SlappyError as error:
        raise newException(VoiceAudioError, error.msg)
  false

proc startCapture*(audio: VoiceAudio) =
  ## Opens microphone capture only after the user requests listening.
  if audio.closed:
    raise newException(VoiceAudioError, "Audio has been closed.")
  if audio.captureStarted:
    return
  when defined(macosx) and not defined(emscripten):
    case microphonePermission()
    of "unconfigured":
      raise newException(VoiceAudioError,
        "The executable is missing its microphone usage description. " &
        "Rebuild and launch the application through its native launcher.")
    of "pending":
      voiceRequestMicrophonePermission()
      raise newException(VoiceAudioError,
        "Allow microphone access in the macOS prompt, then enable it again.")
    of "denied":
      raise newException(VoiceAudioError,
        "Enable this app or your terminal in System Settings > " &
        "Privacy & Security > Microphone.")
    else:
      discard
    audio.prepareNative()
    if not voiceDuplexStart(audio.nativeDuplex):
      audio.checkDuplex()
      raise newException(VoiceAudioError, "Could not start microphone audio.")
    audio.captureStarted = true
    return
  else:
    try:
      if audio.microphone == nil:
        audio.microphone = newMicrophone(
          deviceName = audio.inputDevice,
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
  when defined(macosx) and not defined(emscripten):
    if audio.nativeDuplex != nil:
      voiceDuplexStop(audio.nativeDuplex)
      voiceDuplexFlush(audio.nativeDuplex)
  if audio.microphone != nil and audio.captureStarted:
    try:
      audio.microphone.stop()
    except SlappyError as error:
      when defined(emscripten):
        # Polling reports asynchronous failures; stopping must still clean up.
        audio.microphone.close()
        audio.microphone = nil
      else:
        audio.captureStarted = false
        audio.level = 0
        raise newException(VoiceAudioError, error.msg)
  audio.captureStarted = false
  audio.level = 0

proc releaseCapture*(audio: VoiceAudio) =
  ## Cancels browser capture and permission waits, releasing the input device.
  when defined(emscripten):
    if audio.microphone != nil:
      try:
        audio.microphone.close()
      except SlappyError as error:
        raise newException(VoiceAudioError, error.msg)
      finally:
        audio.microphone = nil
        audio.captureStarted = false
        audio.level = 0
  else:
    audio.stopCapture()

proc readCapture*(audio: VoiceAudio): string =
  ## Drains available microphone samples as PCM16 mono at 24 kHz.
  when defined(macosx) and not defined(emscripten):
    if audio.nativeDuplex != nil:
      audio.checkDuplex()
      let count = voiceDuplexAvailable(audio.nativeDuplex)
      if count > 0:
        result = newString(count.int * 2)
        let read = voiceDuplexRead(
          audio.nativeDuplex, addr result[0], count
        )
        result.setLen(read.int * 2)
      audio.updateInputLevel(result)
      return
  if audio.microphone == nil:
    return
  try:
    let bytes = audio.microphone.readAll()
    if bytes.len > 0:
      result = newString(bytes.len)
      copyMem(addr result[0], unsafeAddr bytes[0], bytes.len)
    audio.updateInputLevel(result)
  except SlappyError as error:
    raise newException(VoiceAudioError, error.msg)

proc checkPlayback(message: string) =
  ## Converts OpenAL failures at the experiment boundary into audio errors.
  if alGetError() != AL_NO_ERROR:
    raise newException(VoiceAudioError, message)

proc prepareOutput*(audio: VoiceAudio) =
  ## Opens speech output from a user gesture without activating the microphone.
  if audio.closed:
    raise newException(VoiceAudioError, "Audio has been closed.")
  when not defined(macosx) or defined(emscripten):
    try:
      if not audio.initialized:
        slappyInit()
        audio.initialized = true
        when defined(emscripten):
          inc browserOutputUsers
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

proc pollPlayback*(audio: VoiceAudio) =
  ## Reclaims completed streaming buffers and advances bounded bookkeeping.
  when defined(macosx) and not defined(emscripten):
    if audio.nativeDuplex != nil:
      audio.checkDuplex()
      return
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
  when defined(macosx) and not defined(emscripten):
    if audio.nativeDuplex != nil:
      return voiceDuplexMilliseconds(audio.nativeDuplex).int
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
  when defined(macosx) and not defined(emscripten):
    if audio.nativeDuplex != nil:
      return voiceDuplexQueued(audio.nativeDuplex) > 0
  audio.queuedBytes > 0

proc queuePcm*(audio: VoiceAudio, pcm: string) =
  ## Queues one ordered PCM16 chunk with a 30-second playback backlog limit.
  if audio.closed:
    raise newException(VoiceAudioError, "Audio has been closed.")
  if pcm.len == 0:
    return
  if pcm.len mod 2 != 0:
    raise newException(VoiceAudioError, "PCM16 audio has an incomplete sample.")
  when defined(macosx) and not defined(emscripten):
    if audio.duplex and not audio.captureStarted:
      raise newException(VoiceAudioError,
        "Start Conversation before playing its voice.")
    audio.prepareNative()
    audio.checkDuplex()
    if not voiceDuplexQueue(
      audio.nativeDuplex, unsafeAddr pcm[0], (pcm.len div 2).cint
    ):
      audio.checkDuplex()
    return
  else:
    audio.prepareOutput()
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
  when defined(macosx) and not defined(emscripten):
    if audio.nativeDuplex != nil:
      voiceDuplexFlush(audio.nativeDuplex)
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
  when defined(emscripten):
    audio.releaseCapture()
  else:
    audio.stopCapture()
  when defined(macosx) and not defined(emscripten):
    if audio.nativeDuplex != nil:
      voiceDuplexClose(audio.nativeDuplex)
      audio.nativeDuplex = nil
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
      when defined(emscripten):
        dec browserOutputUsers
        if browserOutputUsers == 0 and audio.closeDevice:
          slappyClose()
      else:
        if audio.closeDevice:
          slappyClose()
    except SlappyError as error:
      message = error.msg
    audio.initialized = false
  audio.closed = true
  if message.len > 0:
    raise newException(VoiceAudioError, "Could not close audio: " & message)
