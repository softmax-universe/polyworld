## GotA presentation preferences and game-specific control defaults.

import
  jsony, windy,
  polyworld/[inputs, menus],
  replaysettings

export replaysettings

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
  when not defined(backendBench):
    let bytes = getConfig(AppName, "settings.json")
    if bytes.len > 0:
      result.name = bytes.fromJson(Preferences).name
