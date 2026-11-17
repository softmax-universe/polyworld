import
  std/[os, strutils, times],
  windy,
  ../realtimes

let
  window = newWindow("Voice transport lifecycle test", ivec2(160, 100),
    visible = false)
  client = newVoiceClient()
  configuredVoice = client.voice
var
  step = 0
  audioBytes = 0
  done = false
  failure = ""
  deadline = epochTime() + 45
client.onAudio = proc(pcm: string) =
  ## Counts generated audio without playing it or opening a microphone.
  audioBytes += pcm.len
window.onFrame = proc() =
  ## Exercises the same transport order as the real Windy application.
  client.poll()
  if client.state == Failed and step != 1:
    failure = client.status
    done = true
  case step
  of 0:
    client.voice = "invalid-test-voice"
    client.connect()
    step = 1
  of 1:
    if client.state == Failed:
      doAssert "voice" in client.status.toLowerAscii(), client.status
      echo "Rejected voice handled: ", client.status
      client.voice = configuredVoice
      client.connect()
      step = 2
  of 2:
    if client.state == Connected:
      client.sendText("Say exactly: Test complete.")
      step = 3
  of 3:
    if audioBytes > 0 and not client.responseActive:
      client.disconnect()
      step = 4
  of 4:
    doAssert client.state == Disconnected
    client.connect()
    step = 5
  of 5:
    if client.state == Connected:
      client.disconnect()
      step = 6
  of 6:
    done = true
  else:
    discard
  # All UI actions must settle before Windy swaps HTTP dispatchers.
  client.poll()
try:
  while not done and epochTime() < deadline:
    pollEvents()
    sleep(5)
  doAssert failure.len == 0, failure
  doAssert done, "Windy lifecycle deadline exceeded"
  doAssert audioBytes > 0
  echo "Windy rejection, recovery, reply, reconnect, shutdown passed"
finally:
  window.onFrame = nil
  client.disconnect()
  client.poll()
  window.close()
