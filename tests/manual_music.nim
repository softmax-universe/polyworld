import
  openal,
  polyworld/common

# Inspect the real playback source without opening a window or making sound.
include ../src/polyworld/sounddevices

when defined(emscripten) or defined(audioTest) or defined(headless):
  {.error: "This check requires native playback and the art checkout.".}

const MusicPath = DataRoot / "music/yearning-of-the-deep-woods.ogg"

echo "Testing stereo music preload and independent volume"
setSoundVolumes(0, 1, 1)
setMusicVolume(0.4)
doAssert openSoundDevice()
try:
  doAssert listener.gain == 0
  doAssert loadMusic(MusicPath)
  doAssert musicBuffer.channels == 2
  doAssert abs(musicBuffer.duration - 203.56) < 0.05
  doAssert musicSource.looping
  doAssert musicSource.playing
  doAssert musicSource.rolloffFactor == 0
  doAssert abs(musicSource.gain - 0.4) < 0.001
  let firstSource = musicSource
  setSoundVolumes(0, 0, 0)
  doAssert musicSource == firstSource
  doAssert musicSource.playing
  doAssert abs(musicSource.gain - 0.4) < 0.001,
    "FX and UI volume must not change music gain"
  setMusicVolume(0.7)
  doAssert abs(musicSource.gain - 0.7) < 0.001
  doAssert effectsVolume == 0 and interfaceVolume == 0
  doAssert listener.gain == 0

  echo "Testing effects resets and music muting preserve playback"
  musicSource.playback = 5
  sleep(60)
  let beforeReset = musicSource.playback
  stopSoundVoices()
  doAssert musicSource == firstSource
  doAssert musicSource.playing
  doAssert musicSource.playback >= beforeReset
  setMusicVolume(0)
  doAssert musicSource.gain == 0
  doAssert musicSource.playing
  sleep(60)
  let beforeRestore = musicSource.playback
  doAssert beforeRestore > beforeReset
  setMusicVolume(0.6)
  doAssert musicSource.playback >= beforeRestore
  doAssert musicSource.playing
  doAssert abs(musicSource.gain - 0.6) < 0.001

  echo "Testing playback wraps at the end of the recording"
  musicSource.playback = musicBuffer.duration - 0.1
  sleep(300)
  doAssert musicSource.playing
  doAssert musicSource.playback < 1,
    "Looping music must wrap to the start without a new play request"
  doAssert listener.gain == 0
  doAssert alGetError() == AL_NO_ERROR

  echo "Testing music cleanup and device reopening"
  closeSoundDevice()
  doAssert musicSource == nil and musicBuffer == nil
  doAssert firstSource.sound == nil
  doAssert not opened
  closeSoundDevice()
  setMusicVolume(0.25)
  doAssert openSoundDevice()
  doAssert listener.gain == 0
  doAssert loadMusic(MusicPath)
  doAssert musicSource != firstSource
  doAssert musicSource.playing and musicSource.looping
  doAssert abs(musicSource.gain - 0.25) < 0.001
  doAssert alGetError() == AL_NO_ERROR
finally:
  closeSoundDevice()

doAssert musicSource == nil and musicBuffer == nil
echo "Music loops independently and all playback remained muted."
