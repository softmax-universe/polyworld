import
  std/os,
  openal,
  polyworld/[common, soundassets, sounddevices, sounds]

when not defined(nimAllocStats):
  {.error: "Run with -d:nimAllocStats to measure playback allocations.".}
when defined(emscripten) or defined(audioTest) or defined(headless):
  {.error: "This check requires native playback and the art checkout.".}

echo "Testing preallocated voices during overlap, reuse and volume changes"
doAssert openSoundDevice()
for id, clip in SoundClips:
  doAssert loadSoundBuffer(id, DataRoot / clip.path)
prepareSoundDevice()
doAssert not loadSoundBuffer(0, DataRoot / SoundClips[0].path),
  "Sound buffers cannot be replaced after initialization"
setSoundVolumes(0.01, 1, 1)
let beforeVoices = getAllocStats()
for frame in 0 ..< 1000:
  let pan = if frame mod 2 == 0: -0.7'f else: 0.7'f
  if not startSoundVoice(frame mod SoundClips.len, 0.05, pan, false):
    echo "Combat voice failed at iteration ", frame, "; AL error ", alGetError()
    quit(1)
  if not startSoundVoice((frame + 1) mod SoundClips.len, 0.05, -pan, true):
    echo "UI voice failed at iteration ", frame, "; AL error ", alGetError()
    quit(1)
  if frame mod 23 == 0:
    doAssert startSoundVoice(
      (frame + 2) mod SoundClips.len, 0.05, 0, true, fanfare = true
    )
  if frame mod 17 == 0:
    setSoundVolumes(0.01, 0.5, 0.75)
  if frame mod 61 == 0:
    stopSoundVoices()
let afterVoices = getAllocStats()
echo "Voice pool allocation counters: ", beforeVoices, " -> ", afterVoices
doAssert afterVoices == beforeVoices
doAssert alGetError() == AL_NO_ERROR
closeSoundDevice()

echo "Testing cue selection and stop/resume without allocations"
configureSounds(false, 1, 100, 100)
initSounds()
let beforeCues = getAllocStats()
for frame in 0 ..< 200:
  for cue in SoundCue:
    stopSounds()
    playSound(cue, gain = 0.05)
  configureSounds(true, 1, 50, 75)
  configureSounds(false, 1, 100, 100)
let afterCues = getAllocStats()
echo "Cue playback allocation counters: ", beforeCues, " -> ", afterCues
doAssert afterCues == beforeCues
doAssert alGetError() == AL_NO_ERROR
closeSounds()
echo "Zero Nim allocations and deallocations in both playback measurements."
