import
  std/[importutils, monotimes, os, times],
  openal, slappy,
  audios

privateAccess(VoiceAudio)

when defined(macosx):
  proc voiceAudioCreate(voiceProcessing: bool,
    inputDevice, outputDevice: cstring): pointer {.importc.}
    ## Allocates a dormant capture queue for meter regression checks.
  echo "Testing embedded microphone metadata for direct Nim launches"
  doAssert microphonePermission() in ["pending", "denied", "allowed"]
  echo "Testing dormant duplex audio never starts the microphone for output"
  let duplex = newVoiceAudio(duplex = true)
  doAssert not duplex.capturing()
  doAssert not duplex.outputActive()
  doAssert duplex.readCapture() == ""
  echo "Testing meter levels survive empty UI polls and clear on Stop"
  duplex.nativeDuplex = voiceAudioCreate(true, "", "")
  doAssert duplex.nativeDuplex != nil
  duplex.level = 0.05'f
  duplex.levelUpdated = getMonoTime() - initDuration(milliseconds = 10)
  discard duplex.readCapture()
  doAssert duplex.inputLevel() > 0.01'f
  duplex.levelUpdated = getMonoTime() - initDuration(seconds = 1)
  discard duplex.readCapture()
  doAssert duplex.inputLevel() < 0.001'f
  duplex.stopCapture()
  doAssert duplex.inputLevel() == 0
  var refused = false
  try:
    duplex.queuePcm("\0\0")
  except VoiceAudioError:
    refused = true
  doAssert refused
  doAssert not duplex.capturing()
  duplex.close()
  duplex.close()
  when defined(voiceAudioTesting):
    echo "Testing native duplex queues, cancellation and PCM resampling"
    doAssert testDuplexAudio()

echo "Testing PCM16 amplitude and sample validation"
doAssert pcmLevel("") == 0
doAssert pcmLevel("\0\0\0\0") == 0
doAssert abs(pcmLevel("\0\x40\0\xc0") - 0.5'f) < 0.0001'f
doAssert pcmLevel("\0\x80") == 1
var rejected = false
try:
  discard pcmLevel("\0")
except VoiceAudioError:
  rejected = true
doAssert rejected

echo "Testing dormant and repeated audio shutdown"
let audio = newVoiceAudio()
doAssert not audio.capturing()
doAssert not audio.outputActive()
doAssert audio.readCapture() == ""
doAssert audio.playbackMilliseconds() == 0
audio.stopCapture()
audio.stopPlayback()

if "--playback" in commandLineParams():
  echo "Testing silent streaming, queue drainage, and underrun recovery"
  let silence = newString(VoiceBytesPerSecond div 10)
  audio.queuePcm(silence)
  audio.queuePcm(silence)
  doAssert audio.outputActive()
  for i in 0 ..< 50:
    audio.pollPlayback()
    sleep(10)
  doAssert not audio.outputActive()
  doAssert audio.playbackMilliseconds() == 200
  audio.queuePcm(silence)
  doAssert audio.outputActive()
  for i in 0 ..< 30:
    audio.pollPlayback()
    sleep(10)
  doAssert not audio.outputActive()
  doAssert audio.playbackMilliseconds() == 300
  audio.stopPlayback()
  doAssert audio.playbackMilliseconds() == 0
  doAssert not audio.outputActive()
  audio.queuePcm(silence)
  sleep(20)
  audio.stopPlayback()
  audio.queuePcm(silence)
  for i in 0 ..< 30:
    audio.pollPlayback()
    sleep(10)
  doAssert audio.playbackMilliseconds() == 100
  doAssert not audio.outputActive()

audio.close()
audio.close()
if "--playback" in commandLineParams():
  echo "Testing voice shutdown preserves a shared game audio device"
  slappyInit()
  let shared = newVoiceAudio(closeDevice = false)
  shared.queuePcm(newString(VoiceBytesPerSecond div 100))
  shared.close()
  doAssert alcGetCurrentContext() != nil
  slappyClose()
rejected = false
try:
  audio.queuePcm("\0\0")
except VoiceAudioError:
  rejected = true
doAssert rejected
echo "Audio checks passed"
