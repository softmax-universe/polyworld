import
  std/[monotimes, os, strutils, times],
  ../[audios, devices, launches]

when defined(macosx):
  import windy/platforms/macos/macdefs

const ReportPath = currentSourcePath().parentDir.parentDir /
  "build/duplex-check.txt"

proc pollDevices() =
  ## Delivers native device and permission notifications without a GUI window.
  when defined(macosx):
    autoreleasepool:
      discard NSRunLoop.currentRunLoop.runMode(
        NSDefaultRunLoopMode,
        NSDate.dateWithTimeIntervalSinceNow(0.01)
      )
  sleep(10)

proc option(name: string, fallback = ""): string =
  ## Reads a diagnostic option without accepting credentials or audio content.
  for argument in commandLineParams():
    if argument.startsWith(name & "="):
      return argument[name.len + 1 .. ^1]
  fallback

proc selectedDevice(input: bool): string =
  ## Resolves an explicitly requested device name or UID for the hardware check.
  let name = option(if input: "--input" else: "--output")
  if name.len == 0:
    return ""
  for device in audioDevices(input):
    if name in [device.name, device.uid]:
      return device.uid
  raise newException(VoiceAudioError, "Requested audio device is unavailable.")

proc checkDevices(): string =
  ## Checks native capture and silent playback without saving or sending audio.
  let
    duration = parseInt(option("--seconds", "1"))
    cycles = parseInt(option("--cycles", "2"))
    playbackOnly = "--playback-only" in commandLineParams()
    audio = newVoiceAudio(
      duplex = not playbackOnly and "--manual" notin commandLineParams(),
      inputDevice = selectedDevice(true),
      outputDevice = selectedDevice(false)
    )
  defer: audio.close()
  if duration < 1 or duration > 30 or cycles < 1 or cycles > 3:
    raise newException(ValueError, "Use 1-30 seconds and 1-3 cycles.")
  if playbackOnly:
    audio.queuePcm(newString(VoiceBytesPerSecond div 10))
    let deadline = getMonoTime() + initDuration(seconds = 5)
    while audio.outputActive() and getMonoTime() < deadline:
      pollDevices()
    if audio.capturing() or audio.outputActive() or
      audio.playbackMilliseconds() != 100:
        raise newException(VoiceAudioError, "Output-only playback failed.")
    return "Played 100 ms of silence with the microphone closed.\n" &
      audio.captureDiagnostics()
  if microphonePermission() == "pending":
    try:
      audio.startCapture()
    except VoiceAudioError:
      if microphonePermission() notin ["pending", "allowed"]:
        raise
    let deadline = getMonoTime() + initDuration(seconds = 45)
    while microphonePermission() == "pending" and getMonoTime() < deadline:
      pollDevices()
  for cycle in 1 .. cycles:
    audio.startCapture()
    audio.queuePcm(newString(VoiceBytesPerSecond div 10))
    var
      capturedBytes = 0
      peakLevel = 0.0'f
    let deadline = getMonoTime() + initDuration(seconds = duration + 7)
    while getMonoTime() < deadline:
      pollDevices()
      let pcm = audio.readCapture()
      capturedBytes += pcm.len
      peakLevel = max(peakLevel, pcmLevel(pcm))
      audio.pollPlayback()
      if capturedBytes >= VoiceBytesPerSecond * duration and
        not audio.outputActive():
        break
    if capturedBytes < VoiceBytesPerSecond * duration:
      raise newException(VoiceAudioError,
        "The microphone did not deliver enough frames before the deadline. " &
        audio.captureDiagnostics())
    if audio.outputActive() or audio.playbackMilliseconds() != 100:
      raise newException(VoiceAudioError, "Silent playback did not drain.")
    result.add("Cycle " & $cycle & ": captured " & $capturedBytes &
      " bytes (discarded), peak RMS " & $peakLevel &
      ", played 100 ms of silence.\n")
    result.add(audio.captureDiagnostics() & "\n")
    if "--require-signal" in commandLineParams() and peakLevel < 0.001'f:
      raise newException(VoiceAudioError,
        "Microphone frames arrived, but no usable speech level was detected. " &
        audio.captureDiagnostics())
    audio.stopCapture()
    pollDevices()
    audio.pollPlayback()
    if audio.capturing() or audio.outputActive():
      raise newException(VoiceAudioError, "Conversation audio did not stop.")
    sleep(100)

if launchApplication():
  let report = readFile(ReportPath)
  echo report
  if not report.startsWith("PASS\n"):
    quit(1)
else:
  var report: string
  try:
    report = "PASS\n" & checkDevices()
  except CatchableError as error:
    report = "FAIL\n" & error.msg
  writeFile(ReportPath, report)
  finishApplication()
