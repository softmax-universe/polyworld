import
  jsony, windy,
  menus

type ReplayPreferences* = object
  saveReplay*: bool = true

proc decodeReplayPreferences*(bytes: string): ReplayPreferences =
  ## Defaults new installations to recording and rejects malformed settings.
  result = ReplayPreferences()
  if bytes.len > 0:
    try:
      result = bytes.fromJson(ReplayPreferences)
    except JsonError as error:
      raise newException(MenusError, "Cannot read replay settings: " & error.msg)

proc readReplayPreferences*(appName: string): ReplayPreferences =
  ## Loads the device's recording choice independently of shared match rules.
  decodeReplayPreferences(getConfig(appName, "replays.json"))

proc saveReplayPreferences*(
  preferences: ReplayPreferences, appName: string
) =
  ## Persists the recording choice using the game's existing config namespace.
  setConfig(appName, "replays.json", preferences.toJson())
