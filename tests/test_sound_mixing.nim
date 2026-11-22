## Exercises audible mixer gains using silent fixtures and no graphics window.
include ../src/polyworld/sounddevices

when not (defined(emscripten) or defined(headless) or defined(audioTest)):
  import std/tempfiles, openal

  proc appendLittle(bytes: var string, value, size: int) =
    ## Writes a little-endian PCM header field.
    for i in 0 ..< size:
      bytes.add char((value shr (i * 8)) and 255)

  proc silentFixture(channels: int): string =
    ## Creates ten seconds of silent PCM with the requested channel count.
    const Rate = 8000
    let
      frameBytes = channels * 2
      dataBytes = Rate * 10 * frameBytes
    result = "RIFF"
    result.appendLittle(36 + dataBytes, 4)
    result.add "WAVEfmt "
    result.appendLittle(16, 4)
    result.appendLittle(1, 2)
    result.appendLittle(channels, 2)
    result.appendLittle(Rate, 4)
    result.appendLittle(Rate * frameBytes, 4)
    result.appendLittle(frameBytes, 2)
    result.appendLittle(16, 2)
    result.add "data"
    result.appendLittle(dataBytes, 4)
    result.add newString(dataBytes)

  proc testSoundMixing() =
    ## Verifies simultaneous stereo music, mono effects and independent gains.
    let
      directory = createTempDir("polyworld-sound-mixing-", "")
      effectsPath = directory / "effects.wav"
      soundtrackPath = directory / "music.wav"
    defer: removeDir(directory)
    writeFile(effectsPath, silentFixture(1))
    writeFile(soundtrackPath, silentFixture(2))
    setSoundVolumes(1, 0.6, 0.8)
    setMusicVolume(0.25)
    doAssert openSoundDevice()
    defer: closeSoundDevice()
    doAssert loadSoundBuffer(0, effectsPath)
    prepareSoundDevice()
    doAssert loadMusic(soundtrackPath)
    doAssert listener.gain == 1
    doAssert musicBuffer.channels == 2
    doAssert musicSource.looping and musicSource.playing
    let originalMusic = musicSource

    for i in 0 ..< SoundVoiceLimit - InterfaceVoiceLimit:
      doAssert startSoundVoice(0, 0.5, 0, ui = false)
    for i in 0 ..< InterfaceVoiceLimit - 1:
      doAssert startSoundVoice(0, 0.5, 0, ui = true)
    doAssert startSoundVoice(0, 0.5, 0, ui = true, fanfare = true)
    sleep(60)
    doAssert musicSource.playing and musicSource.playback > 0
    for i, voice in voices:
      doAssert voice.active and voice.source.playing,
        "Music must preserve every simultaneous effects and UI voice"
      doAssert voice.source.sound.channels == 1
      doAssert voice.source != musicSource
      let expected = if i < InterfaceVoiceLimit: 0.4'f else: 0.3'f
      doAssert abs(voice.source.gain - expected) < 0.001
      for j in 0 ..< i:
        doAssert voice.source != voices[j].source

    setSoundVolumes(0.25, 0.6, 0.8)
    doAssert listener.gain == 1,
      "Master gain must not also attenuate the listener"
    doAssert abs(musicSource.gain - 0.0625) < 0.001
    doAssert startSoundVoice(0, 0.5, 0, ui = false)
    doAssert startSoundVoice(0, 0.5, 0, ui = true)
    doAssert startSoundVoice(0, 0.5, 0, ui = true, fanfare = true)
    for i, voice in voices:
      let expected = if i < InterfaceVoiceLimit: 0.1'f else: 0.075'f
      doAssert abs(voice.source.gain - expected) < 0.001,
        "Master gain must multiply existing and new voices exactly once"
    setMusicVolume(0.5)
    doAssert abs(musicSource.gain - 0.125) < 0.001
    setMusicVolume(0.25)
    setSoundVolumes(1, 0.6, 0.8)
    doAssert musicSource.gain == 0.25
    for i, voice in voices:
      let expected = if i < InterfaceVoiceLimit: 0.4'f else: 0.3'f
      doAssert abs(voice.source.gain - expected) < 0.001

    setMusicVolume(0)
    doAssert musicSource.playing and musicSource.gain == 0
    for voice in voices:
      doAssert voice.source.playing and voice.source.gain > 0
    doAssert startSoundVoice(0, 0.5, 0, ui = false)
    doAssert startSoundVoice(0, 0.5, 0, ui = true)
    setMusicVolume(0.25)
    doAssert musicSource == originalMusic and musicSource.playing
    doAssert musicSource.gain == 0.25

    setSoundVolumes(1, 0, 0.8)
    doAssert not startSoundVoice(0, 0.5, 0, ui = false)
    doAssert startSoundVoice(0, 0.5, 0, ui = true)
    doAssert startSoundVoice(0, 0.5, 0, ui = true, fanfare = true)
    for i, voice in voices:
      if i < InterfaceVoiceLimit:
        doAssert abs(voice.source.gain - 0.4) < 0.001
      else:
        doAssert voice.source.gain == 0
    doAssert musicSource.playing and musicSource.gain == 0.25

    setSoundVolumes(1, 0.6, 0)
    doAssert startSoundVoice(0, 0.5, 0, ui = false)
    doAssert not startSoundVoice(0, 0.5, 0, ui = true)
    doAssert not startSoundVoice(0, 0.5, 0, ui = true, fanfare = true)
    for i, voice in voices:
      if i < InterfaceVoiceLimit:
        doAssert voice.source.gain == 0
      else:
        doAssert abs(voice.source.gain - 0.3) < 0.001
    doAssert musicSource.playing and musicSource.gain == 0.25

    setSoundVolumes(0, 0.6, 0.8)
    doAssert listener.gain == 1
    doAssert not startSoundVoice(0, 0.5, 0, ui = false)
    doAssert not startSoundVoice(0, 0.5, 0, ui = true)
    doAssert not startSoundVoice(0, 0.5, 0, ui = true, fanfare = true)
    doAssert musicSource.playing and musicSource.gain == 0
    for voice in voices:
      doAssert voice.source.gain == 0,
        "Master mute must silence every source, including stereo music"
    setMusicVolume(0.25)
    doAssert musicSource.gain == 0,
      "Music slider changes must not bypass master mute"
    setSoundVolumes(1, 0.6, 0.8)
    doAssert listener.gain == 1
    doAssert musicSource.gain == 0.25
    for i, voice in voices:
      let expected = if i < InterfaceVoiceLimit: 0.4'f else: 0.3'f
      doAssert abs(voice.source.gain - expected) < 0.001,
        "Unmuting must restore the saved category gain without compounding it"
    doAssert startSoundVoice(0, 0.5, 0, ui = false)
    doAssert startSoundVoice(0, 0.5, 0, ui = true)
    let offset = musicSource.playback
    stopSoundVoices()
    for voice in voices:
      doAssert not voice.active and not voice.source.playing
    doAssert musicSource == originalMusic and musicSource.playing
    doAssert musicSource.playback >= offset
    doAssert alGetError() == AL_NO_ERROR
    echo "PASS 24 effects/UI voices plus stereo music and independent gains"

  testSoundMixing()
else:
  doAssert not openSoundDevice()
  doAssert not loadMusic("unused.wav")
  doAssert not startSoundVoice(0, 0.5, 0, ui = false)
  doAssert not startSoundVoice(0, 0.5, 0, ui = true)
  setMusicVolume(0.5)
  closeSoundDevice()
  echo "Native sound mixing is disabled in headless/audioTest builds."
