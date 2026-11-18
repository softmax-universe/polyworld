# Voice experiment

A standalone native voice bot using Windy for its window, Silky for its
interface, and Slappy for microphone capture and queued OpenAL playback.
The authenticated Realtime connection uses Polyworld's existing `ws`
dependency. All experiment code stays in this directory. It does not modify
or import the main engine's LLM implementation.

## Run

From the Polyworld repository:

```sh
nim r experiments/voice/voice.nim
```

`./experiments/voice/run.sh` is also supported. Both commands use Polyworld's
existing Nim dependencies. On macOS, the executable prepares a signed
`Voice Lab.app` in the ignored `experiments/voice/build` directory and opens it
through LaunchServices. The launcher waits until the app closes and reports
an error if it exits abnormally. Command-line arguments and environment
variables pass to the app in memory, including the API key.

This launch step is required even when the executable already lives in an app
bundle. Direct child processes can inherit the terminal host's macOS privacy
identity. From Runway, this previously caused macOS to abort Voice Lab while
requesting microphone permission because the host had no microphone usage
description. Voice Lab now requests permission under its own app identity.
The usage description is also embedded in the executable, and microphone
initialization checks that it is present before asking for access.

Credentials are read from `OPENAI_API_KEY`, or from the existing raw key file
at `~/secrets/openai.key`. Keys are never written into the app bundle. When
launching the app from Finder, use the key file because Finder does not inherit
your terminal environment.

The default voice model is `gpt-realtime-2.1-mini`. To compare a model available
to your OpenAI account:

```sh
OPENAI_REALTIME_MODEL=gpt-realtime-2.1 ./experiments/voice/run.sh
```

`OPENAI_REALTIME_VOICE` selects the voice. The default is `marin`.

The normal launch starts disconnected. Connect, then hold the talk button or
Space outside the text field to speak. Release to send your turn. You can also
type a message, enable hands-free listening, or switch spoken replies off.
Hands-free mode requires pressing Start microphone. Pause microphone stops
capture and discards speech that has not yet become a completed turn. Capture
also stops when the window loses focus or the connection fails. Push-to-talk
turns have a 30-second limit.

Stop reply or Escape interrupts playback. New starts a fresh server
conversation. Copy copies the visible transcript. Conversations and microphone
recordings are not saved to disk.

Spoken replies controls local playback. Audio is still generated and billed
when playback is muted, while its transcript remains visible. Turning playback
back on takes effect with the next reply. The latency shown for typed and
push-to-talk turns measures submission to the first audio chunk received,
not the full time until audio is heard.

Headphones are recommended for hands-free use because this experiment does
not perform acoustic echo cancellation.

On macOS, allow Voice Lab microphone access when requested, then use Talk
again. If access was denied, enable Voice Lab in System Settings > Privacy &
Security > Microphone. On Linux, the normal Windy window dependencies and an
OpenAL capture device are required. Slappy's microphone API is native OpenAL
code, not a Linux-only implementation. Browser builds are outside this
experiment's scope.

## Build and preview

Build the app without starting it:

```sh
./experiments/voice/run.sh --build-only
```

Pass application arguments after `--`. This offline preview does not connect
to OpenAI or open the microphone:

```sh
./experiments/voice/run.sh -- --demo --frames=5 \
  --screenshot=/tmp/polyworld-voice.png
```

The bundled IBM Plex Sans font and its license are in `assets`. The macOS
bundle also includes these files under `Contents/Resources/assets`.

## Checks

The protocol replay tests run without credentials, networking, or audio devices:

```sh
nim check experiments/voice/voice.nim
nim r --out:experiments/voice/build/tests_realtime \
  experiments/voice/tests/tests_realtime.nim
nim r --out:experiments/voice/build/tests_transport \
  experiments/voice/tests/tests_transport.nim
nim r --out:experiments/voice/build/test_audios \
  experiments/voice/test_audios.nim
python3 experiments/voice/tests/test_launches.py
```

The macOS launcher check opens two short offline windows. It verifies argument
forwarding, screenshot output, clean shutdown, and terminal errors when the
launched app fails. It never connects to OpenAI or requests microphone access.

Add `--playback` after the audio test filename to exercise the actual output
device with silent PCM, including underrun recovery and interrupted playback.
It does not record from the microphone.

The live roundtrip test uses the configured OpenAI account and incurs normal
API charges. It generates speech, sends that audio back as a user turn, and
checks the returned transcription and reply. It does not open a microphone or
play through speakers:

```sh
nim r --out:experiments/voice/build/live_roundtrip \
  experiments/voice/tests/live_roundtrip.nim
```

The transport regression test uses a local server and a fake key. It checks
session and model rejection, partial reads, disconnects, and reconnection.

`tests/live_windy.nim` also checks rejection of an invalid voice, recovery with
the configured voice, a spoken response, reconnection, and shutdown while Windy
and the Realtime transport poll their event loops. It uses the configured API
account but does not record or play audio.

API rejections show the server's error code, parameter, and explanation with
credentials removed. The model is selected when connecting and is not included
in later session updates.
