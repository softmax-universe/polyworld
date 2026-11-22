import std/[json, os]

type
  VoiceDeviceError* = object of IOError
  AudioDevice* = object
    id*: uint32
    uid*, name*: string
    isDefault*: bool

when defined(macosx) and not defined(emscripten):
  {.compile: currentSourcePath().parentDir / "devices.m".}
  {.passL: "-framework CoreAudio -framework AudioToolbox " &
    "-framework AVFAudio -framework Foundation".}
  proc voiceAudioDevices(input: bool): cstring {.importc.}
    ## Returns an owned native device snapshot without opening audio hardware.
  proc voiceAudioDevicesFree(snapshot: cstring) {.importc.}
    ## Frees a snapshot after copying its strings into Nim.
  proc voiceAudioDeviceId(uid: cstring, input: bool,
    error: cstring, capacity: cint): uint32 {.importc.}
    ## Resolves a stable device UID or reports a disconnected selection.

proc audioDevices*(input: bool): seq[AudioDevice] =
  ## Lists live devices with a system-default entry before explicit selections.
  when defined(emscripten):
    result.add(AudioDevice(name: "Browser default", isDefault: true))
  else:
    result.add(AudioDevice(name: "System default", isDefault: true))
  when defined(macosx) and not defined(emscripten):
    let snapshot = voiceAudioDevices(input)
    if snapshot == nil:
      raise newException(VoiceDeviceError, "Could not read audio devices.")
    defer: voiceAudioDevicesFree(snapshot)
    try:
      let parsed = parseJson($snapshot)
      let message = parsed["error"].getStr()
      if message.len > 0:
        raise newException(VoiceDeviceError, message)
      let defaultId = parsed["default"].getInt().uint32
      for item in parsed["devices"]:
        let device = AudioDevice(
          id: item["id"].getInt().uint32,
          uid: item["uid"].getStr(),
          name: item["name"].getStr(),
          isDefault: item["id"].getInt().uint32 == defaultId
        )
        result.add(device)
        if device.isDefault:
          result[0].name = "System default (" & device.name & ")"
    except JsonParsingError, KeyError, ValueError:
      raise newException(VoiceDeviceError,
        "Could not read audio device metadata: " & getCurrentExceptionMsg())

proc audioDeviceId*(uid: string, input: bool): uint32 =
  ## Resolves the current device ID from a persisted UID before opening audio.
  when defined(macosx) and not defined(emscripten):
    var error: array[512, char]
    result = voiceAudioDeviceId(uid.cstring, input,
      cast[cstring](addr error[0]), error.len.cint)
    if result == 0:
      raise newException(VoiceDeviceError, $cast[cstring](addr error[0]))
  else:
    if uid.len > 0:
      raise newException(VoiceDeviceError,
        "Explicit audio device selection is only available on macOS.")
