import
  std/[json, monotimes, os, strutils, times],
  pixie, silky, vmath,
  audios, devices, realtimes, views

when not defined(emscripten):
  import launches

const
  ExperimentDir = currentSourcePath().parentDir
  MaxTalkMilliseconds = 30000

type
  Options = object
    demo, help: bool
    frames: int
    screenshot: string
  App = ref object
    window: Window
    view: VoiceView
    client: VoiceClient
    audio: VoiceAudio
    manualAudio, conversationAudio: VoiceAudio
    inputs, outputs: seq[AudioDevice]
    options: Options
    captureStarted, replyStarted: MonoTime
    waitingForAudio, playbackSuppressed: bool
    pendingCaptureCommit: bool
    conversationRequested, permissionPending, acceptResponses: bool
    conversationReady: bool
    frameCount: int
    finished: bool

when defined(emscripten):
  var
    browserApp: App
    browserState: string
  proc browserSleep(milliseconds: cuint) {.importc: "emscripten_sleep",
    header: "<emscripten.h>".}
    ## Yields browser work between rendered frames.

proc optionsFromArgs(): Options =
  ## Parses experiment arguments before opening a window or audio device.
  for argument in commandLineParams():
    if argument == "--demo":
      result.demo = true
    elif argument in ["--help", "-h"]:
      result.help = true
    elif argument.startsWith("--frames="):
      result.frames = parseInt(argument[9 .. ^1])
      if result.frames < 1 or result.frames > 100000:
        raise newException(ValueError, "--frames must be between 1 and 100000")
    elif argument.startsWith("--screenshot="):
      result.screenshot = argument[13 .. ^1]
      if result.screenshot.len == 0:
        raise newException(ValueError, "--screenshot needs a file path")
    else:
      raise newException(ValueError, "Unknown voice argument: " & argument)
  if result.screenshot.len > 0 and result.frames == 0:
    result.frames = 5

proc fontPath(): string =
  ## Finds the bundled font in either a packaged app or this experiment.
  when defined(emscripten):
    return "/voice-assets/IBMPlexSans-Regular.ttf"
  else:
    for directory in [
      getAppDir() / "../Resources/assets",
      getAppDir() / "assets",
      ExperimentDir / "assets"
    ]:
      let path = directory / "IBMPlexSans-Regular.ttf"
      if fileExists(path):
        return path
    raise newException(IOError, "Voice Lab could not find its bundled font.")

proc stopListening(app: App, commit = false) =
  ## Stops recording and either submits or discards the unfinished turn.
  when defined(emscripten):
    if not app.audio.capturing() and not app.pendingCaptureCommit:
      return
    app.audio.stopCapture()
    if commit and app.client.state == Connected and not app.client.handsFree:
      app.pendingCaptureCommit = true
      app.client.status = "Finishing the recorded turn..."
    else:
      app.pendingCaptureCommit = false
      app.audio.releaseCapture()
      app.client.clearAudio()
    return
  when not defined(emscripten):
    if not app.audio.capturing():
      return
    app.audio.stopCapture()
    if commit and app.client.state == Connected:
      app.client.sendAudio(app.audio.readCapture())
      if not app.client.handsFree:
        app.replyStarted = getMonoTime()
        app.waitingForAudio = true
        app.client.commitAudio()
      else:
        app.client.clearAudio()
    else:
      app.client.clearAudio()

proc interrupt(app: App) =
  ## Stops audible speech and tells the server how much was actually heard.
  let played =
    if app.playbackSuppressed or not app.view.speakReplies: int.high
    else: app.audio.playbackMilliseconds()
  app.client.interrupt(played)
  app.audio.stopPlayback()
  app.waitingForAudio = false
  app.playbackSuppressed = true
  app.acceptResponses = false

proc stopConversation(app: App) =
  ## Disables continuous capture and returns playback to the manual device.
  app.conversationRequested = false
  app.conversationReady = false
  app.permissionPending = false
  app.acceptResponses = false
  app.playbackSuppressed = true
  app.waitingForAudio = false
  when defined(emscripten):
    app.pendingCaptureCommit = false
    app.audio.releaseCapture()
  else:
    app.audio.stopCapture()
  app.audio.stopPlayback()
  app.audio = app.manualAudio
  app.client.discardTranscripts()
  app.client.setHandsFree(false)
  if app.client.state == Connecting:
    app.client.disconnect()

proc reportError(app: App, message: string) =
  ## Keeps a recoverable error visible and turns microphone capture off.
  if app.conversationRequested:
    app.client.interrupt(0)
    app.stopConversation()
  app.view.error = message
  app.stopListening()

proc beginConversation(app: App, apiKey = "") =
  ## Enables natural speech and connects without requiring a separate click.
  app.interrupt()
  app.stopListening()
  app.view.error = ""
  app.client.failure = ""
  app.audio = app.conversationAudio
  app.conversationRequested = true
  app.conversationReady = false
  app.permissionPending = false
  app.client.autoRespond = true
  app.client.semanticVad = true
  app.client.setHandsFree(true)
  when defined(emscripten):
    app.audio.prepareOutput()
    app.audio.startCapture()
    app.permissionPending = app.audio.capturePending()
    app.acceptResponses = not app.permissionPending
  # Restart an incomplete handshake so its initial settings include VAD.
  if app.client.state != Connected:
    app.client.connect(apiKey)

proc startConversationCapture(app: App) =
  ## Resumes an explicitly requested conversation after macOS grants access.
  if app.permissionPending:
    if microphonePermission() == "pending":
      return
    app.permissionPending = false
  let requestingPermission = microphonePermission() == "pending"
  try:
    app.audio.startCapture()
  except VoiceAudioError:
    if requestingPermission and
      microphonePermission() in ["pending", "allowed"]:
        app.permissionPending = true
        return
    raise
  app.acceptResponses = true
  app.view.error = ""

proc beginListening(app: App) =
  ## Starts one explicitly requested recording after stopping an older reply.
  if app.client.state != Connected or app.options.demo or
    app.conversationRequested:
      return
  app.view.error = ""
  when defined(emscripten):
    app.stopListening()
    app.audio.prepareOutput()
  app.interrupt()
  app.client.clearAudio()
  app.audio.startCapture()
  app.acceptResponses = true
  app.captureStarted = getMonoTime()
  app.client.status = "Listening. Release the talk button or Space to send."

proc resetSession(app: App, reconnect = false) =
  ## Ends the current microphone, playback, and network lifetimes together.
  app.stopListening()
  app.stopConversation()
  app.audio.stopPlayback()
  app.client.disconnect()
  app.waitingForAudio = false
  app.view.error = ""
  app.view.latencyMs = 0
  if reconnect:
    when defined(emscripten):
      app.audio.prepareOutput()
    app.client.connect()

proc copyTranscript(app: App) =
  ## Copies the visible conversation without saving recordings or credentials.
  var text: string
  for line in app.view.lines:
    if text.len > 0:
      text.add("\n\n")
    text.add(if line.user: "You: " else: "Voice: ")
    text.add(line.text)
  setClipboardString(text)
  app.client.status = "Conversation copied."

proc deviceSettingsPath(): string =
  ## Keeps this experiment's device preferences separate from engine settings.
  getConfigDir() / "polyworld-voice" / "devices.json"

proc selectedDevice(items: seq[AudioDevice], selected: int): string =
  ## Returns a stable selected device UID, or the system default for an empty UI.
  if selected >= 0 and selected < items.len:
    items[selected].uid
  else:
    ""

proc deviceIndex(items: var seq[AudioDevice], uid: string): int =
  ## Retains an unplugged selection visibly instead of silently changing devices.
  for i, device in items:
    if device.uid == uid:
      return i
  result = items.len
  items.add(AudioDevice(uid: uid, name: "Unavailable device (choose another)"))

proc refreshDevices(app: App, input = "", output = "") =
  ## Reads device choices without opening hardware or changing system defaults.
  app.inputs = audioDevices(input = true)
  app.outputs = audioDevices(input = false)
  app.view.inputDevice = app.inputs.deviceIndex(input)
  app.view.outputDevice = app.outputs.deviceIndex(output)
  app.view.inputDevices.setLen(0)
  app.view.outputDevices.setLen(0)
  for device in app.inputs:
    app.view.inputDevices.add(device.name)
  for device in app.outputs:
    app.view.outputDevices.add(device.name)

proc applyDevices(app: App, save = false) =
  ## Replaces dormant audio objects so conversation and manual modes route alike.
  if app.conversationRequested or app.audio.capturing() or
    app.audio.outputActive() or app.client.responseActive or
    app.client.state == Connecting:
      raise newException(VoiceAudioError,
        "Stop conversation and playback before changing audio devices.")
  let
    input = app.inputs.selectedDevice(app.view.inputDevice)
    output = app.outputs.selectedDevice(app.view.outputDevice)
  app.manualAudio.close()
  app.conversationAudio.close()
  app.manualAudio = newVoiceAudio(inputDevice = input, outputDevice = output)
  app.conversationAudio = newVoiceAudio(
    duplex = true, inputDevice = input, outputDevice = output
  )
  app.audio = app.manualAudio
  app.view.error = ""
  when not defined(emscripten):
    if save:
      let path = deviceSettingsPath()
      createDir(path.parentDir)
      writeFile(path, $(%*{"input": input, "output": output}))

proc loadDevices(app: App) =
  ## Restores explicit choices while leaving all audio devices closed.
  when defined(emscripten):
    app.refreshDevices()
    app.applyDevices()
    return
  when not defined(emscripten):
    var input, output: string
    let path = deviceSettingsPath()
    if fileExists(path):
      let settings = parseJson(readFile(path))
      input = settings{"input"}.getStr()
      output = settings{"output"}.getStr()
    app.refreshDevices(input, output)
    app.applyDevices()

proc handle(app: App, action: UiAction) =
  ## Maps a UI action to one explicit audio or conversation operation.
  if app.options.demo:
    case action
    of ClearAction:
      app.view.lines.setLen(0)
    of CopyAction:
      app.copyTranscript()
    else:
      app.view.status = "Offline preview. Relaunch without --demo to connect."
    return
  case action
  of ConnectAction:
    app.resetSession(reconnect = true)
  of DisconnectAction:
    app.resetSession()
  of BeginTalkAction:
    app.beginListening()
  of EndTalkAction:
    app.stopListening(commit = true)
  of ConversationAction:
    if app.conversationRequested:
      try:
        app.interrupt()
      finally:
        app.stopConversation()
      app.client.status = "Conversation stopped. Microphone off."
    else:
      app.beginConversation()
  of RepliesAction:
    app.view.speakReplies = not app.view.speakReplies
    if not app.view.speakReplies:
      app.playbackSuppressed = true
      app.audio.stopPlayback()
  of SubmitAction:
    if app.conversationRequested and
      (not app.audio.capturing() or app.permissionPending):
        return
    if app.view.draft.strip().len > 4000:
      raise newException(VoiceError, "Please keep messages under 4000 characters.")
    if not app.conversationRequested:
      app.stopListening()
    app.interrupt()
    app.view.error = ""
    app.replyStarted = getMonoTime()
    app.waitingForAudio = true
    app.acceptResponses = true
    app.client.sendText(app.view.draft)
    app.view.clearDraft()
  of InterruptAction:
    if not app.conversationRequested:
      app.stopListening()
    app.interrupt()
    app.client.status = "Stopped. Ready for your next turn."
  of ClearAction:
    let
      resumeConversation = app.conversationRequested
      reconnect = app.client.state == Connected
    app.resetSession(reconnect and not resumeConversation)
    app.client.transcripts.setLen(0)
    app.view.clearDraft()
    if resumeConversation:
      app.beginConversation()
  of CopyAction:
    app.copyTranscript()
  of InputDeviceAction, OutputDeviceAction:
    app.applyDevices(save = true)
  of RefreshDevicesAction:
    let
      input = app.inputs.selectedDevice(app.view.inputDevice)
      output = app.outputs.selectedDevice(app.view.outputDevice)
    app.refreshDevices(input, output)
    app.applyDevices()

proc tick(app: App) =
  ## Polls networking and audio while keeping all callbacks on the UI thread.
  app.client.poll()
  when defined(emscripten):
    if app.pendingCaptureCommit:
      if app.client.state == Connected:
        app.client.sendAudio(app.audio.readCapture())
        if not app.audio.captureStopping():
          app.audio.releaseCapture()
          app.pendingCaptureCommit = false
          app.replyStarted = getMonoTime()
          app.waitingForAudio = true
          app.client.commitAudio()
      else:
        app.pendingCaptureCommit = false
        app.audio.releaseCapture()
    app.permissionPending = app.audio.capturePending()
    if app.conversationRequested and not app.conversationReady and
      not app.permissionPending and app.audio.capturing() and
      app.client.state == Connected:
        app.conversationReady = true
        app.acceptResponses = true
  if app.conversationRequested:
    if app.client.state in {Disconnected, Failed}:
      app.stopConversation()
    elif app.client.failure.len > 0:
      app.reportError(app.client.failure)
    elif app.client.state == Connected and not app.audio.capturing():
      app.startConversationCapture()
  if not app.acceptResponses and app.client.responseActive:
    app.client.interrupt(0)
  if app.client.state != Connected:
    when defined(emscripten):
      if not (app.conversationRequested and app.client.state == Connecting):
        app.stopListening()
    else:
      app.stopListening()
    if app.client.state in [Disconnected, Failed]:
      app.audio.stopPlayback()
  if app.audio.capturing():
    if not app.conversationRequested and not app.window.focused:
      app.stopListening()
      app.client.status = "Microphone paused while the window is inactive."
    else:
      app.client.sendAudio(app.audio.readCapture())
      if not app.client.handsFree and
        (getMonoTime() - app.captureStarted).inMilliseconds >=
          MaxTalkMilliseconds:
            app.stopListening(commit = true)
  app.audio.pollPlayback()

proc syncView(app: App) =
  ## Projects current conversation state into the small independent GUI.
  if app.options.demo:
    return
  app.view.connected = app.client.state == Connected
  app.view.connecting = app.client.state == Connecting
  app.view.listening = app.audio.capturing()
  when defined(emscripten):
    app.view.listening = app.view.listening and not app.permissionPending and
      app.client.state == Connected
  app.view.speaking = app.audio.outputActive()
  app.view.responding = app.client.responseActive
  app.view.level = app.audio.inputLevel()
  app.view.handsFree = app.client.handsFree
  app.view.conversationRequested = app.conversationRequested
  app.view.permissionPending = app.permissionPending
  app.view.model = app.client.model
  app.view.status = app.client.status
  if app.conversationRequested:
    app.view.status =
      if app.permissionPending:
        when defined(emscripten):
          "Allow microphone access in your browser. Listening starts after approval."
        else:
          "Allow Voice Lab microphone access in macOS. " &
            "Listening starts after approval."
      elif app.client.state == Connecting:
        "Connecting for conversation. Press Stop conversation to cancel."
      else:
        "Microphone stays on, including in the background. Speak to interrupt."
  if app.client.state == Failed:
    app.view.error = app.client.status
  app.view.lines.setLen(0)
  for item in app.client.transcripts:
    app.view.lines.add(TranscriptLine(
      user: item.role == User,
      text: item.text
    ))

proc saveScreenshot(window: Window, path: string) =
  ## Saves the completed OpenGL frame for an explicit preview request.
  if path.parentDir.len > 0:
    createDir(path.parentDir)
  let image = newImage(window.size.x, window.size.y)
  glReadPixels(
    0, 0, window.size.x, window.size.y, GL_RGBA,
    GL_UNSIGNED_BYTE, image.data[0].addr
  )
  image.flipVertical()
  image.writeFile(path)

proc drawFrame(app: App) =
  ## Advances the experiment, draws its controls, and honors preview limits.
  try:
    app.tick()
    app.syncView()
  except CatchableError as error:
    app.reportError(error.msg)
  let
    size = app.window.size.vec2
    sk = app.view.sk
  sk.uiScale = max(0.25'f,
    min(app.window.contentScale, min(size.x / 900, size.y / 730)))
  sk.beginUi(app.window, app.window.size)
  for action in app.view.draw():
    try:
      app.handle(action)
    except CatchableError as error:
      app.reportError(error.msg)
  # Settle async completions before Windy changes its HTTP dispatcher.
  app.client.poll()
  sk.endUi()
  inc app.frameCount
  if app.options.frames > 0 and app.frameCount >= app.options.frames:
    if app.options.screenshot.len > 0:
      app.window.saveScreenshot(app.options.screenshot)
    app.finished = true
  app.window.swapBuffers()

proc run(options: Options) =
  ## Creates Voice Lab without opening a connection or microphone.
  let
    builder = buildAtlas(fontPath())
    window = newWindow("Polyworld - Voice Lab", ivec2(1060, 780))
    manualAudio = newVoiceAudio()
  window.size = (window.size.vec2 * window.contentScale).ivec2
  window.makeContextCurrent()
  loadExtensions()
  let app = App(
    window: window,
    options: options,
    client: newVoiceClient(),
    audio: manualAudio,
    manualAudio: manualAudio,
    conversationAudio: newVoiceAudio(duplex = true),
    view: VoiceView(
      window: window,
      sk: newSilky(window, builder.atlasImage, builder.atlas),
      speakReplies: true,
      demo: options.demo
    )
  )
  when defined(emscripten):
    browserApp = app
  try:
    app.loadDevices()
  except CatchableError as error:
    app.view.error = "Could not load audio devices: " & error.msg
  app.client.onAudioStart = proc() =
    ## Starts playback bookkeeping for the next assistant utterance.
    app.audio.stopPlayback()
    app.playbackSuppressed = not app.view.speakReplies or
      not app.acceptResponses
    if app.waitingForAudio:
      app.view.latencyMs = int((getMonoTime() - app.replyStarted).inMilliseconds)
      app.waitingForAudio = false
  app.client.onAudio = proc(pcm: string) =
    ## Streams one speech chunk while preserving text when playback is muted.
    if app.view.speakReplies and not app.playbackSuppressed:
      try:
        app.audio.queuePcm(pcm)
      except VoiceAudioError as error:
        app.audio.stopPlayback()
        app.playbackSuppressed = true
        app.view.speakReplies = false
        app.reportError(error.msg)
  app.client.onSpeechStart = proc() =
    ## Applies hands-free barge-in to local playback and server context.
    if not app.conversationRequested:
      return
    try:
      app.interrupt()
      app.acceptResponses = app.conversationRequested and app.audio.capturing()
    except VoiceAudioError as error:
      app.reportError(error.msg)
  if options.demo:
    app.view.model = app.client.model
    app.view.status = "Offline preview. No microphone or network connection."
    app.view.lines = @[
      TranscriptLine(user: true,
        text: "What should we build in Polyworld today?"),
      TranscriptLine(user: false,
        text: "How about a tiny world that listens? Describe an island, " &
          "then let your voice shape its hills and rivers."),
      TranscriptLine(user: true,
        text: "First, let's just have a conversation."),
      TranscriptLine(user: false,
        text: "Sounds good. I'm here whenever you're ready.")
    ]
  window.onFrame = proc() =
    ## Renders a frame from Windy's native event loop.
    app.drawFrame()
  try:
    while not window.closeRequested and not app.finished:
      pollEvents()
      when defined(emscripten):
        browserSleep(8)
  finally:
    window.onFrame = nil
    app.client.onAudio = nil
    app.client.onAudioStart = nil
    app.client.onSpeechStart = nil
    app.client.disconnect()
    app.client.poll()
    app.conversationAudio.close()
    app.manualAudio.close()
    window.close()

proc main() =
  ## Runs Voice Lab or prints its command-line options.
  let options = optionsFromArgs()
  if options.help:
    echo "Polyworld Voice Lab"
    echo "  --demo             Show a sample conversation offline."
    echo "  --frames=N         Close after N rendered frames."
    echo "  --screenshot=PATH  Save the final frame, then close."
    echo "Credentials: OPENAI_API_KEY or ~/secrets/openai.key"
    echo "Model: OPENAI_REALTIME_MODEL (default " & DefaultModel & ")"
    return
  when defined(emscripten):
    run(options)
  else:
    if not launchApplication():
      run(options)
      finishApplication()

when defined(emscripten):
  proc voiceBrowserAction(action: cint) {.exportc, cdecl.} =
    ## Dispatches accessible browser controls inside their user gesture.
    if browserApp == nil or action < ord(low(UiAction)) or
      action > ord(high(UiAction)):
        return
    try:
      browserApp.handle(UiAction(action))
    except CatchableError as error:
      browserApp.reportError(error.msg)

  proc voiceBrowserText(message: cstring) {.exportc, cdecl.} =
    ## Submits the browser text field through the same conversation controls.
    if browserApp == nil:
      return
    browserApp.view.draft = $message
    voiceBrowserAction(cint(ord(SubmitAction)))

  proc voiceBrowserState(): cstring {.exportc, cdecl.} =
    ## Mirrors the canvas conversation into accessible browser controls.
    if browserApp == nil:
      return "{}"
    let app = browserApp
    var lines = newJArray()
    for item in app.client.transcripts:
      lines.add(%*{"user": item.role == User, "text": item.text})
    browserState = $(%*{
      "status": app.view.status,
      "error": app.view.error,
      "connected": app.client.state == Connected,
      "connecting": app.client.state == Connecting,
      "conversationRequested": app.conversationRequested,
      "listening": app.view.listening,
      "permissionPending": app.permissionPending,
      "speaking": app.audio.outputActive(),
      "responding": app.client.responseActive,
      "model": app.client.model,
      "latencyMs": app.view.latencyMs,
      "lines": lines
    })
    browserState.cstring

when not defined(voiceLabTesting):
  main()
