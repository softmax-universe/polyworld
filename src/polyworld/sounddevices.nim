when not (defined(headless) or defined(audioTest)):
  import std/[math, os], slappy, vmath

const
  SoundBufferLimit* = 128
  SoundVoiceLimit* = 24
  InterfaceVoiceLimit = 4

when not (defined(headless) or defined(audioTest)):
  type SoundVoice = object
    source: Source
    buffer: int
    active: bool
    gain: float32
    serial: uint64

  var
    opened, prepared: bool
    loaded: array[SoundBufferLimit, bool]
    voices: array[SoundVoiceLimit, SoundVoice]
    serial: uint64
    masterVolume = 1.0'f
    effectsVolume = 1.0'f
    interfaceVolume = 1.0'f
    musicVolume = 1.0'f
    buffers: array[SoundBufferLimit, Sound]
    musicBuffer: Sound
    musicSource: Source
    musicPath: string

  when defined(emscripten):
    {.passL: "-lopenal".}
    {.emit: """
    #include <emscripten.h>
    EM_JS(int, polyworldSlappyReady, (), {
      // Emscripten owns Web Audio's one-shot nodes and gesture unlock.
      return !document.hidden && typeof AL !== 'undefined' &&
        AL.currentCtx && AL.currentCtx.audioCtx.state === 'running';
    });
    """.}
    proc slappyReady(): cint {.importc: "polyworldSlappyReady", nodecl.}
      ## Reports whether the visible browser has unlocked Slappy playback.

  proc collectVoices() =
    ## Marks completed slots idle without releasing their playback resources.
    for voice in voices.mitems:
      if voice.active:
        voice.active = voice.source.playing

proc closeSoundDevice*()
  ## Releases voices, buffers and the device only at application shutdown.

proc openSoundDevice*(): bool =
  ## Allocates the fixed Slappy voice pool before gameplay begins.
  when defined(headless) or defined(audioTest):
    false
  else:
    if opened:
      return true
    try:
      slappyInit()
      opened = true
      listener.pos = vec3(0)
      # Master gain is applied per source, avoiding native listener mute bugs.
      listener.gain = 1
      for voice in voices.mitems:
        voice.buffer = -1
        voice.source = newSource()
        voice.source.rolloffFactor = 0
      return true
    except IOError, ValueError:
      echo "Cannot open Slappy audio: ", getCurrentExceptionMsg()
      closeSoundDevice()
      return false

proc loadSoundBuffer*(id: int, path: string): bool =
  ## Decodes a clip during initialization, before the voice pool is sealed.
  if id < 0 or id >= SoundBufferLimit:
    return false
  when defined(headless) or defined(audioTest):
    false
  else:
    if not opened or prepared:
      return false
    try:
      if not fileExists(path):
        return false
      buffers[id] = newSound(path)
      result = true
      loaded[id] = result
    except IOError, ValueError:
      echo "Cannot decode sound ", path, ": ", getCurrentExceptionMsg()
      return false

proc prepareSoundDevice*() =
  ## Seals preloaded buffers so playback cannot replace or decode recordings.
  when not (defined(headless) or defined(audioTest)):
    if not opened or prepared:
      return
    prepared = true

proc updateMusic*() =
  ## Retries a stopped soundtrack once the browser audio context is unlocked.
  when not (defined(headless) or defined(audioTest)):
    if not opened or musicSource == nil or musicSource.playing:
      return
    when defined(emscripten):
      if slappyReady() == 0:
        return
    musicSource.play()

proc loadMusic*(path: string): bool =
  ## Loads a stereo soundtrack into its own continuously looping voice.
  when defined(headless) or defined(audioTest):
    false
  else:
    if musicSource != nil and musicPath == path:
      updateMusic()
      return true
    if not opened or not fileExists(path):
      return false
    var source: Source
    try:
      let buffer = newSound(path, forceMono = false)
      source = newSource()
      source.sound = buffer
      source.rolloffFactor = 0
      source.pos = vec3(0)
      source.looping = true
      source.gain = musicVolume * masterVolume
      if musicSource != nil:
        musicSource.close()
      musicSource = source
      musicBuffer = buffer
      musicPath = path
      # A suspended browser context starts this loop on its first gesture.
      source.play()
      return true
    except IOError, ValueError:
      if source != nil:
        source.close()
      echo "Cannot load music ", path, ": ", getCurrentExceptionMsg()
      return false

proc setMusicVolume*(volume: float32) =
  ## Changes soundtrack gain independently from UI and world effects.
  when not (defined(headless) or defined(audioTest)):
    musicVolume = clamp(volume, 0.0'f, 1.0'f)
    if musicSource != nil:
      musicSource.gain = musicVolume * masterVolume

proc startSoundVoice*(
    id: int, gain, pan: float32, ui: bool, fanfare = false
): bool =
  ## Reserves one UI voice for fanfares, three for UI, and twenty for combat.
  if id < 0 or id >= SoundBufferLimit or gain <= 0:
    return false
  when defined(headless) or defined(audioTest):
    false
  else:
    if not opened or not prepared or not loaded[id] or masterVolume <= 0:
      return false
    when defined(emscripten):
      if slappyReady() == 0:
        return false
    let
      category = if ui: interfaceVolume else: effectsVolume
      first =
        if not ui:
          InterfaceVoiceLimit
        elif fanfare:
          0
        else:
          1
      finish =
        if not ui:
          SoundVoiceLimit
        elif fanfare:
          1
        else:
          InterfaceVoiceLimit
    if category <= 0:
      return false
    collectVoices()
    var slot = first
    for i in first ..< finish:
      if not voices[i].active:
        slot = i
        break
      if voices[i].serial < voices[slot].serial:
        slot = i
    let
      level = clamp(gain, 0.0'f, 1.0'f)
      horizontal = clamp(pan, -1.0'f, 1.0'f)
    let source = voices[slot].source
    source.stop()
    if voices[slot].buffer != id:
      source.sound = buffers[id]
    source.gain = level * category * masterVolume
    source.pos = vec3(
      horizontal, 0, -sqrt(max(0.0'f, 1 - horizontal * horizontal))
    )
    source.play()
    if not source.playing:
      voices[slot].active = false
      return false
    inc serial
    voices[slot].buffer = id
    voices[slot].active = true
    voices[slot].gain = level
    voices[slot].serial = serial
    return true

proc setSoundVolumes*(master, fx, ui: float32) =
  ## Changes gains on existing voices without replacing audio resources.
  when not (defined(headless) or defined(audioTest)):
    masterVolume = clamp(master, 0.0'f, 1.0'f)
    effectsVolume = clamp(fx, 0.0'f, 1.0'f)
    interfaceVolume = clamp(ui, 0.0'f, 1.0'f)
    if not opened:
      return
    listener.gain = 1
    if musicSource != nil:
      musicSource.gain = musicVolume * masterVolume
    collectVoices()
    for i, voice in voices:
      if voice.active:
        let gain = voice.gain * masterVolume *
          (if i < InterfaceVoiceLimit: interfaceVolume else: effectsVolume)
        voice.source.gain = gain

proc stopSoundVoices*() =
  ## Deactivates slots while retaining all preallocated voices and buffers.
  when not (defined(headless) or defined(audioTest)):
    if not opened:
      return
    for voice in voices.mitems:
      if voice.source != nil:
        voice.source.stop()
      voice.active = false

proc closeSoundDevice*() =
  ## Releases voices, buffers and the device only at application shutdown.
  when not (defined(headless) or defined(audioTest)):
    if not opened:
      return
    stopSoundVoices()
    if musicSource != nil:
      musicSource.close()
      musicSource = nil
    musicBuffer = nil
    musicPath.setLen(0)
    for voice in voices.mitems:
      if voice.source != nil:
        voice.source.close()
        voice.source = nil
    buffers = default(array[SoundBufferLimit, Sound])
    try:
      slappyClose()
    except SlappyError as error:
      echo "Cannot close Slappy audio: ", error.msg
    voices = default(array[SoundVoiceLimit, SoundVoice])
    loaded = default(array[SoundBufferLimit, bool])
    serial = 0
    prepared = false
    opened = false
