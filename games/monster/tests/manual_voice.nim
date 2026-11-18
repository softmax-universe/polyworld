import
  std/[monotimes, os, strutils, tempfiles, times],
  vmath,
  ../../../experiments/voice/realtimes,
  ../brains, ../common, ../conversations, ../maps, ../sim, ../voices

const
  Command = "Walk to the village."
  MaximumSeconds = 120
  MaximumAudioBytes = 24000 * 2 * 30

proc run() =
  ## Exercises real voice, transcription and actions without opening devices.
  let
    directory = createTempDir("monster-live-voice-", "")
    brain = newBrain(directory / "conversation.json")
    voice = newMonsterVoice(deviceFree = true)
    started = getMonoTime()
  defer:
    voice.close()
    brain.close()
    removeDir(directory)
  var
    pcm = ""
    transcript = ""
    transcribed = false
    overflowed = false
    world = newWorld(generateMap(42))
  voice.client.onAudio = proc(data: string) =
    ## Collects bounded output in memory instead of opening a speaker.
    if data.len > MaximumAudioBytes - pcm.len:
      overflowed = true
    else:
      pcm.add(data)
  let deliverTranscript = voice.client.onTranscript
  voice.client.onTranscript = proc(text: string) =
    ## Observes automatic transcription while retaining controller behavior.
    transcript = text
    transcribed = true
    deliverTranscript(text)

  proc checkTime() =
    ## Enforces one global deadline across every external-service phase.
    doAssert (getMonoTime() - started).inSeconds < MaximumSeconds,
      "Live voice smoke test exceeded 120 seconds."
    doAssert not overflowed, "Live speech exceeded the bounded test buffer."

  proc checkVoice() =
    ## Reports only the credential-redacted errors exposed by the controller.
    checkTime()
    doAssert voice.error.len == 0, voice.error
    doAssert voice.client.state notin {Failed, Disconnected},
      voice.client.status

  echo "Connecting Monster voice without opening a microphone or speaker"
  voice.setMode(ConversationMode)
  while voice.client.state == Connecting:
    voice.poll()
    checkTime()
    sleep(5)
  checkVoice()
  doAssert voice.client.state == Connected, voice.client.status
  voice.poll()
  doAssert voice.listening()
  doAssert voice.client.handsFree and voice.client.semanticVad
  echo "Connected voice model: ", voice.client.model,
    "; voice: ", voice.client.voice

  echo "Synthesizing the fixed test command"
  doAssert voice.client.speakText(Command)
  while voice.client.responseActive:
    voice.poll()
    checkVoice()
    sleep(5)
  doAssert pcm.len >= 4800, "The voice model returned no usable audio."
  echo "Command PCM bytes: ", pcm.len
  let commandPcm = pcm
  pcm.setLen(0)

  echo "Detecting a spoken turn automatically without a manual commit"
  let input = commandPcm & newString(24000 * 2 * 3)
  var offset = 0
  while offset < input.len:
    let ending = min(input.len, offset + 4800)
    voice.client.sendAudio(input[offset ..< ending])
    offset = ending
    voice.poll()
    checkVoice()
    sleep(100)
  while not transcribed:
    voice.poll()
    checkVoice()
    sleep(5)
  doAssert "walk" in transcript.toLowerAscii() and
    "village" in transcript.toLowerAscii(),
      "The fixed command was not transcribed as expected."
  echo "Input transcript: ", transcript
  voice.submitPending(world, brain)
  doAssert brain.pending, brain.failure

  var
    lastTick = getMonoTime()
    accumulator = 0.0
    arrived = false
    accepted = false
  let initialPosition = world.creature.position
  while true:
    voice.poll()
    checkVoice()
    let now = getMonoTime()
    accumulator += min(0.1, (now - lastTick).inMicroseconds.float64 / 1000000)
    lastTick = now
    while accumulator >= 1.0 / TickRate.float64:
      world.step()
      accumulator -= 1.0 / TickRate.float64
    if world.receive(brain):
      accepted = true
    for text in world.events:
      if text == "Arrived at village.":
        arrived = true
    world.outcomes(brain, directory / "world.json")
    voice.observe(brain.messages)
    doAssert brain.failure.len == 0, brain.failure
    if accepted and arrived and not world.active and
      world.actions.len == 0 and not brain.pending and
      not brain.explanationPending and pcm.len > 0 and
      not voice.client.responseActive:
        break
    sleep(5)
  doAssert length(world.creature.position - initialPosition) > 1
  doAssert length(world.creature.position - world.villages[0].position) < 1.5
  echo "Moss physically arrived at Willow village"
  echo "Creature reply PCM bytes: ", pcm.len
  doAssert voice.listening(), "Conversation must keep listening during output."
  voice.setMode(TextMode)
  doAssert not voice.listening()
  doAssert voice.client.state == Disconnected
  echo "Live hands-free conversation -> game action -> spoken reply passed"

if "--live" in commandLineParams():
  run()
else:
  echo "Opt-in live test: nim r games/monster/tests/manual_voice.nim --live"
  echo "Uses configured API credentials; never records or plays audio."
