import
  std/[monotimes, os, strutils, times],
  pixie, silky, vmath,
  audios, launches, realtimes, views

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
    options: Options
    captureStarted, replyStarted: MonoTime
    waitingForAudio, playbackSuppressed: bool
    frameCount: int
    finished: bool

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
    discard app.audio.readCapture()
    app.client.clearAudio()

proc interrupt(app: App) =
  ## Stops audible speech and tells the server how much was actually heard.
  let played =
    if app.playbackSuppressed or not app.view.speakReplies: int.high
    else: app.audio.playbackMilliseconds()
  app.client.interrupt(played)
  app.audio.stopPlayback()
  app.waitingForAudio = false

proc reportError(app: App, message: string) =
  ## Keeps a recoverable error visible and turns microphone capture off.
  app.view.error = message
  app.stopListening()

proc beginListening(app: App) =
  ## Starts one explicitly requested recording after stopping an older reply.
  if app.client.state != Connected or app.options.demo:
    return
  app.view.error = ""
  app.interrupt()
  app.client.clearAudio()
  app.audio.startCapture()
  app.captureStarted = getMonoTime()
  app.client.status =
    if app.client.handsFree: "Microphone on. Pause it when you are finished."
    else: "Listening. Release the talk button or Space to send."

proc resetSession(app: App, reconnect = false) =
  ## Ends the current microphone, playback, and network lifetimes together.
  app.stopListening()
  app.audio.stopPlayback()
  app.client.disconnect()
  app.waitingForAudio = false
  app.view.error = ""
  app.view.latencyMs = 0
  if reconnect:
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
  of HandsFreeAction:
    app.stopListening()
    app.client.setHandsFree(not app.client.handsFree)
    app.view.handsFree = app.client.handsFree
    app.client.status =
      if app.client.handsFree: "Hands-free selected. Press Start microphone."
      else: "Push-to-talk selected. Hold the talk button or Space."
  of RepliesAction:
    app.view.speakReplies = not app.view.speakReplies
    if not app.view.speakReplies:
      app.playbackSuppressed = true
      app.audio.stopPlayback()
  of SubmitAction:
    if app.view.draft.strip().len > 4000:
      raise newException(VoiceError, "Please keep messages under 4000 characters.")
    app.stopListening()
    app.interrupt()
    app.view.error = ""
    app.replyStarted = getMonoTime()
    app.waitingForAudio = true
    app.client.sendText(app.view.draft)
    app.view.clearDraft()
  of InterruptAction:
    app.stopListening()
    app.interrupt()
    app.client.status = "Stopped. Ready for your next turn."
  of ClearAction:
    let reconnect = app.client.state == Connected
    app.resetSession(reconnect)
    app.client.transcripts.setLen(0)
    app.view.clearDraft()
  of CopyAction:
    app.copyTranscript()

proc tick(app: App) =
  ## Polls networking and audio while keeping all callbacks on the UI thread.
  app.client.poll()
  if app.client.state != Connected:
    app.stopListening()
    if app.client.state in [Disconnected, Failed]:
      app.audio.stopPlayback()
  if app.audio.capturing():
    if not app.window.focused:
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
  app.view.speaking = app.audio.outputActive()
  app.view.responding = app.client.responseActive
  app.view.level = app.audio.inputLevel()
  app.view.handsFree = app.client.handsFree
  app.view.model = app.client.model
  app.view.status = app.client.status
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
  ## Creates the native window without opening a connection or microphone.
  let
    builder = buildAtlas(fontPath())
    window = newWindow("Polyworld - Voice Lab", ivec2(1060, 780))
  window.size = (window.size.vec2 * window.contentScale).ivec2
  window.makeContextCurrent()
  loadExtensions()
  let app = App(
    window: window,
    options: options,
    client: newVoiceClient(),
    audio: newVoiceAudio(),
    view: VoiceView(
      window: window,
      sk: newSilky(window, builder.atlasImage, builder.atlas),
      speakReplies: true,
      demo: options.demo
    )
  )
  app.client.onAudioStart = proc() =
    ## Starts playback bookkeeping for the next assistant utterance.
    app.audio.stopPlayback()
    app.playbackSuppressed = not app.view.speakReplies
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
    try:
      app.interrupt()
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
  finally:
    window.onFrame = nil
    app.client.onAudio = nil
    app.client.onAudioStart = nil
    app.client.onSpeechStart = nil
    app.client.disconnect()
    app.client.poll()
    app.audio.close()
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
  if not launchApplication():
    run(options)
    finishApplication()

main()
