import
  std/[os, strutils, times],
  ../realtimes

const
  SampleBytesPerSecond = 48000
  ChunkBytes = SampleBytesPerSecond div 50
  DeadlineSeconds = 45.0

type Stage = enum
  Preparing, Conversing

let
  client = newVoiceClient()
  deadline = epochTime() + DeadlineSeconds
var
  stage = Preparing
  generated = ""
  speechStarts, speechStops, commits, replies = 0
  firstReplyBytes, replacementBytes = 0
  interruptedActiveResponse = false
  transcripts: seq[string]

proc pump(milliseconds = 5) =
  ## Advances network events within the entire test's finite deadline.
  let until = epochTime() + milliseconds.float64 / 1000
  while true:
    client.poll()
    doAssert client.state != Failed, client.status
    doAssert client.failure.len == 0, client.failure
    doAssert epochTime() < deadline, "Live conversation deadline exceeded"
    if epochTime() >= until:
      break
    sleep(5)

proc awaitReady() =
  ## Waits for the server to accept this connection's session settings.
  while client.state != Connected:
    pump()

proc synthesize(text: string): string =
  ## Generates a spoken test input in memory without opening audio devices.
  generated.setLen(0)
  client.sendText("Read exactly this sentence aloud: " & text)
  while client.responseActive:
    pump()
  doAssert generated.len >= 4800, "Seed speech contained no usable audio"
  result = generated

proc stream(pcm: string) =
  ## Streams PCM at microphone speed without committing or requesting replies.
  var offset = 0
  while offset < pcm.len:
    let stop = min(offset + ChunkBytes, pcm.len)
    client.sendAudio(pcm[offset ..< stop])
    offset = stop
    pump(20)

client.onAudioStart = proc() =
  ## Counts distinct assistant audio streams after automatic turn detection.
  if stage == Conversing:
    inc replies
client.onAudio = proc(pcm: string) =
  ## Counts received audio while leaving the speakers completely untouched.
  case stage
  of Preparing:
    generated.add(pcm)
  of Conversing:
    if speechStarts >= 2:
      replacementBytes += pcm.len
    else:
      firstReplyBytes += pcm.len
client.onSpeechStart = proc() =
  ## Applies the app's barge-in policy without stopping incoming audio.
  inc speechStarts
  if speechStarts == 2:
    interruptedActiveResponse = client.responseActive
  client.interrupt(0)
client.onSpeechStop = proc() =
  ## Counts utterances the server finished without a push-to-talk release.
  inc speechStops
client.onInputCommit = proc() =
  ## Counts automatic audio commits originating from semantic VAD.
  inc commits
client.onTranscript = proc(text: string) =
  ## Retains the synthetic input transcripts for end-to-end assertions.
  transcripts.add(text)

try:
  client.connect()
  awaitReady()
  let
    firstInput = synthesize(
      "Tell me a long, detailed story about a friendly robot."
    )
    secondInput = synthesize(
      "Stop the story. Say exactly: Conversation test complete."
    )
  client.disconnect()
  client.semanticVad = true
  client.autoRespond = true
  client.instructions = "Speak naturally. When asked for a long story, " &
    "tell it in at least twelve sentences. When interrupted, follow the " &
    "newest request immediately and keep the replacement reply brief."
  client.setHandsFree(true)
  stage = Conversing
  client.connect()
  awaitReady()
  echo "Testing automatic semantic turns with model: ", client.model
  stream(firstInput)
  let silence = newString(ChunkBytes)
  while firstReplyBytes == 0:
    stream(silence)
  doAssert speechStarts >= 1 and speechStops >= 1
  doAssert commits >= 1, "Semantic VAD did not commit the first utterance"
  echo "First spoken response arrived without a manual commit"
  stream(secondInput)
  while replacementBytes == 0 or client.responseActive or
    speechStops < 2 or transcripts.len < 2:
      stream(silence)
  doAssert interruptedActiveResponse,
    "The second input did not overlap an active assistant response"
  doAssert replies >= 2, "Barge-in did not produce a new spoken response"
  doAssert commits >= 2, "Semantic VAD did not commit the interruption"
  doAssert "robot" in transcripts[0].toLowerAscii(), transcripts[0]
  doAssert "conversation test complete" in transcripts[1].toLowerAscii(),
    transcripts[1]
  echo "Automatic turns, input transcripts and spoken barge-in passed"
finally:
  client.disconnect()
  client.poll()
