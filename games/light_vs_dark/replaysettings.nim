import
  jsony, windy,
  polyworld/menus

type ReplayPreferences* = object
  saveReplay*: bool = true

proc readReplayPreferences*(): ReplayPreferences =
  ## Loads this device's recording choice separately from match configuration.
  result = ReplayPreferences()
  let bytes = getConfig("Polyworld LvD", "replays.json")
  if bytes.len > 0:
    try:
      result = bytes.fromJson(ReplayPreferences)
    except JsonError as error:
      raise newException(MenusError, "Cannot read replay settings: " & error.msg)

proc saveReplayPreferences*(preferences: ReplayPreferences) =
  ## Remembers recording without changing room rules or other players' choices.
  setConfig("Polyworld LvD", "replays.json", preferences.toJson())
