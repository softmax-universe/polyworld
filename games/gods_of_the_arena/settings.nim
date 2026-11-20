## GotA presentation preferences and game-specific control defaults.

import
  jsony, windy,
  polyworld/[inputs, menus]

const
  GotaControlProfile* = block:
    var profile = ControlProfile(defaults: DefaultBindings)
    profile.defaults[DebugInput] = [KeyF2, ButtonUnknown]
    profile.defaults[TraceInput] = [KeyF1, ButtonUnknown]
    profile.defaults[WaterPanelInput] = [ButtonUnknown, ButtonUnknown]
    for action in InputAction:
      if action != WaterPanelInput:
        profile.actions.add ControlBinding(action: action, label: $action)
    profile

type ReplayPreferences* = object
  saveReplay*: bool = true

proc migrateGotaBindings*(bindings: var InputBindings) =
  ## Moves untouched debug defaults to F2 while preserving custom shortcuts.
  if bindings[DebugInput] == DefaultBindings[DebugInput] and
    bindings[TraceInput] == DefaultBindings[TraceInput]:
      bindings[DebugInput] = GotaControlProfile.defaults[DebugInput]
      bindings[TraceInput] = GotaControlProfile.defaults[TraceInput]
  if bindings[WaterPanelInput] == DefaultBindings[WaterPanelInput]:
    bindings[WaterPanelInput] = GotaControlProfile.defaults[WaterPanelInput]

proc readGotaPreferences*(): Preferences =
  ## Preserves the full saved identity for GotA's name gate and upgrades controls.
  const AppName = "Polyworld GotA"
  result = readPreferences(AppName)
  result.bindings.migrateGotaBindings()
  let bytes = getConfig(AppName, "settings.json")
  if bytes.len > 0:
    result.name = bytes.fromJson(Preferences).name

proc readReplayPreferences*(): ReplayPreferences =
  ## Loads this device's recording choice separately from match configuration.
  result = ReplayPreferences()
  let bytes = getConfig("Polyworld GotA", "replays.json")
  if bytes.len > 0:
    try:
      result = bytes.fromJson(ReplayPreferences)
    except JsonError as error:
      raise newException(MenusError, "Cannot read replay settings: " & error.msg)

proc saveReplayPreferences*(preferences: ReplayPreferences) =
  ## Remembers recording without changing room rules or other players' choices.
  setConfig("Polyworld GotA", "replays.json", preferences.toJson())
