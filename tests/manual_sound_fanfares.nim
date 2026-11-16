import
  std/os,
  openal,
  polyworld/[common, soundassets]

# Inspect real Slappy sources to catch accidental voice stealing.
include ../src/polyworld/sounddevices

when defined(emscripten) or defined(audioTest) or defined(headless):
  {.error: "This check requires native playback and the art checkout.".}

echo "Testing fanfares survive UI and combat bursts"
doAssert openSoundDevice()
for clip in SoundClips:
  case clip.cue
  of VictorySound:
    doAssert loadSoundBuffer(0, DataRoot / clip.path)
  of DefeatSound:
    doAssert loadSoundBuffer(1, DataRoot / clip.path)
  of HoverSound:
    doAssert loadSoundBuffer(2, DataRoot / clip.path)
  else:
    discard
prepareSoundDevice()
setSoundVolumes(0.01, 1, 1)
for outcome in 0 .. 1:
  doAssert startSoundVoice(outcome, 0.5, 0, true, fanfare = true)
  let fanfareSource = voices[0].source
  for i in 0 ..< 100:
    doAssert startSoundVoice(2, 0.1, 0, true)
    doAssert startSoundVoice(2, 0.1, 0, false)
  doAssert fanfareSource.playing
  doAssert fanfareSource.sound == buffers[outcome],
    "Hover feedback and combat must not steal the result voice"
  setSoundVolumes(0.01, 0, 0.25)
  doAssert abs(fanfareSource.gain - 0.125) < 0.001,
    "UI volume must change an active fanfare"
  setSoundVolumes(0.01, 1, 0)
  doAssert fanfareSource.gain == 0
  stopSoundVoices()
  doAssert not fanfareSource.playing
  setSoundVolumes(0.01, 1, 1)
doAssert alGetError() == AL_NO_ERROR
closeSoundDevice()
echo "Fanfares retain their voice and obey UI volume and stop."
