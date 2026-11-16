import
  std/monotimes,
  vmath,
  soundassets, sounddevices

when not defined(headless):
  import std/os, common

export soundassets

type
  SoundGate* = object
    played: array[SoundCue, bool]
    last: array[SoundCue, float64]
    windowStart: float64
    worldCount: int
    workWindowStart: float64
    workCount: int
  SoundMix* = object
    gain*, pan*: float32
  SoundVariants = object
    buffers: array[SoundClips.len, int]
    count: int

const
  WorldBurstLimit* = 6
  WorldBurstSeconds* = 0.1
  WorkBurstLimit* = 2
  WorkBurstSeconds* = 0.25

var
  initialized = false
  available = false
  muted = false
  masterVolume = 1.0'f
  musicVolume = 1.0'f
  effectsVolume = 1.0'f
  interfaceVolume = 1.0'f
  cueVariants: array[SoundCue, SoundVariants]
  variations: array[SoundCue, int]
  gate: SoundGate

proc isInterfaceSound*(cue: SoundCue): bool =
  ## Routes orders, notifications, and menus through the UI volume slider.
  cue in {ClickSound, CancelSound, ErrorSound, SelectSound,
    MoveOrderSound, AttackOrderSound, PurchaseSound, ReadySound,
    VictorySound, DefeatSound, DaybreakSound, NightfallSound, HoverSound}

proc soundCooldown*(cue: SoundCue): float64 =
  ## Prevents repeated events and dense armies from overwhelming the mix.
  case cue
  of HoverSound:
    0.09
  of ChopSound:
    0.45
  of MineSound:
    0.6
  of DeliverWoodSound, DeliverGoldSound:
    0.3
  of BuildPlaceSound, BuildStartSound:
    0.35
  of ClickSound, CancelSound, SelectSound, PurchaseSound:
    0.07
  of MoveOrderSound, AttackOrderSound, ErrorSound:
    0.16
  of VictorySound, DefeatSound, DaybreakSound, NightfallSound:
    2.0
  of ReadySound:
    0.6
  of HumanDeathSound, CreatureDeathSound, BuildingDeathSound:
    0.18
  else:
    0.065

proc isWorkSound*(cue: SoundCue): bool =
  ## Separates routine harvesting from combat and construction feedback.
  cue in {ChopSound, MineSound, DeliverWoodSound, DeliverGoldSound}

proc acceptSound*(gate: var SoundGate, cue: SoundCue, now: float64): bool =
  ## Bounds harvesting independently so busy workers cannot silence battles.
  if gate.played[cue] and now >= gate.last[cue] and
      now - gate.last[cue] < soundCooldown(cue):
    return false
  if now < gate.windowStart or
      now - gate.windowStart >= WorldBurstSeconds:
    gate.windowStart = now
    gate.worldCount = 0
  if cue.isWorkSound:
    if now < gate.workWindowStart or
        now - gate.workWindowStart >= WorkBurstSeconds:
      gate.workWindowStart = now
      gate.workCount = 0
    if gate.workCount >= WorkBurstLimit:
      return false
    inc gate.workCount
  elif not cue.isInterfaceSound:
    if gate.worldCount >= WorldBurstLimit:
      return false
    inc gate.worldCount
  gate.played[cue] = true
  gate.last[cue] = now
  true

proc spatialSoundMix*(position, listener: Vec3, radius: float32): SoundMix =
  ## Attenuates XZ distance and pans across the fixed north-facing camera.
  if radius <= 0:
    return
  let
    delta = vec2(position.x - listener.x, position.z - listener.z)
    distance = delta.length
  if distance >= radius:
    return
  result.gain = (1 - distance / radius) * (1 - distance / radius)
  result.pan = clamp(delta.x / (radius * 0.55'f), -0.85'f, 0.85'f)

proc cueGain(cue: SoundCue): float32 =
  ## Leaves headroom for overlapping combat while keeping orders audible.
  case cue
  of HoverSound:
    0.15'f
  of ChopSound, MineSound:
    0.30'f
  of DeliverWoodSound, DeliverGoldSound, BuildPlaceSound:
    0.25'f
  of BuildStartSound:
    0.34'f
  of ClickSound, CancelSound, SelectSound:
    0.40'f
  of MoveOrderSound, AttackOrderSound, PurchaseSound, ErrorSound,
      DaybreakSound, NightfallSound:
    0.55'f
  of VictorySound, DefeatSound:
    0.50'f
  of ReadySound:
    0.65'f
  of HumanDeathSound, CreatureDeathSound, BuildingDeathSound:
    0.45'f
  else:
    0.36'f

proc soundsMuted*(): bool =
  ## Reports silence from an explicit mute or zero Master volume.
  muted or masterVolume <= 0

proc setSoundMuted*(silent: bool) =
  ## Changes session mute without changing any channel's saved volume.
  muted = silent
  if available:
    setSoundVolumes(
      if muted: 0.0'f else: masterVolume,
      effectsVolume,
      interfaceVolume
    )
    if muted or masterVolume == 0:
      stopSoundVoices()

proc configureSounds*(silent: bool, main, effects, ui: int, music = 100) =
  ## Applies saved channel levels, with zero Master silencing every source.
  masterVolume = clamp(main, 0, 100).float32 / 100
  musicVolume = clamp(music, 0, 100).float32 / 100
  effectsVolume = clamp(effects, 0, 100).float32 / 100
  interfaceVolume = clamp(ui, 0, 100).float32 / 100
  if available:
    setMusicVolume(musicVolume)
  setSoundMuted(silent)

proc initSounds*(musicPath = "") =
  ## Preloads the curated library once without changing simulation state.
  when not defined(headless):
    if initialized:
      if available and musicPath.len > 0 and not loadMusic(musicPath):
        echo "Cannot load soundtrack: ", musicPath
      return
    initialized = true
    available = openSoundDevice()
    if not available:
      echo "Audio unavailable; continuing without sound."
      return
    var
      clipBuffers: array[SoundClips.len, int]
      bufferCount = 0
    for id in clipBuffers.mitems:
      id = -1
    for i, clip in SoundClips:
      var id = -1
      for j in 0 ..< i:
        if SoundClips[j].path == clip.path:
          id = clipBuffers[j]
          break
      if id < 0:
        let path = DataRoot / clip.path
        if bufferCount < SoundBufferLimit and fileExists(path) and
            loadSoundBuffer(bufferCount, path):
          id = bufferCount
          inc bufferCount
        else:
          echo "Cannot load sound: ", path
      clipBuffers[i] = id
      if id >= 0:
        let count = cueVariants[clip.cue].count
        cueVariants[clip.cue].buffers[count] = id
        inc cueVariants[clip.cue].count
    prepareSoundDevice()
    setSoundVolumes(
      if muted: 0.0'f else: masterVolume,
      effectsVolume,
      interfaceVolume
    )
    setMusicVolume(musicVolume)
    if musicPath.len > 0 and not loadMusic(musicPath):
      echo "Cannot load soundtrack: ", musicPath

proc updateSounds*() =
  ## Keeps requested music running after a browser unlock or device interruption.
  if available:
    updateMusic()

proc stopSounds*() =
  ## Clears effect tails and cooldowns without interrupting the soundtrack.
  if available:
    stopSoundVoices()
  gate = SoundGate()

proc closeSounds*() =
  ## Releases the device and recording buffers at application shutdown.
  if initialized:
    closeSoundDevice()
  initialized = false
  available = false
  cueVariants = default(array[SoundCue, SoundVariants])
  gate = SoundGate()
  variations = default(array[SoundCue, int])

proc playSound*(cue: SoundCue, gain = 1.0'f, pan = 0.0'f) =
  ## Plays a bounded variation without touching the simulation's RNG.
  if not available or muted or masterVolume <= 0 or gain <= 0:
    return
  let ui = cue.isInterfaceSound
  if (ui and interfaceVolume <= 0) or (not ui and effectsVolume <= 0):
    return
  let now = getMonoTime().ticks.float64 / 1_000_000_000
  if not gate.acceptSound(cue, now):
    return
  let count = cueVariants[cue].count
  if count == 0:
    return
  let selected = variations[cue] mod count
  if startSoundVoice(
    cueVariants[cue].buffers[selected],
    clamp(gain, 0.0'f, 1.0'f) * cue.cueGain,
    clamp(pan, -1.0'f, 1.0'f),
    ui,
    fanfare = cue in {VictorySound, DefeatSound}
  ):
    variations[cue] = (variations[cue] + 1) mod count

proc playWorldSound*(
    cue: SoundCue, position, listener: Vec3,
    radius = 35.0'f, gain = 1.0'f
) =
  ## Plays a visible world event with camera-relative attenuation.
  let mix = spatialSoundMix(position, listener, radius)
  if mix.gain > 0.01'f:
    playSound(cue, mix.gain * gain, mix.pan)
