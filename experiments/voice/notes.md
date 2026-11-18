# Voice experiment

A standalone native and browser voice bot using Windy for its window and Silky
for its interface. macOS uses native audio with explicit device routing and echo
cancellation during continuous conversation. Other native platforms use
Slappy capture and queued OpenAL playback.
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

Both launch paths sign with the sole existing valid code-signing certificate
when one is available. `VOICE_SIGNING_IDENTITY` selects a certificate explicitly
if there are several. This keeps microphone permission stable across rebuilds.
Switching from an ad-hoc build may require one new approval. Machines without
a signing certificate use ad-hoc signing and may prompt again after changes.
No certificate is created and no macOS privacy settings are changed.

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

The normal launch starts disconnected with the microphone off. Press
**Start conversation** to connect and start continuous listening. If macOS
asks for microphone access, approve it; conversation starts automatically
after approval. Speak naturally and interrupt the agent by speaking again.
The microphone stays on during replies and while another app has focus.
**Stop conversation** stops capture and the current reply. Disconnecting,
closing the window, or an audio/network failure also stops conversation mode.

On macOS, **Sound in** selects the microphone and **Sound out** selects the
speaker or headphones. Choose devices while audio is stopped. **Refresh**
updates the list after connecting or disconnecting hardware. Choices apply
to conversation, manual capture, and typed-message playback. They are saved
under the platform configuration directory in `polyworld-voice/devices.json`
and never change macOS system defaults. An unplugged selection remains visible
until you choose another device. Playing a typed reply never opens the mic.

Use the MacBook microphone and speakers through **System default** for both
selectors. Explicit selections matching the macOS defaults also preserve the
engine's normal routing. Custom aggregate routing remains removed; Sony
microphone support remains unresolved.

MacBook voice processing can expose nine channels at 48 kHz. Capture accepts
that format and explicitly converts the first channel to mono, rather than
rejecting it or mixing in the other channels. The offline regression covers
this format with both interleaved and separate channel buffers. Live MacBook
speech was also verified through the app's transcript and response.

The input meter uses decibels and holds its level between capture callbacks
so ordinary headset speech remains visible.

The API detects when you finish a thought using semantic voice activity
detection and responds automatically. There is no manual send or release step.
Speech and playback run together, so new speech can interrupt a reply.

For manual input, use Connect, then hold **Hold to talk** or Space outside the
text field. Release to send. Manual capture pauses when the window loses
focus and has a 30-second limit. Typed messages and spoken-reply muting remain
available; typing during an active conversation keeps the microphone running.

Stop reply or Escape interrupts playback while continuous conversation keeps
listening. New starts a fresh server conversation and resumes conversation
mode if it was enabled. Copy copies the visible transcript. Conversations and
microphone recordings are not saved to disk.

Spoken replies controls local playback. Audio is still generated and billed
when playback is muted, while its transcript remains visible. Turning playback
back on takes effect with the next reply. The latency shown for typed and
push-to-talk turns measures submission to the first audio chunk received,
not the full time until audio is heard.

On macOS, continuous mode routes both input and output through the same
echo-cancelled audio graph. Headphones can still improve results and are
recommended on other platforms, which use Slappy without echo cancellation.

On macOS, allow Voice Lab microphone access when requested. Manual Talk may
need another press after approval. If access was denied, enable Voice Lab in
System Settings > Privacy & Security > Microphone. On Linux, the normal Windy
window dependencies and an
OpenAL capture device are required. Slappy's microphone API is native OpenAL
code, not a Linux-only implementation. Browser builds use Slappy's Web Audio
capture backend, described below.

## Browser build and local server

Install Emscripten, then run from the repository root:

```sh
./experiments/voice/build_web.sh
python3 experiments/voice/serve.py --port 8001
```

Open <http://localhost:8001/> on the computer running the server. The same
`voice.nim` app runs as WebAssembly with its Windy/Silky canvas UI. Browser
controls above the canvas start audio directly from a click. Click **Start
conversation**, allow microphone access, then speak. Capture continues during
spoken replies, and new speech interrupts playback. **Stop conversation**
releases the microphone. **Disconnect** also closes the OpenAI session. Typed
messages, push-to-talk, and mute use the existing conversation controls.

Browser builds require Slappy's microphone implementation from
[Slappy PR #29](https://github.com/treeform/slappy/pull/29). The build script
recognizes the sibling `slappy-wasm-microphone` checkout. For another checkout,
set `SLAPPY_PATH=/path/to/slappy/src` before building. No engine configuration
or game assets are changed.

The local server reads `OPENAI_API_KEY` or `~/secrets/openai.key`. If neither is
set, enter your key in the password field for this session. The full key stays
on the local server or in the entered field, is never compiled into WASM, and
is not saved in browser storage. The server exchanges it for a short-lived
Realtime token. Audio and transcripts travel directly between the browser and
OpenAI over a WebSocket. This is an experiment server bound to loopback, not a
public hosting service. For a remote work computer, forward its port over SSH
and still open a localhost URL in your browser.

The browser uses its selected input/output devices. Browser permission, autoplay,
and background-tab scheduling rules apply. Microphone capture uses AudioWorklet
and needs localhost or HTTPS. Headphones help when evaluating acoustic feedback;
physical speaker-to-microphone echo cancellation depends on the browser and
hardware. Tests use synthetic input instead of recording room audio.

The browser path retains the native Realtime event parser. It uses the documented
[browser WebSocket authentication](https://developers.openai.com/api/docs/guides/voice-websockets?api=realtime)
and [ephemeral client-secret exchange](https://developers.openai.com/api/docs/guides/voice-webrtc?api=realtime).
WebRTC is OpenAI's recommended browser transport for general applications; this
experiment uses WebSockets to exercise Slappy's PCM capture and playback directly.

Offline browser transport and local-server regressions:

```sh
node experiments/voice/tests/test_browser_transport.mjs
python3 experiments/voice/tests/test_web_server.py
```

The live browser tests require Playwright and use billable OpenAI requests:

```sh
npm install --prefix experiments/voice/build/web-tests --no-save playwright@1.63.0
experiments/voice/build/web-tests/node_modules/.bin/playwright install chromium
node experiments/voice/tests/live_browser_text.mjs
```

`live_browser_duplex.mjs --audio=/absolute/path/to/synthetic-speech.wav`
uses Chromium's fake microphone. Its fixture should contain a few seconds of
silence, "Hello, please explain how flowers grow in five sentences", two seconds
of silence, "Stop, just say blue", then silence. It checks transcription,
simultaneous capture/playback, spoken interruption, and microphone shutdown.
`VOICE_WEB_URL` selects another local server address, and
`VOICE_PLAYWRIGHT_PATH` can point to an existing Playwright installation.

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
nim r -d:voiceAudioTesting --out:experiments/voice/build/test_duplex \
  experiments/voice/test_audios.nim
nim r --out:experiments/voice/build/tests_conversation_controls \
  experiments/voice/tests/tests_conversation_controls.nim
nim r --out:experiments/voice/build/tests_devices \
  experiments/voice/tests/tests_devices.nim
python3 experiments/voice/tests/test_launches.py
python3 experiments/voice/tests/test_signings.py
```

The macOS launcher check opens two short offline windows. It verifies argument
forwarding, screenshot output, clean shutdown, and terminal errors when the
launched app fails. It never connects to OpenAI or requests microphone access.

Add `--playback` after the audio test filename to exercise the actual output
device with silent PCM, including underrun recovery and interrupted playback.
It does not record from the microphone.

To check macOS conversation audio on the selected microphone and speaker:

```sh
nim r --out:experiments/voice/build/manual_duplex \
  experiments/voice/tests/manual_duplex.nim
```

This hardware check collects about one second of microphone samples twice,
allowing up to eight seconds per cycle for device startup. It discards samples
and plays silence without connecting to OpenAI.
It uses the Voice Lab bundle and its existing microphone permission. Run the
usual `nim r experiments/voice/voice.nim` command afterward to restore the GUI.
Conversation audio explicitly matches voice-processing input/output formats,
including Bluetooth routes with different native microphone and speaker rates.
If Bluetooth changes profiles during startup, it resumes the existing audio
engine after the configuration notification, with a bounded retry limit.
Its report includes frame counts and signal peaks. A frame count alone does
not prove speech was captured. To test a particular headset while speaking:

```sh
nim r --out:experiments/voice/build/manual_duplex \
  experiments/voice/tests/manual_duplex.nim \
  --input=WH-1000XM6 --output=WH-1000XM6 \
  --seconds=15 --cycles=1 --require-signal
```

`--manual` exercises the same selected devices without voice processing.

The live roundtrip test uses the configured OpenAI account and incurs normal
API charges. It generates speech, sends that audio back as a user turn, and
checks the returned transcription and reply. It does not open a microphone or
play through speakers:

```sh
nim r --out:experiments/voice/build/live_roundtrip \
  experiments/voice/tests/live_roundtrip.nim
```

The continuous-conversation test generates synthetic speech and streams it
at microphone speed. It checks automatic semantic turn detection, a spoken
reply, and an interruption while that reply is being generated. It uses the
configured API account without recording or playing audio:

```sh
nim r --out:experiments/voice/build/live_conversation \
  experiments/voice/tests/live_conversation.nim
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
