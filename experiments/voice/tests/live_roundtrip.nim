import
  std/[os, strutils, times],
  ../realtimes

let client = newVoiceClient()
var
  pcm = ""
  firstAudioAt = 0.0
client.onAudio = proc(data: string) =
  ## Saves generated PCM in memory without accessing audio devices.
  if firstAudioAt == 0:
    firstAudioAt = epochTime()
  pcm.add(data)

proc awaitReady(client: VoiceClient, seconds: float64) =
  ## Pumps the transport until a session is configured or fails.
  let deadline = epochTime() + seconds
  while client.state notin {Connected, Failed} and epochTime() < deadline:
    client.poll()
    sleep(5)
  doAssert client.state == Connected, client.status

proc awaitReply(client: VoiceClient, seconds: float64) =
  ## Waits for a response while maintaining a finite test deadline.
  let deadline = epochTime() + seconds
  while client.responseActive and epochTime() < deadline:
    client.poll()
    doAssert client.state == Connected, client.status
    sleep(5)
  doAssert not client.responseActive, "Response deadline exceeded"

client.connect()
client.awaitReady(30)
echo "Connected model: ", client.model
let requestedAt = epochTime()
client.sendText("Say exactly: The little green robot is ready to explore.")
client.awaitReply(45)
doAssert pcm.len > 4800, client.status
echo "First audio latency ms: ", ((firstAudioAt - requestedAt) * 1000).int
echo "Generated PCM bytes: ", pcm.len
for item in client.transcripts:
  if item.role == Assistant:
    echo "Generated transcript: ", item.text
let spoken = pcm
pcm.setLen(0)
client.sendAudio(spoken)
client.commitAudio()
client.awaitReply(45)
let deadline = epochTime() + 10
var transcribed = false
while not transcribed and epochTime() < deadline:
  client.poll()
  for item in client.transcripts:
    if item.role == User and item.itemId.startsWith("item_") and item.final:
      echo "Input transcript: ", item.text
      doAssert "robot" in item.text.toLowerAscii()
      transcribed = true
  sleep(5)
doAssert transcribed, "Input transcription did not arrive"
doAssert pcm.len > 0, "Audio-input turn produced no spoken response"
client.disconnect()
echo "Live text -> audio -> input transcription -> spoken reply passed"
