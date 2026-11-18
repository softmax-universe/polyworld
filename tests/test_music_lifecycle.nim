## Native soundtrack checks use a silent stereo fixture and per-source gains.
include ../src/polyworld/sounddevices

when not (defined(emscripten) or defined(headless) or defined(audioTest)):
  import std/os

  proc appendLittle(bytes: var string, value, size: int) =
    ## Writes a portable little-endian PCM header field.
    for i in 0 ..< size:
      bytes.add char((value shr (i * 8)) and 255)

  proc stereoFixture(): string =
    ## Builds one second of silent stereo PCM without relying on art assets.
    const
      Rate = 8000
      DataBytes = Rate * 4
    result = "RIFF"
    result.appendLittle(36 + DataBytes, 4)
    result.add "WAVEfmt "
    result.appendLittle(16, 4)
    result.appendLittle(1, 2)
    result.appendLittle(2, 2)
    result.appendLittle(Rate, 4)
    result.appendLittle(Rate * 4, 4)
    result.appendLittle(4, 2)
    result.appendLittle(16, 2)
    result.add "data"
    result.appendLittle(DataBytes, 4)
    result.add newString(DataBytes)

  proc testMusicLifecycle() =
    ## Verifies continuous stereo playback, independent gains, and teardown.
    let path = getTempDir() /
      ("polyworld-music-" & $getCurrentProcessId() & ".wav")
    writeFile(path, stereoFixture())
    defer: removeFile(path)
    setSoundVolumes(0, 0.4, 0.6)
    doAssert openSoundDevice()
    defer: closeSoundDevice()
    doAssert listener.gain == 1,
      "The listener stays at unity while master gain is applied per source"
    setMusicVolume(0.25)
    prepareSoundDevice()
    doAssert loadMusic(path)
    doAssert musicBuffer.channels == 2
    doAssert musicSource.looping and musicSource.playing
    doAssert musicSource.gain == 0,
      "A soundtrack loaded while muted must have zero source gain"
    let original = musicSource
    sleep(80)
    let offset = musicSource.playback
    doAssert offset > 0,
      "The native device must advance the muted soundtrack"
    doAssert loadMusic(path)
    updateMusic()
    doAssert musicSource == original and musicSource.playback >= offset,
      "Repeated requests and frame updates must not restart the soundtrack"
    stopSoundVoices()
    doAssert musicSource.playing and musicSource == original,
      "Stopping effects during a match transition must preserve music"
    setSoundVolumes(1, 0.9, 0.1)
    doAssert listener.gain == 1 and musicSource.gain == 0.25,
      "Unmuting must restore the Music level independently of effects and UI"
    setSoundVolumes(0.25, 0.9, 0.1)
    doAssert listener.gain == 1 and musicSource.gain == 0.0625,
      "Master volume must be applied exactly once"
    setMusicVolume(0.5)
    doAssert musicSource.gain == 0.125
    setSoundVolumes(0, 0.9, 0.1)
    doAssert listener.gain == 1 and musicSource.gain == 0
    setSoundVolumes(1, 0.9, 0.1)
    doAssert musicSource.gain == 0.5
    setMusicVolume(0)
    doAssert musicSource.playing and musicSource.gain == 0
    setMusicVolume(0.75)
    doAssert musicSource.playing and musicSource.gain == 0.75
    doAssert musicSource == original
    doAssert not loadMusic(path & ".missing")
    doAssert musicSource == original and musicSource.playing,
      "An unavailable replacement must preserve the playing soundtrack"
    when defined(nimAllocStats):
      let before = getAllocStats()
      for frame in 0 ..< 1000:
        updateMusic()
        doAssert loadMusic(path)
        setMusicVolume(0.25)
        stopSoundVoices()
      doAssert getAllocStats() == before,
        "Music polling and gain updates must not allocate Nim memory"
    closeSoundDevice()
    doAssert musicSource == nil and musicBuffer == nil and musicPath.len == 0
    echo "PASS looping stereo music, gains, idempotent requests and cleanup"

  testMusicLifecycle()
else:
  doAssert not loadMusic("unused.ogg")
  updateMusic()
  setMusicVolume(0.5)
  echo "Music playback is disabled in headless/audioTest builds."
